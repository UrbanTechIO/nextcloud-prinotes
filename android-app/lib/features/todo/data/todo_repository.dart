import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../data/local/database.dart';

class TodoStep {
  final String id;
  final String text;
  final bool done;
  const TodoStep(this.id, this.text, this.done);

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};

  static List<TodoStep> decode(String raw) {
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((m) => TodoStep(m['id']?.toString() ?? '', m['text']?.toString() ?? '', m['done'] == true))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String encode(List<TodoStep> steps) => jsonEncode(steps.map((s) => s.toJson()).toList());
}

int nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

String localDateString([DateTime? d]) {
  final x = d ?? DateTime.now();
  return '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
}

/// All To-Do writes go through here so reminders, the widget snapshot and sync
/// are refreshed in one place via [onChanged].
class TodoRepository {
  final AppDatabase db;
  final Future<void> Function()? onChanged;
  TodoRepository(this.db, {this.onChanged});

  Future<void> _changed() async {
    if (onChanged != null) await onChanged!();
  }

  Future<int> inboxLocalId() async {
    final inbox = await db.getInboxList();
    if (inbox != null) return inbox.id;
    final now = nowSeconds();
    return db.insertTodoList(TodoListsCompanion.insert(
      title: 'Inbox',
      createdAt: now,
      updatedAt: now,
      isSystem: const Value(true),
    ));
  }

  Future<int> addTodo(
    String title, {
    int? listLocalId,
    String? dueDate,
    int? remindAt,
    String? repeatRule,
    bool important = false,
  }) async {
    final t = title.trim();
    if (t.isEmpty) throw ArgumentError('Title required');
    final now = nowSeconds();
    final id = await db.insertTodo(TodosCompanion.insert(
      listLocalId: listLocalId ?? await inboxLocalId(),
      title: t.length > 500 ? t.substring(0, 500) : t,
      createdAt: now,
      updatedAt: now,
      dueDate: Value(dueDate),
      remindAt: Value(remindAt),
      repeatRule: Value(repeatRule),
      isImportant: Value(important),
    ));
    await _changed();
    return id;
  }

  Future<void> updateTodo(int id, TodosCompanion patch) async {
    await db.updateTodoRow(
      id,
      patch.copyWith(
        updatedAt: Value(nowSeconds()),
        hasLocalChanges: const Value(true),
        isSynced: const Value(false),
      ),
    );
    await _changed();
  }

  Future<void> setDone(int id, bool done) => updateTodo(
        id,
        TodosCompanion(
          isDone: Value(done),
          doneAt: Value(done ? nowSeconds() : null),
          // A new reminder time or un-completing re-arms the reminder.
          reminderSent: done ? const Value.absent() : const Value(false),
        ),
      );

  Future<void> toggleDone(int id) async {
    final t = await db.getTodoById(id);
    if (t == null) return;
    await setDone(id, !t.isDone);
  }

  /// Deletes a task and returns a snapshot of it, so the caller can offer Undo via [restoreTodo].
  Future<Todo?> deleteTodo(int id) async {
    final t = await db.getTodoById(id);
    if (t == null) return null;
    if (t.remoteId == null) {
      await db.hardDeleteTodo(id);
    } else {
      await db.updateTodoRow(id, const TodosCompanion(isDeleted: Value(true)));
    }
    await _changed();
    return t;
  }

  /// Undo for [deleteTodo]: un-flags a soft-deleted row, or re-inserts a hard-deleted one.
  Future<void> restoreTodo(Todo snapshot) async {
    final existing = await db.getTodoById(snapshot.id);
    if (existing != null) {
      await db.updateTodoRow(snapshot.id, const TodosCompanion(isDeleted: Value(false)));
    } else {
      // The sync already removed the row (and the server's copy). Create it again as a new task;
      // keeping the old server id would make the next pull delete it as "gone on the server".
      await db.insertTodo(snapshot.toCompanion(false).copyWith(
        remoteId: const Value(null),
        isSynced: const Value(false),
        hasLocalChanges: const Value(true),
        isDeleted: const Value(false),
      ));
    }
    await _changed();
  }

  // ── Categories ────────────────────────────────────────────────────────────

  Future<int> addList(String title, {int? parentLocalId, String? color}) async {
    final t = title.trim();
    if (t.isEmpty) throw ArgumentError('Title required');
    if (parentLocalId != null) {
      final parent = await db.getTodoListById(parentLocalId);
      if (parent == null || parent.parentLocalId != null || parent.isSystem) {
        throw ArgumentError('Sub-categories can only be one level deep');
      }
    }
    final now = nowSeconds();
    final id = await db.insertTodoList(TodoListsCompanion.insert(
      title: t,
      createdAt: now,
      updatedAt: now,
      parentLocalId: Value(parentLocalId),
      color: Value(color),
    ));
    await _changed();
    return id;
  }

  Future<void> updateList(int id, {String? title, String? color, bool clearColor = false}) async {
    final l = await db.getTodoListById(id);
    if (l == null) return;
    await db.updateTodoListRow(
      id,
      TodoListsCompanion(
        title: (title != null && !l.isSystem) ? Value(title.trim()) : const Value.absent(),
        color: clearColor ? const Value(null) : (color != null ? Value(color) : const Value.absent()),
        updatedAt: Value(nowSeconds()),
        isSynced: const Value(false),
      ),
    );
    await _changed();
  }

  /// Deletes a category with its sub-categories and all their tasks.
  Future<void> deleteList(int id) async {
    final l = await db.getTodoListById(id);
    if (l == null || l.isSystem) return;
    final all = await db.getAllTodoLists();
    final ids = <int>{id, ...all.where((x) => x.parentLocalId == id).map((x) => x.id)};
    for (final todo in await db.getAllTodos()) {
      if (ids.contains(todo.listLocalId)) await deleteTodo(todo.id);
    }
    for (final listId in ids) {
      final row = await db.getTodoListById(listId);
      if (row == null) continue;
      if (row.remoteId == null) {
        await db.hardDeleteTodoList(listId);
      } else {
        await db.updateTodoListRow(listId, const TodoListsCompanion(isDeleted: Value(true)));
      }
    }
    await _changed();
  }
}
