import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_quill/flutter_quill.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NotePageEditor — flutter_quill based rich-text editor
//
// Content format (quill-1.0):
//   { "version": "quill-1.0",
//     "delta":   [...quill delta ops...],
//     "images":  { "id": {"data":"data:…","width":200,"height":150,"rotation":0} },
//     "strokes": [{"pts":[[x,y],…],"color":"0xFF…","width":…,"eraser":…}] }
// ─────────────────────────────────────────────────────────────────────────────

enum _EditorMode { text, draw }

class NotePageEditor extends StatefulWidget {
  final Map<String, dynamic> content;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const NotePageEditor({
    super.key,
    required this.content,
    required this.onChanged,
  });

  @override
  NotePageEditorState createState() => NotePageEditorState();
}

class NotePageEditorState extends State<NotePageEditor> {
  _EditorMode _mode = _EditorMode.text;

  late QuillController _qCtrl;
  final _focusNode = FocusNode();
  final _scrollCtrl = ScrollController();
  final Map<String, Map<String, dynamic>> _images = {};

  // Drawing state
  late List<_Stroke> _strokes;
  _Stroke? _currentStroke;
  final List<_Stroke> _undoStack = [];
  Color _penColor = Colors.black;
  double _penWidth = 4.0;
  bool _isEraser = false;

  // Text color
  Color _textColor = Colors.black;

  // Image selection
  String? _selectedImageId;
  // Set to true by the image's own Listener on pointer-down (child fires before
  // parent because hit-test dispatch is leaf-to-root).  The outer translucent
  // Listener reads and resets this flag so it never clears selection when the
  // user is actually touching an image (drag / resize / re-tap).
  bool _suppressNextDeselect = false;
  double _imgReorderAccum = 0.0;
  int _editorRebuildKey = 0; // Incremented to force QuillEditor rebuild after delta reorder

  // Content-change deduplication — QuillController notifies on BOTH document
  // changes AND selection/cursor changes.  We must not call widget.onChanged
  // on a selection-only event because that would mark the note as locally
  // modified and permanently block server pulls for that note.
  String? _lastDeltaJson;

  // UID counter
  int _uidSeq = 0;
  String _uid() => '${DateTime.now().microsecondsSinceEpoch}_${_uidSeq++}';

  // Popup overlay keys
  final _penBtnKey = GlobalKey();
  final _eraserBtnKey = GlobalKey();
  OverlayEntry? _sizePopupEntry;

  @override
  void initState() {
    super.initState();
    _parseContent(widget.content);
    _qCtrl.addListener(_onEditorChange);
    _focusNode.addListener(_onEditorFocusChange);
  }

