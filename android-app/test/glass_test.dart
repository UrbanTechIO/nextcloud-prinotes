import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/core/theme/glass.dart';
import 'package:prinotes/core/theme/app_theme.dart';

void main() {
  transitionTests();
  group('GlassSettings', () {
    test('defaults to the Classic look with sensible glass opacities', () {
      const s = GlassSettings();
      expect(s.style, ThemeStyle.classic);
      expect(s.glass, isFalse);
      expect(s.headerOpacity, inInclusiveRange(0, 1));
      expect(s.cardOpacity, inInclusiveRange(0, 1));
    });

    test('opacities are clamped to 0..1 so a bad stored value cannot break drawing', () {
      final s = const GlassSettings().copyWith(headerOpacity: 3, cardOpacity: -1);
      expect(s.headerOpacity, 1);
      expect(s.cardOpacity, 0);
    });

    test('parses stored values and falls back to Classic for unknown ones', () {
      expect(GlassSettings.fromStored(style: 'liquid', header: '0.4', card: '0.7').style, ThemeStyle.liquid);
      expect(GlassSettings.fromStored(style: 'frosted', header: null, card: null).glass, isTrue);
      final bad = GlassSettings.fromStored(style: 'nonsense', header: 'x', card: '');
      expect(bad.style, ThemeStyle.classic);
      expect(bad.headerOpacity, const GlassSettings().headerOpacity);
    });
  });

  group('backgrounds', () {
    test('ships several presets, the first is the original look and ids are unique', () {
      expect(kGlassBackgrounds.length, greaterThanOrEqualTo(6));
      expect(kGlassBackgrounds.first.id, 'aurora');
      expect(kGlassBackgrounds.map((b) => b.id).toSet().length, kGlassBackgrounds.length);
      for (final b in kGlassBackgrounds) {
        expect(b.blobs.length, 3);
      }
    });

    test('stored background parses; unknown id falls back to aurora; custom needs a path', () {
      expect(GlassSettings.fromStored(background: 'sunset').background, 'sunset');
      expect(GlassSettings.fromStored(background: 'zzz').background, 'aurora');
      expect(GlassSettings.fromStored(background: 'custom').background, 'aurora', reason: 'no image path');
      final c = GlassSettings.fromStored(background: 'custom', customPath: '/x/bg.jpg');
      expect(c.background, 'custom');
      expect(c.customPath, '/x/bg.jpg');
    });

    testWidgets('GlassBackdrop paints the chosen preset, and an image for custom', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GlassBackdrop(background: 'ocean')));
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const MaterialApp(home: GlassBackdrop(background: 'custom', customPath: '/nope.jpg')));
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('GlassAppBar', () {
    testWidgets('the frosted pane fills the whole header, so it actually paints a bar', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: const GlassAppBar(settings: GlassSettings(style: ThemeStyle.frosted), title: Text('T')),
          body: Container(color: Colors.red),
        ),
      ));
      final pane = tester.getSize(find.byType(BackdropFilter));
      expect(pane.height, greaterThanOrEqualTo(kToolbarHeight), reason: 'a zero-height pane draws nothing');
      expect(pane.width, tester.view.physicalSize.width / tester.view.devicePixelRatio);
    });
  });

  group('trimTopInset', () {
    test('caps a big camera-cutout inset so the header sits at the top of an immersive screen', () {
      const mq = MediaQueryData(padding: EdgeInsets.only(top: 37, bottom: 20), viewPadding: EdgeInsets.only(top: 37, bottom: 20));
      final t = trimTopInset(mq, 8);
      expect(t.padding.top, 8);
      expect(t.viewPadding.top, 8);
      expect(t.padding.bottom, 20, reason: 'only the top changes');
    });

    test('leaves a smaller inset alone', () {
      const mq = MediaQueryData(padding: EdgeInsets.only(top: 3));
      expect(trimTopInset(mq, 8).padding.top, 3);
    });
  });

  group('GlassMenuButton', () {
    Future<List<String>> pumpMenu(WidgetTester tester, ThemeStyle style) async {
      final picked = <String>[];
      await tester.pumpWidget(ProviderScope(
        overrides: [glassInitialProvider.overrideWithValue(GlassSettings(style: style))],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: [
              GlassMenuButton<String>(
                onSelected: picked.add,
                items: const [
                  GlassMenuItem('settings', 'Settings', icon: Icons.settings_outlined),
                  GlassMenuItem('lock', 'Lock app', icon: Icons.lock_outline),
                ],
              ),
            ]),
          ),
        ),
      ));
      return picked;
    }

    testWidgets('glass themes open a glass panel with the entries; picking one reports it', (tester) async {
      final picked = await pumpMenu(tester, ThemeStyle.frosted);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Lock app'), findsOneWidget);
      expect(find.byType(GlassPanel), findsOneWidget, reason: 'menu should be a pane of glass, not a solid popup');
      await tester.tap(find.text('Lock app'));
      await tester.pumpAndSettle();
      expect(picked, ['lock']);
      expect(find.text('Settings'), findsNothing, reason: 'menu closes after a pick');
    });

    testWidgets('Classic keeps the normal popup menu', (tester) async {
      final picked = await pumpMenu(tester, ThemeStyle.classic);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.byType(GlassPanel), findsNothing);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(picked, ['settings']);
    });
  });

  group('HeaderSearch', () {
    Future<_Harness> pump(WidgetTester tester) async {
      final h = _Harness();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(builder: (ctx, set) {
        h.set = set;
        return SizedBox(
          width: 360,
          child: HeaderSearch(
            title: const Text('PriNotes'),
            open: h.open,
            controller: h.ctrl,
            focusNode: h.focus,
            onOpen: () => set(() {
              h.open = true;
              h.opened++;
            }),
            onClose: () => set(() {
              h.open = false;
              h.closed++;
            }),
            onChanged: (q) => h.queries.add(q),
          ),
        );
      }))));
      return h;
    }

    testWidgets('in a loose-width slot (like an AppBar title) the icon sits at the right end, clear of the title', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: HeaderSearch(
                title: const Text('PriNotes'),
                open: false,
                controller: TextEditingController(),
                focusNode: FocusNode(),
                onOpen: () {},
                onClose: () {},
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ));
      final title = tester.getRect(find.text('PriNotes'));
      final icon = tester.getRect(find.byIcon(Icons.search));
      expect(icon.center.dx, greaterThan(300), reason: 'icon belongs at the right end of the slot');
      expect(title.right, lessThan(icon.left), reason: 'title and icon must not overlap');
    });

    testWidgets('the opened field fills the whole header, on top of the action icons', (tester) async {
      final ctrl = TextEditingController();
      final focus = FocusNode();
      late StateSetter set;
      var open = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              child: StatefulBuilder(builder: (ctx, s) {
                set = s;
                return HeaderSearch(
                  title: const Text('PriNotes'),
                  actions: const [Icon(Icons.sync, key: ValueKey('a1')), SizedBox(width: 8), Icon(Icons.more_vert, key: ValueKey('a2'))],
                  open: open,
                  controller: ctrl,
                  focusNode: focus,
                  onOpen: () => s(() => open = true),
                  onClose: () => s(() => open = false),
                  onChanged: (_) {},
                );
              }),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // Closed: the search icon sits left of the action icons.
      expect(tester.getCenter(find.byIcon(Icons.search)).dx, lessThan(tester.getCenter(find.byKey(const ValueKey('a1'))).dx));
      set(() => open = true);
      await tester.pumpAndSettle();
      final field = tester.getRect(find.byKey(const ValueKey('header-search-field')));
      final more = tester.getRect(find.byKey(const ValueKey('a2')));
      expect(field.width, greaterThan(330), reason: 'field should span the header, not stay small');
      expect(field.right, greaterThan(more.center.dx), reason: 'field must cover the last action icon');
      expect(field.left, lessThan(20));
    });

    testWidgets('on first show the search icon is already beside the actions, it does not slide in from the edge', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              child: HeaderSearch(
                title: const Text('PriNotes'),
                actions: const [Icon(Icons.sync, key: ValueKey('a1')), SizedBox(width: 8), Icon(Icons.more_vert, key: ValueKey('a2'))],
                open: false,
                controller: TextEditingController(),
                focusNode: FocusNode(),
                onOpen: () {},
                onClose: () {},
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ));
      await tester.pump(); // measures the actions
      await tester.pump(); // applies their width
      final icon = tester.getRect(find.byIcon(Icons.search));
      final firstAction = tester.getRect(find.byKey(const ValueKey('a1')));
      expect(icon.right, lessThanOrEqualTo(firstAction.left + 1), reason: 'icon must not be gliding in from the right edge');
    });

    testWidgets('shows the title and a search icon, with no text field until opened', (tester) async {
      await pump(tester);
      expect(find.text('PriNotes'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('tapping the icon opens the field; typing reports the query', (tester) async {
      final h = await pump(tester);
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      expect(h.opened, 1);
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'keto');
      expect(h.queries.last, 'keto');
    });

    testWidgets('the close button clears the text and reports the close', (tester) async {
      final h = await pump(tester);
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'keto');
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(h.closed, 1);
      expect(h.ctrl.text, isEmpty);
      expect(h.queries.last, '');
      expect(find.byType(TextField), findsNothing);
    });
  });
}

class _Harness {
  bool open = false;
  int opened = 0;
  int closed = 0;
  final List<String> queries = [];
  final ctrl = TextEditingController();
  final focus = FocusNode();
  late StateSetter set;
}

void transitionTests() {
  testWidgets('glass theme: old page is gone right after a push, no overlap', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.glass(const GlassSettings(style: ThemeStyle.frosted)),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('second')))),
            child: const Text('first'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('first'));
    await tester.pump(); // start
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('second'), findsOneWidget);
    expect(find.text('first'), findsNothing, reason: 'old page must not stay drawn under the new one');
  });
}
