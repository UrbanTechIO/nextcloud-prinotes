import 'dart:convert';
import 'dart:developer' as dev;
import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/app_constants.dart';
import '../../data/local/database.dart';
import '../../data/remote/api_client.dart';

class SyncService {
  final AppDatabase db;
  final ApiClient api;
  final _storage = const FlutterSecureStorage();

  SyncService({required this.db, required this.api});

  /// Returns the number of stale notes removed from local DB during the pull cleanup.
  Future<int> sync() async {
    // Pull FIRST so server changes (web edits) are applied before we push.
    // With push-first the push would overwrite newer web content with stale
    // mobile content; the subsequent pull would then get back the mobile
    // content it just pushed — web edits permanently lost.
    // Both steps are wrapped independently so a failure in one never blocks the other.
    int cleaned = 0;
    try {
      final (count, serverTime) = await _pull();
      cleaned = count;
      await _saveLastSync(serverTime);
    } catch (e) {
      dev.log('[Sync] Pull error: $e', name: 'SyncService');
    }
    try {
      await _push();
    } catch (e) {
      dev.log('[Sync] Push error: $e', name: 'SyncService');
    }
    return cleaned;
  }

  /// Push any tags that were created on mobile (no remoteId yet) so they
  /// receive server IDs before note payloads reference them.
  Future<void> _pushNewTags() async {
    final newTags = await (db.select(db.tags)
      ..where((t) => t.remoteId.isNull()))
        .get();
    if (newTags.isEmpty) return;

    final tagPayloads = newTags.map((t) => {
      'name': t.name,
      'color': t.color,
    }).toList();

    final payload = {
      'notes': <Map>[],
      'notebooks': <Map>[],
      'tags': tagPayloads,
      'deletedNoteIds': <int>[],
    };

    try {
      final result = await api.post(AppConstants.syncPushPath, payload) as Map;
      final returnedTags = (result['tags'] as List? ?? []);
      for (final apiTag in returnedTags) {
        final remoteId = apiTag['id']?.toString();
        final name = apiTag['name'] as String?;
        if (remoteId == null || name == null) continue;
        try {
          final localTag = newTags.firstWhere((t) => t.name == name);
          await (db.update(db.tags)..where((t) => t.id.equals(localTag.id))).write(
            TagsCompanion(
              remoteId: Value(remoteId),
              isSynced: const Value(true),
            ),
          );
        } catch (_) {}
      }
    } catch (_) {
      // Tag push failure is non-fatal — notes will still push without those tags
    }
  }

