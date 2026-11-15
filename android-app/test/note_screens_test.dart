import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:prinotes/core/constants/app_constants.dart';
import 'package:prinotes/data/local/database.dart';
import 'package:prinotes/data/remote/api_client.dart';
import 'package:prinotes/features/notes/presentation/note_editor_screen.dart';
import 'package:prinotes/features/notes/presentation/note_list_screen.dart';
import 'package:prinotes/features/notes/presentation/widgets/note_options_sheet.dart';
import 'package:prinotes/features/notes/providers/notes_provider.dart';

/// Answers every call with an empty map: enough for the screens, which only sync in the background.
class _QuietApi extends Fake implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<dynamic>.value(<String, dynamic>{});
}

final _secure = <String, String>{};
final _platformCalls = <String>[];

void _mockPlatform() {
  final messenger = TestDefaultBinaryMessenger;
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      final key = (call.arguments as Map?)?['key'] as String?;
      switch (call.method) {
        case 'read':
          return _secure[key];
        case 'write':
          _secure[key!] = (call.arguments as Map)['value'] as String;
          return null;
        case 'delete':
          _secure.remove(key);
          return null;
        case 'containsKey':
          return _secure.containsKey(key);
        default:
          return null;
      }
    },
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    _platformCalls.add(call.method);
    return null;
  });
  // ignore: unused_local_variable
  final _ = messenger;
}

Future<int> _addNote(AppDatabase db, String title, {bool hidden = false}) async {
  final id = await db.into(db.notes).insert(NotesCompanion.insert(
        title: Value(title),
        content: const Value('{}'),
        createdAt: 1,
        updatedAt: 1,
      ));
  if (hidden) await db.setNoteHidden(id, hidden: true);
  return id;
}

void main() {
  late AppDatabase db;

  setUp(() {
    _secure.clear();
    _platformCalls.clear();
    _mockPlatform();
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  List<Override> overrides() => [
        databaseProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(_QuietApi()),
      ];

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  group('note options: Move to trash', () {
    testWidgets('confirming trashes the note and reports it (the dialog used to never appear)', (tester) async {
      final id = await _addNote(db, 'To delete');
      final note = (await db.getNoteById(id))!;
      var trashed = 0;
      await tester.pumpWidget(ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet(
                  context: ctx,
                  builder: (_) => NoteOptionsSheet(note: note, onChanged: (_) {}, onTrashed: () => trashed++),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Move to trash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to trash'));
      await tester.pumpAndSettle();
      expect(find.text('Move to trash?'), findsOneWidget, reason: 'confirmation dialog must show');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Move to trash'));
      await tester.pumpAndSettle();
      expect((await db.getNoteById(id))!.isTrashed, isTrue);
      expect(trashed, 1);
      await finish(tester);
    });
  });

  group('editor: system back button', () {
    testWidgets('saves the edit before leaving', (tester) async {
      final id = await _addNote(db, 'Old title');
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('home'))),
        GoRoute(path: '/e', builder: (_, __) => NoteEditorScreen(noteId: id)),
      ]);
      await tester.pumpWidget(ProviderScope(overrides: overrides(), child: MaterialApp.router(routerConfig: router)));
      router.push('/e');
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Old title'), 'New title');
      await tester.pump();
      await tester.binding.handlePopRoute(); // the phone's back button / gesture
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect((await db.getNoteById(id))!.title, 'New title');
      await finish(tester);
    });
  });

  group('note list', () {
    Future<void> pumpList(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(overrides: overrides(), child: const MaterialApp(home: NoteListScreen())));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('first selected note vibrates once; more selections do not', (tester) async {
      await _addNote(db, 'Alpha');
      await _addNote(db, 'Beta');
      await pumpList(tester);
      await tester.longPress(find.text('Alpha'));
      await tester.pump();
      expect(_platformCalls.where((c) => c.startsWith('HapticFeedback')).length, 1);
      await tester.tap(find.text('Beta'));
      await tester.pump();
      expect(_platformCalls.where((c) => c.startsWith('HapticFeedback')).length, 1, reason: 'only the first selection');
      await finish(tester);
    });

    testWidgets('back button with notes selected clears the selection instead of closing the app', (tester) async {
      await _addNote(db, 'Alpha');
      await pumpList(tester);
      await tester.longPress(find.text('Alpha'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      _platformCalls.clear();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('1 selected'), findsNothing);
      expect(_platformCalls, isNot(contains('SystemNavigator.pop')));
      await finish(tester);
    });

    testWidgets('typing ::vault in the search bar opens the vault setup', (tester) async {
      await _addNote(db, 'Visible note');
      await pumpList(tester);
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '::vault');
      await tester.pumpAndSettle();
      expect(find.text('Set Vault Password'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('typing the vault password in the search bar reveals hidden notes', (tester) async {
      _secure[AppConstants.vaultPasswordKey] = sha256.convert(utf8.encode('secret:prinotes-vault')).toString();
      await _addNote(db, 'Visible note');
      await _addNote(db, 'Secret note', hidden: true);
      await pumpList(tester);
      expect(find.text('Secret note'), findsNothing);
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.pumpAndSettle();
      expect(find.text('Secret note'), findsOneWidget);
      await finish(tester);
    });
  });
}
