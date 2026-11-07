import 'dart:convert';
import 'package:home_widget/home_widget.dart';
import '../reminders/todo_reminders.dart';
import '../../../data/local/database.dart';
import '../../../data/remote/api_client.dart';
import '../../sync/sync_service.dart';
import '../data/todo_repository.dart';

const _widgetClasses = [
  'com.prinotes.app.todo.TodoWidgetMedium',
  'com.prinotes.app.todo.TodoWidgetLarge',
];

/// Flutter <-> native widget bridge. Flutter publishes a read-only snapshot; the widget queues
/// taps (`todo_queue`) and wakes [todoWidgetBackgroundCallback] to apply them to the database.
class TodoWidgetBridge {
  static Future<void> register() async {
    await HomeWidget.registerInteractivityCallback(todoWidgetBackgroundCallback);
  }

  /// Writes the lists tree and all open tasks, then redraws the widgets.
  static Future<void> publish(AppDatabase db) async {
    final lists = await db.getAllTodoLists();
    final todos = await db.getAllTodos();

    // Parents first, each followed by its children: the native pickers render in this order.
    final top = lists.where((l) => l.parentLocalId == null).toList();
    final ordered = <TodoList>[];
    for (final l in top) {
      ordered.add(l);
      ordered.addAll(lists.where((c) => c.parentLocalId == l.id));
    }
    final tree = ordered
        .map((l) => {
              'id': l.id,
              'title': l.title,
              'color': l.color,
              'parentId': l.parentLocalId,
              'isSystem': l.isSystem,
            })
        .toList();

    String path(int id) {
      final l = lists.where((x) => x.id == id).firstOrNull;
      if (l == null) return '';
      final p = l.parentLocalId == null ? null : lists.where((x) => x.id == l.parentLocalId).firstOrNull;
      return p == null ? l.title : '${p.title} › ${l.title}';
    }

    final tasks = todos
        .where((t) => !t.isDone)
        .map((t) => {
              'id': t.id,
              'title': t.title,
              'listId': t.listLocalId,
              'listPath': path(t.listLocalId),
              'dueDate': t.dueDate,
              'remindAt': t.remindAt,
              'important': t.isImportant,
            })
        .toList();

    await HomeWidget.saveWidgetData<String>('todo_tree', jsonEncode(tree));
    await HomeWidget.saveWidgetData<String>('todo_tasks', jsonEncode(tasks));
    for (final cls in _widgetClasses) {
      await HomeWidget.updateWidget(qualifiedAndroidName: cls);
    }
  }
}

/// Invoked by the home_widget background receiver (also when the app is closed).
@pragma('vm:entry-point')
Future<void> todoWidgetBackgroundCallback(Uri? uri) async {
  final db = AppDatabase();
  try {
    final raw = await HomeWidget.getWidgetData<String>('todo_queue', defaultValue: '[]');
    await HomeWidget.saveWidgetData<String>('todo_queue', '[]');
    final ops = (jsonDecode(raw ?? '[]') as List).whereType<Map>().toList();

    final repo = TodoRepository(db);
    for (final op in ops) {
      try {
        if (op['op'] == 'complete') {
          final id = (op['id'] as num?)?.toInt();
          if (id != null && id > 0) await repo.setDone(id, true);
        } else if (op['op'] == 'add') {
          final title = (op['title'] as String?)?.trim() ?? '';
          if (title.isEmpty) continue;
          await repo.addTodo(
            title,
            listLocalId: (op['listId'] as num?)?.toInt(),
            dueDate: op['due'] as String?,
          );
        }
      } catch (_) {}
    }

    // Show the real data right away, then sync so the phone and the web see the change.
    await TodoWidgetBridge.publish(db);
    if (ops.isNotEmpty) {
      try {
        await SyncService(db: db, api: ApiClient()).sync();
      } catch (_) {}
      await TodoWidgetBridge.publish(db);
      // A task completed from the widget must not still fire its reminder.
      await TodoReminders.rescheduleAll(await db.select(db.todos).get());
    }
  } finally {
    await db.close();
  }
}