  /// Push local changes to server
  Future<void> _push() async {
    // Push any locally-created tags first so they have server IDs when notes reference them
    await _pushNewTags();

    final unsyncedNotes = await db.getUnsyncedNotes();
    final pendingNoteDeletes = await db.getPendingDeleteRemoteIds();
    final pendingTagDeletes = await db.getPendingDeleteTagRemoteIds();

    if (unsyncedNotes.isEmpty && pendingNoteDeletes.isEmpty && pendingTagDeletes.isEmpty) return;

    // Skip notes that were never synced to server AND are already trashed —
    // the server's create() would recreate them as non-trashed causing them to reappear.
    // Just delete them locally instead.
    final notesToPush = <Note>[];
    for (final n in unsyncedNotes) {
      if (n.remoteId == null && n.isTrashed) {
        await (db.delete(db.notes)..where((t) => t.id.equals(n.id))).go();
      } else {
        notesToPush.add(n);
      }
    }

    if (notesToPush.isEmpty && pendingNoteDeletes.isEmpty && pendingTagDeletes.isEmpty) return;

    // Build note payloads — include each note's tags and notebook (by server remoteId)
    final notePayloads = await Future.wait(notesToPush.map((n) async {
      final noteTags = await db.getTagsForNote(n.id);
      String? notebookRemoteId;
      if (n.notebookId != null) {
        final nb = await (db.select(db.notebooks)
          ..where((nb) => nb.id.equals(n.notebookId!))).getSingleOrNull();
        notebookRemoteId = nb?.remoteId;
      }
      return _noteToApi(n, noteTags, notebookRemoteId: notebookRemoteId);
    }));

    final payload = {
      'notes': notePayloads,
      'notebooks': <Map>[],
      'tags': <Map>[],
      'deletedNoteIds': pendingNoteDeletes
          .map((id) => int.tryParse(id))
          .where((id) => id != null)
          .toList(),
      'deletedTagIds': pendingTagDeletes
          .map((id) => int.tryParse(id))
          .where((id) => id != null)
          .toList(),
    };

    final result = await api.post(AppConstants.syncPushPath, payload) as Map;

    // Update local records with server IDs — match by remoteId first, then by title
    final syncedNotes = (result['notes'] as List? ?? []);
    for (final apiNote in syncedNotes) {
      final remoteIdStr = apiNote['id']?.toString();
      Note? localNote;
      // 1. Prefer exact remoteId match (updated notes)
      if (remoteIdStr != null) {
        try {
          localNote = unsyncedNotes.firstWhere((n) => n.remoteId == remoteIdStr);
        } catch (_) {}
      }
      // 2. Fall back to title match (newly created notes returned by server)
      if (localNote == null && apiNote['title'] != null) {
        try {
          localNote = unsyncedNotes.firstWhere(
            (n) => n.remoteId == null && n.title == apiNote['title'],
          );
        } catch (_) {}
      }
      if (localNote == null) continue; // skip — can't safely match

      // Defensive guard: verify server correctly applied our isTrashed change.
      // If there's a mismatch, leave hasLocalChanges=true so this note retries next sync.
      // This prevents the pull from overwriting a locally-trashed note back to untrashed.
      final serverIsTrashed = apiNote['isTrashed'] == true;
      if (localNote.isTrashed != serverIsTrashed) {
        dev.log('[Sync] isTrashed mismatch for note ${localNote.id}: '
            'local=${localNote.isTrashed}, server=$serverIsTrashed — will retry',
            name: 'SyncService');
        continue;
      }

      await (db.update(db.notes)..where((n) => n.id.equals(localNote!.id))).write(
        NotesCompanion(
          remoteId: Value(remoteIdStr),
          isSynced: const Value(true),
          hasLocalChanges: const Value(false),
          // Store the server-assigned version so the next pull's version
          // comparison correctly recognises this note as already up-to-date.
          version: Value((apiNote['version'] as num?)?.toInt() ?? localNote!.version),
        ),
      );
    }

    // Mark pending note deletes as processed
    if (pendingNoteDeletes.isNotEmpty) {
      await db.markDeletesProcessed();
    }
    // Mark pending tag deletes as processed
    if (pendingTagDeletes.isNotEmpty) {
      await db.markTagDeletesProcessed();
    }
  }

