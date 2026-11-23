import '../../data/local/database.dart';
import '../../data/remote/api_client.dart';
import '../todo/providers/todo_provider.dart';
import 'sync_service.dart';

class BackgroundSync {
  /// Runs one background sync. Never throws: a failure (no network, expired password, bad response)
  /// returns false so WorkManager just tries again later, and the database is always closed.
  static Future<bool> run({AppDatabase? db, ApiClient? api}) async {
    final database = db ?? AppDatabase();
    try {
      await SyncService(db: database, api: api ?? ApiClient()).sync(waitForVoices: true);
      // Keep To-Do alarms and the home-screen widget in step with what sync just pulled.
      try {
        await TodoEffects.refresh(database);
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    } finally {
      await database.close();
    }
  }
}
