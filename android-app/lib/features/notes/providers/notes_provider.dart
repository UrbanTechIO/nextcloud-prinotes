import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../data/local/database.dart';
import '../../../data/remote/api_client.dart';
import '../../../core/constants/app_constants.dart';

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

// ── Filter state ──────────────────────────────────────────────────────────────

class NoteFilter {
  final int? notebookId;
  final int? tagId;
  final bool trashed;
  final bool archived;
  final String searchQuery;

  const NoteFilter({
    this.notebookId,
    this.tagId,
    this.trashed = false,
    this.archived = false,
    this.searchQuery = '',
  });

  NoteFilter copyWith({
    int? notebookId,
    bool clearNotebook = false,
    int? tagId,
    bool clearTag = false,
    bool? trashed,
    bool? archived,
    String? searchQuery,
  }) => NoteFilter(
    notebookId: clearNotebook ? null : (notebookId ?? this.notebookId),
    tagId: clearTag ? null : (tagId ?? this.tagId),
    trashed: trashed ?? this.trashed,
    archived: archived ?? this.archived,
    searchQuery: searchQuery ?? this.searchQuery,
  );
}

final noteFilterProvider = StateProvider<NoteFilter>((ref) => const NoteFilter());

// ── Vault state ───────────────────────────────────────────────────────────────

final vaultUnlockedProvider = StateProvider<bool>((ref) => false);

// ── Note stream ───────────────────────────────────────────────────────────────

final notesStreamProvider = StreamProvider<List<Note>>((ref) {
  final db = ref.watch(databaseProvider);
  final filter = ref.watch(noteFilterProvider);
  final vaultUnlocked = ref.watch(vaultUnlockedProvider);

  if (filter.searchQuery.length >= 2) {
    return db.searchNotes(filter.searchQuery, showHidden: vaultUnlocked).asStream();
  }

  if (filter.tagId != null) {
    return db.watchNotesByTag(filter.tagId!, showHidden: vaultUnlocked);
  }

  return db.watchNotes(
    notebookId: filter.notebookId,
    trashed: filter.trashed,
    archived: filter.archived,
    showHidden: vaultUnlocked,
  );
});

// ── Notebooks stream ──────────────────────────────────────────────────────────

final notebooksProvider = StreamProvider<List<Notebook>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.notebooks)
    ..where((n) => n.isDeleted.equals(false))
    ..orderBy([(n) => OrderingTerm.asc(n.sortOrder)]))
      .watch();
});

// ── Tags stream ───────────────────────────────────────────────────────────────

final tagsProvider = StreamProvider<List<Tag>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.tags)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
});

// ── Per-note tags stream (for NoteCard) ───────────────────────────────────────

final noteTagsProvider = StreamProvider.family<List<Tag>, int>((ref, noteId) {
  return ref.watch(databaseProvider).watchTagsForNote(noteId);
});

// ── Note CRUD ──────────────────────────────────────────────────────────────────

final notesRepoProvider = Provider<NotesRepository>((ref) {
  return NotesRepository(
    db: ref.watch(databaseProvider),
    api: ref.watch(apiClientProvider),
  );
});

class NotesRepository {
  final AppDatabase db;
  final ApiClient api;
  final _uuid = const Uuid();

  NotesRepository({required this.db, required this.api});

