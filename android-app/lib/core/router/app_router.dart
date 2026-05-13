import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/lock_screen.dart';
import '../../features/auth/presentation/setup_screen.dart';
import '../../features/notes/presentation/note_list_screen.dart';
import '../../features/notes/presentation/note_editor_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/auth/providers/auth_provider.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/lock',
    redirect: (context, state) {
      final isSetup = authState.isSetup;
      final isLocked = authState.isLocked;
      final isAuthenticated = authState.isAuthenticated;
      final loc = state.matchedLocation;

      if (!isSetup) return loc == '/setup' ? null : '/setup';
      if (!isAuthenticated && isLocked) return loc == '/lock' ? null : '/lock';
      // Authenticated — don't stay on lock or setup screens
      if (loc == '/lock' || loc == '/setup') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/setup', builder: (ctx, state) => const SetupScreen()),
      GoRoute(path: '/lock', builder: (ctx, state) => const LockScreen()),
      GoRoute(
        path: '/',
        builder: (ctx, state) => const NoteListScreen(),
        routes: [
          GoRoute(
            path: 'note/new',
            builder: (ctx, state) {
              final notebookId = state.extra as int?;
              return NoteEditorScreen(noteId: null, initialNotebookId: notebookId);
            },
          ),
          GoRoute(
            path: 'note/:id',
            builder: (ctx, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              return NoteEditorScreen(noteId: id);
            },
          ),
          GoRoute(
            path: 'settings',
            builder: (ctx, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (ctx, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.uri}')),
    ),
  );
});
