import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/data/local/database.dart';
import 'package:prinotes/data/remote/api_client.dart';
import 'package:prinotes/features/sync/background_sync.dart';

/// A server that is unreachable: every call fails.
class _DownApi extends Fake implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<dynamic>.error(Exception('network down'));
}

void main() {
  test('a background sync against an unreachable server does not throw, and always closes the database', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await expectLater(BackgroundSync.run(db: db, api: _DownApi()), completes);
    // A closed drift database refuses new queries.
    await expectLater(db.select(db.notes).get(), throwsA(anything));
  });
}
