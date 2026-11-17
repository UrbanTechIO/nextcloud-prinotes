import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/router/app_router.dart';
import '../../data/local/database.dart';
import '../auth/providers/auth_provider.dart';
import '../notes/providers/notes_provider.dart' show databaseProvider;
import 'providers/todo_provider.dart';

/// Task id carried by a widget row link (`todo://open?id=12`), or null. Negative ids are tasks added from
/// the widget that the app has not stored yet, so they cannot be opened.
int? taskIdFromWidgetUri(Uri? uri) {
  final id = int.tryParse(uri?.queryParameters['id'] ?? '');
  return (id == null || id <= 0) ? null : id;
}

/// Task id stored in a reminder notification, or null.
int? taskIdFromPayload(String? payload) => int.tryParse(payload ?? '');

/// Opens the To-Do page. When [taskId] is a known task, the page shows that task's category;
/// otherwise it keeps the view it had.
Future<void> openTodoTask({
  required AppDatabase db,
  required int? taskId,
  required void Function(TodoViewSel) setView,
  required void Function() goTodo,
}) async {
  if (taskId != null) {
    try {
      final t = await db.getTodoById(taskId);
      if (t != null) setView(TodoViewSel.list(t.listLocalId));
    } catch (_) {}
  }
  goTodo();
}

/// What a widget row tap or a reminder notification tap does. The tap can arrive before the app has read
/// its saved settings, or while it is locked: then the router would send the user to setup or the lock
/// screen and forget the To-Do page, so the destination is remembered first and used after unlock.
Future<void> openTodoFromTap(ProviderContainer c, int? taskId) {
  if (!c.read(authStateProvider).isAuthenticated) {
    c.read(pendingRouteProvider).value = '/todo';
  }
  return openTodoTask(
    db: c.read(databaseProvider),
    taskId: taskId,
    setView: (v) => c.read(todoViewProvider.notifier).state = v,
    goTodo: () => c.read(appRouterProvider).go('/todo'),
  );
}
