import 'package:drift/drift.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../../../data/local/database.dart';
import '../../../data/remote/api_client.dart';
import '../../sync/sync_service.dart';
import '../data/todo_repository.dart';

const _channelId = 'todo_reminders';
const _actionDone = 'done';
const _actionSnooze = 'snooze_1h';

/// Runs when the user taps an action button while the app is not in the foreground.
@pragma('vm:entry-point')
Future<void> todoNotificationBackgroundHandler(NotificationResponse r) async {
  await TodoReminders.handleResponse(r);
}

class TodoReminders {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => handleResponse(r),
      onDidReceiveBackgroundNotificationResponse: todoNotificationBackgroundHandler,
    );
    _ready = true;
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> requestPermissions() async {
    await _android?.requestNotificationsPermission();
  }

  static Future<bool> canScheduleExact() async => (await _android?.canScheduleExactNotifications()) ?? false;
  static Future<void> openExactAlarmSettings() async => _android?.requestExactAlarmsPermission();

  static Future<void> cancel(int localId) async {
    await init();
    await _plugin.cancel(localId);
  }

  /// Schedules (or cancels) the alarm for one task so it matches its current state.
  static Future<void> reschedule(Todo t) async {
    await init();
    await _plugin.cancel(t.id);
    final remindAt = t.remindAt;
    if (remindAt == null || t.isDone || t.isDeleted) return;
    final when = DateTime.fromMillisecondsSinceEpoch(remindAt * 1000);
    if (!when.isAfter(DateTime.now())) return;

    Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          t.id,
          t.title,
          t.dueDate != null ? 'Due ${t.dueDate}' : 'To-Do reminder',
          tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, remindAt * 1000),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              'To-Do reminders',
              channelDescription: 'Reminders for your To-Do tasks',
              importance: Importance.high,
              priority: Priority.high,
              actions: [
                AndroidNotificationAction(_actionDone, 'Done'),
                AndroidNotificationAction(_actionSnooze, 'Snooze 1 h'),
              ],
            ),
          ),
          payload: t.id.toString(),
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );

    final exact = await canScheduleExact();
    try {
      await schedule(exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle);
    } catch (_) {
      // Exact alarms can be refused at runtime; an approximate reminder beats none.
      await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  /// One bad task must not stop the others from being scheduled.
  static Future<void> rescheduleAll(List<Todo> todos) async {
    for (final t in todos) {
      try {
        await reschedule(t);
      } catch (_) {}
    }
  }

  static Future<void> handleResponse(NotificationResponse r) async {
    final id = int.tryParse(r.payload ?? '');
    if (id == null) return;
    if (r.actionId != _actionDone && r.actionId != _actionSnooze) return;

    final db = AppDatabase();
    try {
      final repo = TodoRepository(db);
      if (r.actionId == _actionDone) {
        await repo.setDone(id, true);
        await cancel(id);
      } else {
        await repo.updateTodo(
          id,
          TodosCompanion(
            remindAt: Value(nowSeconds() + 3600),
            reminderSent: const Value(false),
          ),
        );
        final t = await db.getTodoById(id);
        if (t != null) await reschedule(t);
      }
      try {
        await SyncService(db: db, api: ApiClient()).sync();
      } catch (_) {}
    } finally {
      await db.close();
    }
  }
}
