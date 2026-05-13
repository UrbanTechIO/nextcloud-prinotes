import 'dart:convert';
import 'dart:math' show max;
import 'package:flutter/material.dart';

// ── BlockEditor ───────────────────────────────────────────────────────────────

/// Free-form canvas block editor.
/// Every block has absolute (x, y) coordinates stored in its data map.
/// Drag the handle bar at the top of any block to move it freely.
/// Tap on empty canvas to create a new text block at that location.
class BlockEditor extends StatefulWidget {
  final List<Map<String, dynamic>> blocks;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  const BlockEditor({super.key, required this.blocks, required this.onChanged});

  @override
  State<BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends State<BlockEditor> {
  late List<Map<String, dynamic>> _blocks;
  String? _selectedUid;
  Offset? _lastTapDown;
  int _uidSeq = 0;

  @override
  void initState() {
    super.initState();
    int seq = 0;
    _blocks = widget.blocks.map((b) {
      final block = Map<String, dynamic>.from(b);
      if (!block.containsKey('_uid')) block['_uid'] = _uid();
      if (!block.containsKey('_x')) block['_x'] = 20.0;
      if (!block.containsKey('_y')) block['_y'] = 20.0 + seq * 80.0;
      seq++;
      return block;
    }).toList();
    if (_blocks.isEmpty) _blocks = [_makeParagraph(x: 20, y: 20)];
  }

  String _uid() => '${DateTime.now().microsecondsSinceEpoch}_${_uidSeq++}';

  @override
  void didUpdateWidget(BlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Absorb blocks added externally (e.g. from the toolbar in note_editor_screen).
    // Compare by _uid — any block in widget.blocks that has no matching uid in
    // our internal list is a new insertion from outside.
    if (widget.blocks.length > _blocks.length) {
      final knownUids = {for (final b in _blocks) b['_uid'] as String?};
      double nextY = 20.0;
      for (final b in _blocks) {
        final y = (b['_y'] as num?)?.toDouble() ?? 0;
        if (y + 80 > nextY) nextY = y + 80;
      }
      for (final b in widget.blocks) {
        final uid = b['_uid'] as String?;
        if (!knownUids.contains(uid)) {
          final block = Map<String, dynamic>.from(b);
          block['_uid'] = _uid();
          block['_x'] = 20.0;
          block['_y'] = nextY;
          nextY += 80;
          _blocks.add(block);
        }
      }
      // Notify parent so it holds the positioned version
      widget.onChanged(_blocks);
    }
  }

  Map<String, dynamic> _makeParagraph({double x = 20, double y = 20}) => {
    'type': 'paragraph',
    'content': [],
    '_uid': _uid(),
    '_x': x,
    '_y': y,
  };

  void _update(int idx, Map<String, dynamic> updated) {
    setState(() => _blocks[idx] = updated);
    widget.onChanged(_blocks);
  }

  void _delete(int idx) {
    final uid = _blocks[idx]['_uid'] as String?;
    setState(() {
      _blocks.removeAt(idx);
      if (_blocks.isEmpty) _blocks.add(_makeParagraph());
      if (_selectedUid == uid) _selectedUid = null;
    });
    widget.onChanged(_blocks);
  }

  void _insertBelow(int idx) {
    final baseY = (_blocks[idx]['_y'] as num?)?.toDouble() ?? 0;
    setState(() => _blocks.insert(idx + 1, _makeParagraph(x: 20, y: baseY + 70)));
    widget.onChanged(_blocks);
  }

  double _canvasHeight() {
    double h = 500;
    for (final b in _blocks) {
      final y = (b['_y'] as num?)?.toDouble() ?? 0;
      h = max(h, y + 300);
    }
    return h + 200;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final cw = constraints.maxWidth;
      final bw = cw - 40; // default block width: nearly full width with margins

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _lastTapDown = d.localPosition,
        onTap: () {
          // onTap only fires when no child widget consumed the tap (i.e., empty canvas area)
          final pos = _lastTapDown;
          _lastTapDown = null;
          if (pos == null) return;
          // Deselect if something is selected; otherwise create a new block
          if (_selectedUid != null) {
            setState(() => _selectedUid = null);
            return;
          }
          setState(() {
            _blocks.add(_makeParagraph(x: 20.0, y: max(0.0, pos.dy - 16.0)));
          });
          widget.onChanged(_blocks);
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 120),
          child: SizedBox(
            width: cw,
            height: _canvasHeight(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (int i = 0; i < _blocks.length; i++)
                  _CanvasBlock(
                    key: ValueKey(_blocks[i]['_uid']),
                    index: i,
                    block: _blocks[i],
                    defaultWidth: bw,
                    isSelected: _blocks[i]['_uid'] == _selectedUid,
                    onSelect: (uid) => setState(
                      () => _selectedUid = (_selectedUid == uid) ? null : uid,
                    ),
                    onUpdate: (b) => _update(i, b),
                    onDelete: () => _delete(i),
                    onInsertBelow: () => _insertBelow(i),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

// ── Canvas Block wrapper ──────────────────────────────────────────────────────
// Handles absolute positioning, dragging via handle bar, and block toolbar.

class _CanvasBlock extends StatefulWidget {
  final int index;
  final Map<String, dynamic> block;
  final double defaultWidth;
  final bool isSelected;
  final ValueChanged<String?> onSelect;
  final ValueChanged<Map<String, dynamic>> onUpdate;
  final VoidCallback onDelete;
  final VoidCallback onInsertBelow;

  const _CanvasBlock({
    super.key,
    required this.index,
    required this.block,
    required this.defaultWidth,
    required this.isSelected,
    required this.onSelect,
    required this.onUpdate,
    required this.onDelete,
    required this.onInsertBelow,
  });

  @override
  State<_CanvasBlock> createState() => _CanvasBlockState();
}

class _CanvasBlockState extends State<_CanvasBlock> {
  late double _x, _y;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _x = (widget.block['_x'] as num?)?.toDouble() ?? 20.0;
    _y = (widget.block['_y'] as num?)?.toDouble() ?? 20.0;
  }

  double get _blockWidth {
    // Image / drawing blocks use their own stored width
    final type = widget.block['type'] as String? ?? '';
    if (type == 'image' || type == 'drawing') {
      final saved = (widget.block['displayWidth'] as num?)?.toDouble();
      return (saved != null && saved > 0) ? saved : widget.defaultWidth;
    }
    return widget.defaultWidth;
  }

  void _onPan(DragUpdateDetails d) {
    setState(() {
      _x = max(0.0, _x + d.delta.dx);
      _y = max(0.0, _y + d.delta.dy);
    });
    widget.onUpdate({...widget.block, '_x': _x, '_y': _y});
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.block['type'] as String? ?? 'paragraph';
    final uid = widget.block['_uid'] as String?;
    final isSelected = widget.isSelected;

    return Positioned(
      left: _x,
      top: _y,
      width: _blockWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Handle bar (drag + label + delete) ──────────────────────────
          SizedBox(
            height: 22,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Drag handle
                GestureDetector(
                  onPanStart: (_) => setState(() => _dragging = true),
                  onPanUpdate: _onPan,
                  onPanEnd: (_) => setState(() => _dragging = false),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 30,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _dragging
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 14,
                      color: _dragging ? Colors.white : Colors.grey.shade500,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _typeLabel(type),
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey.shade400,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                // Delete button
                GestureDetector(
                  onTap: widget.onDelete,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 14, color: Colors.grey.shade400),
                  ),
                ),
              ],
            ),
          ),
          // ── Block content ───────────────────────────────────────────────
          _buildContent(type, uid, isSelected),
        ],
      ),
    );
  }

