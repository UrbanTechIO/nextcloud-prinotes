import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/data/remote/api_client.dart';
import 'package:prinotes/features/todo/reminders/reminder_settings.dart';

class _Api extends Fake implements ApiClient {
  Object? settings;
  final posted = <String, dynamic>{};
  bool fail = false;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? params}) async {
    if (fail) throw Exception('offline');
    expect(path, '/settings');
    return settings;
  }

  @override
  Future<dynamic> post(String path, dynamic data) async {
    if (fail) throw Exception('offline');
    expect(path, '/settings');
    posted.addAll(Map<String, dynamic>.from(data as Map));
    return {};
  }
}

void main() {
  test('Nextcloud reminder notifications are on unless the server setting says false', () {
    expect(nextcloudRemindersOn(null), isTrue);
    expect(nextcloudRemindersOn({}), isTrue);
    expect(nextcloudRemindersOn({'todo_nextcloud_notifications': 'true'}), isTrue);
    expect(nextcloudRemindersOn({'todo_nextcloud_notifications': 'false'}), isFalse);
    expect(nextcloudRemindersOn({'todo_nextcloud_notifications': '0'}), isFalse);
    expect(nextcloudRemindersOn('not a map'), isTrue);
  });

  test('loads the current choice from the server and saves a new one', () async {
    final api = _Api()..settings = {'todo_nextcloud_notifications': 'false'};
    final s = ReminderSettings(api);
    expect(await s.loadNextcloudReminders(), isFalse);
    expect(await s.saveNextcloudReminders(true), isTrue);
    expect(api.posted, {'todo_nextcloud_notifications': 'true'});
    expect(await s.saveNextcloudReminders(false), isTrue);
    expect(api.posted, {'todo_nextcloud_notifications': 'false'});
  });

  test('offline: loading returns null (unknown) and saving reports failure', () async {
    final api = _Api()..fail = true;
    final s = ReminderSettings(api);
    expect(await s.loadNextcloudReminders(), isNull);
    expect(await s.saveNextcloudReminders(false), isFalse);
  });
}
