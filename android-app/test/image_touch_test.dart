import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/features/notes/presentation/widgets/note_page_editor.dart';

// A 30 x 60 picture.
const png =
    'iVBORw0KGgoAAAANSUhEUgAAAB4AAAA8CAIAAAD+Np3IAAAAMElEQVR4nO3MsQ0AAAwCIP9/2l5hupAwkyYjq1etVqvVarVarVar1Wq1Wq1Wq/tVH8vxAWKq2xQJAAAAAElFTkSuQmCC';

Future<GlobalKey<NotePageEditorState>> open(WidgetTester tester) async {
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
              {'insert': 'top\n'},
              {
                'insert': {'image': 'img1'}
              },
              {'insert': '\nbottom\n'},
            ],
            'images': {
              'img1': {'data': 'data:image/png;base64,$png', 'width': 120.0, 'height': 240.0, 'rotation': 0.0}
            },
            'strokes': <dynamic>[],
          },
          onChanged: (_) {},
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  return key;
}

Map imageOf(GlobalKey<NotePageEditorState> key) =>
    ((key.currentState!.currentContent()['images'] as Map).values.first as Map);

void main() {
  testWidgets('tapping a picture selects it and does not open the keyboard', (tester) async {
    final key = await open(tester);
    await tester.tap(find.byType(Image));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(Icons.close), findsOneWidget, reason: 'selected: the delete button shows');
    expect(tester.testTextInput.isVisible, isFalse);
    expect(key.currentState, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping a picture that is already selected keeps it selected', (tester) async {
    await open(tester);
    await tester.tap(find.byType(Image));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byType(Image));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the delete button works on the part that sticks out of the picture', (tester) async {
    final key = await open(tester);
    await tester.tap(find.byType(Image));
    await tester.pump(const Duration(milliseconds: 400));
    final c = tester.getCenter(find.byIcon(Icons.close));
    await tester.tapAt(c + const Offset(5, -5)); // the outer corner of the red button
    await tester.pump(const Duration(milliseconds: 400));
    expect((key.currentState!.currentContent()['images'] as Map), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a resize handle works on the part that sticks out of the picture', (tester) async {
    final key = await open(tester);
    await tester.tap(find.byType(Image));
    await tester.pump(const Duration(milliseconds: 400));
    final corner = tester.getRect(find.byType(Image)).bottomRight;
    final before = (imageOf(key)['width'] as num).toDouble();
    final g = await tester.startGesture(corner + const Offset(9, 9)); // outside the picture, on the handle
    await g.moveBy(const Offset(20, 0));
    await g.moveBy(const Offset(20, 0));
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect((imageOf(key)['width'] as num).toDouble(), greaterThan(before + 20));
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resizing keeps the picture\'s shape when a corner is dragged', (tester) async {
    final key = await open(tester);
    await tester.tap(find.byType(Image));
    await tester.pump(const Duration(milliseconds: 400));
    final corner = tester.getRect(find.byType(Image)).bottomRight;
    final g = await tester.startGesture(corner);
    await g.moveBy(const Offset(15, 0));
    await g.moveBy(const Offset(15, 0));
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
    final img = imageOf(key);
    expect((img['width'] as num) / (img['height'] as num), closeTo(0.5, 1e-6));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping the text after using a picture brings the keyboard back', (tester) async {
    await open(tester);
    await tester.tap(find.byType(Image));
    await tester.pump(const Duration(milliseconds: 400));
    final editor = tester.getTopLeft(find.byType(QuillEditor));
    await tester.tapAt(editor + const Offset(40, 24)); // on the word "top"
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(Icons.close), findsNothing, reason: 'deselected');
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
