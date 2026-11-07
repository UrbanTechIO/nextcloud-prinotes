import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

// ── Tables ───────────────────────────────────────────────────────────────────

class Notebooks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()(); // server ID (null if not synced yet)
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get color => text().nullable()();
  TextColumn get icon => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  IntColumn get notebookId => integer().nullable().references(Notebooks, #id)();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get content => text().withDefault(const Constant('{"version":"1.0","blocks":[]}'))();
  TextColumn get preview => text().nullable()();
  TextColumn get color => text().nullable()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isLocked => boolean().withDefault(const Constant(false))();
  TextColumn get lockPinHash => text().nullable()();
  BoolColumn get isTrashed => boolean().withDefault(const Constant(false))();
  IntColumn get trashedAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get hasLocalChanges => boolean().withDefault(const Constant(true))();
  // Local-only — never synced to the server
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();
}

class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get color => text().nullable()();
  IntColumn get createdAt => integer()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
}

class NoteTags extends Table {
  IntColumn get noteId => integer().references(Notes, #id)();
  IntColumn get tagId => integer().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {noteId, tagId};
}

class Reminders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  IntColumn get noteId => integer().references(Notes, #id)();
  IntColumn get remindAt => integer()();
  BoolColumn get isRecurring => boolean().withDefault(const Constant(false))();
  TextColumn get recurrenceRule => text().nullable()();
  BoolColumn get isSent => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
}

class SyncLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()(); // 'note' | 'notebook' | 'tag'
  TextColumn get entityId => text()();
  TextColumn get action => text()(); // 'create' | 'update' | 'delete'
  IntColumn get timestamp => integer()();
  BoolColumn get processed => boolean().withDefault(const Constant(false))();
}

class TodoLists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  IntColumn get parentLocalId => integer().nullable()();
  TextColumn get title => text()();
  TextColumn get color => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