  /// Pull server changes into local DB.
  /// Returns (stale notes deleted, server timestamp to use as next lastSync).
  Future<(int, int)> _pull() async {
    final lastSync = await _getLastSync();
    final data = await api.get(
      AppConstants.syncPullPath,
      params: {'since': lastSync.toString()},
    ) as Map;

    // Use the server's clock as next lastSync to avoid missing notes when the
    // mobile clock is ahead of the server clock (clock skew).
    final serverTime = (data['serverTime'] as num?)?.toInt()
        ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Fetch pending-delete list once so _upsertNote can skip re-inserting deleted notes
    final pendingDeletes = await db.getPendingDeleteRemoteIds();

    // Sync notebooks — each wrapped so one bad item never aborts the rest
    for (final apiNb in (data['notebooks'] as List? ?? [])) {
      try { await _upsertNotebook(apiNb as Map); } catch (e) {
        dev.log('[Sync] notebook upsert error: $e', name: 'SyncService');
      }
    }

    // Sync tags
    for (final apiTag in (data['tags'] as List? ?? [])) {
      try { await _upsertTag(apiTag as Map); } catch (e) {
        dev.log('[Sync] tag upsert error: $e', name: 'SyncService');
      }
    }

    // Sync notes
    for (final apiNote in (data['notes'] as List? ?? [])) {
      try { await _upsertNote(apiNote as Map, pendingDeletes: pendingDeletes); } catch (e) {
        dev.log('[Sync] note upsert error: $e', name: 'SyncService');
      }
    }

    // Use allNoteIds for two purposes:
    // 1. Remove local notes permanently deleted on the server.
    // 2. Detect notes that exist on the server but are missing locally (e.g. missed
    //    due to clock-skew inflating lastSync beyond their updated_at). If any are
    //    found, do a full pull (since=0) to recover them.
    int cleanedCount = 0;
    try {
      final rawAllNoteIds = data['allNoteIds'];
      if (rawAllNoteIds != null) {
        final allServerIds = (rawAllNoteIds as List)
            .map((id) => id.toString())
            .toSet();
        final allLocalNotes = await db.select(db.notes).get();

        // ── 1. Delete stale local notes ───────────────────────────────────────
        for (final note in allLocalNotes) {
          if (note.remoteId != null && !allServerIds.contains(note.remoteId)) {
            dev.log('[Sync] Removing stale note: remoteId=${note.remoteId}',
                name: 'SyncService');
            await (db.delete(db.notes)..where((n) => n.id.equals(note.id))).go();
            cleanedCount++;
          }
        }

        // ── 2. Detect and recover server notes missing from local DB ──────────
        final localRemoteIds = allLocalNotes
            .where((n) => n.remoteId != null)
            .map((n) => n.remoteId!)
            .toSet();
        final missingIds = allServerIds
            .difference(localRemoteIds)
            .where((id) => !pendingDeletes.contains(id))
            .toSet();

        if (missingIds.isNotEmpty) {
          dev.log('[Sync] ${missingIds.length} server note(s) missing locally — '
              'running full pull to recover', name: 'SyncService');
          try {
            final fullData = await api.get(
              AppConstants.syncPullPath,
              params: {'since': '0'},
            ) as Map;
            for (final apiNote in (fullData['notes'] as List? ?? [])) {
              try {
                await _upsertNote(apiNote as Map, pendingDeletes: pendingDeletes);
              } catch (e) {
                dev.log('[Sync] full-pull note upsert error: $e', name: 'SyncService');
              }
            }
          } catch (e) {
            dev.log('[Sync] full-pull error: $e', name: 'SyncService');
          }
        }
      }
    } catch (e, st) {
      dev.log('[Sync] allNoteIds cleanup error: $e\n$st', name: 'SyncService');
    }

    return (cleanedCount, serverTime);
  }

  Future<void> _upsertNotebook(Map nb) async {
    final remoteId = nb['id']?.toString();
    if (remoteId == null) return;

    final existing = await (db.select(db.notebooks)
      ..where((n) => n.remoteId.equals(remoteId)))
        .getSingleOrNull();

    final companion = NotebooksCompanion(
      remoteId: Value(remoteId),
      title: Value(nb['title'] ?? ''),
      description: Value(nb['description']),
      color: Value(nb['color']),
      createdAt: Value(nb['createdAt'] ?? 0),
      updatedAt: Value(nb['updatedAt'] ?? 0),
      isSynced: const Value(true),
    );

    if (existing == null) {
      await db.into(db.notebooks).insert(companion);
    } else {
      await (db.update(db.notebooks)..where((n) => n.remoteId.equals(remoteId))).write(companion);
    }
  }