  Widget _buildContent(String type, String? uid, bool isSelected) {
    switch (type) {
      case 'heading':
        return _HeadingBlock(
          block: widget.block,
          onUpdate: widget.onUpdate,
          onInsertAfter: widget.onInsertBelow,
          onDelete: widget.onDelete,
        );
      case 'checklist':
        return _ChecklistBlock(block: widget.block, onUpdate: widget.onUpdate);
      case 'list':
        return _ListBlock(block: widget.block, onUpdate: widget.onUpdate);
      case 'image':
        return _ImageBlock(
          block: widget.block,
          onUpdate: widget.onUpdate,
          onDelete: widget.onDelete,
          isSelected: isSelected,
          onSelect: () => widget.onSelect(isSelected ? null : uid),
        );
      case 'drawing':
        return _DrawingBlock(
          block: widget.block,
          onUpdate: widget.onUpdate,
          onDelete: widget.onDelete,
          isSelected: isSelected,
          onSelect: () => widget.onSelect(isSelected ? null : uid),
        );
      case 'divider':
        // Consume tap so empty-canvas logic doesn't fire here
        return GestureDetector(
          onTap: () {},
          behavior: HitTestBehavior.opaque,
          child: const Divider(thickness: 2),
        );
      case 'code':
        return _CodeBlock(block: widget.block, onUpdate: widget.onUpdate);
      case 'quote':
        return _QuoteBlock(
          block: widget.block,
          onUpdate: widget.onUpdate,
          onInsertAfter: widget.onInsertBelow,
          onDelete: widget.onDelete,
        );
      default:
        return _ParagraphBlock(
          block: widget.block,
          onUpdate: widget.onUpdate,
          onInsertAfter: widget.onInsertBelow,
          onDelete: widget.onDelete,
        );
    }
  }

