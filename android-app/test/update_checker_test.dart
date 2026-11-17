import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/features/update/update_checker.dart';

Map<String, dynamic> release(String tag, List<String> assets, {bool draft = false, bool pre = false, String body = 'notes'}) => {
      'tag_name': tag,
      'draft': draft,
      'prerelease': pre,
      'body': body,
      'assets': [
        for (final a in assets) {'name': a, 'size': 1000, 'browser_download_url': 'https://example.test/$tag/$a'},
      ],
    };

void main() {
  group('versions', () {
    test('compare numerically, ignoring a leading v and the build number', () {
      expect(isNewerVersion('1.2.10', '1.2.9'), isTrue, reason: 'not a text comparison');
      expect(isNewerVersion('v1.3.0', '1.2.9'), isTrue);
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(isNewerVersion('1.2.4', '1.2.4'), isFalse);
      expect(isNewerVersion('1.2.3', '1.2.4+8'), isFalse);
      expect(isNewerVersion('1.2.5', '1.2.4+8'), isTrue);
    });

    test('shorter or odd versions do not crash', () {
      expect(isNewerVersion('1.3', '1.2.9'), isTrue);
      expect(isNewerVersion('1', '1.0.0'), isFalse);
      expect(isNewerVersion('garbage', '1.0.0'), isFalse, reason: 'unreadable means no update');
      expect(isNewerVersion('1.0.1', ''), isFalse);
    });
  });

  group('picking the Android release', () {
    test('takes the newest release that has an APK, skipping web-only, draft and pre-releases', () {
      final r = pickAndroidRelease([
        release('v1.3.0', ['prinotes-1.3.0.tar.gz']), // web only
        release('v1.2.9', ['prinotes-android-1.2.9.apk'], draft: true),
        release('v1.2.8', ['prinotes-android-1.2.8.apk'], pre: true),
        release('v1.2.4', ['prinotes-1.2.4.tar.gz', 'prinotes-android-1.2.4.apk'], body: 'what changed'),
        release('v1.2.3', ['prinotes-android-1.2.3.apk']),
      ]);
      expect(r, isNotNull);
      expect(r!.version, '1.2.4');
      expect(r.apkUrl, 'https://example.test/v1.2.4/prinotes-android-1.2.4.apk');
      expect(r.notes, 'what changed');
      expect(r.apkSize, 1000);
    });

    test('no APK anywhere, or nonsense input, gives null', () {
      expect(pickAndroidRelease([release('v1.0.0', ['x.tar.gz'])]), isNull);
      expect(pickAndroidRelease([]), isNull);
      expect(pickAndroidRelease('oops'), isNull);
      expect(pickAndroidRelease([42, null, {'tag_name': 5}]), isNull);
    });
  });

  group('UpdateChecker', () {
    test('returns the release when it is newer than the installed version', () async {
      final c = UpdateChecker(fetch: (_) async => [release('v1.2.5', ['prinotes-android-1.2.5.apk'])]);
      expect((await c.latestIfNewer('1.2.4'))?.version, '1.2.5');
    });

    test('returns null when up to date', () async {
      final c = UpdateChecker(fetch: (_) async => [release('v1.2.4', ['prinotes-android-1.2.4.apk'])]);
      expect(await c.latestIfNewer('1.2.4'), isNull);
    });

    test('a network failure is an error the caller can report, not a crash', () async {
      final c = UpdateChecker(fetch: (_) async => throw Exception('offline'));
      expect(c.latestIfNewer('1.2.4'), throwsA(isA<UpdateCheckFailed>()));
    });
  });

  test('the automatic prompt is skipped for a version the user already dismissed', () {
    const r = ReleaseInfo(tag: 'v1.2.5', version: '1.2.5', apkUrl: 'u', apkSize: 1, notes: '');
    expect(shouldAutoPrompt(r, null), isTrue);
    expect(shouldAutoPrompt(r, '1.2.4'), isTrue);
    expect(shouldAutoPrompt(r, '1.2.5'), isFalse);
  });
}
