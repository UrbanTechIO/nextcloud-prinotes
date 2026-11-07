import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/glass.dart';
import '../../../data/local/database.dart';
import '../../auth/providers/auth_provider.dart';
import '../../notes/providers/notes_provider.dart' show NoteFilter, noteFilterProvider;
import '../data/todo_repository.dart';
import '../providers/todo_provider.dart';
import 'todo_list_form.dart';

class TodoDrawer extends ConsumerWidget {
  const TodoDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(todosProvider).valueOrNull ?? [];
    final lists = ref.watch(todoListsProvider).valueOrNull ?? [];
    final view = ref.watch(todoViewProvider);
    final auth = ref.watch(authStateProvider);
    final today = localDateString();

    int count(TodoViewSel s) => openTodosFor(todos, lists, s, today).length;
    final top = lists.where((l) => l.parentLocalId == null).toList();

    void goView(TodoViewSel s) {
      ref.read(todoViewProvider.notifier).state = s;
      Navigator.pop(context);
    }

    void goNotes(NoteFilter f) {
      ref.read(noteFilterProvider.notifier).state = f;
      Navigator.pop(context);
      context.go('/');
    }

    Widget smart(String key, String label, IconData icon, Color color) => ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 28, right: 16),
          leading: Icon(icon, size: 18, color: color),
          title: Text(label),
          trailing: Text('${count(TodoViewSel.smart(key))}', style: const TextStyle(fontSize: 12)),
          selected: view.smart == key,
          onTap: () => goView(TodoViewSel.smart(key)),
        );

    Widget listTile(TodoList l, {required bool child}) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: child ? 52 : 28, right: 4),
          leading: CircleAvatar(radius: 6, backgroundColor: todoColor(l.color)),
          title: Text(l.title),
          selected: view.listId == l.id,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (!child && !l.isSystem)
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'New sub-category',
                onPressed: () => showTodoListDialog(context, ref, parentLocalId: l.id),
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16),
              tooltip: 'Edit',
              onPressed: () => showTodoListDialog(context, ref, list: l),
            ),
            Text('${count(TodoViewSel.list(l.id))}', style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
          ]),
          onTap: () => goView(TodoViewSel.list(l.id)),
        );

    final glass = ref.watch(glassProvider);
    return Drawer(
      width: 280,
      child: GlassDrawerBody(child: Column(children: [
        UserAccountsDrawerHeader(
          accountName: Text(auth.username ?? 'PriNotes', style: const TextStyle(fontWeight: FontWeight.w600)),
          accountEmail: Text(auth.serverUrl ?? ''),
          currentAccountPicture: const CircleAvatar(
            backgroundColor: Colors.white,
            child: Icon(Icons.task_alt_rounded, color: Color(0xFF2563EB), size: 32),
          ),
          decoration: BoxDecoration(
            color: glass.glass ? const Color(0xFF2563EB).withOpacity(0.4) : const Color(0xFF2563EB),
          ),
        ),
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            ListTile(leading: const Icon(Icons.notes_rounded), title: const Text('All Notes'), onTap: () => goNotes(const NoteFilter())),
            ListTile(leading: const Icon(Icons.archive_outlined), title: const Text('Archived'), onTap: () => goNotes(const NoteFilter(archived: true))),
            ListTile(
              leading: const Icon(Icons.task_alt_rounded),
              title: const Text('To-Do'),
              selected: true,
              trailing: Text('${count(const TodoViewSel.smart('all'))}'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Trash'), onTap: () => goNotes(const NoteFilter(trashed: true))),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.checklist_rounded),
              title: const Text('To-Do lists'),
              trailing: IconButton(
                icon: const Icon(Icons.add, size: 20),
                tooltip: 'New category',
                onPressed: () => showTodoListDialog(context, ref),
              ),
            ),
            smart('today', 'Today', Icons.today_rounded, const Color(0xFF8B5CF6)),
            smart('important', 'Important', Icons.star_rounded, Colors.amber),
            smart('planned', 'Planned', Icons.event_rounded, const Color(0xFF22C55E)),
            smart('all', 'All tasks', Icons.all_inbox_rounded, Colors.grey),
            const Divider(indent: 28),
            for (final l in top) ...[
              listTile(l, child: false),
              for (final c in lists.where((x) => x.parentLocalId == l.id)) listTile(c, child: true),
            ],
          ]),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Settings'),
          onTap: () {
            Navigator.pop(context);
            context.push('/settings');
          },
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
      ])),
    );
  }
}