  String _typeLabel(String type) => switch (type) {
    'heading'   => 'HEADING',
    'checklist' => 'CHECKLIST',
    'list'      => 'LIST',
    'image'     => 'IMAGE',
    'drawing'   => 'DRAWING',
    'code'      => 'CODE',
    'quote'     => 'QUOTE',
    'divider'   => 'DIVIDER',
    _           => 'TEXT',
  };
}

// ── Paragraph ─────────────────────────────────────────────────────────────────

class _ParagraphBlock extends StatefulWidget {
  final Map<String, dynamic> block;
  final ValueChanged<Map<String, dynamic>> onUpdate;
  final VoidCallback onInsertAfter;
  final VoidCallback onDelete;

  const _ParagraphBlock({
    required this.block,
    required this.onUpdate,
    required this.onInsertAfter,
    required this.onDelete,
  });

  @override
  State<_ParagraphBlock> createState() => _ParagraphBlockState();
}

class _ParagraphBlockState extends State<_ParagraphBlock> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _extractText(widget.block['content']));
  }

  String _extractText(dynamic content) {
    if (content is! List) return '';
    return content.map((s) => (s as Map)['text'] ?? '').join();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      textDirection: TextDirection.ltr,
      maxLines: null,
      decoration: const InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        hintText: 'Write something...',
        contentPadding: EdgeInsets.symmetric(vertical: 4),
      ),
      style: const TextStyle(fontSize: 16, height: 1.6),
      onChanged: (text) {
        widget.onUpdate({...widget.block, 'content': [{'text': text}]});
      },
      onSubmitted: (_) => widget.onInsertAfter(),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}

// ── Heading ───────────────────────────────────────────────────────────────────

class _HeadingBlock extends StatefulWidget {
  final Map<String, dynamic> block;
  final ValueChanged<Map<String, dynamic>> onUpdate;
  final VoidCallback onInsertAfter;
  final VoidCallback onDelete;

  const _HeadingBlock({
    required this.block,
    required this.onUpdate,
    required this.onInsertAfter,
    required this.onDelete,
  });

  @override
  State<_HeadingBlock> createState() => _HeadingBlockState();
}

