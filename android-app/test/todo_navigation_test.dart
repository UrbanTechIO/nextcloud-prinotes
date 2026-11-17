import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/data/local/database.dart';
import 'package:prinotes/features/todo/providers/todo_provider.dart';
import 'package:prinotes/features/todo/todo_navigation.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> list(String t) => db.insertTodoList(TodoListsCompanion.insert(title: t, createdAt: 1, updatedAt: 1));
  Future<int> task(int listId) => db.insertTodo(TodosCompanion.insert(listLocalId: listId, title: 'x', createdAt: 1, updatedAt: 1));

  test("tapping a task opens the To-Do page on that task's category", () async {
    final a = await list('Home');
    final b = await list('Work');
    final t = await task(b);
    TodoViewSel? view;
    var went = 0;
    await openTodoTask(db: db, taskId: t, setView: (v) => view = v, goTodo: () => went++);
    expect(view, TodoViewSel.list(b));
    expect(view, isNot(TodoViewSel.list(a)));
    expect(went, 1);
  });

  test('an unknown or missing task still opens the To-Do page and keeps the current view', () async {
    TodoViewSel? view;
    var went = 0;
    await openTodoTask(db: db, taskId: 999, setView: (v) => view = v, goTodo: () => went++);
    await openTodoTask(db: db, taskId: null, setView: (v) => view = v, goTodo: () => went++);
    expect(view, isNull);
    expect(went, 2);
  });

  test('parses the task id from a widget link and a notification payload', () {
    expect(taskIdFromWidgetUri(Uri.parse('todo://open?id=12')), 12);
    expect(taskIdFromWidgetUri(Uri.parse('todo://open')), isNull);
    expect(taskIdFromWidgetUri(Uri.parse('todo://open?id=abc')), isNull);
    expect(taskIdFromWidgetUri(null), isNull);
    expect(taskIdFromWidgetUri(Uri.parse('todo://open?id=-3')), isNull, reason: 'negative ids are widget-only tasks');
    expect(taskIdFromPayload('7'), 7);
    expect(taskIdFromPayload(null), isNull);
    expect(taskIdFromPayload('x'), isNull);
  });
}
