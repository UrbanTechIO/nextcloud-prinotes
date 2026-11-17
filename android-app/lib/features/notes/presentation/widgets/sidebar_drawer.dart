import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/notes_provider.dart';
import '../../../../core/widgets/app_sidebar.dart';
import '../../../../data/local/database.dart';
import '../../../auth/providers/auth_provider.dart';

Color? _parseColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  try {
    return Color(int.parse(hex.replaceAll('#', 'FF'), radix: 16));
  } catch (_) {
    return null;
  }
}

/// The notes sidebar: a Notes / To-Do switch, tiles for All notes and Archived, notebooks as rows,
/// tags as chips, and a bottom bar. Deleting a notebook or tag is a long-press, not an X on every row.
class SidebarDrawer extends ConsumerWidget {
  const SidebarDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(noteFilterProvider);
    final notebooks = ref.watch(notebooksProvider).valueOrNull ?? [];
    final tags = ref.watch(tagsProvider).valueOrNull ?? [];

    final isAll = filter.notebookId == null && filter.tagId == null && !filter.trashed && !filter.archived;

    return AppSidebar(
      mode: SidebarMode.notes,
      onNotes: () => Navigator.pop(context),
      onTodo: () {
        Navigator.pop(context);
        context.go('/todo');
      },
      content: [
        SidebarTileGrid(tiles: [
          SidebarTile(icon: Icons.notes_rounded, label: 'All notes', selected: isAll, onTap: () => _selectAll(ref, context)),
          SidebarTile(icon: Icons.archive_outlined, label: 'Archived', selected: filter.archived, onTap: () => _selectArchived(ref, context)),
        ]),
        SidebarSection('Notebooks', onAdd: () => _createNotebook(context, ref)),
        for (final nb in notebooks) _notebookRow(nb, filter, ref, context),
        SidebarSection('Tags', onAdd: () => _createTag(context, ref)),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final tag in tags) _tagChip(tag, filter, ref, context),
          ]),
        ),
        const SizedBox(height: 4),
      ],
      bar: [
        SidebarBarItem(Icons.delete_outline_rounded, 'Trash', () => _selectTrash(ref, context)),
        SidebarBarItem(Icons.settings_outlined, 'Settings', () {
          Navigator.pop(context);
          context.push('/settings');
        }),
        SidebarBarItem(Icons.lock_outline, 'Lock', () {
          Navigator.pop(context);
          ref.read(authStateProvider.notifier).lock();
          context.go('/lock');
        }),
      ],
    );
  }

  Widget _notebookRow(Notebook nb, NoteFilter filter, WidgetRef ref, BuildContext context) {
    return SidebarRow(
      leading: SidebarDot(_parseColor(nb.color) ?? Colors.grey.shade500),
      title: Text(nb.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      selected: filter.notebookId == nb.id,
      onTap: () {
        ref.read(noteFilterProvider.notifier).update((f) => NoteFilter(notebookId: nb.id));
        Navigator.pop(context);
      },
      onLongPress: () => showSidebarActions(context, title: nb.title, actions: [
        SidebarAction(Icons.delete_outline, 'Delete', () => _deleteNotebook(context, ref, nb), danger: true),
      ]),
    );
  }

  Widget _tagChip(Tag tag, NoteFilter filter, WidgetRef ref, BuildContext context) {
    return SidebarChip(
      label: '#${tag.name}',
      color: _parseColor(tag.color),
      selected: filter.tagId == tag.id,
      onTap: () {
        ref.read(noteFilterProvider.notifier).update((f) => NoteFilter(tagId: tag.id));
        Navigator.pop(context);
      },
      onLongPress: () => showSidebarActions(context, title: '#${tag.name}', actions: [
        SidebarAction(Icons.delete_outline, 'Delete', () => _deleteTag(context, ref, tag), danger: true),
      ]),
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
