import '../../data/local/database.dart';
import '../../data/remote/api_client.dart';
import 'sync_service.dart';

class BackgroundSync {
  static Future<void> run() async {
    final db = AppDatabase();
    final api = ApiClient();
    final service = SyncService(db: db, api: api);
    await service.sync();
    await db.close();
  }
}
