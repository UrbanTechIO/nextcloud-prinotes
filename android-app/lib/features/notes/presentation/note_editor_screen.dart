import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../data/local/database.dart';
import '../providers/notes_provider.dart';
import 'widgets/note_page_editor.dart';
import 'widgets/note_lock_screen.dart';
import 'widgets/note_options_sheet.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final int? noteId;
  final int? initialNotebookId;

  const NoteEditorScreen({super.key, this.noteId, this.initialNotebookId});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  Note? _note;
  final _titleCtrl = TextEditingController();
  Map<String, dynamic> _content = {};
  final _editorKey = GlobalKey<NotePageEditorState>();
  Timer? _saveTimer;
  String _saveStatus = 'saved';
  bool _loading = true;
  bool _unlocked = false;
  bool _isSaving = false;
  bool _hasChanges = false;
  List<Tag> _tags = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.noteId == null) {
      // New note
      final repo = ref.read(notesRepoProvider);
      _note = await repo.createNote(notebookId: widget.initialNotebookId);
      _content = migrateNoteContent('');
      setState(() => _loading = false);
      return;
    }

    final db = ref.read(databaseProvider);
    _note = await db.getNoteById(widget.noteId!);
    if (_note == null) {
      if (mounted) context.pop();
      return;
    }

    _titleCtrl.text = _note!.title;
    _tags = await db.getTagsForNote(_note!.id);
    _content = migrateNoteContent(_note!.content);

    setState(() {
      _loading = false;
      _unlocked = !(_note?.isLocked ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Show lock screen if note is locked and not yet unlocked
    if (_note?.isLocked == true && !_unlocked) {
      return NoteLockScreen(
        note: _note!,
        onUnlocked: () => setState(() => _unlocked = true),
      );
    }

    final noteColor = _parseColor(_note?.color);

    return Scaffold(
      backgroundColor: noteColor?.withOpacity(0.08) ?? Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: noteColor?.withOpacity(0.12) ?? Theme.of(context).appBarTheme.backgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _saveNow();
            context.pop();
          },
        ),
        title: _SaveStatusIndicator(status: _saveStatus),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Attach',
            onPressed: _showAttachSheet,
          ),
          TextButton(
            onPressed: _addTag,
            child: const Text('+ Tag'),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showOptions(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // ── Title ──────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: TextField(
                  controller: _titleCtrl,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => _debouncedSave(),
                ),
              ),

              // ── Samsung Notes–style page editor ────────────────────────────
              Expanded(
                child: NotePageEditor(
                  key: _editorKey,
                  content: _content,
                  onChanged: (content) {
                    _content = content;
                    _debouncedSave();
                  },
                ),
              ),
            ],
          ),

          // ── Tag pills — top-right overlay ──────────────────────────────────
          if (_tags.isNotEmpty)
            Positioned(
              top: 8,
              right: 8,
              child: _buildTagColumn(),
            ),
        ],
      ),
    );
  }

  // ── Tag column ─────────────────────────────────────────────────────────────

  Widget _buildTagColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: _tags.map((tag) {
        Color? c;
        if (tag.color != null) {
          try {
            c = Color(int.parse(tag.color!.replaceAll('#', 'FF'), radix: 16));
          } catch (_) {}
        }
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: (c ?? Colors.blue).withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: (c ?? Colors.blue).withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tag.name,
                  style: TextStyle(
                      fontSize: 11,
                      color: c ?? Colors.blue,
                      fontWeight: FontWeight.w500)),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _removeTag(tag),
                child: Icon(Icons.close, size: 11, color: c ?? Colors.blue),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Attachment sheet ────────────────────────────────────────────────────────

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              _attachRow([
                _AttachOption(Icons.photo_library_outlined, 'Image',       () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); }),
                _AttachOption(Icons.camera_alt_outlined,    'Camera',      () { Navigator.pop(ctx); _pickImage(ImageSource.camera);  }),
                _AttachOption(Icons.mic_outlined,           'Voice',       () { Navigator.pop(ctx); _comingSoon('Voice recording');   }),
              ]),
              const SizedBox(height: 8),
              _attachRow([
                _AttachOption(Icons.picture_as_pdf_outlined,'PDF',         () { Navigator.pop(ctx); _comingSoon('PDF viewer');        }),
                _AttachOption(Icons.document_scanner_outlined,'Scan',      () { Navigator.pop(ctx); _comingSoon('Document scan');     }),
                _AttachOption(Icons.table_chart_outlined,   'Table',       () { Navigator.pop(ctx); _comingSoon('Table');             }),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachRow(List<_AttachOption> opts) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: opts.map((o) => InkWell(
      onTap: o.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(o.icon, size: 26, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 6),
            Text(o.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    )).toList(),
  );

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 80);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    final dataUrl = 'data:${file.mimeType ?? 'image/jpeg'};base64,${base64Encode(bytes)}';
    _editorKey.currentState?.addImage(dataUrl);
    _debouncedSave();
  }

  void _comingSoon(String feature) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature — coming soon'), duration: const Duration(seconds: 2)),
    );
  }

  // ── Tags ───────────────────────────────────────────────────────────────────

  Future<void> _addTag() async {
    final allTags =
        await ref.read(databaseProvider).select(ref.read(databaseProvider).tags).get();
    final existing = _tags.map((t) => t.id).toSet();
    final available = allTags.where((t) => !existing.contains(t.id)).toList();

    if (!mounted) return;
    final selected = await showModalBottomSheet<Tag>(
      context: context,
      builder: (_) => _TagPicker(tags: available),
    );
    if (selected != null) {
      setState(() => _tags.add(selected));
      _debouncedSave();
    }
  }

  void _removeTag(Tag tag) {
    setState(() => _tags.removeWhere((t) => t.id == tag.id));
    _debouncedSave();
  }

  // ── Options sheet ──────────────────────────────────────────────────────────

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => NoteOptionsSheet(
        note: _note!,
        onChanged: (updatedNote) {
          setState(() => _note = updatedNote);
        },
      ),
    );
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  void _debouncedSave() {
    if (!mounted) return;
    _hasChanges = true;
    setState(() => _saveStatus = 'saving');
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1200), _saveNow);
  }

  Future<void> _saveNow() async {
    if (_note == null || _isSaving || !_hasChanges) return;
    _isSaving = true;
    _saveTimer?.cancel();
    _saveTimer = null;

    try {
      final contentStr = jsonEncode(_content);
      final preview = _extractPreview(_content);

      await ref.read(notesRepoProvider).updateNote(
        _note!,
        title: _titleCtrl.text,
        content: contentStr,
        tagIds: _tags.map((t) => t.id).toList(),
      );

      // Write preview separately (not part of notesRepo.updateNote)
      await (ref.read(databaseProvider).update(ref.read(databaseProvider).notes)
            ..where((n) => n.id.equals(_note!.id)))
          .write(NotesCompanion(preview: Value(preview)));

      if (mounted) setState(() => _saveStatus = 'saved');
    } catch (e) {
      if (mounted) setState(() => _saveStatus = 'error');
    } finally {
      _isSaving = false;
    }
  }

  /// Extracts a short plain-text preview from quill-1.0 or v2.0 content.
  String _extractPreview(Map<String, dynamic> content) {
    final buf = StringBuffer();
    if (content['version'] == 'quill-1.0') {
      final delta = content['delta'] as List? ?? [];
      for (final op in delta) {
        final insert = (op as Map)['insert'];
        if (insert is String) buf.write(insert.replaceAll('\n', ' '));
        if (buf.length > 300) break;
      }
    } else {
      final paras = content['paragraphs'] as List? ?? [];
      for (final p in paras) {
        final text = (p as Map)['text'] as String? ?? '';
        if (text.isNotEmpty) { buf.write(text); buf.write(' '); }
        if (buf.length > 300) break;
      }
    }
    final text = buf.toString().trim();
    return text.substring(0, text.length.clamp(0, 300));
  }

  Color? _parseColor(String? hex) {
    if (hex == null) return null;
    try {
      return Color(int.parse(hex.replaceAll('#', 'FF'), radix: 16));
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    // Only flush to DB if the user actually made changes
    if (_hasChanges) _saveNow();
    _titleCtrl.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Save status indicator
// ─────────────────────────────────────────────────────────────────────────────

class _SaveStatusIndicator extends StatelessWidget {
  final String status;
  const _SaveStatusIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'saving':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text('Saving...',
              style: TextStyle(fontSize: 13, color: Colors.orange.shade400)),
        ]);
      case 'error':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 16, color: Colors.red.shade400),
          const SizedBox(width: 4),
          Text('Save failed',
              style: TextStyle(fontSize: 13, color: Colors.red.shade400)),
        ]);
      default:
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_done_outlined, size: 16, color: Colors.green.shade400),
          const SizedBox(width: 4),
          Text('Saved',
              style: TextStyle(fontSize: 13, color: Colors.green.shade400)),
        ]);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tag picker bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AttachOption {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AttachOption(this.icon, this.label, this.onTap);
}

class _TagPicker extends StatelessWidget {
  final List<Tag> tags;
  const _TagPicker({required this.tags});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select a tag',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 12),
          if (tags.isEmpty)
            const Text('No tags available. Create tags from the sidebar.')
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: tags
                    .map((tag) => ListTile(
                          title: Text(tag.name),
                          onTap: () => Navigator.pop(context, tag),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}