class Todos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  IntColumn get listLocalId => integer()();
  TextColumn get title => text()();
  TextColumn get note => text().nullable()();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
  IntColumn get doneAt => integer().nullable()();
  TextColumn get dueDate => text().nullable()(); // YYYY-MM-DD, no timezone
  IntColumn get remindAt => integer().nullable()();
  BoolColumn get reminderSent => boolean().withDefault(const Constant(false))();
  TextColumn get repeatRule => text().nullable()();
  BoolColumn get isImportant => boolean().withDefault(const Constant(false))();
  TextColumn get steps => text().withDefault(const Constant('[]'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  BoolColumn get hasLocalChanges => boolean().withDefault(const Constant(true))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

// ── Database ──────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [Notebooks, Notes, Tags, NoteTags, Reminders, SyncLog, TodoLists, Todos])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For tests: run against an in-memory database.
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await (update(notes)
          ..where((n) => n.isLocked.equals(true) & n.lockPinHash.isNotNull()))
          .write(const NotesCompanion(hasLocalChanges: Value(true)));
      }
      if (from < 3) {
        await m.addColumn(notes, notes.isHidden);
      }
      if (from < 4) {
        await m.createTable(todoLists);
        await m.createTable(todos);
      }
    },
  );

  // ── To-Do queries ─────────────────────────────────────────────────────────

  Stream<List<Todo>> watchTodos() =>
      (select(todos)..where((t) => t.isDeleted.equals(false))).watch();

  Stream<List<TodoList>> watchTodoLists() => (select(todoLists)
        ..where((l) => l.isDeleted.equals(false))
        ..orderBy([(l) => OrderingTerm.asc(l.sortOrder), (l) => OrderingTerm.asc(l.title)]))
      .watch();

  Future<List<Todo>> getAllTodos() =>
      (select(todos)..where((t) => t.isDeleted.equals(false))).get();
  Future<List<TodoList>> getAllTodoLists() =>
      (select(todoLists)..where((l) => l.isDeleted.equals(false))).get();

  Future<Todo?> getTodoById(int id) =>
      (select(todos)..where((t) => t.id.equals(id))).getSingleOrNull();
  Future<Todo?> getTodoByRemoteId(String remoteId) =>
      (select(todos)..where((t) => t.remoteId.equals(remoteId))).getSingleOrNull();
  Future<TodoList?> getTodoListById(int id) =>
      (select(todoLists)..where((l) => l.id.equals(id))).getSingleOrNull();
  Future<TodoList?> getTodoListByRemoteId(String remoteId) =>
      (select(todoLists)..where((l) => l.remoteId.equals(remoteId))).getSingleOrNull();
  Future<TodoList?> getInboxList() =>
      (select(todoLists)..where((l) => l.isSystem.equals(true))).getSingleOrNull();

  Future<int> insertTodo(TodosCompanion c) => into(todos).insert(c);
  Future<void> updateTodoRow(int id, TodosCompanion c) =>
      (update(todos)..where((t) => t.id.equals(id))).write(c);
  Future<void> hardDeleteTodo(int id) =>
      (delete(todos)..where((t) => t.id.equals(id))).go();

  Future<int> insertTodoList(TodoListsCompanion c) => into(todoLists).insert(c);
  Future<void> updateTodoListRow(int id, TodoListsCompanion c) =>
      (update(todoLists)..where((l) => l.id.equals(id))).write(c);
  Future<void> hardDeleteTodoList(int id) =>
      (delete(todoLists)..where((l) => l.id.equals(id))).go();

  Future<List<Todo>> getTodosToPush() => (select(todos)
        ..where((t) => t.hasLocalChanges.equals(true) & t.isDeleted.equals(false)))
      .get();
  Future<List<Todo>> getDeletedTodos() =>
      (select(todos)..where((t) => t.isDeleted.equals(true))).get();
  Future<List<TodoList>> getTodoListsToPush() => (select(todoLists)
        ..where((l) => l.isSynced.equals(false) & l.isDeleted.equals(false)))
      .get();
  Future<List<TodoList>> getDeletedTodoLists() =>
      (select(todoLists)..where((l) => l.isDeleted.equals(true))).get();

  // ── Note queries ──────────────────────────────────────────────────────────

  Stream<List<Note>> watchNotes({
    int? notebookId,
    bool trashed = false,
    bool archived = false,
    bool showHidden = false,
  }) {
    final query = select(notes)
      ..where((n) => n.isTrashed.equals(trashed))
      ..orderBy([
        (n) => OrderingTerm.desc(n.isPinned),
        (n) => OrderingTerm.desc(n.updatedAt),
      ]);

    if (!showHidden) {
      query.where((n) => n.isHidden.equals(false));
    }
    if (notebookId != null) {
      query.where((n) => n.notebookId.equals(notebookId));
    }
    if (!trashed) {
      query.where((n) => n.isArchived.equals(archived));
    }

    return query.watch();
  }

  Stream<List<Note>> watchNotesByTag(int tagId, {bool showHidden = false}) {
    final q = select(notes).join([
      innerJoin(noteTags, noteTags.noteId.equalsExp(notes.id)),
    ])
      ..where(noteTags.tagId.equals(tagId))
      ..where(notes.isTrashed.equals(false))
      ..orderBy([
        OrderingTerm.desc(notes.isPinned),
        OrderingTerm.desc(notes.updatedAt),
      ]);
    if (!showHidden) {
      q.where(notes.isHidden.equals(false));
    }
    return q.map((r) => r.readTable(notes)).watch();
  }

  Future<Note?> getNoteById(int id) =>
      (select(notes)..where((n) => n.id.equals(id))).getSingleOrNull();

  Future<List<Note>> searchNotes(String query, {bool showHidden = false}) {
    final q = '%${query.toLowerCase()}%';
    return (select(notes)
      ..where((n) =>
          (n.isLocked.equals(true)  & n.title.lower().like(q)) |
          (n.isLocked.equals(false) & (
            n.title.lower().like(q) |
            n.preview.lower().like(q) |
            n.content.lower().like(q)
          )))
      ..where((n) => n.isTrashed.equals(false))
      ..where((n) => showHidden ? const Constant(true) : n.isHidden.equals(false))
      ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)])
      ..limit(100))
        .get();
  }

  Future<void> setNoteHidden(int id, {required bool hidden}) async {
    await (update(notes)..where((n) => n.id.equals(id)))
        .write(NotesCompanion(isHidden: Value(hidden)));
  }

  Future<List<Note>> getUnsyncedNotes() =>
      (select(notes)..where((n) => n.hasLocalChanges.equals(true))).get();

  Future<int> upsertNote(NotesCompanion note) =>
      into(notes).insertOnConflictUpdate(note);

  /// Get remote IDs of permanently-deleted notes pending sync
  Future<List<String>> getPendingDeleteRemoteIds() async {
    final rows = await (select(syncLog)
      ..where((s) => s.entityType.equals('note'))
      ..where((s) => s.action.equals('delete'))
      ..where((s) => s.processed.equals(false)))
        .get();
    return rows.map((r) => r.entityId).toList();
  }

  /// Mark all pending note-delete sync entries as processed
  Future<void> markDeletesProcessed() async {
    await (update(syncLog)
      ..where((s) => s.entityType.equals('note'))
      ..where((s) => s.action.equals('delete'))
      ..where((s) => s.processed.equals(false)))
        .write(const SyncLogCompanion(processed: Value(true)));
  }

  /// Log a permanent delete for sync
  Future<void> logPermanentDelete(String remoteId) async {
    await into(syncLog).insert(SyncLogCompanion.insert(
      entityType: 'note',
      entityId: remoteId,
      action: 'delete',
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ));
  }

  /// Get remote IDs of deleted tags pending sync
  Future<List<String>> getPendingDeleteTagRemoteIds() async {
    final rows = await (select(syncLog)
      ..where((s) => s.entityType.equals('tag'))
      ..where((s) => s.action.equals('delete'))
      ..where((s) => s.processed.equals(false)))
        .get();
    return rows.map((r) => r.entityId).toList();
  }

  /// Mark all pending tag-delete sync entries as processed
  Future<void> markTagDeletesProcessed() async {
    await (update(syncLog)
      ..where((s) => s.entityType.equals('tag'))
      ..where((s) => s.action.equals('delete'))
      ..where((s) => s.processed.equals(false)))
        .write(const SyncLogCompanion(processed: Value(true)));
  }

  /// Log a tag deletion for sync
  Future<void> logTagDelete(String remoteId) async {
    await into(syncLog).insert(SyncLogCompanion.insert(
      entityType: 'tag',
      entityId: remoteId,
      action: 'delete',
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ));
  }

  Future<List<Tag>> getTagsForNote(int noteId) {
    final q = select(tags).join([
      innerJoin(noteTags, noteTags.tagId.equalsExp(tags.id)),
    ])..where(noteTags.noteId.equals(noteId));
    return q.map((r) => r.readTable(tags)).get();
  }

  Stream<List<Tag>> watchTagsForNote(int noteId) {
    final q = select(tags).join([
      innerJoin(noteTags, noteTags.tagId.equalsExp(tags.id)),
    ])..where(noteTags.noteId.equals(noteId));
    return q.map((r) => r.readTable(tags)).watch();
  }

  Future<void> setTagsForNote(int noteId, List<int> tagIds) async {
    await (delete(noteTags)..where((nt) => nt.noteId.equals(noteId))).go();
    for (final tagId in tagIds) {
      await into(noteTags).insert(NoteTagsCompanion(
        noteId: Value(noteId),
        tagId: Value(tagId),
      ));
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'prinotes.db'));
    return NativeDatabase.createInBackground(
      file,
      setup: (db) => db.execute('PRAGMA journal_mode=WAL'),
    );
  });
}
