import '../../../data/remote/api_client.dart';

const _key = 'todo_nextcloud_reminders';

/// False unless the user has switched the extra Nextcloud notification for To-Do reminders on.
/// To-Do reminders come from PriNotes itself; Nextcloud only adds its own when asked to.
bool nextcloudRemindersOn(dynamic settings) {
  if (settings is! Map) return false;
  final v = '${settings[_key] ?? ''}'.trim().toLowerCase();
  return v == 'true' || v == '1';
}

/// The per-user server setting behind "also send To-Do reminders through Nextcloud notifications".
/// The app always shows its own reminder (a local alarm); this only controls the extra Nextcloud one.
class ReminderSettings {
  final ApiClient api;
  ReminderSettings(this.api);

  /// Current choice, or null when the server cannot be reached.
  Future<bool?> loadNextcloudReminders() async {
    try {
      return nextcloudRemindersOn(await api.get('/settings'));
    } catch (_) {
      return null;
    }
  }

  /// Returns false when the change could not be saved.
  Future<bool> saveNextcloudReminders(bool on) async {
    try {
      await api.post('/settings', {_key: on ? 'true' : 'false'});
      return true;
    } catch (_) {
      return false;
    }
  }
}
