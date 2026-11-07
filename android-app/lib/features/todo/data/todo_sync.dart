import 'dart:convert';
import 'dart:developer' as dev;
import 'package:drift/drift.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/local/database.dart';
import '../../../data/remote/api_client.dart';
import '../reminders/todo_reminders.dart';

/// To-Do part of the sync. Called by SyncService inside its own try/catch so a
/// failure here can never affect note sync.
class TodoSync {
  final AppDatabase db;
  final ApiClient api;
  /// Cancels the reminder alarm of a task the pull removes. Injectable so tests need no plugin.
  final Future<void> Function(int localId)? cancelAlarm;
  TodoSync(this.db, this.api, {this.cancelAlarm});

  static int? _int(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));

  // ── Pull ──────────────────────────────────────────────────────────────────

  Future<void> pull(Map data) async {
    // null means the server could not read its To-Do data. That is not "no categories":
    // acting on it would delete every local category.
    final lists = data['todoLists'] as List?;
    final todos = (data['todos'] as List?) ?? const [];
    final allIds = data['allTodoIds'] as List?;

    if (lists != null) await _upsertLists(lists.cast<Map>());
    for (final t in todos) {
      try { await _upsertTodo(t as Map); } catch (e) {
        dev.log('[TodoSync] todo upsert error: $e', name: 'TodoSync');
      }
    }

    if (allIds != null) {
      final serverIds = allIds.map((e) => e.toString()).toSet();
      final local = await db.getAllTodos();
      for (final t in local) {
        if (t.remoteId != null && !serverIds.contains(t.remoteId)) {
          await _cancel(t.id);
          await db.hardDeleteTodo(t.id);
        }
      }
      final localRemote = (await db.getAllTodos()).where((t) => t.remoteId != null).map((t) => t.remoteId!).toSet();
      final pendingDeletes = (await db.getDeletedTodos()).map((t) => t.remoteId).toSet();
      final missing = serverIds.difference(localRemote).where((id) => !pendingDeletes.contains(id));
      if (missing.isNotEmpty) {
        // Tasks the incremental pull missed (first run on this phone, clock skew): full pull.
        final full = await api.get(AppConstants.syncPullPath, params: {'since': '0'}) as Map;
        for (final t in ((full['todos'] as List?) ?? const [])) {
          try { await _upsertTodo(t as Map); } catch (e) {
            dev.log('[TodoSync] full-pull todo error: $e', name: 'TodoSync');
          }
        }
      }
    }
  }

  Future<void> _cancel(int localId) async {
    try {
      await (cancelAlarm ?? TodoReminders.cancel)(localId);
    } catch (_) {}
  }

  Future<void> _upsertLists(List<Map> apiLists) async {
    final serverIds = apiLists.map((l) => l['id'].toString()).toSet();

    // Parents first so children can resolve parentLocalId.
    final ordered = [...apiLists]..sort((a, b) =>
        (a['parentId'] == null ? 0 : 1).compareTo(b['parentId'] == null ? 0 : 1));

    for (final l in ordered) {
      final remoteId = l['id'].toString();
      var existing = await db.getTodoListByRemoteId(remoteId);
      if (existing == null && l['isSystem'] == true) {
        // Adopt the local Inbox instead of creating a second one.
        final inbox = await db.getInboxList();
        if (inbox != null) existing = inbox;
      }
      if (existing != null && !existing.isSynced && existing.remoteId != null) continue; // local edit pending
      if (existing != null && existing.isDeleted) continue; // deleted here, the push will delete it there

      int? parentLocal;
      final parentRemote = l['parentId']?.toString();
      if (parentRemote != null) parentLocal = (await db.getTodoListByRemoteId(parentRemote))?.id;

      final companion = TodoListsCompanion(
        remoteId: Value(remoteId),
        parentLocalId: Value(parentLocal),
        title: Value(l['title'] as String? ?? ''),
        color: Value(l['color'] as String?),
        sortOrder: Value(_int(l['sortOrder']) ?? 0),
        isSystem: Value(l['isSystem'] == true),
        createdAt: Value(_int(l['createdAt']) ?? 0),
        updatedAt: Value(_int(l['updatedAt']) ?? 0),
        isSynced: const Value(true),
        isDeleted: const Value(false),
      );
      if (existing == null) {
        await db.insertTodoList(companion);
      } else {
        await db.updateTodoListRow(existing.id, companion);
      }
    }

    // Lists the server no longer has (deleted on web or another device).
    for (final local in await db.getAllTodoLists()) {
      if (local.remoteId != null && !serverIds.contains(local.remoteId)) {
        await db.hardDeleteTodoList(local.id);
      }
    }
  }

  Future<int> _localListFor(dynamic serverListId) async {
    final remote = serverListId?.toString();
    if (remote != null) {
      final l = await db.getTodoListByRemoteId(remote);
      if (l != null) return l.id;
    }
    final inbox = await db.getInboxList();
    if (inbox != null) return inbox.id;
    return await db.insertTodoList(TodoListsCompanion.insert(
      title: 'Inbox',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      isSystem: const Value(true),
    ));
  }

  Future<void> _upsertTodo(Map t) async {
    final remoteId = t['id'].toString();
    final existing = await db.getTodoByRemoteId(remoteId);
    final serverVersion = _int(t['version']) ?? 1;

    if (existing != null && existing.hasLocalChanges && existing.version >= serverVersion) {
      return; // same version: our pending change wins and is pushed next
    }
    if (existing != null && existing.isDeleted) return; // pending local delete

    final companion = TodosCompanion(
      remoteId: Value(remoteId),
      listLocalId: Value(await _localListFor(t['listId'])),
      title: Value(t['title'] as String? ?? ''),
      note: Value(t['note'] as String?),
      isDone: Value(t['isDone'] == true),
      doneAt: Value(_int(t['doneAt'])),
      dueDate: Value(t['dueDate'] as String?),
      remindAt: Value(_int(t['remindAt'])),
      reminderSent: Value(t['reminderSent'] == true),
      repeatRule: Value(t['repeatRule'] as String?),
      isImportant: Value(t['isImportant'] == true),
      steps: Value(jsonEncode(t['steps'] ?? const [])),
      sortOrder: Value(_int(t['sortOrder']) ?? 0),
      createdAt: Value(_int(t['createdAt']) ?? 0),
      updatedAt: Value(_int(t['updatedAt']) ?? 0),
      version: Value(serverVersion),
      isSynced: const Value(true),
      hasLocalChanges: const Value(false),
      isDeleted: const Value(false),
    );
    if (existing == null) {
      await db.insertTodo(companion);
    } else {
      await db.updateTodoRow(existing.id, companion);
    }
  }

  // ── Push ──────────────────────────────────────────────────────────────────

  Future<void> push() async {
    final lists = await db.getTodoListsToPush();
    final todos = await db.getTodosToPush();
    final deletedTodos = await db.getDeletedTodos();
    final deletedLists = await db.getDeletedTodoLists();
    if (lists.isEmpty && todos.isEmpty && deletedTodos.isEmpty && deletedLists.isEmpty) return;

    // Parents before children; a child whose parent has no server id yet waits for the next sync.
    final listPayloads = <Map<String, dynamic>>[];
    final orderedLists = [...lists]..sort((a, b) =>
        (a.parentLocalId == null ? 0 : 1).compareTo(b.parentLocalId == null ? 0 : 1));
    for (final l in orderedLists) {
      // The Inbox is created by the server; a local one waits to be adopted by pull().
      if (l.isSystem && l.remoteId == null) continue;
      String? parentRemote;
      if (l.parentLocalId != null) {
        parentRemote = (await db.getTodoListById(l.parentLocalId!))?.remoteId;
        if (parentRemote == null) continue;
      }
      listPayloads.add({
        if (l.remoteId != null) 'id': int.tryParse(l.remoteId!),
        'clientId': l.id.toString(),
        'title': l.title,
        'color': l.color,
        'sortOrder': l.sortOrder,
        'parentId': parentRemote == null ? null : int.tryParse(parentRemote),
      });
    }

    final todoPayloads = <Map<String, dynamic>>[];
    for (final t in todos) {
      final list = await db.getTodoListById(t.listLocalId);
      int? listRemote;
      String? listClientId;
      if (list != null) {
        if (list.remoteId != null) {
          listRemote = int.tryParse(list.remoteId!);
        } else if (listPayloads.any((p) => p['clientId'] == list.id.toString())) {
          // New category pushed in this same batch: the server maps its clientId to the new id.
          listClientId = list.id.toString();
        } else {
          continue; // its category is not on the server yet (e.g. parent pending): next sync
        }
      }
      // list == null: the category was deleted elsewhere. Send no list; the server files it under Inbox.
      todoPayloads.add({
        if (t.remoteId != null) 'id': int.tryParse(t.remoteId!),
        'clientId': t.id.toString(),
        'listId': listRemote,
        if (listClientId != null) 'listClientId': listClientId,
        'title': t.title,
        'note': t.note,
        'isDone': t.isDone,
        'dueDate': t.dueDate,
        'remindAt': t.remindAt,
        'repeatRule': t.repeatRule,
        'isImportant': t.isImportant,
        'steps': jsonDecode(t.steps),
        'sortOrder': t.sortOrder,
        'version': t.version,
      });
    }

    final payload = {
      'notes': <Map>[],
      'notebooks': <Map>[],
      'tags': <Map>[],
      'todoLists': listPayloads,
      'todos': todoPayloads,
      'deletedTodoIds': deletedTodos.where((t) => t.remoteId != null).map((t) => int.tryParse(t.remoteId!)).whereType<int>().toList(),
      'deletedTodoListIds': deletedLists.where((l) => l.remoteId != null).map((l) => int.tryParse(l.remoteId!)).whereType<int>().toList(),
    };

    final result = await api.post(AppConstants.syncPushPath, payload) as Map;

    for (final r in ((result['todoLists'] as List?) ?? const []).cast<Map>()) {
      final local = int.tryParse(r['clientId']?.toString() ?? '');
      if (local == null) continue;
      await db.updateTodoListRow(local, TodoListsCompanion(
        remoteId: Value(r['id'].toString()),
        isSynced: const Value(true),
        updatedAt: Value(_int(r['updatedAt']) ?? 0),
      ));
    }

    var repeatingCompleted = false;
    for (final r in ((result['todos'] as List?) ?? const []).cast<Map>()) {
      final local = int.tryParse(r['clientId']?.toString() ?? '');
      if (local == null) continue;
      final row = await db.getTodoById(local);
      if (row == null) continue;
      if (r['isDone'] == true && r['repeatRule'] != null) repeatingCompleted = true;
      // A stale push comes back as the newer server row: take it as the truth.
      await db.updateTodoRow(local, TodosCompanion(
        remoteId: Value(r['id'].toString()),
        listLocalId: Value(await _localListFor(r['listId'])),
        title: Value(r['title'] as String? ?? row.title),
        note: Value(r['note'] as String?),
        isDone: Value(r['isDone'] == true),
        doneAt: Value(_int(r['doneAt'])),
        dueDate: Value(r['dueDate'] as String?),
        remindAt: Value(_int(r['remindAt'])),
        reminderSent: Value(r['reminderSent'] == true),
        repeatRule: Value(r['repeatRule'] as String?),
        isImportant: Value(r['isImportant'] == true),
        steps: Value(jsonEncode(r['steps'] ?? const [])),
        updatedAt: Value(_int(r['updatedAt']) ?? 0),
        version: Value(_int(r['version']) ?? row.version),
        isSynced: const Value(true),
        hasLocalChanges: const Value(false),
      ));
    }

    for (final t in deletedTodos) { await db.hardDeleteTodo(t.id); }
    for (final l in deletedLists) { await db.hardDeleteTodoList(l.id); }

    // The server creates the next occurrence of a completed repeating task: fetch it now.
    if (repeatingCompleted) {
      final since = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 30;
      final data = await api.get(AppConstants.syncPullPath, params: {'since': since.toString()}) as Map;
      await pull(data);
    }
  }
}
