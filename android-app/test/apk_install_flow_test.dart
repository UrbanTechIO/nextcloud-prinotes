import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/features/update/apk_installer.dart';
import 'package:prinotes/features/update/update_checker.dart';
import 'package:prinotes/features/update/update_ui.dart';

class _Installer implements ApkInstaller {
  final calls = <String>[];
  bool allowed = true;
  bool failDownload = false;

  @override
  Future<bool> canInstall() async => allowed;
  @override
  Future<void> openInstallSettings() async => calls.add('settings');
  @override
  Future<String> download(ReleaseInfo r, void Function(double) onProgress) async {
    calls.add('download');
    if (failDownload) throw Exception('connection lost');
    onProgress(0.5);
    onProgress(1);
    return '/cache/updates/prinotes-update.apk';
  }

  @override
  Future<void> install(String path) async => calls.add('install:$path');
}

const _release = ReleaseInfo(tag: 'v1.2.5', version: '1.2.5', apkUrl: 'https://x/a.apk', apkSize: 70 * 1024 * 1024, notes: '### Fixed\n- Something');

void main() {
  group('runUpdate', () {
    test('downloads, then hands the file to the installer, reporting progress', () async {
      final i = _Installer();
      final seen = <double>[];
      await runUpdate(_release, i, onProgress: seen.add);
      expect(i.calls, ['download', 'install:/cache/updates/prinotes-update.apk']);
      expect(seen, [0.5, 1.0]);
    });

    test('without permission to install apps it opens the settings page and does not download', () async {
      final i = _Installer()..allowed = false;
      await expectLater(runUpdate(_release, i), throwsA(isA<InstallNotAllowed>()));
      expect(i.calls, ['settings']);
    });

    test('a failed download never reaches the installer', () async {
      final i = _Installer()..failDownload = true;
      await expectLater(runUpdate(_release, i), throwsA(isA<Exception>()));
      expect(i.calls, ['download']);
    });
  });

  group('formatting', () {
    test('size is shown in MB', () {
      expect(formatMegabytes(70 * 1024 * 1024), '70 MB');
      expect(formatMegabytes(0), '');
    });
  });

  group('update dialog', () {
    Future<void> open(WidgetTester tester, _Installer i, List<bool?> results) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [apkInstallerProvider.overrideWithValue(i)],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () async => results.add(await showUpdateDialog(ctx, _release, currentVersion: '1.2.4')),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the new version, the size and the notes, with Later and Download and install', (tester) async {
      await open(tester, _Installer(), []);
      expect(find.textContaining('1.2.5'), findsWidgets);
      expect(find.textContaining('1.2.4'), findsWidgets, reason: 'what is installed now');
      expect(find.textContaining('70 MB'), findsOneWidget);
      expect(find.textContaining('Something'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Download and install'), findsOneWidget);
    });

    testWidgets('Later closes it and reports not installed', (tester) async {
      final results = <bool?>[];
      await open(tester, _Installer(), results);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(results, [false]);
    });

    testWidgets('Download and install runs the update and then closes', (tester) async {
      final i = _Installer();
      final results = <bool?>[];
      await open(tester, i, results);
      await tester.tap(find.text('Download and install'));
      await tester.pumpAndSettle();
      expect(i.calls, ['download', 'install:/cache/updates/prinotes-update.apk']);
      expect(results, [true]);
    });

    testWidgets('without install permission it explains and sends the user to settings', (tester) async {
      final i = _Installer()..allowed = false;
      await open(tester, i, []);
      await tester.tap(find.text('Download and install'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Install unknown apps'), findsOneWidget);
      expect(i.calls, ['settings']);
    });

    testWidgets('a failed download shows an error and keeps the dialog usable', (tester) async {
      final i = _Installer()..failDownload = true;
      await open(tester, i, []);
      await tester.tap(find.text('Download and install'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Download failed'), findsOneWidget);
      expect(find.text('Download and install'), findsOneWidget);
    });
  });
}
