import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/notes_provider.dart';
import '../../../../data/local/database.dart';
import '../../../auth/providers/auth_provider.dart';

class SidebarDrawer extends ConsumerWidget {
  const SidebarDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(noteFilterProvider);
    final notebooks = ref.watch(notebooksProvider).valueOrNull ?? [];
    final tags = ref.watch(tagsProvider).valueOrNull ?? [];
    final authState = ref.watch(authStateProvider);

    return Drawer(
      width: 260,
      child: Column(
        children: [
          // Header
          UserAccountsDrawerHeader(
            accountName: Text(authState.username ?? 'PriNotes',
              style: const TextStyle(fontWeight: FontWeight.w600)),
            accountEmail: Text(authState.serverUrl ?? ''),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.note_alt_rounded, color: Color(0xFF2563EB), size: 32),
            ),
            decoration: const BoxDecoration(color: Color(0xFF2563EB)),
          ),

          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // All Notes
                ListTile(
                  leading: const Icon(Icons.notes_rounded),
                  title: const Text('All Notes'),
                  selected: filter.notebookId == null && filter.tagId == null
                    && !filter.trashed && !filter.archived,
                  onTap: () => _selectAll(ref, context),
                ),
                ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: const Text('Archived'),
                  selected: filter.archived,
                  onTap: () => _selectArchived(ref, context),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Trash'),
                  selected: filter.trashed,
                  onTap: () => _selectTrash(ref, context),
                ),

                const Divider(),

                // Notebooks
                ListTile(
                  leading: const Icon(Icons.menu_book_rounded),
                  title: const Text('Notebooks'),
                  trailing: IconButton(
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: () => _createNotebook(context, ref),
                  ),
                ),
                ...notebooks.map((nb) => _buildNotebookTile(nb, filter, ref, context)),

                const Divider(),

