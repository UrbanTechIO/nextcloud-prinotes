import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/data/local/database.dart';
import 'package:prinotes/data/remote/api_client.dart';
import 'package:prinotes/features/todo/data/todo_repository.dart';
import 'package:prinotes/features/todo/data/todo_sync.dart';

/// Records what the app posts and answers like the server does for new items.
class FakeApi implements ApiClient {
  final List<Map> posted = [];

  @override
  Future<dynamic> post(String path, dynamic data) async {
    final body = data as Map;
    posted.add(body);
    final lists = (body['todoLists'] as List).cast<Map>();
    final todos = (body['todos'] as List).cast<Map>();
    final listIds = <String, int>{};
    final listResults = [
      for (var i = 0; i < lists.length; i++)
        {'clientId': lists[i]['clientId'], 'id': listIds[lists[i]['clientId'] as String] = 100 + i, 'updatedAt': 5},
    ];
    final todoResults = [
      for (var i = 0; i < todos.length; i++)
        {
          'clientId': todos[i]['clientId'],
          'id': 200 + i,
          'listId': todos[i]['listId'] ?? listIds[todos[i]['listClientId']],
          'title': todos[i]['title'],
          'isDone': false,
          'steps': [],
          'version': 1,
          'updatedAt': 5,
        },
    ];
    return {'todoLists': listResults, 'todos': todoResults};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppDatabase newDb() => AppDatabase.forTesting(NativeDatabase.memory());

Future<int> addList(AppDatabase db, String title, {String? remoteId, bool synced = true, bool deleted = false}) =>
    db.insertTodoList(TodoListsCompanion.insert(
      title: title,
      createdAt: 1,
      updatedAt: 1,
      remoteId: Value(remoteId),
      isSynced: Value(synced),
      isDeleted: Value(deleted),
    ));

Future<int> addTodo(AppDatabase db, int listId, {String? remoteId}) => db.insertTodo(TodosCompanion.insert(
      listLocalId: listId,
      title: 'task',
      createdAt: 1,
      updatedAt: 1,
      remoteId: Value(remoteId),
    ));

void main() {
  late AppDatabase db;
  setUp(() => db = newDb());
  tearDown(() => db.close());

  test('a failed server To-Do read (todoLists null) does not delete local categories', () async {
    await addList(db, 'Work', remoteId: '10');
    await TodoSync(db, FakeApi()).pull({'todoLists': null, 'todos': null, 'allTodoIds': null});
    expect((await db.getAllTodoLists()).length, 1);
  });

  test('an unsynced task whose category vanished is still pushed, re-homed by the server', () async {
    final api = FakeApi();
    await addTodo(db, 999); // list 999 does not exist (deleted by an earlier pull)
    await TodoSync(db, api).push();
    final todos = (api.posted.single['todos'] as List).cast<Map>();
    expect(todos.length, 1);
    expect(todos.single['listId'], isNull);
  });

  test('a task in a category created offline names that category by clientId', () async {
    final api = FakeApi();
    final listId = await addList(db, 'Groceries', synced: false);
    final todoId = await addTodo(db, listId);
    await TodoSync(db, api).push();
    final sent = (api.posted.single['todos'] as List).cast<Map>().single;
    expect(sent['listId'], isNull);
    expect(sent['listClientId'], listId.toString());
    // After the round trip the task stays in Groceries instead of falling back to Inbox.
    expect((await db.getTodoById(todoId))!.listLocalId, listId);
  });

  test('a category deleted on the phone is not brought back by the next pull', () async {
    final id = await addList(db, 'Work', remoteId: '10', deleted: true);
    await TodoSync(db, FakeApi()).pull({
      'todoLists': [
        {'id': 10, 'title': 'Work', 'isSystem': false, 'parentId': null}
      ],
      'todos': [],
      'allTodoIds': [],
    });
    expect((await db.getTodoListById(id))!.isDeleted, isTrue);
  });

  test('a task the pull removes also has its alarm cancelled', () async {
    final listId = await addList(db, 'Work', remoteId: '10');
    final todoId = await addTodo(db, listId, remoteId: '5');
    final cancelled = <int>[];
    await TodoSync(db, FakeApi(), cancelAlarm: (id) async => cancelled.add(id)).pull({
      'todoLists': [
        {'id': 10, 'title': 'Work', 'isSystem': false, 'parentId': null}
      ],
      'todos': [],
      'allTodoIds': [], // task 5 is gone on the server
    });
    expect(await db.getTodoById(todoId), isNull);
    expect(cancelled, [todoId]);
  });

  test('Undo after a delete that already synced re-creates the task instead of resurrecting a dead server id', () async {
    final repo = TodoRepository(db);
    final listId = await addList(db, 'Work', remoteId: '10');
    final id = await addTodo(db, listId, remoteId: '5');
    final snap = (await repo.deleteTodo(id))!;
    await db.hardDeleteTodo(id); // what the sync does once the server confirmed the delete
    await repo.restoreTodo(snap);
    final back = (await db.getTodoById(id))!;
    expect(back.isDeleted, isFalse);
    expect(back.remoteId, isNull);
    expect(back.hasLocalChanges, isTrue);
  });
}
