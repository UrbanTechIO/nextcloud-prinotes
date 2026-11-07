import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/glass.dart';
import '../../../data/local/database.dart';
import '../data/todo_repository.dart';
import '../providers/todo_provider.dart';
import '../reminders/todo_reminders.dart';
import '../../notes/providers/notes_provider.dart' show databaseProvider;
import 'todo_detail_sheet.dart';
import 'todo_drawer.dart';
import 'todo_list_form.dart';
import 'todo_quick_add.dart';

class TodoScreen extends ConsumerStatefulWidget {
  const TodoScreen({super.key});
  @override
  ConsumerState<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends ConsumerState<TodoScreen> {
  bool _showFinished = false;
  final Set<int> _sel = {};
  bool get _selecting => _sel.isNotEmpty;

  void _toggleSel(int id) => setState(() => _sel.contains(id) ? _sel.remove(id) : _sel.add(id));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TodoReminders.requestPermissions();
      TodoEffects.syncSoon(ref.read(databaseProvider));
    });
  }

  String _title(TodoViewSel v, List<TodoList> lists) {
    switch (v.smart) {
      case 'today': return 'Today';
      case 'important': return 'Important';
      case 'planned': return 'Planned';
      case 'all': return 'All tasks';
    }
    return lists.where((l) => l.id == v.listId).firstOrNull?.title ?? 'To-Do';
  }

  @override
  Widget build(BuildContext context) {
    final todos = ref.watch(todosProvider).valueOrNull ?? [];
    final lists = ref.watch(todoListsProvider).valueOrNull ?? [];
    final view = ref.watch(todoViewProvider);
    final today = localDateString();
    final open = openTodosFor(todos, lists, view, today);
    final finished = finishedTodosFor(todos, lists, view, today);
    final showPath = view.smart != null || lists.any((l) => l.parentLocalId == view.listId);
    final repo = ref.read(todoRepositoryProvider);
    final glass = ref.watch(glassProvider);
    final topInset = GlassAppBar.bodyTopInset(context, glass);

    final visible = [...open, if (_showFinished) ...finished];
    // Selected tasks that disappeared (deleted elsewhere, sync) must not keep selection mode alive.
    _sel.removeWhere((id) => !todos.any((t) => t.id == id));

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_sel.clear);
      },
      child: Scaffold(
      extendBodyBehindAppBar: glass.glass,
      drawer: _selecting ? null : const TodoDrawer(),
      appBar: _selecting
          ? GlassAppBar(
              settings: glass,
              leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cancel', onPressed: () => setState(_sel.clear)),
              title: Text('${_sel.length} selected'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Select all',
                  onPressed: () => setState(() => _sel.addAll(visible.map((t) => t.id))),
                ),
                IconButton(
                  icon: const Icon(Icons.done_all),
                  tooltip: 'Mark finished',
                  onPressed: () => _bulkDone(todos),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: _bulkDelete,
                ),
              ],
            )
          : GlassAppBar(
        settings: glass,
        title: Text(_title(view, lists)),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Sync',
            onPressed: () => TodoEffects.syncSoon(ref.read(databaseProvider)),
          ),
          if (view.listId != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit category',
              onPressed: () {
                final l = lists.where((x) => x.id == view.listId).firstOrNull;
                if (l != null) showTodoListDialog(context, ref, list: l);
              },
            ),
        ],
      ),
      floatingActionButton: _selecting
          ? null
          : GlassFab(onPressed: () => showTodoQuickAdd(context, lists: lists, view: view)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(12, 8 + topInset, 12, 96),
        children: [
          if (open.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  switch (view.smart) {
                    'today' => 'Nothing due today.',
                    'important' => 'No starred tasks.',
                    'planned' => 'No tasks with a due date.',
                    _ => 'No open tasks. Tap + to add one.',
                  },
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          for (final t in open) _card(t, lists, showPath, repo),
          if (finished.isNotEmpty) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => setState(() => _showFinished = !_showFinished),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(children: [
                  Icon(_showFinished ? Icons.expand_more : Icons.chevron_right),
                  const SizedBox(width: 4),
                  Text('Finished (${finished.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            if (_showFinished)
              for (final t in finished) _card(t, lists, showPath, repo),
          ],
        ],
      ),
      ),
    );
  }

  Widget _card(Todo t, List<TodoList> lists, bool showPath, TodoRepository repo) => _TodoCard(
        key: ValueKey('card-${t.id}'),
        todo: t,
        path: showPath ? listPath(lists, t.listLocalId) : '',
        repo: repo,
        selecting: _selecting,
        selected: _sel.contains(t.id),
        onToggleSelect: () => _toggleSel(t.id),
      );

  Future<void> _bulkDone(List<Todo> all) async {
    final repo = ref.read(todoRepositoryProvider);
    final chosen = all.where((t) => _sel.contains(t.id)).toList();
    // If everything chosen is already finished, this reopens them instead.
    final finish = chosen.any((t) => !t.isDone);
    setState(_sel.clear);
    for (final t in chosen) {
      if (t.isDone != finish) await repo.setDone(t.id, finish);
    }
  }

  Future<void> _bulkDelete() async {
    final repo = ref.read(todoRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final ids = _sel.toList();
    setState(_sel.clear);
    final snaps = <Todo>[];
    for (final id in ids) {
      final snap = await repo.deleteTodo(id);
      if (snap != null) snaps.add(snap);
    }
    if (snaps.isEmpty) return;
    messenger.showSnackBar(SnackBar(
      content: Text(snaps.length == 1 ? 'Task deleted' : '${snaps.length} tasks deleted'),
      action: SnackBarAction(label: 'Undo', onPressed: () async {
        for (final s in snaps) {
          await repo.restoreTodo(s);
        }
      }),
    ));
  }

}

