import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import '../providers/notes_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/local/database.dart';
import '../../../data/remote/api_client.dart';
import '../../../features/auth/providers/auth_provider.dart';
import 'widgets/note_card.dart';
import 'widgets/sidebar_drawer.dart';
import '../../sync/sync_service.dart';

class NoteListScreen extends ConsumerStatefulWidget {
  const NoteListScreen({super.key});

  @override
  ConsumerState<NoteListScreen> createState() => _NoteListScreenState();
}

class _NoteListScreenState extends ConsumerState<NoteListScreen>
    with WidgetsBindingObserver {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _storage = const FlutterSecureStorage();
  bool _syncing = false;
  bool _gridView = true;
  Set<int> _selectedIds = {};
  Timer? _syncTimer;
  String? _vaultHashCache;

  bool get _selecting => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) => _sync());
  }

  Future<void> _loadPrefs() async {
    final storedView = await _storage.read(key: AppConstants.viewModeKey);
    final storedHash = await _storage.read(key: AppConstants.vaultPasswordKey);
    if (mounted) {
      setState(() {
        if (storedView != null) _gridView = storedView == 'true';
        _vaultHashCache = storedHash;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-sync whenever the app comes back to the foreground
    if (state == AppLifecycleState.resumed) {
      _sync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesStreamProvider);
    final filter = ref.watch(noteFilterProvider);
    final notebooks = ref.watch(notebooksProvider).valueOrNull ?? [];
    final tags = ref.watch(tagsProvider).valueOrNull ?? [];
    final isTrashView = filter.trashed;

    return Scaffold(
      appBar: AppBar(
        title: _selecting
            ? Text('${_selectedIds.length} selected')
            : Text(_getTitle(filter, notebooks, tags)),
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedIds = {}),
              )
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
        actions: _selecting
            ? []
            : [
                IconButton(
                  icon: Icon(_gridView ? Icons.view_list_rounded : Icons.grid_view_rounded),
                  onPressed: () {
                    final next = !_gridView;
                    setState(() => _gridView = next);
                    _storage.write(key: AppConstants.viewModeKey, value: next.toString());
                  },
                ),
                _syncing
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: const Icon(Icons.sync_rounded),
                        onPressed: _sync,
                        tooltip: 'Sync now',
                      ),
                PopupMenuButton<String>(
                  onSelected: _onMenuAction,
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'settings', child: Text('Settings')),
                    const PopupMenuItem(value: 'lock', child: Text('Lock app')),
                  ],
                ),
              ],
        bottom: _selecting
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: SearchBar(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    hintText: 'Search notes...',
                    leading: const Icon(Icons.search),
                    backgroundColor: WidgetStateProperty.all(
                      Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF1E3A5F)
                          : const Color(0xFFE8EEF8),
                    ),
                    elevation: WidgetStateProperty.all(0),
                    trailing: [
                      if (_searchCtrl.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            ref.read(noteFilterProvider.notifier).update(
                              (f) => f.copyWith(searchQuery: ''),
                            );
                          },
                        ),
                    ],
                    onChanged: (q) {
                      if (q == '::vault') {
                        _searchCtrl.clear();
                        _searchFocus.unfocus();
                        ref.read(noteFilterProvider.notifier).update(
                          (f) => f.copyWith(searchQuery: ''),
                        );
                        _handleVaultCommand();
                        return;
                      }
                      // Check if typed text matches vault password
                      if (_vaultHashCache != null) {
                        final typed = sha256.convert(utf8.encode('$q:prinotes-vault')).toString();
                        if (typed == _vaultHashCache) {
                          _searchCtrl.clear();
                          _searchFocus.unfocus();
                          ref.read(noteFilterProvider.notifier).update(
                            (f) => f.copyWith(searchQuery: ''),
                          );
                          ref.read(vaultUnlockedProvider.notifier).state = true;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Hidden notes visible')),
                          );
                          return;
                        }
                      }
                      ref.read(noteFilterProvider.notifier).update(
                        (f) => f.copyWith(searchQuery: q),
                      );
                    },
                  ),
                ),
              ),
      ),
      drawer: const SidebarDrawer(),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _searchFocus.unfocus(),
        child: Stack(
        children: [
          notesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (notes) {
              if (notes.isEmpty) {
                return _buildEmptyState();
              }
              final pinned = notes.where((n) => n.isPinned).toList();
              final others = notes.where((n) => !n.isPinned).toList();
              return RefreshIndicator(
                onRefresh: _sync,
                child: CustomScrollView(
                  slivers: [
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    if (pinned.isNotEmpty) ...[
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Text('PINNED',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                              color: Colors.grey, letterSpacing: 0.8)),
                        ),
                      ),
                      _buildNoteGrid(pinned),
                    ],
                    if (pinned.isNotEmpty && others.isNotEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Text('NOTES',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                              color: Colors.grey, letterSpacing: 0.8)),
                        ),
                      ),
                    _buildNoteGrid(others),
                    // Extra bottom padding so FAB / action bar doesn't cover notes
                    SliverToBoxAdapter(child: SizedBox(height: _selecting ? 96 : 80)),
                  ],
                ),
              );
            },
          ),
          // Bottom selection action bar
          if (_selecting)
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (isTrashView) ...[
                        _actionBarBtn(
                          icon: Icons.delete_forever,
                          label: 'Delete',
                          color: Colors.red,
                          onTap: () => _permanentDeleteSelected(),
                        ),
                        _actionBarBtn(
                          icon: Icons.restore_from_trash_rounded,
                          label: 'Restore',
                          onTap: () => _restoreSelected(),
                        ),
                        _actionBarBtn(
                          icon: Icons.select_all,
                          label: 'All',
                          onTap: () {
                            final notes = ref.read(notesStreamProvider).valueOrNull ?? [];
                            setState(() => _selectedIds = notes.map((n) => n.id).toSet());
                          },
                        ),
                      ] else ...[
                        _actionBarBtn(
                          icon: Icons.delete_outline,
                          label: 'Trash',
                          color: Colors.red,
                          onTap: () => _trashSelected(),
                        ),
                        _actionBarBtn(
                          icon: Icons.archive_outlined,
                          label: 'Archive',
                          onTap: () => _archiveSelected(),
                        ),
                        _actionBarBtn(
                          icon: Icons.share_outlined,
                          label: 'Share',
                          onTap: () => _shareSelected(),
                        ),
                        _actionBarBtn(
                          icon: Icons.select_all,
                          label: 'All',
                          onTap: () {
                            final notes = ref.read(notesStreamProvider).valueOrNull ?? [];
                            setState(() => _selectedIds = notes.map((n) => n.id).toSet());
                          },
                        ),
                      ],
                      TextButton(
                        onPressed: () => setState(() => _selectedIds = {}),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
        ),
      ),
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton(
              onPressed: _createNote,
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _actionBarBtn({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color ?? Theme.of(context).iconTheme.color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteGrid(List<Note> notes) {
    if (_gridView) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final note = notes[i];
              return NoteCard(
                note: note,
                isSelected: _selectedIds.contains(note.id),
                onTap: _selecting
                    ? () => _toggleSelection(note.id)
                    : () => _openNote(note),
                onLongPress: () => _toggleSelection(note.id),
              );
            },
            childCount: notes.length,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.05,
          ),
        ),
      );
    } else {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final note = notes[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: NoteCard(
                  note: note,
                  isListView: true,
                  isSelected: _selectedIds.contains(note.id),
                  onTap: _selecting
                      ? () => _toggleSelection(note.id)
                      : () => _openNote(note),
                  onLongPress: () => _toggleSelection(note.id),
                ),
              );
            },
            childCount: notes.length,
          ),
        ),
      );
    }
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _trashSelected() async {
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to trash?'),
        content: Text(
          'Move $count note${count > 1 ? 's' : ''} to trash? You can restore them later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Move to trash', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final repo = ref.read(notesRepoProvider);
    for (final id in _selectedIds) {
      await repo.trashNote(id);
    }
    setState(() => _selectedIds = {});
  }

  Future<void> _archiveSelected() async {
    final repo = ref.read(notesRepoProvider);
    final db = ref.read(databaseProvider);
    for (final id in _selectedIds) {
      final note = await db.getNoteById(id);
      if (note != null) {
        await repo.updateNote(note, isArchived: true);
      }
    }
    setState(() => _selectedIds = {});
  }

  Future<void> _permanentDeleteSelected() async {
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          'This will permanently delete $count note${count > 1 ? 's' : ''}. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete forever', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final repo = ref.read(notesRepoProvider);
    for (final id in _selectedIds) {
      await repo.deleteNotePermanently(id);
    }
    setState(() => _selectedIds = {});
  }

  Future<void> _restoreSelected() async {
    final repo = ref.read(notesRepoProvider);
    final db = ref.read(databaseProvider);
    for (final id in _selectedIds) {
      final note = await db.getNoteById(id);
      if (note != null) {
        await repo.updateNote(note, isTrashed: false);
      }
    }
    setState(() => _selectedIds = {});
  }

  void _shareSelected() {
    // TODO: implement share for multiple notes
    setState(() => _selectedIds = {});
  }

  Future<void> _handleVaultCommand() async {
    if (_vaultHashCache == null) {
      // Vault not set up yet — prompt to create password
      await _showVaultSetupDialog();
    } else {
      // Vault already configured — show manage options
      await _showVaultManageDialog();
    }
  }

  Future<void> _showVaultSetupDialog() async {
    final pwCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Set Vault Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Choose a password to unlock hidden notes. Type it in the search bar to reveal them.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pwCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Vault password'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm password'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (pwCtrl.text.isEmpty) {
                  setDlg(() => error = 'Password cannot be empty');
                  return;
                }
                if (pwCtrl.text != confirmCtrl.text) {
                  setDlg(() => error = 'Passwords do not match');
                  return;
                }
                final hash = sha256.convert(utf8.encode('${pwCtrl.text}:prinotes-vault')).toString();
                await _storage.write(key: AppConstants.vaultPasswordKey, value: hash);
                setState(() => _vaultHashCache = hash);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Vault password set. Type it in search to reveal hidden notes.')),
                  );
                }
              },
              child: const Text('Set password'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showVaultManageDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vault'),
        content: const Text('What would you like to do?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _storage.delete(key: AppConstants.vaultPasswordKey);
              // Also unhide all hidden notes
              final db = ref.read(databaseProvider);
              final hidden = await (db.select(db.notes)
                ..where((n) => n.isHidden.equals(true))).get();
              for (final n in hidden) {
                await db.setNoteHidden(n.id, hidden: false);
              }
              if (mounted) setState(() => _vaultHashCache = null);
              ref.read(vaultUnlockedProvider.notifier).state = false;
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vault removed. All notes are now visible.')),
                );
              }
            },
            child: const Text('Remove vault', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showVaultSetupDialog(); // reuse setup dialog to change password
            },
            child: const Text('Change password'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.note_add_outlined, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text('No notes yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Tap + to create your first note',
            style: TextStyle(color: Colors.grey.shade500)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _createNote,
            icon: const Icon(Icons.add),
            label: const Text('New Note'),
          ),
        ],
      ),
    );
  }

  Future<void> _createNote() async {
    final filter = ref.read(noteFilterProvider);
    final repo = ref.read(notesRepoProvider);
    final note = await repo.createNote(notebookId: filter.notebookId);
    if (mounted) context.push('/note/${note.id}');
  }

  void _openNote(Note note) => context.push('/note/${note.id}');

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final db = ref.read(databaseProvider);
      final api = ref.read(apiClientProvider);
      await SyncService(db: db, api: api).sync();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _onMenuAction(String action) {
    switch (action) {
      case 'settings': context.push('/settings'); break;
      case 'lock':
        ref.read(authStateProvider.notifier).lock();
        context.go('/lock');
        break;
    }
  }

  String _getTitle(NoteFilter filter, List<Notebook> notebooks, List<Tag> tags) {
    if (filter.trashed) return 'Trash';
    if (filter.archived) return 'Archived';
    if (filter.tagId != null) {
      final tag = tags.firstWhere((t) => t.id == filter.tagId, orElse: () => tags.first);
      return '#${tag.name}';
    }
    if (filter.notebookId != null) {
      final nb = notebooks.firstWhere((n) => n.id == filter.notebookId, orElse: () => notebooks.first);
      return nb.title;
    }
    return 'PriNotes';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }
}