  Future<void> _upsertTag(Map tag) async {
    final remoteId = tag['id']?.toString();
    if (remoteId == null) return;

    final existing = await (db.select(db.tags)
      ..where((t) => t.remoteId.equals(remoteId)))
        .getSingleOrNull();

    final companion = TagsCompanion(
      remoteId: Value(remoteId),
      name: Value(tag['name'] ?? ''),
      color: Value(tag['color']),
      createdAt: Value(tag['createdAt'] ?? 0),
      isSynced: const Value(true),
    );

    if (existing == null) {
      await db.into(db.tags).insert(companion);
    } else {
      await (db.update(db.tags)..where((t) => t.remoteId.equals(remoteId))).write(companion);
    }
  }

  Future<void> _upsertNote(Map note, {required List<String> pendingDeletes}) async {
    final remoteId = note['id']?.toString();
    if (remoteId == null) return;

    // Don't re-insert a note the user has explicitly permanently deleted on this device.
    // Without this guard, the pull can resurrect a locally-deleted note if the server
    // still has it (e.g. the batch-push deletedNoteIds hasn't been processed yet).
    if (pendingDeletes.contains(remoteId)) return;

    // Find existing note by remoteId
    final existing = await (db.select(db.notes)
      ..where((n) => n.remoteId.equals(remoteId)))
        .getSingleOrNull();

    final serverUpdatedAt = (note['updatedAt'] as num?)?.toInt() ?? 0;
    final localUpdatedAt  = existing?.updatedAt ?? 0;

    // Version-based conflict resolution.
    //
    // The server increments `version` on every real save; the mobile client
    // never increments it locally (updateNote() leaves it unchanged).  This
    // makes `version` a reliable edit counter that is immune to the spurious
    // `updatedAt` updates that occurred when notes were merely *opened* on
    // old APK builds (opening set hasLocalChanges=true and bumped updatedAt
    // without any content change, causing timestamp comparison to incorrectly
    // keep stale mobile content instead of applying the newer web edit).
    //
    // Decision matrix when hasLocalChanges == true:
    //  serverVersion > localVersion  → web made real edits → apply server
    //  serverVersion == localVersion → only mobile has edits (web unchanged)
    //                                  → preserve for push
    //  serverVersion < localVersion  → shouldn't happen; be safe, keep local
    if (existing != null && existing.hasLocalChanges) {
      final serverVersion = (note['version'] as num?)?.toInt() ?? 1;
      final localVersion  = existing.version;

      if (localVersion > serverVersion) {
        // Local somehow ahead — keep it (safety net, shouldn't normally happen)
        dev.log('[Sync] Local version ($localVersion) > server ($serverVersion) '
            '— keeping local for push, remoteId=$remoteId', name: 'SyncService');
        await _syncNoteTags(existing.id, note);
        return;
      }

      if (localVersion == serverVersion) {
        // Versions match → server has no new web edits since last sync.
        // Keep local changes so the next push delivers them.
        dev.log('[Sync] Same version ($localVersion), local has pending changes '
            '— keeping local for push, remoteId=$remoteId', name: 'SyncService');
        await _syncNoteTags(existing.id, note);
        return;
      }

      // serverVersion > localVersion: web made at least one real edit.
      // Apply server content even though local has unsaved changes (web wins
      // in a true conflict; the local edit will be visible in history if the
      // server keeps revisions).
      dev.log('[Sync] Server version ($serverVersion) > local ($localVersion) '
          '— applying web edits for remoteId=$remoteId', name: 'SyncService');
    }

    // Determine whether to trust the server's isTrashed value.
    // If the local note was trashed more recently than the server's last update,
    // keep the local isTrashed=true rather than letting the pull restore it.
    // Use local isTrashed when: local is newer AND local says trashed AND server says not
    final serverIsTrashed = note['isTrashed'] == true;
    final keepLocalTrashed = existing != null &&
        existing.isTrashed &&
        !serverIsTrashed &&
        localUpdatedAt > serverUpdatedAt;

    // Resolve notebookId from remoteId
    int? notebookId;
    if (note['notebookId'] != null) {
      final nb = await (db.select(db.notebooks)
        ..where((n) => n.remoteId.equals(note['notebookId'].toString())))
          .getSingleOrNull();
      notebookId = nb?.id;
    }

    // Prefer 'blocks' (raw JSON) if available, fall back to 'content'
    final rawContent = note['blocks'] as String?
        ?? note['content'] as String?
        ?? '{"version":"1.0","blocks":[]}';

    // Lock state: web clients don't include lockPinHash in their saves, so a
    // web-side edit clears it on the server.  Treat a null server hash as
    // "web didn't touch the lock" and preserve whatever the local note has.
    // Only trust the server's lock data when it actually sends a hash.
    final serverLockPinHash = note['lockPinHash'] as String?;
    final serverIsLocked    = note['isLocked'] == true;
    final resolvedLockPinHash = serverLockPinHash ?? existing?.lockPinHash;
    final resolvedIsLocked    = serverLockPinHash != null
        ? serverIsLocked                       // server has full lock info → use it
        : (existing?.isLocked ?? serverIsLocked); // server cleared hash → keep local

    // If the server had no hash but we restored one from local, the server is
    // out of date.  Mark the note dirty so the next push re-uploads the hash,
    // which fixes it for all other clients (web, etc.).
    final lockRestoredFromLocal =
        resolvedLockPinHash != null && serverLockPinHash == null;

    final companion = NotesCompanion(
      remoteId: Value(remoteId),
      title: Value(note['title'] ?? ''),
      content: Value(rawContent),
      preview: Value(note['preview']),
      color: Value(note['color']),
      notebookId: Value(notebookId),
      isPinned: Value(note['isPinned'] == true),
      isArchived: Value(note['isArchived'] == true),
      isLocked: Value(resolvedIsLocked),
      lockPinHash: Value(resolvedLockPinHash),
      // If local trash state is newer than server, preserve it rather than restoring the note
      isTrashed: keepLocalTrashed ? Value(true) : Value(serverIsTrashed),
      createdAt: Value(note['createdAt'] ?? 0),
      updatedAt: Value(note['updatedAt'] ?? 0),
      version: Value(note['version'] ?? 1),
      isSynced: const Value(true),
      // Mark dirty if we had to restore the lock hash from local — the next push
      // will re-upload it to the server so the web can also verify the PIN.
      hasLocalChanges: (keepLocalTrashed || lockRestoredFromLocal)
          ? const Value(true)
          : const Value(false),
    );

    int localNoteId;
    if (existing == null) {
      localNoteId = await db.into(db.notes).insert(companion);
    } else {
      await (db.update(db.notes)..where((n) => n.remoteId.equals(remoteId))).write(companion);
      localNoteId = existing.id;
    }

    // Sync tags from server into local NoteTags table
    await _syncNoteTags(localNoteId, note);
  }

