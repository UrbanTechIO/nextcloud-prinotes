import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../data/local/database.dart';
import '../../providers/notes_provider.dart';

class NoteOptionsSheet extends ConsumerWidget {
  final Note note;
  final ValueChanged<Note> onChanged;

  const NoteOptionsSheet({super.key, required this.note, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vaultUnlocked = ref.watch(vaultUnlockedProvider);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          ListTile(
            leading: Icon(note.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
            title: Text(note.isPinned ? 'Unpin' : 'Pin note'),
            onTap: () async {
              Navigator.pop(context);
              await ref.read(notesRepoProvider).updateNote(note, isPinned: !note.isPinned);
              final db = ref.read(databaseProvider);
              final updated = await db.getNoteById(note.id);
              if (updated != null) onChanged(updated);
            },
          ),
          ListTile(
            leading: Icon(note.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
            title: Text(note.isArchived ? 'Unarchive' : 'Archive'),
            onTap: () async {
              Navigator.pop(context);
              await ref.read(notesRepoProvider).updateNote(note, isArchived: !note.isArchived);
              final db = ref.read(databaseProvider);
              final updated = await db.getNoteById(note.id);
              if (updated != null) onChanged(updated);
            },
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Note color'),
            onTap: () => _showColorPicker(context, ref),
          ),
          ListTile(
            leading: Icon(note.isLocked ? Icons.lock_open_outlined : Icons.lock_outlined),
            title: Text(note.isLocked ? 'Remove lock' : 'Lock note'),
            onTap: () => _showLockDialog(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.book_outlined),
            title: const Text('Move to notebook'),
            onTap: () => _showNotebookPicker(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share_outlined),
            title: const Text('Share note'),
            onTap: () async {
              Navigator.pop(context);
              final text = _buildShareText(note);
              await Share.share(
                text,
                subject: note.title.isNotEmpty ? note.title : 'Note',
              );
            },
          ),
          if (vaultUnlocked)
            ListTile(
              leading: Icon(note.isHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              title: Text(note.isHidden ? 'Unhide note' : 'Hide note'),
              onTap: () async {
                Navigator.pop(context);
                await ref.read(notesRepoProvider).setNoteHidden(note.id, hidden: !note.isHidden);
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Move to trash', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(context);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Move to trash?'),
                  content: const Text('This note will be moved to the trash. You can restore it later.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Move to trash', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;
              await ref.read(notesRepoProvider).trashNote(note.id);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Converts block-editor JSON to a plain-text string suitable for sharing.
  static String _buildShareText(Note note) {
    final buf = StringBuffer();
    if (note.title.isNotEmpty) {
      buf.writeln(note.title);
      buf.writeln();
    }
    try {
      final parsed = jsonDecode(note.content) as Map;
      final blocks = (parsed['blocks'] as List? ?? []);
      for (final block in blocks) {
        final b = block as Map;
        final type = b['type'] as String? ?? '';
        switch (type) {
          case 'heading':
          case 'paragraph':
          case 'quote':
            final content = b['content'];
            if (content is List) {
              final text = content.map((s) => (s as Map)['text'] ?? '').join();
              if (text.isNotEmpty) buf.writeln(text);
            }
            break;
          case 'code':
            final code = b['code'] as String? ?? '';
            if (code.isNotEmpty) buf.writeln(code);
            break;
          case 'list':
            final ordered = b['ordered'] == true;
            int idx = 1;
            for (final item in (b['items'] as List? ?? [])) {
              final text = (item as Map)['text'] ?? '';
              buf.writeln(ordered ? '$idx. $text' : '• $text');
              idx++;
            }
            break;
          case 'checklist':
            for (final item in (b['items'] as List? ?? [])) {
              final m = item as Map;
              final checked = m['checked'] == true;
              buf.writeln('${checked ? '☑' : '☐'} ${m['text'] ?? ''}');
            }
            break;
          case 'divider':
            buf.writeln('─────────────');
            break;
          case 'image':
            final caption = b['caption'] as String? ?? '';
            buf.writeln('[Image${caption.isNotEmpty ? ': $caption' : ''}]');
            break;
          case 'drawing':
            buf.writeln('[Drawing]');
            break;
        }
      }
    } catch (_) {
      buf.write(note.content);
    }
    return buf.toString().trim();
  }

  void _showNotebookPicker(BuildContext context, WidgetRef ref) {
    final notebooks = ref.read(notebooksProvider).valueOrNull ?? [];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to notebook'),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              // "No notebook" option
              ListTile(
                leading: const Icon(Icons.book_outlined),
                title: const Text('No notebook'),
                selected: note.notebookId == null,
                selectedColor: Colors.blue,
                onTap: () async {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                  final repo = ref.read(notesRepoProvider);
                  final db = ref.read(databaseProvider);
                  await repo.updateNote(note, clearNotebook: true);
                  final updated = await db.getNoteById(note.id);
                  if (updated != null) onChanged(updated);
                },
              ),
              const Divider(height: 1),
              ...notebooks.map((nb) {
                Color? c;
                if (nb.color != null) {
                  try { c = Color(int.parse(nb.color!.replaceAll('#', 'FF'), radix: 16)); } catch (_) {}
                }
                return ListTile(
                  leading: Icon(Icons.book, color: c),
                  title: Text(nb.title),
                  selected: note.notebookId == nb.id,
                  selectedColor: Colors.blue,
                  onTap: () async {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                    final repo = ref.read(notesRepoProvider);
                    final db = ref.read(databaseProvider);
                    await repo.updateNote(note, notebookId: nb.id);
                    final updated = await db.getNoteById(note.id);
                    if (updated != null) onChanged(updated);
                  },
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(BuildContext context, WidgetRef ref) {
    Color current = Colors.blue;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDlg) => AlertDialog(
          title: const Text('Note color'),
          content: BlockPicker(
            pickerColor: current,
            onColorChanged: (c) {
              current = c;
              setDlg(() {});
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final repo = ref.read(notesRepoProvider);
                final db = ref.read(databaseProvider);
                final hex = '#${current.value.toRadixString(16).substring(2)}';
                Navigator.pop(ctx);
                Navigator.pop(context);
                await repo.updateNote(note, color: hex);
                final updated = await db.getNoteById(note.id);
                if (updated != null) onChanged(updated);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLockDialog(BuildContext context, WidgetRef ref) {
    if (note.isLocked) {
      // Require the current PIN before removing the lock
      final pinCtrl = TextEditingController();
      String? errorMsg;
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx2, setDlg) => AlertDialog(
            title: const Text('Enter PIN to remove lock'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Current PIN'),
                ),
                if (errorMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final bytes = utf8.encode('${pinCtrl.text}:prinotes-salt');
                  final hash = sha256.convert(bytes).toString();
                  if (hash != note.lockPinHash) {
                    setDlg(() => errorMsg = 'Incorrect PIN');
                    return;
                  }
                  final repo = ref.read(notesRepoProvider);
                  final db = ref.read(databaseProvider);
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                  await repo.updateNote(note, isLocked: false, lockPinHash: null);
                  final updated = await db.getNoteById(note.id);
                  if (updated != null) onChanged(updated);
                },
                child: const Text('Remove lock'),
              ),
            ],
          ),
        ),
      );
    } else {
      final pinCtrl = TextEditingController();
      final confirmCtrl = TextEditingController();
      String? errorMsg;
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx2, setDlg) => AlertDialog(
            title: const Text('Lock note'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: const InputDecoration(labelText: 'PIN (4-8 digits)'),
                ),
                TextField(
                  controller: confirmCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: const InputDecoration(labelText: 'Confirm PIN'),
                ),
                if (errorMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (pinCtrl.text.length < 4) {
                    setDlg(() => errorMsg = 'PIN must be at least 4 digits');
                    return;
                  }
                  if (pinCtrl.text != confirmCtrl.text) {
                    setDlg(() => errorMsg = 'PINs do not match');
                    return;
                  }
                  final repo = ref.read(notesRepoProvider);
                  final db = ref.read(databaseProvider);
                  final bytes = utf8.encode('${pinCtrl.text}:prinotes-salt');
                  final hash = sha256.convert(bytes).toString();
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                  await repo.updateNote(note, isLocked: true, lockPinHash: hash);
                  final updated = await db.getNoteById(note.id);
                  if (updated != null) onChanged(updated);
                },
                child: const Text('Lock'),
              ),
            ],
          ),
        ),
      );
    }
  }
}
