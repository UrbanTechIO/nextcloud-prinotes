import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/features/notes/presentation/widgets/note_page_editor.dart';

Map<String, dynamic> note({List<Map<String, dynamic>> strokes = const []}) => {
      'version': 'quill-1.0',
      'delta': [
        {'insert': 'hello\n'}
      ],
      'images': <String, dynamic>{},
      'strokes': strokes,
    };

const stroke = {
  'pts': [
    [10.0, 10.0],
    [60.0, 80.0]
  ],
  'color': '0xff112233',
  'width': 4.0,
  'eraser': false,
};

Future<Map<String, dynamic>> contentOf(WidgetTester tester, Map<String, dynamic> content, double width) async {
  final key = GlobalKey<NotePageEditorState>();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, height: 700, child: NotePageEditor(key: key, content: content, onChanged: (_) {})),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  return key.currentState!.currentContent();
}

void main() {
  drawColorTests();
  testWidgets('a note with a drawing also records the page width it was drawn on (the web needs it to scale it)', (tester) async {
    final c = await contentOf(tester, note(strokes: [Map<String, dynamic>.from(stroke)]), 360);
    expect(c['strokesWidth'], 360);
    expect((c['strokes'] as List).length, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a different page width is recorded as it is', (tester) async {
    final c = await contentOf(tester, note(strokes: [Map<String, dynamic>.from(stroke)]), 412);
    expect(c['strokesWidth'], 412);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a note without a drawing is left exactly as before (no new field)', (tester) async {
    final c = await contentOf(tester, note(), 360);
    expect(c.containsKey('strokesWidth'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<String> firstStrokeColor(WidgetTester tester, ThemeData theme) async {
  final key = GlobalKey<NotePageEditorState>();
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(body: SizedBox(width: 360, height: 700, child: NotePageEditor(key: key, content: note(), onChanged: (_) {}))),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text('Draw'));
  await tester.pump(const Duration(milliseconds: 100));
  final g = await tester.startGesture(const Offset(120, 300));
  await g.moveTo(const Offset(220, 360));
  await g.moveTo(const Offset(260, 330));
  await g.up();
  await tester.pump();
  final strokes = key.currentState!.currentContent()['strokes'] as List;
  expect(strokes, isNotEmpty);
  final c = (strokes.first as Map)['color'] as String;
  await tester.pumpWidget(const SizedBox());
  return c;
}

void drawColorTests() {
  testWidgets('the pen starts white on a dark theme', (tester) async {
    expect(await firstStrokeColor(tester, ThemeData.dark()), '0xffffffff');
  });

  testWidgets('the pen starts black on a light theme (white would be invisible there)', (tester) async {
    expect(await firstStrokeColor(tester, ThemeData.light()), '0xff000000');
  });
}