  @override
  void dispose() {
    _dismissSizePopup();
    _focusNode.removeListener(_onEditorFocusChange);
    _qCtrl.removeListener(_onEditorChange);
    _qCtrl.dispose();
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onEditorChange() {
    if (!mounted) return;
    setState(() {}); // Always update toolbar active-state indicators

    // QuillController fires on selection/cursor changes as well as content
    // changes.  Only propagate to widget.onChanged when the actual document
    // content changed — otherwise merely tapping into the editor would mark
    // the note as having local changes, permanently blocking server pulls.
    final deltaJson = jsonEncode(_qCtrl.document.toDelta().toJson());
    if (deltaJson == _lastDeltaJson) return;
    _lastDeltaJson = deltaJson;
    widget.onChanged(_serialize());
  }

  /// When the text editor gains focus, deselect any selected image and restore
  /// normal scroll physics.
  void _onEditorFocusChange() {
    if (_focusNode.hasFocus && _selectedImageId != null && mounted) {
      setState(() => _selectedImageId = null);
    }
  }

  // ── Image drag-to-reorder ──────────────────────────────────────────────────

  // Called once on drag-end with total accumulated dy.
  // Converts pixel distance to block steps (~60px per block) and reorders.
  // Never called mid-drag so _rebuildDocument never fires while the gesture
  // is live, which is what was causing the grip-loss after one line.
  void _handleImageDrag(String imageId, double totalDy) {
    final steps = (totalDy / 60).round();
    if (steps == 0) return;
    for (int i = 0; i < steps.abs(); i++) {
      _moveImageInDoc(imageId, steps > 0 ? 1 : -1);
    }
    _imgReorderAccum = 0.0;
  }

  /// Split a flat list of delta ops into "blocks", where each block ends with
  /// a `\n` character (which is Quill's paragraph / embed-line terminator).
  List<List<Map<String, dynamic>>> _deltaToBlocks(
      List<Map<String, dynamic>> ops) {
    final blocks = <List<Map<String, dynamic>>>[];
    var currentBlock = <Map<String, dynamic>>[];

    for (final op in ops) {
      final insert = op['insert'];
      final attrs = op['attributes'] as Map<String, dynamic>?;

      if (insert is Map) {
        // Block embed (image) — belongs to current block
        currentBlock.add(Map<String, dynamic>.from(op));
      } else if (insert is String) {
        int start = 0;
        for (int i = 0; i < insert.length; i++) {
          if (insert[i] == '\n') {
            if (i > start) {
              currentBlock.add({
                'insert': insert.substring(start, i),
                if (attrs != null) 'attributes': attrs,
              });
            }
            currentBlock.add({
              'insert': '\n',
              if (attrs != null) 'attributes': attrs,
            });
            blocks.add(currentBlock);
            currentBlock = [];
            start = i + 1;
          }
        }
        if (start < insert.length) {
          currentBlock.add({
            'insert': insert.substring(start),
            if (attrs != null) 'attributes': attrs,
          });
        }
      }
    }
    if (currentBlock.isNotEmpty) blocks.add(currentBlock);
    return blocks;
  }

  void _moveImageInDoc(String imageId, int dir) {
    final opsJson = _qCtrl.document.toDelta().toJson() as List;
    final ops =
        opsJson.map((o) => Map<String, dynamic>.from(o as Map)).toList();
    final blocks = _deltaToBlocks(ops);

    // Find which block contains the image embed
    int imgBlockIdx = -1;
    for (int i = 0; i < blocks.length; i++) {
      for (final op in blocks[i]) {
        final ins = op['insert'];
        if (ins is Map && ins['image'] == imageId) {
          imgBlockIdx = i;
          break;
        }
      }
      if (imgBlockIdx >= 0) break;
    }
    if (imgBlockIdx < 0) return;

    final newBlocks = List<List<Map<String, dynamic>>>.from(blocks);
    if (dir < 0 && imgBlockIdx > 0) {
      final block = newBlocks.removeAt(imgBlockIdx);
      newBlocks.insert(imgBlockIdx - 1, block);
    } else if (dir > 0 && imgBlockIdx < newBlocks.length - 1) {
      final block = newBlocks.removeAt(imgBlockIdx);
      newBlocks.insert(imgBlockIdx + 1, block);
    } else {
      return; // Already at boundary
    }

    final newOps = newBlocks.expand((b) => b).toList();
    _rebuildDocument(newOps);
  }

  void _rebuildDocument(List<Map<String, dynamic>> newOps) {
    final oldCtrl = _qCtrl;
    oldCtrl.removeListener(_onEditorChange);

    _qCtrl = QuillController(
      document: Document.fromJson(newOps),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _qCtrl.addListener(_onEditorChange);
    // Seed cache so the rebuild itself doesn't re-trigger onChanged unnecessarily
    _lastDeltaJson = jsonEncode(_qCtrl.document.toDelta().toJson());

    setState(() => _editorRebuildKey++);

    // Dispose old controller after rebuild so the old QuillEditor can finish
    WidgetsBinding.instance.addPostFrameCallback((_) => oldCtrl.dispose());
    widget.onChanged(_serialize());
  }

  // ── Content parsing ────────────────────────────────────────────────────────

  void _parseContent(Map<String, dynamic> content) {
    _strokes = _parseStrokes(content['strokes']);

    if (content['version'] == 'quill-1.0') {
      // Native quill format — load delta directly
      final rawImages = content['images'] as Map? ?? {};
      rawImages.forEach((k, v) {
        _images[k as String] = Map<String, dynamic>.from(v as Map);
      });
      final rawDelta = content['delta'] as List?;
      // Sanitize ops: replace unregistered embed types (e.g. divider) with a
      // plain text equivalent so Document.fromJson doesn't throw.
      final delta = rawDelta?.map((op) {
        final m = Map<String, dynamic>.from(op as Map);
        final insert = m['insert'];
        if (insert is Map) {
          if (insert.containsKey('divider')) {
            return {'insert': '────────────────────\n'};
          }
          // Any other unknown embed — skip by rendering as empty paragraph
          if (!insert.containsKey('image')) {
            return {'insert': '\n'};
          }
        }
        return m;
      }).toList();
      _qCtrl = QuillController(
        document: delta != null ? Document.fromJson(delta) : Document(),
        selection: const TextSelection.collapsed(offset: 0),
      );
    } else if (content['version'] == '1.0') {
      // Web v1.0 blocks format — convert to quill ops
      _qCtrl = QuillController(
        document: _migrateV1BlocksToQuill(content),
        selection: const TextSelection.collapsed(offset: 0),
      );
    } else {
      // v2.0 paragraph-based format — migrate to quill
      _qCtrl = QuillController(
        document: _migrateV2ToQuill(content),
        selection: const TextSelection.collapsed(offset: 0),
      );
    }

    // Seed the delta cache so the first selection-change event from QuillEditor
    // (cursor placement on first render) is not mistaken for a content change.
    _lastDeltaJson = jsonEncode(_qCtrl.document.toDelta().toJson());
  }

  List<_Stroke> _parseStrokes(dynamic raw) {
    return (raw as List? ?? []).map((s) {
      final m = s as Map;
      final pts = (m['pts'] as List)
          .map((p) => Offset((p as List)[0].toDouble(), (p[1] as num).toDouble()))
          .toList();
      return _Stroke(
        points: pts,
        color: _colorFromHex(m['color'] as String? ?? '0xFF000000'),
        width: (m['width'] as num).toDouble(),
        isEraser: m['eraser'] as bool? ?? false,
      );
    }).toList();
  }

  Document _migrateV2ToQuill(Map<String, dynamic> content) {
    final ops = <Map<String, dynamic>>[];
    final paras = content['paragraphs'] as List? ?? [];

    for (final p in paras) {
      final para = p as Map;
      final style = para['style'] as String? ?? 'normal';
      final text = para['text'] as String? ?? '';

      switch (style) {
        case 'image':
          final id = _uid();
          _images[id] = {
            'data': para['data'] as String? ?? '',
            'width': (para['imgWidth'] as num?)?.toDouble() ?? 160.0,
            'height': (para['imgHeight'] as num?)?.toDouble() ?? 120.0,
            'rotation': (para['imgRotation'] as num?)?.toDouble() ?? 0.0,
          };
          ops.add({'insert': <String, dynamic>{'image': id}});
          ops.add({'insert': '\n'});
        case 'bullet':
          ops.add({'insert': text});
          ops.add({'insert': '\n', 'attributes': <String, dynamic>{'list': 'bullet'}});
        case 'numbered':
          ops.add({'insert': text});
          ops.add({'insert': '\n', 'attributes': <String, dynamic>{'list': 'ordered'}});
        case 'checklist':
          final checked = para['checked'] as bool? ?? false;
          ops.add({'insert': text});
          ops.add({'insert': '\n', 'attributes': <String, dynamic>{'list': checked ? 'checked' : 'unchecked'}});
        default:
          // normal, h1, h2, h3 — convert to plain text
          if (text.isNotEmpty) ops.add({'insert': text});
          ops.add({'insert': '\n'});
      }
    }

    if (ops.isEmpty) ops.add({'insert': '\n'});
    return Document.fromJson(ops);
  }

  /// Converts web v1.0 blocks format → quill delta ops so notes saved on the
  /// web are fully readable and editable on mobile.
  Document _migrateV1BlocksToQuill(Map<String, dynamic> content) {
    final ops = <Map<String, dynamic>>[];
    final blocks = content['blocks'] as List? ?? [];

    for (final block in blocks) {
      final b = block as Map;
      final type = b['type'] as String? ?? '';
      switch (type) {
        case 'paragraph':
        case 'quote':
          final text = (b['content'] as List? ?? [])
              .map((s) => (s as Map)['text'] ?? '').join();
          if (text.isNotEmpty) ops.add({'insert': text});
          ops.add({'insert': '\n'});
        case 'heading':
          final text = (b['content'] as List? ?? [])
              .map((s) => (s as Map)['text'] ?? '').join();
          if (text.isNotEmpty) ops.add({'insert': text});
          ops.add({'insert': '\n'});
        case 'list':
          for (final item in (b['items'] as List? ?? [])) {
            final text = (item as Map)['text'] as String? ?? '';
            final listType = (b['ordered'] as bool? ?? false) ? 'ordered' : 'bullet';
            if (text.isNotEmpty) ops.add({'insert': text});
            ops.add({'insert': '\n', 'attributes': <String, dynamic>{'list': listType}});
          }
        case 'checklist':
          for (final item in (b['items'] as List? ?? [])) {
            final m = item as Map;
            final text = m['text'] as String? ?? '';
            final checked = m['checked'] as bool? ?? false;
            if (text.isNotEmpty) ops.add({'insert': text});
            ops.add({'insert': '\n', 'attributes': <String, dynamic>{'list': checked ? 'checked' : 'unchecked'}});
          }
        case 'divider':
          ops.add({'insert': '────────────────────\n'});
        case 'image':
        case 'drawing':
          final imgData = b['data'] as String? ?? '';
          if (imgData.isNotEmpty) {
            final id = _uid();
            _images[id] = {
              'data': imgData,
              'width': (b['displayWidth'] as num?)?.toDouble() ?? 260.0,
              'height': (b['displayHeight'] as num?)?.toDouble() ?? 200.0,
              'rotation': (b['rotation'] as num?)?.toDouble() ?? 0.0,
            };
            ops.add({'insert': <String, dynamic>{'image': id}});
            ops.add({'insert': '\n'});
          }
      }
    }

    if (ops.isEmpty) ops.add({'insert': '\n'});
    return Document.fromJson(ops);
  }

  // ── Serialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> _serialize() => {
        'version': 'quill-1.0',
        'delta': _qCtrl.document.toDelta().toJson(),
        'images': _images,
        'strokes': _strokes
            .map((s) => {
                  'pts': s.points.map((p) => [p.dx, p.dy]).toList(),
                  'color': '0x${s.color.toARGB32().toRadixString(16).padLeft(8, '0')}',
                  'width': s.width,
                  'eraser': s.isEraser,
                })
            .toList(),
      };

  // ── Public API ─────────────────────────────────────────────────────────────

  void addImage(String dataUrl) {
    final screenW = MediaQuery.sizeOf(context).width;
    final initW = ((screenW - 40) / 2).clamp(120.0, 400.0);
    final initH = initW * 3 / 4;
    final id = _uid();
    _images[id] = {'data': dataUrl, 'width': initW, 'height': initH, 'rotation': 0.0};

    final index = _qCtrl.selection.baseOffset;
    final safeIndex = index < 0 ? _qCtrl.document.length : index;
    _qCtrl.document.insert(safeIndex, BlockEmbed.image(id));
    _qCtrl.updateSelection(
      TextSelection.collapsed(offset: safeIndex + 1),
      ChangeSource.local,
    );
    widget.onChanged(_serialize());
  }

  // ── Drawing operations ─────────────────────────────────────────────────────

  Color _resolveEraserColor() => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF121212)
      : Colors.white;

