import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/data/local/database.dart';
import 'package:prinotes/features/notes/presentation/note_list_screen.dart' show noteGridDelegate;
import 'package:prinotes/features/notes/presentation/widgets/sidebar_drawer.dart';
import 'package:prinotes/features/notes/providers/notes_provider.dart';
import 'package:prinotes/features/todo/presentation/todo_drawer.dart';
import 'package:prinotes/features/todo/providers/todo_provider.dart';

SliverConstraints _c(double w) => SliverConstraints(
      axisDirection: AxisDirection.down,
      growthDirection: GrowthDirection.forward,
      userScrollDirection: ScrollDirection.idle,
      scrollOffset: 0,
      precedingScrollExtent: 0,
      overlap: 0,
      remainingPaintExtent: 600,
      crossAxisExtent: w,
      crossAxisDirection: AxisDirection.right,
      viewportMainAxisExtent: 600,
      remainingCacheExtent: 600,
      cacheOrigin: 0,
    );

void main() {
  group('last opened To-Do view is remembered', () {
    test('encodes and decodes smart lists and categories', () {
      expect(const TodoViewSel.smart('important').encode(), 'smart:important');
      expect(const TodoViewSel.list(7).encode(), 'list:7');
      expect(TodoViewSel.decode('smart:planned'), const TodoViewSel.smart('planned'));
      expect(TodoViewSel.decode('list:7'), const TodoViewSel.list(7));
    });

    test('a saved category that no longer exists falls back to Today', () {
      expect(const TodoViewSel.list(7).existingIn({1, 7}), const TodoViewSel.list(7));
      expect(const TodoViewSel.list(7).existingIn({1, 2}), const TodoViewSel.smart('today'));
      expect(const TodoViewSel.smart('all').existingIn({}), const TodoViewSel.smart('all'));
    });

    test('anything unreadable falls back to Today', () {
      for (final bad in [null, '', 'junk', 'smart:nope', 'list:x', 'list:']) {
        expect(TodoViewSel.decode(bad), const TodoViewSel.smart('today'), reason: '$bad');
      }
    });
  });

  group('note grid', () {
    test('portrait keeps two columns', () {
      final l = noteGridDelegate.getLayout(_c(336)) as SliverGridRegularTileLayout;
      expect(l.crossAxisStride > 0, isTrue);
      expect((336 / l.crossAxisStride).round(), 2);
    });

    test('landscape adds columns instead of stretching the cards', () {
      final l = noteGridDelegate.getLayout(_c(800)) as SliverGridRegularTileLayout;
      final cols = (800 / l.crossAxisStride).round();
      expect(cols, greaterThanOrEqualTo(4));
      expect(l.crossAxisStride, lessThanOrEqualTo(260));
    });
  });

  group('drawers scroll in landscape', () {
    Future<void> pump(WidgetTester tester, Widget drawer) async {
      tester.view.physicalSize = const Size(800, 360); // landscape phone
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: Scaffold(drawer: drawer, body: const SizedBox())),
      ));
      final s = tester.firstState<ScaffoldState>(find.byType(Scaffold));
      s.openDrawer();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    for (final entry in {'notes': const SidebarDrawer(), 'to-do': const TodoDrawer()}.entries) {
      testWidgets('${entry.key} drawer: the last item can be scrolled into view, no overflow', (tester) async {
        await pump(tester, entry.value);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('Lock'), 120, scrollable: find.descendant(of: find.byType(Drawer), matching: find.byType(Scrollable)).first);
        expect(find.text('Lock'), findsOneWidget);
        // Let drift's stream clean-up timers run before the test ends.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  });
}
