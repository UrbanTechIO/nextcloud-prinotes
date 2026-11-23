import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/features/notes/presentation/widgets/note_page_editor.dart';

Future<GlobalKey<NotePageEditorState>> open(WidgetTester tester, String text, List<Map<String, dynamic>> changes) async {
  final key = GlobalKey<NotePageEditorState>();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 360,
        height: 700,
        child: NotePageEditor(
          key: key,
          content: {
            'version': 'quill-1.0',
            'delta': [
              {'insert': text}
            ],
            'images': <String, dynamic>{},
            'strokes': <dynamic>[],
          },
          onChanged: changes.add,
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  return key;
}

String plain(Map<String, dynamic> c) => (c['delta'] as List).map((o) => (o as Map)['insert']).whereType<String>().join();

void main() {
  testWidgets('scanned text goes into the note on its own line and the note is told it changed', (tester) async {
    final changes = <Map<String, dynamic>>[];
    final key = await open(tester, 'hello\n', changes);
    key.currentState!.insertText('Thank you for your order');
    expect(plain(key.currentState!.currentContent()), contains('Thank you for your order\n'));
    expect(changes, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('scanned text lands at the cursor (the start of a fresh note), and the next scanned line follows it', (tester) async {
    final key = await open(tester, 'ab\n', []);
    key.currentState!.insertText('ONE');
    key.currentState!.insertText('TWO');
    expect(plain(key.currentState!.currentContent()), 'ONE\nTWO\nab\n');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with the cursor moved to the end, scanned text is added after what is already written', (tester) async {
    final key = await open(tester, 'ab\n', []);
    key.currentState!.moveCursorToEnd();
    key.currentState!.insertText('ONE');
    key.currentState!.insertText('TWO');
    expect(plain(key.currentState!.currentContent()), 'ab\nONE\nTWO\n');
    await tester.pumpWidget(const SizedBox());
  });
}
