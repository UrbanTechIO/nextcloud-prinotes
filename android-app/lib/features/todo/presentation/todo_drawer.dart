import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_sidebar.dart';
import '../../../data/local/database.dart';
import '../../auth/providers/auth_provider.dart';
import '../../notes/providers/notes_provider.dart' show NoteFilter, noteFilterProvider, trashCountProvider;
import '../data/todo_repository.dart';
import '../providers/todo_provider.dart';
import 'todo_list_form.dart';

/// The To-Do sidebar: a Notes / To-Do switch, four smart-list tiles with counts, the categories as
/// plain rows (sub-categories fold under their parent), and a bottom bar.
class TodoDrawer extends ConsumerStatefulWidget {
  const TodoDrawer({super.key});

  @override
  ConsumerState<TodoDrawer> createState() => _TodoDrawerState();
}

class _TodoDrawerState extends ConsumerState<TodoDrawer> {
  final _expanded = <int>{};

  @override
  Widget build(BuildContext context) {
    final todos = ref.watch(todosProvider).valueOrNull ?? [];
    final lists = ref.watch(todoListsProvider).valueOrNull ?? [];
    final view = ref.watch(todoViewProvider);
    final today = localDateString();

    int count(TodoViewSel s) => openTodosFor(todos, lists, s, today).length;
    final top = lists.where((l) => l.parentLocalId == null).toList();
    List<TodoList> kids(TodoList l) => lists.where((c) => c.parentLocalId == l.id).toList();

    void goView(TodoViewSel s) {
      ref.read(todoViewProvider.notifier).state = s;
      Navigator.pop(context);
    }

    void goNotes(NoteFilter f) {
      ref.read(noteFilterProvider.notifier).state = f;
      Navigator.pop(context);
      context.go('/');
    }

    Widget smart(String key, String label, IconData icon, Color color) => SidebarTile(
          icon: icon,
          iconColor: color,
          label: label,
          count: count(TodoViewSel.smart(key)),
          selected: view.smart == key,
          onTap: () => goView(TodoViewSel.smart(key)),
        );

    void actions(TodoList l) => showSidebarActions(context, title: l.title, actions: [
          SidebarAction(Icons.edit_outlined, 'Edit', () => showTodoListDialog(context, ref, list: l)),
          if (l.parentLocalId == null && !l.isSystem)
            SidebarAction(Icons.add, 'Add sub-category', () => showTodoListDialog(context, ref, parentLocalId: l.id)),
        ]);

    Widget row(TodoList l, {required bool child}) {
      final children = child ? <TodoList>[] : kids(l);
      final open = _expanded.contains(l.id) || (view.listId != null && children.any((c) => c.id == view.listId));
      Widget? arrow;
      if (!child) {
        arrow = children.isEmpty
            ? const SizedBox(width: 20)
            : InkResponse(
                radius: 18,
                onTap: () => setState(() => open ? _expanded.remove(l.id) : _expanded.add(l.id)),
                child: Icon(open ? Icons.expand_more : Icons.chevron_right, size: 20),
              );
      }
      return SidebarRow(
        indent: child ? 30 : 0,
        leading: Row(mainAxisSize: MainAxisSize.min, children: [
          if (arrow != null) ...[arrow, const SizedBox(width: 4)],
          SidebarDot(todoColor(l.color)),
        ]),
        title: Text(
          l.title + (!child && !open && children.isNotEmpty ? '  · ${children.length} sub' : ''),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        count: count(TodoViewSel.list(l.id)),
        selected: view.listId == l.id,
        onTap: () => goView(TodoViewSel.list(l.id)),
        onLongPress: () => actions(l),
      );
    }

    return AppSidebar(
      mode: SidebarMode.todo,
      onNotes: () => goNotes(const NoteFilter()),
      onTodo: () => Navigator.pop(context),
      content: [
        SidebarTileGrid(tiles: [
          smart('today', 'Today', Icons.today_rounded, const Color(0xFF8B5CF6)),
          smart('important', 'Important', Icons.star_rounded, Colors.amber),
          smart('planned', 'Planned', Icons.event_rounded, const Color(0xFF22C55E)),
          smart('all', 'All tasks', Icons.all_inbox_rounded, Colors.grey),
        ]),
        SidebarSection('Categories', onAdd: () => showTodoListDialog(context, ref)),
        for (final l in top) ...[
          row(l, child: false),
          if (_expanded.contains(l.id) || (view.listId != null && kids(l).any((c) => c.id == view.listId)))
            for (final c in kids(l)) row(c, child: true),
        ],
        const SizedBox(height: 4),
      ],
      bar: [
        SidebarBarItem(Icons.archive_outlined, 'Archive', () => goNotes(const NoteFilter(archived: true))),
        SidebarBarItem(Icons.delete_outline_rounded, 'Trash', () => goNotes(const NoteFilter(trashed: true)),
            count: ref.watch(trashCountProvider).valueOrNull ?? 0),
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
}