  void _onDown(PointerDownEvent e) {
    final color = _isEraser ? _resolveEraserColor() : _penColor;
    setState(() => _currentStroke = _Stroke(
          points: [e.localPosition],
          color: color,
          width: _isEraser ? _penWidth * 3 : _penWidth,
          isEraser: _isEraser,
        ));
  }

  void _onMove(PointerMoveEvent e) {
    if (_currentStroke == null) return;
    setState(() => _currentStroke!.points.add(e.localPosition));
  }

  void _onUp(PointerUpEvent e) {
    if (_currentStroke == null) return;
    setState(() {
      if (_currentStroke!.points.isNotEmpty) {
        _strokes.add(_currentStroke!);
        _undoStack.clear();
      }
      _currentStroke = null;
    });
    widget.onChanged(_serialize());
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _undoStack.add(_strokes.removeLast()));
    widget.onChanged(_serialize());
  }

  void _clearDrawing() {
    setState(() {
      _undoStack.addAll(_strokes);
      _strokes.clear();
      _currentStroke = null;
    });
    widget.onChanged(_serialize());
  }

  // ── Size popup ─────────────────────────────────────────────────────────────

  void _dismissSizePopup() {
    _sizePopupEntry?.remove();
    _sizePopupEntry = null;
  }

  void _showSizePopup(GlobalKey btnKey) {
    _dismissSizePopup();
    final ctx = btnKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset(0, box.size.height + 4));
    _sizePopupEntry = OverlayEntry(
      builder: (_) => _SizePopup(
        left: (offset.dx - 80).clamp(8.0, double.infinity),
        top: offset.dy,
        initialValue: _penWidth,
        isEraser: _isEraser,
        penColor: _penColor,
        onChanged: (v) => setState(() => _penWidth = v),
        onDismiss: _dismissSizePopup,
      ),
    );
    Overlay.of(context).insert(_sizePopupEntry!);
  }

  static const _textColorPalette = [
    Color(0xFF000000), Color(0xFF5f6368), Color(0xFFb0b0b0), Color(0xFFFFFFFF),
    Color(0xFFe53935), Color(0xFFf4511e), Color(0xFFf6bf26), Color(0xFF33b679),
    Color(0xFF039be5), Color(0xFF3f51b5), Color(0xFF8e24aa), Color(0xFFd81b60),
  ];

  void _openTextColorPicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Text colour'),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _textColorPalette.map((c) {
            final isSelected = _textColor.toARGB32() == c.toARGB32();
            return GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _textColor = c);
                // Apply color as hex to the current selection
                final hex = '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
                _qCtrl.formatSelection(Attribute.fromKeyValue('color', hex));
              },
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : (c == Colors.white
                            ? Colors.grey.shade300
                            : Colors.transparent),
                    width: isSelected ? 3 : 1,
                  ),
                  boxShadow: isSelected
                      ? [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.4), blurRadius: 6)]
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _textColor = Colors.black);
              _qCtrl.formatSelection(Attribute.clone(Attribute.color, null));
            },
            child: const Text('Remove colour'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
  }

  void _openColorPicker() {
    Color picked = _penColor;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pen colour'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (c) => picked = c,
            enableAlpha: false,
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              setState(() {
                _penColor = picked;
                _isEraser = false;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        Expanded(child: _buildEditorArea()),
      ],
    );
  }

  // ── Toolbar ────────────────────────────────────────────────────────────────

  Widget _buildToolbar() {
    final scheme = Theme.of(context).colorScheme;
    final inText = _mode == _EditorMode.text;
    final inDraw = _mode == _EditorMode.draw;
    final style = _qCtrl.getSelectionStyle();

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            // Mode toggles
            _modeBtn(Icons.text_fields_rounded, 'Text', inText,
                () => setState(() => _mode = _EditorMode.text)),
            _modeBtn(Icons.edit_rounded, 'Draw', inDraw,
                () => setState(() => _mode = _EditorMode.draw)),
            Container(
                width: 1,
                height: 28,
                color: Colors.grey.shade300,
                margin: const EdgeInsets.symmetric(horizontal: 4)),

            if (inText) ...[
              // Bold
              _fmtIconBtn(
                Icons.format_bold,
                'Bold',
                style.containsKey(Attribute.bold.key),
                () => _toggleInline(Attribute.bold, style),
              ),
              // Italic
              _fmtIconBtn(
                Icons.format_italic,
                'Italic',
                style.containsKey(Attribute.italic.key),
                () => _toggleInline(Attribute.italic, style),
              ),
              // Underline
              _fmtIconBtn(
                Icons.format_underlined,
                'Underline',
                style.containsKey(Attribute.underline.key),
                () => _toggleInline(Attribute.underline, style),
              ),
              // Font size dropdown
              _fontSizeDropdown(style),
              // Text color
              Tooltip(
                message: 'Text colour',
                child: GestureDetector(
                  onTap: _openTextColorPicker,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withOpacity(0.5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withOpacity(0.4),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'A',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            // Always readable — use the theme's on-surface color
                            color: Theme.of(context).colorScheme.onSurface,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Color bar shows the selected color
                        Container(
                          height: 3,
                          width: 16,
                          decoration: BoxDecoration(
                            color: _textColor,
                            borderRadius: BorderRadius.circular(2),
                            // Add a subtle border so light colors (white/yellow) stay visible
                            border: Border.all(
                              color: Colors.grey.shade400,
                              width: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                  width: 1,
                  height: 28,
                  color: Colors.grey.shade300,
                  margin: const EdgeInsets.symmetric(horizontal: 4)),
              // Bullet list
              _fmtIconBtn(
                Icons.format_list_bulleted,
                'Bullet list',
                style.attributes[Attribute.list.key]?.value == 'bullet',
                () => _toggleList('bullet', style),
              ),
              // Numbered list
              _fmtIconBtn(
                Icons.format_list_numbered,
                'Numbered list',
                style.attributes[Attribute.list.key]?.value == 'ordered',
                () => _toggleList('ordered', style),
              ),
              // Checklist
              _fmtIconBtn(
                Icons.check_box_outlined,
                'Checklist',
                style.attributes[Attribute.list.key]?.value == 'unchecked' ||
                    style.attributes[Attribute.list.key]?.value == 'checked',
                () => _toggleList('unchecked', style),
              ),
              // Clear format
              _fmtIconBtn(Icons.format_clear, 'Clear format', false, () {
                _qCtrl.formatSelection(Attribute.clone(Attribute.bold, null));
                _qCtrl.formatSelection(Attribute.clone(Attribute.italic, null));
                _qCtrl.formatSelection(Attribute.clone(Attribute.underline, null));
                _qCtrl.formatSelection(Attribute.clone(Attribute.size, null));
                _qCtrl.formatSelection(Attribute.clone(Attribute.color, null));
                _qCtrl.formatSelection(Attribute.clone(Attribute.list, null));
                setState(() => _textColor = Colors.black);
              }),
            ] else ...[
              // Draw tools
              SizedBox(
                key: _penBtnKey,
                child: IconButton(
                  icon: Icon(Icons.brush_rounded,
                      color: !_isEraser ? scheme.primary : Colors.grey),
                  tooltip: 'Pen (tap for size)',
                  onPressed: () {
                    setState(() => _isEraser = false);
                    _showSizePopup(_penBtnKey);
                  },
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: EdgeInsets.zero,
                ),
              ),
              SizedBox(
                key: _eraserBtnKey,
                child: IconButton(
                  icon: _EraserIcon(
                      color: _isEraser ? scheme.primary : Colors.grey.shade500),
                  tooltip: 'Eraser (tap for size)',
                  onPressed: () {
                    setState(() => _isEraser = true);
                    _showSizePopup(_eraserBtnKey);
                  },
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: EdgeInsets.zero,
                ),
              ),
              GestureDetector(
                onTap: _openColorPicker,
                child: Container(
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: _penColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade400, width: 1.5),
                  ),
                ),
              ),
              Container(
                width: (_penWidth / 24 * 22).clamp(3.0, 22.0),
                height: (_penWidth / 24 * 22).clamp(3.0, 22.0),
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: _isEraser ? Colors.grey.shade400 : _penColor,
                  shape: BoxShape.circle,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: 'Undo stroke',
                onPressed: _undo,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Clear drawing',
                onPressed: _clearDrawing,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _modeBtn(IconData icon, String label, bool active, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        decoration: BoxDecoration(
          color: active ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : Colors.grey.shade600,
                )),
          ],
        ),
      ),
    );
  }

  Widget _fmtIconBtn(
      IconData icon, String tooltip, bool active, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon,
            size: 20, color: active ? scheme.primary : Colors.grey.shade600),
        onPressed: onTap,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _fontSizeDropdown(Style style) {
    final sizes = ['12', '15', '18', '22', '28'];
    final currentSize =
        style.attributes[Attribute.size.key]?.value?.toString() ?? '15';
    final dropdownValue = sizes.contains(currentSize) ? currentSize : '15';
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.4),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: dropdownValue,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down, size: 16, color: textColor),
          style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w600),
          dropdownColor: Theme.of(context).colorScheme.surface,
          items: sizes
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text('${s}px',
                        style: TextStyle(fontSize: 13, color: textColor)),
                  ))
              .toList(),
          onChanged: (s) {
            if (s == null) return;
            _qCtrl.formatSelection(
                Attribute.fromKeyValue('size', s == '15' ? null : s));
          },
        ),
      ),
    );
  }

  void _toggleInline(Attribute attribute, Style style) {
    final active = style.containsKey(attribute.key);
    _qCtrl.formatSelection(
        active ? Attribute.clone(attribute, null) : attribute);
  }

  void _toggleList(String listValue, Style style) {
    final current = style.attributes[Attribute.list.key]?.value;
    if (current == listValue ||
        (listValue == 'unchecked' && current == 'checked')) {
      _qCtrl.formatSelection(Attribute.clone(Attribute.list, null));
    } else {
      _qCtrl.formatSelection(Attribute.fromKeyValue('list', listValue));
    }
  }

  // ── Editor area ────────────────────────────────────────────────────────────

  Widget _buildEditorArea() {
    final inDraw = _mode == _EditorMode.draw;
    return Stack(
      children: [
        // Quill editor with pinch-to-zoom.
        // Listener (translucent) clears image selection on any pointer-down that
        // lands outside an image's opaque GestureDetector — giving us "tap outside
        // to deselect" without interfering with the editor's own gesture handling.
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            // If the image's own inner Listener already fired (child fires first),
            // skip deselection — the touch is on the image itself.
            if (_suppressNextDeselect) {
              _suppressNextDeselect = false;
              return;
            }
            if (_selectedImageId != null && mounted) {
              setState(() => _selectedImageId = null);
            }
          },
          child: InteractiveViewer(
            panEnabled: false,
            scaleEnabled: !inDraw && _selectedImageId == null,
            minScale: 0.5,
            maxScale: 4.0,
            child: QuillEditor(
              key: ValueKey(_editorRebuildKey),
              controller: _qCtrl,
              focusNode: _focusNode,
              scrollController: _scrollCtrl,
              config: QuillEditorConfig(
                scrollPhysics: _selectedImageId != null
                    ? const NeverScrollableScrollPhysics()
                    : null,
                embedBuilders: [
                  _ImageEmbedBuilder(
                    images: _images,
                    selectedId: _selectedImageId,
                    onSelect: (id) {
                      final selecting = _selectedImageId != id;
                      setState(() =>
                          _selectedImageId = selecting ? id : null);
                      // Dismiss the keyboard when an image is selected
                      if (selecting) FocusScope.of(context).unfocus();
                    },
                    onDelete: (id) {
                      setState(() {
                        _images.remove(id);
                        _selectedImageId = null;
                      });
                      widget.onChanged(_serialize());
                    },
                    onChanged: (id, w, h, r) {
                      _images[id]?['width'] = w;
                      _images[id]?['height'] = h;
                      _images[id]?['rotation'] = r;
                      widget.onChanged(_serialize());
                    },
                    onDragY: (id, dy) => _handleImageDrag(id, dy),
                    onDragEnd: () => _imgReorderAccum = 0.0,
                    onPointerDown: () => _suppressNextDeselect = true,
                  ),
                ],
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 200),
                placeholder: 'Write something…',
                autoFocus: false,
                expands: false,
                showCursor: !inDraw,
                enableInteractiveSelection: !inDraw,
              ),
            ),
          ),
        ),

        // Drawing canvas (always rendered, IgnorePointer so editor still works)
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _PagePainter(strokes: _strokes, current: _currentStroke),
              ),
            ),
          ),
        ),

        // Draw-mode input capture
        if (inDraw)
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: _onUp,
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Color _colorFromHex(String hex) {
    try {
      return Color(
          int.parse(hex.replaceAll('0x', '').replaceAll('#', 'FF'), radix: 16));
    } catch (_) {
      return Colors.black;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image embed builder for flutter_quill
// ─────────────────────────────────────────────────────────────────────────────

class _ImageEmbedBuilder extends EmbedBuilder {
  final Map<String, Map<String, dynamic>> images;
  final String? selectedId;
  final void Function(String id) onSelect;
  final void Function(String id) onDelete;
  final void Function(String id, double w, double h, double r) onChanged;
  final void Function(String id, double dy)? onDragY;
  final VoidCallback? onDragEnd;
  final VoidCallback? onPointerDown;

  _ImageEmbedBuilder({
    required this.images,
    required this.selectedId,
    required this.onSelect,
    required this.onDelete,
    required this.onChanged,
    this.onDragY,
    this.onDragEnd,
    this.onPointerDown,
  });

  @override
  String get key => BlockEmbed.imageType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final id = embedContext.node.value.data as String;
    final img = images[id];
    if (img == null) return const SizedBox(height: 8);

    return _InlineImageBlock(
      key: ValueKey(id),
      data: img['data'] as String? ?? '',
      width: (img['width'] as num?)?.toDouble() ?? 160.0,
      height: (img['height'] as num?)?.toDouble() ?? 120.0,
      rotation: (img['rotation'] as num?)?.toDouble() ?? 0.0,
      selected: selectedId == id,
      onTap: () => onSelect(id),
      onDelete: () => onDelete(id),
      onChanged: (w, h, r) => onChanged(id, w, h, r),
      onDragY: onDragY != null ? (dy) => onDragY!(id, dy) : null,
      onDragEnd: onDragEnd,
      onPointerDown: onPointerDown,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline image block — tap to select, 8 resize handles + rotation knob
// ─────────────────────────────────────────────────────────────────────────────

enum _HandleType { tl, t, tr, r, br, b, bl, l, rotate }

class _InlineImageBlock extends StatefulWidget {
  final String data;
  final double width, height, rotation;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final void Function(double w, double h, double r) onChanged;
  final ValueChanged<double>? onDragY;
  final VoidCallback? onDragEnd;
  final VoidCallback? onPointerDown;

  const _InlineImageBlock({
    super.key,
    required this.data,
    required this.width,
    required this.height,
    required this.rotation,
    required this.selected,
    required this.onTap,
    required this.onDelete,
    required this.onChanged,
    this.onDragY,
    this.onDragEnd,
    this.onPointerDown,
  });

  @override
  State<_InlineImageBlock> createState() => _InlineImageBlockState();
}

class _InlineImageBlockState extends State<_InlineImageBlock> {
  late double _w, _h, _r;
  double _startW = 0, _startH = 0, _startR = 0;
  Offset _startFinger = Offset.zero;
  Offset _centerGlobal = Offset.zero;
  // _imgKey is on the inner SizedBox (_w x _h) so localToGlobal correctly
  // accounts for the ancestor Transform.rotate when computing the center.
  final _imgKey = GlobalKey();

  // True while any handle (resize or rotate) owns a pointer.
  // Prevents the outer body-drag GestureDetector from stealing the gesture.
  bool _handleActive = false;

  // Body-drag (reorder) state
  double _bodyDragY = 0.0;
  bool _bodyDragging = false;

  static const double _hSize         = 16;
  static const double _hTarget       = 36;
  static const double _rotHTarget    = 56.0; // larger touch area for rotate handle
  static const double _rotDotSize    = 28.0; // visual dot diameter
  static const double _rotHandleGap  = 10.0; // line connecting handle to image top
  static const double _minDim        = 40;

  @override
  void initState() {
    super.initState();
    _w = widget.width;
    _h = widget.height;
    _r = widget.rotation;
  }

  @override
  void didUpdateWidget(_InlineImageBlock old) {
    super.didUpdateWidget(old);
    _w = widget.width;
    _h = widget.height;
    _r = widget.rotation;
  }

  // ── Rotated bounding box ──────────────────────────────────────────────────

  // Width / height of the axis-aligned box that fully contains the rotated image.
  double get _rotW => _w * math.cos(_r).abs() + _h * math.sin(_r).abs();
  double get _rotH => _w * math.sin(_r).abs() + _h * math.cos(_r).abs();

  // Convert screen-space delta → image-local-space delta
  Offset _imgDelta(Offset d) {
    final c = math.cos(-_r), s = math.sin(-_r);
    return Offset(c * d.dx - s * d.dy, s * d.dx + c * d.dy);
  }

  // ── Resize — raw pointer events (no gesture arena, no conflict) ───────────

  void _onResizeDown(PointerDownEvent e) {
    _startW = _w;
    _startH = _h;
    _startFinger = e.position;
    _handleActive = true;
  }
  void _onResizeUp(PointerUpEvent e)         => _handleActive = false;
  void _onResizeCancel(PointerCancelEvent e) => _handleActive = false;

  void _onCornerMove(PointerMoveEvent e, int sx) {
    final id     = _imgDelta(e.delta);
    final aspect = _startH / math.max(_startW, 1);
    final nw     = (_w + id.dx * sx).clamp(_minDim, 2000.0);
    setState(() { _w = nw; _h = nw * aspect; });
    widget.onChanged(_w, _h, _r);
  }

  void _onEdgeWMove(PointerMoveEvent e, int sx) {
    final id = _imgDelta(e.delta);
    setState(() => _w = (_w + id.dx * sx).clamp(_minDim, 2000.0));
    widget.onChanged(_w, _h, _r);
  }

  void _onEdgeHMove(PointerMoveEvent e, int sy) {
    final id = _imgDelta(e.delta);
    setState(() => _h = (_h + id.dy * sy).clamp(_minDim, 2000.0));
    widget.onChanged(_w, _h, _r);
  }

  // ── Rotate — raw pointer events ───────────────────────────────────────────

  void _onRotateDown(PointerDownEvent e) {
    _startR      = _r;
    _startFinger = e.position;
    _handleActive = true;
    // localToGlobal walks the render tree including the Transform.rotate ancestor,
    // so this correctly returns the visual center of the image in global coords.
    final box = _imgKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) _centerGlobal = box.localToGlobal(Offset(_w / 2, _h / 2));
  }

  void _onRotateMove(PointerMoveEvent e) {
    if (_centerGlobal == Offset.zero) return;
    final f     = e.position;
    final angle = math.atan2(f.dy - _centerGlobal.dy, f.dx - _centerGlobal.dx);
    final start = math.atan2(
        _startFinger.dy - _centerGlobal.dy, _startFinger.dx - _centerGlobal.dx);
    setState(() => _r = _startR + (angle - start));
    widget.onChanged(_w, _h, _r);
  }

  void _onRotateUp(PointerUpEvent e)         => _handleActive = false;
  void _onRotateCancel(PointerCancelEvent e) => _handleActive = false;

  // ── Handle widgets ────────────────────────────────────────────────────────

  Widget _resizeDot() => Container(
    width: _hSize,
    height: _hSize,
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.blue.shade600, width: 1.5),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
    ),
  );

  Widget _resizeHandle(_HandleType type) {
    final half = _hTarget / 2;
    double? left, right, top, bottom;
    void Function(PointerMoveEvent) onMove;

    if      (type == _HandleType.tl) { left = -half;       top    = -half;           onMove = (e) => _onCornerMove(e, -1); }
    else if (type == _HandleType.t)  { left = _w/2 - half; top    = -half;           onMove = (e) => _onEdgeHMove(e, -1); }
    else if (type == _HandleType.tr) { right = -half;       top    = -half;           onMove = (e) => _onCornerMove(e,  1); }
    else if (type == _HandleType.r)  { right = -half;       top    = _h/2 - half;    onMove = (e) => _onEdgeWMove(e,  1); }
    else if (type == _HandleType.br) { right = -half;       bottom = -half;           onMove = (e) => _onCornerMove(e,  1); }
    else if (type == _HandleType.b)  { left = _w/2 - half; bottom = -half;           onMove = (e) => _onEdgeHMove(e,  1); }
    else if (type == _HandleType.bl) { left = -half;       bottom = -half;           onMove = (e) => _onCornerMove(e, -1); }
    else                             { left = -half;       top    = _h/2 - half;    onMove = (e) => _onEdgeWMove(e, -1); } // l

    return Positioned(
      left: left, right: right, top: top, bottom: bottom,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onResizeDown,
        onPointerMove: onMove,
        onPointerUp:   _onResizeUp,
        onPointerCancel: _onResizeCancel,
        child: SizedBox(width: _hTarget, height: _hTarget, child: Center(child: _resizeDot())),
      ),
    );
  }

  // Rotate handle: large white dot + connecting line.
  // Returns a plain widget (not Positioned) — caller places it in a Column
  // ABOVE the image so it is always within the parent's hit-test bounds.
  Widget _rotateHandleWidget() {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown:   _onRotateDown,
      onPointerMove:   _onRotateMove,
      onPointerUp:     _onRotateUp,
      onPointerCancel: _onRotateCancel,
      child: SizedBox(
        width:  _rotHTarget,
        height: _rotHTarget + _rotHandleGap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // Large white dot with rotation icon
            SizedBox(
              width: _rotHTarget, height: _rotHTarget,
              child: Center(
                child: Container(
                  width: _rotDotSize, height: _rotDotSize,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue.shade400, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 6,
                          spreadRadius: 1, offset: Offset(0, 2)),
                    ],
                  ),
                  child: const Icon(Icons.refresh_rounded, size: 16, color: Colors.black54),
                ),
              ),
            ),
            // Connecting line (string) to the image selection border
            Expanded(
              child: Center(
                child: Container(width: 2, color: Colors.white.withOpacity(0.9)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes   = _decodeImg(widget.data);
    final sel     = widget.selected;
    final canDrag = sel && widget.onDragY != null;
    final rw = _rotW;
    final rh = _rotH;

    final imageWidget = bytes != null
        ? Image.memory(bytes, fit: BoxFit.fill, width: _w, height: _h, gaplessPlayback: true)
        : Container(
            color: Colors.grey.shade200,
            child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
          );

    // Inner box (actual _w x _h): holds image, selection border, resize handles.
    // Transform.rotate wraps this, so all handles are in image-local space.
    final innerBox = SizedBox(
      key: _imgKey,
      width: _w,
      height: _h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: imageWidget),
          if (sel) Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue.shade400, width: 2),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (sel) ...[
            _resizeHandle(_HandleType.tl),
            _resizeHandle(_HandleType.t),
            _resizeHandle(_HandleType.tr),
            _resizeHandle(_HandleType.r),
            _resizeHandle(_HandleType.br),
            _resizeHandle(_HandleType.b),
            _resizeHandle(_HandleType.bl),
            _resizeHandle(_HandleType.l),
          ],
        ],
      ),
    );

    // Outer block: Column with rotate handle ABOVE the image when selected.
    // The handle lives in normal layout flow so Flutter's hit-test always
    // reaches it (a Positioned with negative top is outside bounds and
    // is never hit-testable — that was the original bug).
    final imageStack = SizedBox(
      width: rw,
      height: rh,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Transform.rotate(angle: _r, alignment: Alignment.center, child: innerBox),
          if (sel) Positioned(
            top: -10, right: -10,
            child: GestureDetector(
              onTap: widget.onDelete,
              child: Container(
                width: 22, height: 22,
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );

    final outerBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Rotate handle row — only shown when selected.
        // Centering within rw keeps the dot above the image centre.
        if (sel) SizedBox(
          width: rw,
          height: _rotHTarget + _rotHandleGap,
          child: Center(child: _rotateHandleWidget()),
        ),
        imageStack,
      ],
    );

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => widget.onPointerDown?.call(),
      child: GestureDetector(
        onTap: () {
          if (_handleActive) return;
          widget.onTap();
        },
        // Body drag — accumulates delta visually; commits reorder on release.
        // Never calls onDragY mid-drag so _rebuildDocument never fires while
        // the gesture is live (the original cause of grip-loss).
        onPanStart: canDrag ? (d) {
          if (_handleActive) return;
          setState(() { _bodyDragY = 0.0; _bodyDragging = true; });
        } : null,
        onPanUpdate: canDrag ? (d) {
          if (!_bodyDragging) return;
          setState(() => _bodyDragY += d.delta.dy);
        } : null,
        onPanEnd: canDrag ? (_) {
          if (!_bodyDragging) return;
          final totalDy = _bodyDragY;
          setState(() { _bodyDragY = 0.0; _bodyDragging = false; });
          widget.onDragY!(totalDy);   // total dy → _handleImageDrag → block steps
          widget.onDragEnd?.call();
        } : null,
        onPanCancel: canDrag ? () {
          setState(() { _bodyDragY = 0.0; _bodyDragging = false; });
          widget.onDragEnd?.call();
        } : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Transform.translate(
            offset: _bodyDragging ? Offset(0, _bodyDragY) : Offset.zero,
            child: Opacity(
              opacity: _bodyDragging ? 0.65 : 1.0,
              child: outerBlock,
            ),
          ),
        ),
      ),
    );
  }

  static Uint8List? _decodeImg(String data) {
    try {
      final idx = data.indexOf(',');
      return base64Decode(idx >= 0 ? data.substring(idx + 1) : data);
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pen / eraser size popup
// ─────────────────────────────────────────────────────────────────────────────

class _SizePopup extends StatefulWidget {
  final double left, top, initialValue;
  final bool isEraser;
  final Color penColor;
  final ValueChanged<double> onChanged;
  final VoidCallback onDismiss;

  const _SizePopup({
    required this.left,
    required this.top,
    required this.initialValue,
    required this.isEraser,
    required this.penColor,
    required this.onChanged,
    required this.onDismiss,
  });

  @override
  State<_SizePopup> createState() => _SizePopupState();
}

class _SizePopupState extends State<_SizePopup> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onDismiss,
          child: const SizedBox.expand(),
        ),
        Positioned(
          left: widget.left,
          top: widget.top,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).cardColor,
            child: Container(
              width: 210,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(widget.isEraser ? 'Eraser size' : 'Pen size',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Container(
                        width: (_value / 24 * 22).clamp(3.0, 22.0),
                        height: (_value / 24 * 22).clamp(3.0, 22.0),
                        decoration: BoxDecoration(
                          color: widget.isEraser
                              ? Colors.grey.shade400
                              : widget.penColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _value,
                    min: 1,
                    max: 24,
                    onChanged: (v) {
                      setState(() => _value = v);
                      widget.onChanged(v);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Eraser icon
// ─────────────────────────────────────────────────────────────────────────────

class _EraserIcon extends StatelessWidget {
  final Color color;
  const _EraserIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: Center(
        child: Container(
          width: 20,
          height: 13,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            border: Border.all(color: color, width: 1.5),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            children: [
              const Spacer(),
              Container(
                width: 7,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.45),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(1),
                    bottomRight: Radius.circular(1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drawing painter
// ─────────────────────────────────────────────────────────────────────────────

class _Stroke {
  final List<Offset> points;
  final Color color;
  final double width;
  final bool isEraser;
  _Stroke(
      {required this.points,
      required this.color,
      required this.width,
      required this.isEraser});
}

class _PagePainter extends CustomPainter {
  final List<_Stroke> strokes;
  final _Stroke? current;

  const _PagePainter({required this.strokes, this.current});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.saveLayer(rect, Paint());
    for (final stroke in [...strokes, if (current != null) current!]) {
      _draw(canvas, stroke);
    }
    canvas.restore();
  }

  void _draw(Canvas canvas, _Stroke stroke) {
    if (stroke.points.length < 2) {
      canvas.drawCircle(
        stroke.points.first,
        stroke.width / 2,
        Paint()
          ..color = stroke.color
          ..blendMode =
              stroke.isEraser ? BlendMode.clear : BlendMode.srcOver,
      );
      return;
    }
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver;

    final path = Path()
      ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (int i = 1; i < stroke.points.length - 1; i++) {
      final mid = Offset(
        (stroke.points[i].dx + stroke.points[i + 1].dx) / 2,
        (stroke.points[i].dy + stroke.points[i + 1].dy) / 2,
      );
      path.quadraticBezierTo(
          stroke.points[i].dx, stroke.points[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(stroke.points.last.dx, stroke.points.last.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PagePainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Content migration: v1.0 blocks / v2.0 / plain-text → passthrough map
// NotePageEditorState._parseContent handles the actual quill conversion.
// ─────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> migrateNoteContent(String rawContent) {
  int seq = 0;
  String uid() => '${DateTime.now().microsecondsSinceEpoch}_${seq++}';

  try {
    final parsed = jsonDecode(rawContent);
    if (parsed is! Map) throw const FormatException('not a map');

    final version = parsed['version'] as String?;
    // quill-1.0 and '1.0' are handled natively by NotePageEditor._parseContent.
    // '2.0' is the legacy paragraph format also handled there.
    // Pass all three through without any transformation here so that
    // _parseContent / _migrateV1BlocksToQuill can correctly extract images.
    if (version == 'quill-1.0' || version == '1.0' || version == '2.0') {
      return Map<String, dynamic>.from(parsed);
    }

    // ── Legacy: very old format with no version field ─────────────────────────
    final blocks = parsed['blocks'] as List? ?? [];
    final paras = <Map<String, dynamic>>[];
    final images = <Map<String, dynamic>>[];

    for (final block in blocks) {
      final b = block as Map;
      final type = b['type'] as String? ?? '';
      switch (type) {
        case 'paragraph':
          final text = (b['content'] as List? ?? [])
              .map((s) => (s as Map)['text'] ?? '')
              .join();
          paras.add({'id': uid(), 'style': 'normal', 'text': text, 'checked': false});
        case 'heading':
          final text = (b['content'] as List? ?? [])
              .map((s) => (s as Map)['text'] ?? '')
              .join();
          final lvl = b['level'] as int? ?? 1;
          paras.add({'id': uid(), 'style': 'h$lvl', 'text': text, 'checked': false});
        case 'quote':
          final text = (b['content'] as List? ?? [])
              .map((s) => (s as Map)['text'] ?? '')
              .join();
          paras.add({'id': uid(), 'style': 'normal', 'text': '❝ $text', 'checked': false});
        case 'code':
          paras.add({'id': uid(), 'style': 'normal', 'text': b['code'] ?? '', 'checked': false});
        case 'list':
          for (final item in (b['items'] as List? ?? [])) {
            final text = (item as Map)['text'] as String? ?? '';
            final style = (b['ordered'] as bool? ?? false) ? 'numbered' : 'bullet';
            paras.add({'id': uid(), 'style': style, 'text': text, 'checked': false});
          }
        case 'checklist':
          for (final item in (b['items'] as List? ?? [])) {
            final m = item as Map;
            paras.add({
              'id': uid(),
              'style': 'checklist',
              'text': m['text'] as String? ?? '',
              'checked': m['checked'] as bool? ?? false,
            });
          }
        case 'image':
        case 'drawing':
          images.add({
            'id': uid(),
            'data': b['data'] as String? ?? '',
            'x': 20.0,
            'y': 100.0 + images.length * 20.0,
            'width': (b['displayWidth'] as num?)?.toDouble() ?? 260.0,
            'rotation': 0.0,
          });
      }
    }

    if (paras.isEmpty) {
      paras.add({'id': uid(), 'style': 'normal', 'text': '', 'checked': false});
    }
    return {'version': '2.0', 'paragraphs': paras, 'images': images, 'strokes': <Map>[]};
  } catch (_) {
    // Plain text / markdown
    final lines =
        rawContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final paras = <Map<String, dynamic>>[];
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) continue;
      String style = 'normal';
      String text = t;
      if (t.startsWith('### ')) {
        style = 'h3';
        text = t.substring(4);
      } else if (t.startsWith('## ')) {
        style = 'h2';
        text = t.substring(3);
      } else if (t.startsWith('# ')) {
        style = 'h1';
        text = t.substring(2);
      } else if (t.startsWith('- [x] ') || t.startsWith('- [X] ')) {
        style = 'checklist';
        text = t.substring(6);
      } else if (t.startsWith('- [ ] ')) {
        style = 'checklist';
        text = t.substring(6);
      } else if (t.startsWith('- ') || t.startsWith('* ')) {
        style = 'bullet';
        text = t.substring(2);
      } else if (RegExp(r'^\d+\. ').hasMatch(t)) {
        style = 'numbered';
        text = t.replaceFirst(RegExp(r'^\d+\. '), '');
      }
      paras.add({'id': uid(), 'style': style, 'text': text, 'checked': false});
    }
    if (paras.isEmpty) {
      paras.add({'id': uid(), 'style': 'normal', 'text': '', 'checked': false});
    }
    return {'version': '2.0', 'paragraphs': paras, 'images': <Map>[], 'strokes': <Map>[]};
  }
}