  /// Resolve server tag objects → local tag IDs and update the NoteTags table.
  Future<void> _syncNoteTags(int localNoteId, Map note) async {
    final serverTags = note['tags'] as List?;
    if (serverTags == null) return; // server didn't include tags → leave local as-is

    final localTagIds = <int>[];
    for (final tagData in serverTags) {
      final remoteTagId = (tagData as Map)['id']?.toString();
      if (remoteTagId == null) continue;
      final localTag = await (db.select(db.tags)
        ..where((t) => t.remoteId.equals(remoteTagId)))
          .getSingleOrNull();
      if (localTag != null) localTagIds.add(localTag.id);
    }
    await db.setTagsForNote(localNoteId, localTagIds);
  }

  Map<String, dynamic> _noteToApi(Note note, List<Tag> tags, {String? notebookRemoteId}) => {
    'id': note.remoteId != null ? int.tryParse(note.remoteId!) : null,
    'title': note.title,
    'content': note.content,   // JSON blocks — web converts to markdown on load
    'preview': note.preview,
    'color': note.color,
    // Send the server-side notebook integer ID so the server links the note correctly
    'notebookId': notebookRemoteId != null ? int.tryParse(notebookRemoteId) : null,
    'isPinned': note.isPinned,
    'isArchived': note.isArchived,
    'isLocked': note.isLocked,
    'lockPinHash': note.lockPinHash,
    'isTrashed': note.isTrashed,
    // Send server-side tag IDs so the server can update note-tag associations
    'tags': tags
        .where((t) => t.remoteId != null)
        .map((t) => int.tryParse(t.remoteId!))
        .whereType<int>()
        .toList(),
  };

