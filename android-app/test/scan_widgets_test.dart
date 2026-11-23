import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/features/scan/flying_lines.dart';
import 'package:prinotes/features/scan/scan_panel.dart';

void main() {
  testWidgets('a scanned line rises and enters the note only when it has arrived', (tester) async {
    final key = GlobalKey<FlyingLinesState>();
    final landed = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox(height: 300, child: FlyingLines(key: key, rise: 400))),
    ));
    key.currentState!.launch('Thank you for your order', () => landed.add('Thank you for your order'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Thank you for your order'), findsOneWidget);
    expect(landed, isEmpty);
    await tester.pump(const Duration(milliseconds: 900));
    expect(landed, ['Thank you for your order']);
    await tester.pump();
    expect(find.text('Thank you for your order'), findsNothing);
  });

  testWidgets('lines launched one after the other land in the same order', (tester) async {
    final key = GlobalKey<FlyingLinesState>();
    final landed = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox(height: 300, child: FlyingLines(key: key, rise: 400))),
    ));
    for (final t in ['one', 'two', 'three']) {
      key.currentState!.launch(t, () => landed.add(t));
    }
    await tester.pump(const Duration(seconds: 1));
    expect(landed, ['one', 'two', 'three']);
    await tester.pump();
  });

  testWidgets('the photo text can be corrected, and Insert gives the corrected text', (tester) async {
    String? inserted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: SnapResultBox(text: 'Helo world', onRetake: () {}, onInsert: (t) => inserted = t),
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'Hello world');
    await tester.tap(find.text('Insert'));
    expect(inserted, 'Hello world');
  });

  testWidgets('Retake leaves the note alone', (tester) async {
    String? inserted;
    var retook = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: SnapResultBox(text: 'abc def', onRetake: () => retook = true, onInsert: (t) => inserted = t),
        ),
      ),
    ));
    await tester.tap(find.text('Retake'));
    expect(retook, isTrue);
    expect(inserted, isNull);
  });

  testWidgets('when nothing was read the box says so and Insert does nothing', (tester) async {
    String? inserted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(height: 400, child: SnapResultBox(text: '', onRetake: () {}, onInsert: (t) => inserted = t)),
      ),
    ));
    expect(find.text('No text found'), findsOneWidget);
    await tester.tap(find.text('Insert'));
    expect(inserted, isNull);
  });
}
