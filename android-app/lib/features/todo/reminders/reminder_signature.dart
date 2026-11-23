import '../../../data/local/database.dart';

/// A short fingerprint of everything that decides which alarms exist: which tasks have a reminder, when, and
/// what the notification says. When it has not changed since the last time, the alarms need no rescheduling.
String reminderSignature(List<Todo> todos) {
  final rows = [
    for (final t in todos)
      if (t.remindAt != null || t.isDeleted)
        '${t.id}|${t.remindAt}|${t.isDone}|${t.isDeleted}|${t.title}|${t.dueDate}',
  ]..sort();
  return rows.join('\n');
}
