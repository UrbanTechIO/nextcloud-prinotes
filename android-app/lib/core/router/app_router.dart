import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/lock_screen.dart';
import '../../features/auth/presentation/setup_screen.dart';
import '../../features/notes/presentation/note_list_screen.dart';
import '../../features/notes/presentation/note_editor_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/todo/presentation/todo_screen.dart';

/// Where to send the user, or null to stay. [pending] is the page that was asked for while the app was
/// locked (widget or notification tap): after unlocking the user lands there instead of the notes list.
String? appRedirect({
  required bool isSetup,
  required bool isLocked,
  required bool isAuthenticated,
  required String loc,
  String? pending,
}) {
  if (!isSetup) return loc == '/setup' ? null : '/setup';
  if (!isAuthenticated && isLocked) return loc == '/lock' ? null : '/lock';
  // Authenticated. A remembered page wins wherever the router happens to be: after unlock the replaced
  // router starts at the notes list, not at the lock screen.
  if (pending != null && loc != pending) return pending;
  // Don't stay on lock or setup screens
  if (loc == '/lock' || loc == '/setup') return '/';
  return null;
}

/// The page to remember when [target] sends the user to the lock screen from somewhere else.
String? pendingForLock({required String? target, required String loc}) =>
    (target == '/lock' && loc != '/lock' && loc != '/setup' && loc != '/') ? loc : null;

/// Page asked for while the app was locked; opened right after unlock. A plain holder (not provider state)
/// so a router that has just been replaced can still read it from its redirect.
final pendingRouteProvider = Provider<ValueNotifier<String?>>((_) => ValueNotifier<String?>(null));

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final pendingHolder = ref.read(pendingRouteProvider);

  return GoRouter(
    initialLocation: '/lock',
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final pending = pendingHolder.value;
      final target = appRedirect(
        isSetup: authState.isSetup,
        isLocked: authState.isLocked,
        isAuthenticated: authState.isAuthenticated,
        loc: loc,
        pending: pending,
      );
      final remember = pendingForLock(target: target, loc: loc);
      if (remember != null && remember != pending) {
        pendingHolder.value = remember;
      } else if (pending != null && target == pending) {
        pendingHolder.value = null;
      }
      return target;
    },
    routes: [
      GoRoute(path: '/setup', builder: (ctx, state) => const SetupScreen()),
      GoRoute(path: '/lock', builder: (ctx, state) => const LockScreen()),
      GoRoute(path: '/todo', builder: (ctx, state) => const TodoScreen()),
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
