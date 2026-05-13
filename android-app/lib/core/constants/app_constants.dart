class AppConstants {
  static const String appName = 'PriNotes';
  static const String syncTaskName = 'prinotes_sync';
  static const String secureStorageKeyPrefix = 'prinotes_';
  static const String serverUrlKey = 'server_url';
  static const String usernameKey = 'username';
  static const String appPasswordKey = 'app_password';
  static const String lastSyncKey = 'last_sync';
  static const String viewModeKey = 'view_mode_grid';
  static const String vaultPasswordKey = 'vault_password_hash';
  static const String appLockEnabledKey = 'app_lock_enabled';
  static const String appLockTypeKey = 'app_lock_type'; // 'pin' | 'biometric' | 'both'
  static const String appPinHashKey = 'app_pin_hash';
  static const int maxImageSizeMb = 20;
  static const int defaultAutoSaveSeconds = 3;

  // API paths (relative to server URL)
  static const String apiBase = '/index.php/apps/prinotes/api';
  static const String notesPath = '/notes';
  static const String notebooksPath = '/notebooks';
  static const String tagsPath = '/tags';
  static const String remindersPath = '/reminders';
  static const String syncPullPath = '/sync/pull';
  static const String syncPushPath = '/sync/push';
  static const String settingsPath = '/settings';
}
