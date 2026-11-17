import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/core/constants/app_constants.dart';
import 'package:prinotes/core/router/app_router.dart';
import 'package:prinotes/data/local/database.dart';
import 'package:prinotes/data/remote/api_client.dart';
import 'package:prinotes/features/auth/providers/auth_provider.dart';
import 'package:prinotes/features/notes/presentation/note_list_screen.dart';
import 'package:prinotes/features/notes/providers/notes_provider.dart';
import 'package:prinotes/features/todo/presentation/todo_screen.dart';
import 'package:prinotes/features/todo/todo_navigation.dart';

class _QuietApi extends Fake implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<dynamic>.value(<String, dynamic>{});
}

void main() {
  final secure = <String, String>{};

  setUp(() {
    secure
      ..clear()
      ..[AppConstants.serverUrlKey] = 'https://example.test'
      ..[AppConstants.usernameKey] = 'rami'
      ..[AppConstants.appLockEnabledKey] = 'true'
      ..[AppConstants.appLockTypeKey] = 'pin'
      ..[AppConstants.appPinHashKey] = sha256.convert(utf8.encode('1234:prinotes-mobile-salt')).toString();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async {
      // Real storage reads take a moment; the app starts before they finish.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final key = (call.arguments as Map?)?['key'] as String?;
      if (call.method == 'read') return secure[key];
      if (call.method == 'write') secure[key!] = (call.arguments as Map)['value'] as String;
      if (call.method == 'delete') secure.remove(key);
      return null;
    });
    m.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  testWidgets('a widget/notification tap while the app is locked opens the To-Do page after the PIN, not the notes list', (tester) async {
    tester.view.physicalSize = const Size(800, 1800); // phone-sized, so the whole keypad is on screen
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(_QuietApi()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(builder: (_, ref, __) => MaterialApp.router(routerConfig: ref.watch(appRouterProvider))),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Enter PIN to unlock'), findsOneWidget);

    await openTodoFromTap(container, null); // what a widget or notification tap does
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Enter PIN to unlock'), findsOneWidget, reason: 'still locked');

    for (final d in ['1', '2', '3', '4']) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TodoScreen), findsOneWidget);
    expect(find.byType(NoteListScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('cold start from a widget: the tap arrives before the app has finished starting, and still opens the To-Do page after the PIN', (tester) async {
    tester.view.physicalSize = const Size(800, 1800); // phone-sized, so the whole keypad is on screen
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(_QuietApi()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(builder: (_, ref, __) => MaterialApp.router(routerConfig: ref.watch(appRouterProvider))),
    ));
    // No waiting: a widget tap that starts the app calls go('/todo') in the very first frame, before the
    // saved server and lock settings have been read.
    await openTodoFromTap(container, null);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Enter PIN to unlock'), findsOneWidget);
    expect(find.text('Enter PIN to unlock'), findsOneWidget, reason: 'still locked');

    for (final d in ['1', '2', '3', '4']) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TodoScreen), findsOneWidget);
    expect(find.byType(NoteListScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('fingerprint-style unlock (no lock screen button): the To-Do page still opens', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(_QuietApi()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(builder: (_, ref, __) => MaterialApp.router(routerConfig: ref.watch(appRouterProvider))),
    ));
    await openTodoFromTap(container, null);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Enter PIN to unlock'), findsOneWidget);

    // The biometric prompt finishes after the lock screen may already be gone: unlock the app directly.
    await tester.runAsync(() => container.read(authStateProvider.notifier).authenticateWithPin('1234'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TodoScreen), findsOneWidget);
    expect(find.byType(NoteListScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