class _HeadingBlockState extends State<_HeadingBlock> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final content = widget.block['content'];
    final text = content is List
        ? content.map((s) => (s as Map)['text'] ?? '').join()
        : '';
    _ctrl = TextEditingController(text: text);
  }

  @override
  Widget build(BuildContext context) {
    final level = widget.block['level'] as int? ?? 1;
    final style = switch (level) {
      1 => const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.3),
      2 => const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.3),
      _ => const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.3),
    };

    return TextField(
      controller: _ctrl,
      textDirection: TextDirection.ltr,
      maxLines: null,
      decoration: InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        hintText: 'Heading $level',
        contentPadding: EdgeInsets.symmetric(vertical: level == 1 ? 8 : 4),
      ),
      style: style,
      onChanged: (text) {
        widget.onUpdate({...widget.block, 'content': [{'text': text}]});
      },
      onSubmitted: (_) => widget.onInsertAfter(),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}

// ── Checklist ─────────────────────────────────────────────────────────────────

class _ChecklistBlock extends StatefulWidget {
  final Map<String, dynamic> block;
  final ValueChanged<Map<String, dynamic>> onUpdate;
  const _ChecklistBlock({required this.block, required this.onUpdate});

  @override
  State<_ChecklistBlock> createState() => _ChecklistBlockState();
}

class _ChecklistBlockState extends State<_ChecklistBlock> {
  late List<Map<String, dynamic>> _items;
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _items = ((widget.block['items'] as List?) ?? [])
        .map((i) => Map<String, dynamic>.from(i as Map))
        .toList();
    if (_items.isEmpty) _items = [{'text': '', 'checked': false}];
    _controllers = _items
        .map((item) => TextEditingController(text: item['text'] as String? ?? ''))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  void _toggle(int i) {
    setState(() => _items[i]['checked'] = !(_items[i]['checked'] as bool? ?? false));
    widget.onUpdate({...widget.block, 'items': _items});
  }

  void _addItem() {
    setState(() {
      _items.add({'text': '', 'checked': false});
      _controllers.add(TextEditingController());
    });
    widget.onUpdate({...widget.block, 'items': _items});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._items.asMap().entries.map((e) {
          final i = e.key;
          final item = e.value;
          final checked = item['checked'] as bool? ?? false;
          return Row(
            children: [
              Checkbox(
                value: checked,
                onChanged: (_) => _toggle(i),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              Expanded(
                child: TextField(
                  controller: _controllers[i],
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    decoration: checked ? TextDecoration.lineThrough : null,
                    color: checked ? Colors.grey : null,
                  ),
                  onChanged: (text) {
                    _items[i]['text'] = text;
                    widget.onUpdate({...widget.block, 'items': _items});
                  },
                  onSubmitted: (_) => _addItem(),
                ),
              ),
            ],
          );
        }),
        TextButton.icon(
          onPressed: _addItem,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add item', style: TextStyle(fontSize: 13)),
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8)),
        ),
      ],
    );
  }
}

// ── List ──────────────────────────────────────────────────────────────────────

class _ListBlock extends StatefulWidget {
  final Map<String, dynamic> block;
  final ValueChanged<Map<String, dynamic>> onUpdate;
  const _ListBlock({required this.block, required this.onUpdate});

  @override
  State<_ListBlock> createState() => _ListBlockState();
}

class _ListBlockState extends State<_ListBlock> {
  late List<Map<String, dynamic>> _items;
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _items = ((widget.block['items'] as List?) ?? [])
        .map((i) => Map<String, dynamic>.from(i as Map))
        .toList();
    if (_items.isEmpty) _items = [{'text': ''}];
    _controllers = _items
        .map((item) => TextEditingController(text: item['text'] as String? ?? ''))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  void _addItem() {
    setState(() {
      _items.add({'text': ''});
      _controllers.add(TextEditingController());
    });
    widget.onUpdate({...widget.block, 'items': _items});
  }

