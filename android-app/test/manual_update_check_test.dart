import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prinotes/features/update/update_checker.dart';
import 'package:prinotes/features/update/update_ui.dart';

class _Checker implements UpdateChecker {
  final ReleaseInfo? result;
  final bool fail;
  String? askedWith;
  _Checker({this.result, this.fail = false});

  @override
  Future<ReleaseInfo?> latestIfNewer(String currentVersion) async {
    askedWith = currentVersion;
    if (fail) throw UpdateCheckFailed('offline');
    return result;
  }
}

const _newer = ReleaseInfo(tag: 'v1.9.0', version: '1.9.0', apkUrl: 'u', apkSize: 0, notes: 'Shiny things');

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'PriNotes',
      packageName: 'com.prinotes.app',
      version: '1.2.5',
      buildNumber: '9',
      buildSignature: '',
    );
  });

  Future<_Checker> pump(WidgetTester tester, _Checker checker) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [updateCheckerProvider.overrideWithValue(checker)],
      child: MaterialApp(
        home: Consumer(
          builder: (ctx, ref, _) => Scaffold(
            body: TextButton(onPressed: () => checkForUpdateManually(ctx, ref), child: const Text('check')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();
    return checker;
  }

  testWidgets('up to date: says so and compares against the installed version', (tester) async {
    final c = await pump(tester, _Checker());
    expect(find.textContaining("You're up to date (1.2.5)"), findsOneWidget);
    expect(c.askedWith, '1.2.5');
  });

  testWidgets('a newer release opens the update dialog', (tester) async {
    await pump(tester, _Checker(result: _newer));
    expect(find.textContaining('Update available: 1.9.0'), findsOneWidget);
    expect(find.textContaining('Shiny things'), findsOneWidget);
  });

  testWidgets('no connection: a clear message, no crash', (tester) async {
    await pump(tester, _Checker(fail: true));
    expect(find.textContaining("Couldn't check for updates"), findsOneWidget);
  });
}
