import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/core/widgets/app_sidebar.dart';
import 'package:prinotes/data/local/database.dart';
import 'package:prinotes/features/notes/presentation/widgets/sidebar_drawer.dart';
import 'package:prinotes/features/notes/providers/notes_provider.dart';
import 'package:prinotes/features/todo/presentation/todo_drawer.dart';
import 'package:prinotes/features/todo/providers/todo_provider.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<int> list(String title, {int? parent, bool system = false, String? color}) =>
      db.insertTodoList(TodoListsCompanion.insert(
        title: title,
        createdAt: 1,
        updatedAt: 1,
        parentLocalId: Value(parent),
        isSystem: Value(system),
        color: Value(color),
      ));
  Future<void> task(int listId, {String? due, bool important = false}) => db.insertTodo(TodosCompanion.insert(
        listLocalId: listId,
        title: 't',
        createdAt: 1,
        updatedAt: 1,
        dueDate: Value(due),
        isImportant: Value(important),
      ));

  Future<void> pump(WidgetTester tester, Widget drawer, {Size size = const Size(360, 780)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(drawer: drawer, body: const SizedBox())),
    ));
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  group('sidebar width follows the screen', () {
    test('80% of the screen, between 272 and 320 dp', () {
      expect(sidebarWidth(320), 272, reason: '80% would be 256: raised to the minimum');
      expect(sidebarWidth(360), closeTo(288, 0.01));
      expect(sidebarWidth(412), 320, reason: '80% would be 329.6: capped');
      expect(sidebarWidth(800), 320, reason: 'tablets and landscape stay a side panel');
    });

    testWidgets('the drawer is that wide on screen', (tester) async {
      await pump(tester, const TodoDrawer(), size: const Size(412, 860));
      expect(tester.getSize(find.byType(Drawer)).width, 320);
      await finish(tester);
    });
  });

  group('To-Do sidebar', () {
    testWidgets('shows the four smart lists as tiles with their counts, and a tap selects one', (tester) async {
      final home = await list('Home');
      await task(home, important: true);
      await task(home, due: '2000-01-01');
      await task(home);
      await pump(tester, const TodoDrawer());
      for (final label in ['Today', 'Important', 'Planned', 'All tasks']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.byType(SidebarTile), findsNWidgets(4));
      await tester.tap(find.text('Important'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(container.read(todoViewProvider), const TodoViewSel.smart('important'));
      await finish(tester);
    });

    testWidgets('categories are plain rows: one line each, no + and pencil on every row', (tester) async {
      await list('Home Repair');
      await list('HomeAssistant with a very long name that cannot possibly fit on one line');
      await pump(tester, const TodoDrawer());
      expect(find.byIcon(Icons.add), findsOneWidget, reason: 'only the one in the Categories header');
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      final long = tester.widget<Text>(find.textContaining('HomeAssistant with'));
      expect(long.maxLines, 1);
      expect(long.overflow, TextOverflow.ellipsis);
      await finish(tester);
    });

    testWidgets('a category with sub-categories is collapsed until its arrow is tapped', (tester) async {
      final parent = await list('Nextcloud');
      await list('Prinotes', parent: parent);
      await list('UrbanPhotos', parent: parent);
      await pump(tester, const TodoDrawer());
      expect(find.text('Prinotes'), findsNothing);
      expect(find.textContaining('2 sub'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Prinotes'), findsOneWidget);
      expect(find.text('UrbanPhotos'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('long-press on a category offers Edit and, for top-level ones, Add sub-category', (tester) async {
      await list('Travel Plan');
      await pump(tester, const TodoDrawer());
      await tester.longPress(find.text('Travel Plan'));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Add sub-category'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a system category (Inbox) has no Add sub-category', (tester) async {
      await list('Inbox', system: true);
      await pump(tester, const TodoDrawer());
      await tester.longPress(find.text('Inbox'));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Add sub-category'), findsNothing);
      await finish(tester);
    });

    testWidgets('Notes / To-Do switch is at the top with To-Do selected', (tester) async {
      await pump(tester, const TodoDrawer());
      expect(find.text('Notes'), findsWidgets);
      expect(find.byType(SidebarModeSwitch), findsOneWidget);
      await finish(tester);
    });
  });

  group('Notes sidebar', () {
    testWidgets('tiles for All notes and Archived; notebooks as rows; tags as chips; no delete X on rows', (tester) async {
      await db.into(db.notebooks).insert(NotebooksCompanion.insert(title: 'Coding', createdAt: 1, updatedAt: 1));
      await db.into(db.tags).insert(TagsCompanion.insert(name: 'Business', createdAt: 1));
      await pump(tester, const SidebarDrawer());
      expect(find.byType(SidebarTile), findsNWidgets(2));
      expect(find.text('All notes'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
      expect(find.text('Coding'), findsOneWidget);
      expect(find.text('#Business'), findsOneWidget);
      expect(find.byType(SidebarChip), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing, reason: 'delete moved to long-press');
      await finish(tester);
    });

    testWidgets('long-press on a notebook offers Delete, and asks before deleting', (tester) async {
      final id = await db.into(db.notebooks).insert(NotebooksCompanion.insert(title: 'Coding', createdAt: 1, updatedAt: 1));
      await pump(tester, const SidebarDrawer());
      await tester.longPress(find.text('Coding'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete notebook?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect((await db.select(db.notebooks).get()).any((n) => n.id == id && !n.isDeleted), isTrue);
      await finish(tester);
    });
  });

  group('bottom bar', () {
    testWidgets('on a tall screen it stays pinned at the bottom', (tester) async {
      await pump(tester, const TodoDrawer(), size: const Size(360, 780));
      final bottom = tester.getBottomLeft(find.text('Lock')).dy;
      expect(bottom, greaterThan(700));
      await finish(tester);
    });

    testWidgets('on a short (landscape) screen it scrolls with the list and nothing overflows', (tester) async {
      await list('Home');
      await pump(tester, const TodoDrawer(), size: const Size(800, 360));
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Lock'), 120,
          scrollable: find.descendant(of: find.byType(Drawer), matching: find.byType(Scrollable)).first);
      expect(find.text('Lock'), findsOneWidget);
      await finish(tester);
    });
  });
}
