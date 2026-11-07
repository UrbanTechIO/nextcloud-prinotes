import '../../data/local/database.dart';
import '../../data/remote/api_client.dart';
import '../todo/providers/todo_provider.dart';
import 'sync_service.dart';

class BackgroundSync {
  static Future<void> run() async {
    final db = AppDatabase();
    final api = ApiClient();
    final service = SyncService(db: db, api: api);
    await service.sync();
    // Keep To-Do alarms and the home-screen widget in step with what sync just pulled.
    try {
      await TodoEffects.refresh(db);
    } catch (_) {}
    await db.close();
  }
}