  // ── Create ──────────────────────────────────────────────────────────────────
  Future<Note> createNote({
    int? notebookId,
    String title = '',
    String? content,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final companion = NotesCompanion.insert(
      title: Value(title),
      content: Value(content ?? '{"version":"1.0","blocks":[]}'),
      notebookId: Value(notebookId),
      createdAt: now,
      updatedAt: now,
      isSynced: const Value(false),
      hasLocalChanges: const Value(true),
    );
    final id = await db.into(db.notes).insert(companion);
    return (await db.getNoteById(id))!;
  }

  // ── Update ──────────────────────────────────────────────────────────────────
  Future<void> updateNote(Note note, {
    String? title,
    String? content,
    String? color,
    int? notebookId,
    bool clearNotebook = false,
    bool? isPinned,
    bool? isArchived,
    bool? isLocked,
    String? lockPinHash,
    bool? isTrashed,
    List<int>? tagIds,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await (db.update(db.notes)..where((n) => n.id.equals(note.id))).write(
      NotesCompanion(
        title: title != null ? Value(title) : const Value.absent(),
        content: content != null ? Value(content) : const Value.absent(),
        color: color != null ? Value(color) : const Value.absent(),
        notebookId: clearNotebook
            ? const Value(null)
            : (notebookId != null ? Value(notebookId) : const Value.absent()),
        isPinned: isPinned != null ? Value(isPinned) : const Value.absent(),
        isArchived: isArchived != null ? Value(isArchived) : const Value.absent(),
        isLocked: isLocked != null ? Value(isLocked) : const Value.absent(),
        lockPinHash: isLocked != null ? Value(lockPinHash) : const Value.absent(),
        isTrashed: isTrashed != null ? Value(isTrashed) : const Value.absent(),
        trashedAt: isTrashed == true ? Value(now) : const Value.absent(),
        updatedAt: Value(now),
        hasLocalChanges: const Value(true),
        isSynced: const Value(false),
      ),
    );

    if (tagIds != null) {
      await db.setTagsForNote(note.id, tagIds);
    }
  }

  // ── Delete ──────────────────────────────────────────────────────────────────
  Future<void> trashNote(int id) async {
    // Update locally immediately so the UI responds without waiting for the network
    await updateNote(
      Note(
        id: id,
        title: '',
        content: '',
        notebookId: null,
        color: null,
        isPinned: false,
        isArchived: false,
        isLocked: false,
        lockPinHash: null,
        isTrashed: false,
        trashedAt: null,
        createdAt: 0,
        updatedAt: 0,
        version: 1,
        isSynced: false,
        hasLocalChanges: false,
        remoteId: null,
        preview: null,
        isHidden: false,
      ),
      isTrashed: true,
    );

    // Also call the server's individual DELETE endpoint immediately — the same
    // route the web app uses. This is more reliable than waiting for batch sync
    // to propagate isTrashed=true, because the batch push sometimes doesn't
    // apply isTrashed on the server side.
    final note = await db.getNoteById(id);
    if (note?.remoteId != null) {
      try {
        await api.delete('${AppConstants.notesPath}/${note!.remoteId}');
        // Server moved the note to trash — mark local copy as synced
        await (db.update(db.notes)..where((n) => n.id.equals(id))).write(
          const NotesCompanion(
            isSynced: Value(true),
            hasLocalChanges: Value(false),
          ),
        );
      } catch (_) {
        // Offline or server error — hasLocalChanges stays true so batch sync retries
      }
    }
  }

  Future<void> deleteNotePermanently(int id) async {
    final note = await db.getNoteById(id);
    if (note?.remoteId != null) {
      // Log for batch-sync fallback
      await db.logPermanentDelete(note!.remoteId!);
      // Also try an immediate REST call — same as web's "Delete permanently"
      try {
        await api.delete(
          '${AppConstants.notesPath}/${note.remoteId}',
          params: {'force': 'true'},
        );
      } catch (_) {
        // Offline or error — batch sync will send deletedNoteIds on next cycle
      }
    }
    // Remove locally after attempting server delete
    await (db.delete(db.notes)..where((n) => n.id.equals(id))).go();
  }

  // ── Notebook CRUD ────────────────────────────────────────────────────────────
  Future<Notebook> createNotebook({
    required String title,
    String? color,
    String? description,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final companion = NotebooksCompanion.insert(
      title: title,
      color: Value(color),
      description: Value(description),
      createdAt: now,
      updatedAt: now,
    );
    final id = await db.into(db.notebooks).insert(companion);
    return (db.select(db.notebooks)..where((n) => n.id.equals(id))).getSingle();
  }

  Future<void> updateNotebook(int id, {String? title, String? color, String? description}) async {
    await (db.update(db.notebooks)..where((n) => n.id.equals(id))).write(
      NotebooksCompanion(
        title: title != null ? Value(title) : const Value.absent(),
        color: color != null ? Value(color) : const Value.absent(),
        description: description != null ? Value(description) : const Value.absent(),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        isSynced: const Value(false),
      ),
    );
  }

  Future<void> deleteNotebook(int id) async {
    await (db.update(db.notebooks)..where((n) => n.id.equals(id))).write(
      const NotebooksCompanion(isDeleted: Value(true)),
    );
  }

  // ── Tag CRUD ─────────────────────────────────────────────────────────────────
  Future<Tag> createTag({required String name, String? color}) async {
    final companion = TagsCompanion.insert(
      name: name,
      color: Value(color),
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    final id = await db.into(db.tags).insert(companion);
    return (db.select(db.tags)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> updateTag(int id, {String? name, String? color}) async {
    await (db.update(db.tags)..where((t) => t.id.equals(id))).write(
      TagsCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        color: color != null ? Value(color) : const Value.absent(),
      ),
    );
  }

  Future<void> setNoteHidden(int id, {required bool hidden}) =>
      db.setNoteHidden(id, hidden: hidden);

  Future<void> deleteTag(int id) async {
    // Fetch tag first so we can log remoteId for sync
    final tag = await (db.select(db.tags)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (tag?.remoteId != null) {
      await db.logTagDelete(tag!.remoteId!);
    }
    // Remove all note-tag associations for this tag
    await (db.delete(db.noteTags)..where((nt) => nt.tagId.equals(id))).go();
    // Delete the tag itself
    await (db.delete(db.tags)..where((t) => t.id.equals(id))).go();
  }
}
