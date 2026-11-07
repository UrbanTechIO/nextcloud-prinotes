import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/local/database.dart';
import '../../../data/remote/api_client.dart';
import '../../notes/providers/notes_provider.dart' show databaseProvider;
import '../../sync/sync_service.dart';
import '../data/todo_repository.dart';
import '../reminders/todo_reminders.dart';
import '../widget/todo_widget_bridge.dart';

/// Side effects after any To-Do change: alarms, widget snapshot, background sync.
class TodoEffects {
  static bool _syncing = false;

  static Future<void> refresh(AppDatabase db) async {
    // Include soft-deleted rows so their alarms are cancelled too.
    final all = await db.select(db.todos).get();
    await TodoReminders.rescheduleAll(all);
    await TodoWidgetBridge.publish(db);
  }

  static bool _busy = false;
  static bool _again = false;

  /// Never throws and never blocks the UI: a failing alarm must not break adding a task.
  /// Changes that arrive while a refresh runs are folded into one extra pass.
  static Future<void> afterChange(AppDatabase db) async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        try {
          await refresh(db);
        } catch (_) {}
      } while (_again);
    } finally {
      _busy = false;
    }
    syncSoon(db);
  }

  static void syncSoon(AppDatabase db) {
    if (_syncing) return;
    _syncing = true;
    () async {
      try {
        await SyncService(db: db, api: ApiClient()).sync();
        await refresh(db);
      } catch (_) {
      } finally {
        _syncing = false;
      }
    }();
  }
}

final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return TodoRepository(db, onChanged: () {
    unawaited(TodoEffects.afterChange(db));
    return Future.value();
  });
});

final todosProvider = StreamProvider<List<Todo>>((ref) => ref.watch(databaseProvider).watchTodos());
final todoListsProvider = StreamProvider<List<TodoList>>((ref) => ref.watch(databaseProvider).watchTodoLists());

/// Which list the To-Do screen shows: a smart list or one category.
class TodoViewSel {
  final String? smart; // today | important | planned | all
  final int? listId;
  const TodoViewSel.smart(String this.smart) : listId = null;
  const TodoViewSel.list(int this.listId) : smart = null;

  @override
  bool operator ==(Object other) => other is TodoViewSel && other.smart == smart && other.listId == listId;
  @override
  int get hashCode => Object.hash(smart, listId);
}

final todoViewProvider = StateProvider<TodoViewSel>((ref) => const TodoViewSel.smart('today'));

// ── Pure view logic (also unit-testable) ─────────────────────────────────────

bool Function(Todo) todoPredicate(TodoViewSel sel, List<TodoList> lists, String today) {
  if (sel.smart == 'today') return (t) => t.dueDate != null && t.dueDate!.compareTo(today) <= 0;
  if (sel.smart == 'important') return (t) => t.isImportant;
  if (sel.smart == 'planned') return (t) => t.dueDate != null;
  if (sel.smart == 'all') return (_) => true;
  final id = sel.listId!;
  final ids = <int>{id, ...lists.where((l) => l.parentLocalId == id).map((l) => l.id)};
  return (t) => ids.contains(t.listLocalId);
}

int compareTodos(Todo a, Todo b) {
  final da = a.dueDate ?? '9999-99-99';
  final db = b.dueDate ?? '9999-99-99';
  final c = da.compareTo(db);
  return c != 0 ? c : a.id.compareTo(b.id);
}

List<Todo> openTodosFor(List<Todo> all, List<TodoList> lists, TodoViewSel sel, String today) {
  final p = todoPredicate(sel, lists, today);
  return all.where((t) => !t.isDone && p(t)).toList()..sort(compareTodos);
}

List<Todo> finishedTodosFor(List<Todo> all, List<TodoList> lists, TodoViewSel sel, String today) {
  final p = todoPredicate(sel, lists, today);
  final weekAgo = nowSeconds() - 7 * 86400;
  return all
      .where((t) => t.isDone && p(t) && (sel.smart == null || (t.doneAt ?? 0) >= weekAgo))
      .toList()
    ..sort((a, b) => (b.doneAt ?? 0).compareTo(a.doneAt ?? 0));
}

String listPath(List<TodoList> lists, int id) {
  final l = lists.where((x) => x.id == id).firstOrNull;
  if (l == null) return '';
  final p = l.parentLocalId == null ? null : lists.where((x) => x.id == l.parentLocalId).firstOrNull;
  return p == null ? l.title : '${p.title} › ${l.title}';
}