                // Tags
                ListTile(
                  leading: const Icon(Icons.label_outline_rounded),
                  title: const Text('Tags'),
                  trailing: IconButton(
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: () => _createTag(context, ref),
                  ),
                ),
                ...tags.map((tag) => _buildTagTile(tag, filter, ref, context)),
              ],
            ),
          ),

          // Bottom actions
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () { Navigator.pop(context); context.push('/settings'); },
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Lock app'),
            onTap: () {
              Navigator.pop(context);
              ref.read(authStateProvider.notifier).lock();
              context.go('/lock');
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildNotebookTile(Notebook nb, NoteFilter filter, WidgetRef ref, BuildContext context) {
    Color? color;
    if (nb.color != null) {
      try { color = Color(int.parse(nb.color!.replaceAll('#', 'FF'), radix: 16)); } catch (_) {}
    }
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 32, right: 8),
      leading: CircleAvatar(
        radius: 8,
        backgroundColor: color ?? Colors.grey.shade400,
      ),
      title: Text(nb.title, style: const TextStyle(fontSize: 14)),
      selected: filter.notebookId == nb.id,
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 16, color: Colors.grey),
        tooltip: 'Delete notebook',
        onPressed: () => _deleteNotebook(context, ref, nb),
      ),
      onTap: () {
        ref.read(noteFilterProvider.notifier).update(
          (f) => NoteFilter(notebookId: nb.id),
        );
        Navigator.pop(context);
      },
    );
  }

  Future<void> _deleteNotebook(BuildContext context, WidgetRef ref, Notebook nb) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete notebook?'),
        content: Text('Delete "${nb.title}"? Notes inside will not be deleted, they will just become unassigned.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    // If we were filtering by this notebook, reset filter
    final filter = ref.read(noteFilterProvider);
    if (filter.notebookId == nb.id) {
      ref.read(noteFilterProvider.notifier).state = const NoteFilter();
    }
    await ref.read(notesRepoProvider).deleteNotebook(nb.id);
  }

  Widget _buildTagTile(Tag tag, NoteFilter filter, WidgetRef ref, BuildContext context) {
    Color? color;
    if (tag.color != null) {
      try { color = Color(int.parse(tag.color!.replaceAll('#', 'FF'), radix: 16)); } catch (_) {}
    }
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 32, right: 8),
      leading: Icon(Icons.label, size: 16, color: color ?? Colors.grey),
      title: Text('#${tag.name}', style: const TextStyle(fontSize: 14)),
      selected: filter.tagId == tag.id,
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 16, color: Colors.grey),
        tooltip: 'Delete tag',
        onPressed: () => _deleteTag(context, ref, tag),
      ),
      onTap: () {
        ref.read(noteFilterProvider.notifier).update(
          (f) => NoteFilter(tagId: tag.id),
        );
        Navigator.pop(context);
      },
    );
  }

  Future<void> _deleteTag(BuildContext context, WidgetRef ref, Tag tag) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete tag?'),
        content: Text('Delete "#${tag.name}"? This will remove it from all notes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    // If we were filtering by this tag, reset filter
    final filter = ref.read(noteFilterProvider);
    if (filter.tagId == tag.id) {
      ref.read(noteFilterProvider.notifier).state = const NoteFilter();
    }
    await ref.read(notesRepoProvider).deleteTag(tag.id);
  }

  void _selectAll(WidgetRef ref, BuildContext context) {
    ref.read(noteFilterProvider.notifier).state = const NoteFilter();
    Navigator.pop(context);
  }

  void _selectArchived(WidgetRef ref, BuildContext context) {
    ref.read(noteFilterProvider.notifier).state = const NoteFilter(archived: true);
    Navigator.pop(context);
  }

  void _selectTrash(WidgetRef ref, BuildContext context) {
    ref.read(noteFilterProvider.notifier).state = const NoteFilter(trashed: true);
    Navigator.pop(context);
  }

  Future<void> _createNotebook(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _NotebookDialog(),
    );
    if (result != null) {
      await ref.read(notesRepoProvider).createNotebook(
        title: result['title']!,
        color: result['color'],
      );
    }
  }

  Future<void> _createTag(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _TagDialog(),
    );
    if (result != null) {
      await ref.read(notesRepoProvider).createTag(
        name: result['name']!,
        color: result['color'],
      );
    }
  }
}

class _NotebookDialog extends StatefulWidget {
  const _NotebookDialog();
  @override
  State<_NotebookDialog> createState() => _NotebookDialogState();
}

class _NotebookDialogState extends State<_NotebookDialog> {
  final _ctrl = TextEditingController();
  String? _color;
  final _colors = ['#ef4444','#f97316','#eab308','#22c55e','#3b82f6','#8b5cf6','#ec4899','#6b7280'];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Notebook'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _ctrl, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          Row(
            children: _colors.map((c) {
              final color = Color(int.parse(c.replaceAll('#', 'FF'), radix: 16));
              return GestureDetector(
                onTap: () => setState(() => _color = c),
                child: Container(
                  width: 28, height: 28,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _color == c ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _ctrl.text.isEmpty ? null : () => Navigator.pop(context, {'title': _ctrl.text, 'color': _color ?? ''}),
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _TagDialog extends StatefulWidget {
  const _TagDialog();
  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  final _ctrl = TextEditingController();
  String? _color;
  final _colors = ['#ef4444','#f97316','#eab308','#22c55e','#3b82f6','#8b5cf6','#ec4899','#6b7280'];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Tag'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _ctrl, decoration: const InputDecoration(labelText: 'Tag name')),
          const SizedBox(height: 12),
          Row(
            children: _colors.map((c) {
              final color = Color(int.parse(c.replaceAll('#', 'FF'), radix: 16));
              return GestureDetector(
                onTap: () => setState(() => _color = c),
                child: Container(
                  width: 28, height: 28,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: _color == c ? Colors.white : Colors.transparent, width: 2),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _ctrl.text.isEmpty ? null : () => Navigator.pop(context, {'name': _ctrl.text, 'color': _color ?? ''}),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