class _TodoCard extends ConsumerWidget {
  final Todo todo;
  final String path;
  final TodoRepository repo;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggleSelect;
  const _TodoCard({
    super.key,
    required this.todo,
    required this.path,
    required this.repo,
    required this.selecting,
    required this.selected,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final glass = ref.watch(glassProvider);
    final today = localDateString();
    final overdue = !todo.isDone && todo.dueDate != null && todo.dueDate!.compareTo(today) < 0;
    final steps = TodoStep.decode(todo.steps);
    final meta = <Widget>[
      if (path.isNotEmpty) _meta(path, scheme.onSurfaceVariant),
      if (todo.dueDate != null) _meta('📅 ${_dueText(todo.dueDate!, today)}', overdue ? Colors.redAccent : scheme.onSurfaceVariant),
      if (todo.remindAt != null && !todo.isDone) _meta('⏰ ${_time(todo.remindAt!)}', scheme.onSurfaceVariant),
      if (todo.repeatRule != null) _meta('🔁 ${todo.repeatRule}', scheme.onSurfaceVariant),
      if (steps.isNotEmpty) _meta('☑ ${steps.where((s) => s.done).length}/${steps.length}', scheme.onSurfaceVariant),
      if (todo.isDone && todo.doneAt != null) _meta('Done ${_time(todo.doneAt!)}', scheme.onSurfaceVariant),
    ];

    return Dismissible(
      key: ValueKey('todo-${todo.id}'),
      direction: selecting ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final snap = await repo.deleteTodo(todo.id);
        if (snap == null) return;
        messenger.showSnackBar(SnackBar(
          content: const Text('Task deleted'),
          action: SnackBarAction(label: 'Undo', onPressed: () => repo.restoreTodo(snap)),
        ));
      },
      child: _wrap(glass, scheme, Card(
        margin: glass.glass ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 4),
        color: glass.glass ? Colors.transparent : (selected ? scheme.primary.withValues(alpha: 0.18) : null),
        shape: glass.glass ? const RoundedRectangleBorder() : null,
        child: Opacity(
          opacity: todo.isDone ? 0.6 : 1,
          child: ListTile(
            onTap: selecting ? onToggleSelect : () => showTodoDetailSheet(context, todo.id),
            onLongPress: onToggleSelect,
            leading: GestureDetector(
              onTap: selecting ? onToggleSelect : () => repo.toggleDone(todo.id),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (selecting ? selected : todo.isDone) ? scheme.primary : Colors.transparent,
                  border: Border.all(color: (selecting ? selected : todo.isDone) ? scheme.primary : scheme.outline, width: 2),
                ),
                child: (selecting ? selected : todo.isDone) ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
              ),
            ),
            title: Text(todo.title, style: TextStyle(decoration: todo.isDone ? TextDecoration.lineThrough : null)),
            subtitle: meta.isEmpty ? null : Wrap(spacing: 10, runSpacing: 2, children: meta),
            trailing: IconButton(
              icon: Icon(todo.isImportant ? Icons.star_rounded : Icons.star_border_rounded, color: todo.isImportant ? Colors.amber : null),
              onPressed: () => repo.updateTodo(todo.id, TodosCompanion(isImportant: Value(!todo.isImportant))),
            ),
          ),
        ),
      )),
    );
  }

  /// In the glass themes the card is a pane of glass (tinted blue while selected); Classic keeps the Card as is.
  Widget _wrap(GlassSettings glass, ColorScheme scheme, Widget card) => glass.glass
      ? Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GlassPanel(
            radius: glass.liquid ? 18 : 12,
            tint: selected ? scheme.primary : null,
            child: card,
          ),
        )
      : card;

  Widget _meta(String s, Color c) => Text(s, style: TextStyle(fontSize: 11, color: c));

  String _time(int s) {
    final d = DateTime.fromMillisecondsSinceEpoch(s * 1000);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  String _dueText(String due, String today) {
    if (due == today) return 'Today';
    final t = DateTime.now();
    if (due == localDateString(t.add(const Duration(days: 1)))) return 'Tomorrow';
    if (due == localDateString(t.subtract(const Duration(days: 1)))) return 'Yesterday';
    return due;
  }
}