  @override
  Widget build(BuildContext context) {
    final ordered = widget.block['ordered'] as bool? ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._items.asMap().entries.map((e) {
          final i = e.key;
          final item = e.value;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, right: 8, left: 4),
                child: Text(
                  ordered ? '${i + 1}.' : '•',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _controllers[i],
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 15, height: 1.6),
                  onChanged: (text) {
                    _items[i]['text'] = text;
                    widget.onUpdate({...widget.block, 'items': _items});
                  },
                  onSubmitted: (_) => _addItem(),
                ),
              ),
            ],
          );
        }),
        TextButton.icon(
          onPressed: _addItem,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add item', style: TextStyle(fontSize: 13)),
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8)),
        ),
      ],
    );
  }
}

// ── Image ─────────────────────────────────────────────────────────────────────

class _ImageBlock extends StatefulWidget {
  final Map<String, dynamic> block;
  final ValueChanged<Map<String, dynamic>> onUpdate;
  final VoidCallback onDelete;
  final bool isSelected;
  final VoidCallback onSelect;

  const _ImageBlock({
    required this.block,
    required this.onUpdate,
    required this.onDelete,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  State<_ImageBlock> createState() => _ImageBlockState();
}

class _ImageBlockState extends State<_ImageBlock> {
  late TextEditingController _captionCtrl;

  @override
  void initState() {
    super.initState();
    _captionCtrl = TextEditingController(
      text: widget.block['caption'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.block['data'] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (data.startsWith('data:'))
          GestureDetector(
            onTap: widget.onSelect,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.isSelected
                      ? Colors.blue.shade400
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  Uri.parse(data).data!.contentAsBytes(),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        TextField(
          controller: _captionCtrl,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            hintText: 'Caption...',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.zero,
          ),
          style: const TextStyle(fontSize: 13, color: Colors.grey),
          textAlign: TextAlign.center,
          onChanged: (text) => widget.onUpdate({...widget.block, 'caption': text}),
        ),
      ],
    );
  }
}

// ── Drawing ───────────────────────────────────────────────────────────────────

class _DrawingBlock extends StatefulWidget {
  final Map<String, dynamic> block;
  final ValueChanged<Map<String, dynamic>> onUpdate;
  final VoidCallback onDelete;
  final bool isSelected;
  final VoidCallback onSelect;

  const _DrawingBlock({
    required this.block,
    required this.onUpdate,
    required this.onDelete,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  State<_DrawingBlock> createState() => _DrawingBlockState();
}

class _DrawingBlockState extends State<_DrawingBlock> {
  double _width = 280.0;
  double _height = 160.0;

  @override
  void initState() {
    super.initState();
    _initDimensions(widget.block);
  }

  @override
  void didUpdateWidget(_DrawingBlock old) {
    super.didUpdateWidget(old);
    if (old.block['data'] != widget.block['data']) {
      _initDimensions(widget.block);
    }
  }

  void _initDimensions(Map<String, dynamic> block) {
    final savedW = (block['displayWidth'] as num?)?.toDouble();
    final savedH = (block['displayHeight'] as num?)?.toDouble();
    if (savedW != null && savedH != null) {
      _width = savedW;
      _height = savedH;
      return;
    }
    final storedW = (block['width'] as num?)?.toDouble();
    final storedH = (block['height'] as num?)?.toDouble();
    if (storedW != null && storedH != null && storedW > 0 && storedH > 0) {
      const targetW = 280.0;
      final scale = targetW / storedW;
      _width = targetW;
      _height = (storedH * scale).clamp(80.0, 350.0);
    }
  }

  void _resize(double dw, double dh) {
    setState(() {
      _width = (_width + dw).clamp(80.0, 600.0);
      _height = (_height + dh).clamp(60.0, 500.0);
    });
    widget.onUpdate({
      ...widget.block,
      'displayWidth': _width,
      'displayHeight': _height,
    });
  }

  Widget _cornerHandle({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required void Function(DragUpdateDetails) onPanUpdate,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: GestureDetector(
        onPanUpdate: onPanUpdate,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.blue.shade500,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.block['data'] as String? ?? '';
    final bgColorStr = widget.block['bgColor'] as String? ?? 'white';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = bgColorStr == 'dark'
        ? const Color(0xFF1E293B)
        : bgColorStr == 'system'
            ? (isDark ? const Color(0xFF1E293B) : Colors.white)
            : Colors.white;

    const double pad = 20.0;
    final isSelected = widget.isSelected;

    return Center(
      child: SizedBox(
        width: _width + pad * 2,
        height: _height + pad * 2 + (isSelected ? 24.0 : 0.0),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: pad,
              left: pad,
              child: GestureDetector(
                onTap: widget.onSelect,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _width,
                  height: _height,
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: Border.all(
                      color: isSelected
                          ? Colors.blue.shade400
                          : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: data.startsWith('data:')
                        ? Image.memory(
                            Uri.parse(data).data!.contentAsBytes(),
                            fit: BoxFit.contain,
                          )
                        : const Center(
                            child: Icon(Icons.draw, color: Colors.grey)),
                  ),
                ),
              ),
            ),
            if (isSelected) ...[
              // Corner resize handles
              _cornerHandle(
                top: pad - 16, left: pad - 16,
                onPanUpdate: (d) => _resize(-d.delta.dx, -d.delta.dy),
              ),
              _cornerHandle(
                top: pad - 16, right: pad - 16,
                onPanUpdate: (d) => _resize(d.delta.dx, -d.delta.dy),
              ),
              _cornerHandle(
                bottom: 24 + pad - 16, left: pad - 16,
                onPanUpdate: (d) => _resize(-d.delta.dx, d.delta.dy),
              ),
              _cornerHandle(
                bottom: 24 + pad - 16, right: pad - 16,
                onPanUpdate: (d) => _resize(d.delta.dx, d.delta.dy),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Code ──────────────────────────────────────────────────────────────────────

class _CodeBlock extends StatefulWidget {
  final Map<String, dynamic> block;
  final ValueChanged<Map<String, dynamic>> onUpdate;
  const _CodeBlock({required this.block, required this.onUpdate});

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.block['code'] as String? ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E293B)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Text(
              widget.block['language'] as String? ?? 'plain',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl,
              textDirection: TextDirection.ltr,
              maxLines: null,
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              style:
                  const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
              onChanged: (code) =>
                  widget.onUpdate({...widget.block, 'code': code}),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quote ─────────────────────────────────────────────────────────────────────

class _QuoteBlock extends StatefulWidget {
  final Map<String, dynamic> block;
  final ValueChanged<Map<String, dynamic>> onUpdate;
  final VoidCallback onInsertAfter;
  final VoidCallback onDelete;

  const _QuoteBlock({
    required this.block,
    required this.onUpdate,
    required this.onInsertAfter,
    required this.onDelete,
  });

  @override
  State<_QuoteBlock> createState() => _QuoteBlockState();
}

class _QuoteBlockState extends State<_QuoteBlock> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final content = widget.block['content'];
    final text = content is List
        ? content.map((s) => (s as Map)['text'] ?? '').join()
        : '';
    _ctrl = TextEditingController(text: text);
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            color: Theme.of(context).colorScheme.primary,
            margin: const EdgeInsets.symmetric(vertical: 4),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _ctrl,
              textDirection: TextDirection.ltr,
              maxLines: null,
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: 'Quote...',
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              style: TextStyle(
                fontSize: 16,
                height: 1.6,
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade600,
              ),
              onChanged: (text) {
                widget.onUpdate({
                  ...widget.block,
                  'content': [
                    {'text': text}
                  ],
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}