  /// Convert block-editor JSON to Markdown for display in Nextcloud
  String _blocksToMarkdown(String content) {
    try {
      final parsed = jsonDecode(content) as Map;
      final blocks = (parsed['blocks'] as List? ?? []);
      final buf = StringBuffer();
      for (final block in blocks) {
        final b = block as Map;
        final type = b['type'] as String? ?? '';
        switch (type) {
          case 'heading':
            final level = (b['level'] as num?)?.toInt() ?? 1;
            final prefix = '#' * level.clamp(1, 6);
            buf.writeln('$prefix ${_spansToText(b['content'])}');
            break;
          case 'paragraph':
            final text = _spansToText(b['content']);
            if (text.isNotEmpty) buf.writeln(text);
            break;
          case 'quote':
            buf.writeln('> ${_spansToText(b['content'])}');
            break;
          case 'code':
            final lang = b['language'] as String? ?? '';
            buf.writeln('```$lang');
            buf.writeln(b['code'] ?? '');
            buf.writeln('```');
            break;
          case 'list':
            final ordered = b['ordered'] == true;
            int i = 1;
            for (final item in (b['items'] as List? ?? [])) {
              final text = (item as Map)['text'] ?? '';
              buf.writeln(ordered ? '$i. $text' : '- $text');
              i++;
            }
            break;
          case 'checklist':
            for (final item in (b['items'] as List? ?? [])) {
              final m = item as Map;
              final checked = m['checked'] == true;
              final text = m['text'] ?? '';
              buf.writeln('- [${checked ? 'x' : ' '}] $text');
            }
            break;
          case 'divider':
            buf.writeln('---');
            break;
          case 'image':
            final caption = b['caption'] as String? ?? '';
            buf.writeln('![${caption.isNotEmpty ? caption : 'image'}]');
            break;
          case 'drawing':
            buf.writeln('[Drawing]');
            break;
        }
        buf.writeln();
      }
      return buf.toString().trim();
    } catch (_) {
      return content;
    }
  }

  String _spansToText(dynamic spans) {
    if (spans is! List) return '';
    return spans.map((s) => (s as Map)['text'] ?? '').join();
  }

  // Bump this when a sync-logic change requires a forced full pull on next launch.
  // The stored value is compared; if it differs, lastSync is reset to 0.
  static const int _syncSchemaVersion = 2;
  static const String _syncSchemaKey  = 'prinotes_sync_schema_v';

  Future<int> _getLastSync() async {
    // If this is the first run with a new sync schema version, reset lastSync to 0
    // so the mobile performs a full pull and picks up all server-side data.
    final storedSchema = await _storage.read(key: _syncSchemaKey);
    if (int.tryParse(storedSchema ?? '0') != _syncSchemaVersion) {
      await _storage.write(key: _syncSchemaKey, value: _syncSchemaVersion.toString());
      await _storage.write(key: AppConstants.lastSyncKey, value: '0');
      dev.log('[Sync] Sync schema updated to v$_syncSchemaVersion — forcing full pull',
          name: 'SyncService');
      return 0;
    }
    final val = await _storage.read(key: AppConstants.lastSyncKey);
    return int.tryParse(val ?? '0') ?? 0;
  }

  Future<void> _saveLastSync(int serverTime) async {
    await _storage.write(key: AppConstants.lastSyncKey, value: serverTime.toString());
  }
}
