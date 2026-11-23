import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/features/notes/presentation/widgets/note_page_editor.dart';
import 'package:prinotes/features/voice/voice_playback.dart';
import 'package:prinotes/features/voice/voice_store.dart';
import 'package:prinotes/features/voice/voice_tile.dart';

Map<String, dynamic> meta(String label) => {'label': label, 'duration': 12000, 'mime': 'audio/mp4'};

Map<String, dynamic> noteWithVoice() => {
      'version': 'quill-1.0',
      'delta': [
        {'insert': 'before\n'},
        {
          'insert': {'voice': 'aaaaaaaa-1'}
        },
        {'insert': '\nafter\n'},
      ],
      'images': <String, dynamic>{},
      'strokes': <dynamic>[],
      'voices': {'aaaaaaaa-1': meta('Delivery date')},
    };

List<String> voiceIdsInDelta(Map<String, dynamic> content) => [
      for (final op in (content['delta'] as List))
        if ((op as Map)['insert'] is Map && (op['insert'] as Map).containsKey('voice')) (op['insert'] as Map)['voice'] as String,
    ];

void main() {
  late Directory tmp;
  late VoiceStore store;
  final changes = <Map<String, dynamic>>[];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('voice_editor');
    store = VoiceStore(tmp);
    File('${tmp.path}/aaaaaaaa-1.m4a').writeAsBytesSync([1]);
    changes.clear();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<GlobalKey<NotePageEditorState>> open(WidgetTester tester, Map<String, dynamic> content) async {
    final key = GlobalKey<NotePageEditorState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 700,
          child: NotePageEditor(key: key, content: content, voiceStore: store, voicePlayback: VoicePlayback.shared, onChanged: changes.add),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    return key;
  }

  testWidgets('a note with a recording shows it as a player', (tester) async {
    await open(tester, noteWithVoice());
    expect(find.byType(VoiceTile), findsOneWidget);
    expect(find.text('Delivery date'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('saving keeps the recording in the text and in the voices list', (tester) async {
    final key = await open(tester, noteWithVoice());
    final c = key.currentState!.currentContent();
    expect(voiceIdsInDelta(c), ['aaaaaaaa-1']);
    expect((c['voices'] as Map).keys, ['aaaaaaaa-1']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a new recording is added at the cursor and the note is told it changed', (tester) async {
    final key = await open(tester, {
      'version': 'quill-1.0',
      'delta': [
        {'insert': 'hello\n'}
      ],
      'images': <String, dynamic>{},
      'strokes': <dynamic>[],
    });
    File('${tmp.path}/bbbbbbbb-2.m4a').writeAsBytesSync([2]); // the recorder has already stored the audio
    key.currentState!.addVoice('bbbbbbbb-2', meta('Voice note 09:05'));
    await tester.pump(const Duration(milliseconds: 200));
    final c = key.currentState!.currentContent();
    expect(voiceIdsInDelta(c), ['bbbbbbbb-2']);
    expect((c['voices'] as Map)['bbbbbbbb-2']['label'], 'Voice note 09:05');
    expect(changes, isNotEmpty);
    expect(find.text('Voice note 09:05'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('several recordings can sit in one note, in the order they were added', (tester) async {
    final key = await open(tester, noteWithVoice());
    key.currentState!.addVoice('bbbbbbbb-2', meta('Second'));
    key.currentState!.addVoice('cccccccc-3', meta('Third'));
    await tester.pump(const Duration(milliseconds: 200));
    final c = key.currentState!.currentContent();
    expect(voiceIdsInDelta(c).toSet(), {'aaaaaaaa-1', 'bbbbbbbb-2', 'cccccccc-3'});
    expect(find.byType(VoiceTile), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('removing a recording takes it out of the text and the list', (tester) async {
    final key = await open(tester, noteWithVoice());
    await tester.tap(find.byKey(const ValueKey('voice-delete')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    final c = key.currentState!.currentContent();
    expect(voiceIdsInDelta(c), isEmpty);
    expect(c.containsKey('voices'), isFalse);
    expect(find.byType(VoiceTile), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('renaming a recording is saved in the note', (tester) async {
    final key = await open(tester, noteWithVoice());
    key.currentState!.renameVoice('aaaaaaaa-1', 'Price and deposit');
    await tester.pump(const Duration(milliseconds: 200));
    expect((key.currentState!.currentContent()['voices'] as Map)['aaaaaaaa-1']['label'], 'Price and deposit');
    expect(find.text('Price and deposit'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a note without recordings has no voices field', (tester) async {
    final key = await open(tester, {
      'version': 'quill-1.0',
      'delta': [
        {'insert': 'hello\n'}
      ],
      'images': <String, dynamic>{},
      'strokes': <dynamic>[],
    });
    expect(key.currentState!.currentContent().containsKey('voices'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('touching a recording does not open the keyboard', (tester) async {
    await open(tester, noteWithVoice());
    await tester.tap(find.byKey(const ValueKey('voice-seek')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  String layout(Map<String, dynamic> c) => [
        for (final op in (c['delta'] as List))
          if ((op as Map)['insert'] is Map) '[voice]' else (op['insert'] as String),
      ].join();

  Map<String, dynamic> threeParagraphs() => {
        'version': 'quill-1.0',
        'delta': [
          {'insert': 'one\n'},
          {
            'insert': {'voice': 'aaaaaaaa-1'}
          },
          {'insert': '\ntwo\nthree\n'},
        ],
        'images': <String, dynamic>{},
        'strokes': <dynamic>[],
        'voices': {'aaaaaaaa-1': meta('Delivery date')},
      };

  testWidgets('a recording dropped on a line further down moves below that line', (tester) async {
    final key = await open(tester, threeParagraphs());
    key.currentState!.moveVoiceToOffset('aaaaaaaa-1', 10); // inside "three"
    await tester.pump(const Duration(milliseconds: 300));
    expect(layout(key.currentState!.currentContent()), 'one\ntwo\nthree\n[voice]\n');
    expect(find.byType(VoiceTile), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a recording dropped on a line above moves above that line', (tester) async {
    final key = await open(tester, threeParagraphs());
    key.currentState!.moveVoiceToOffset('aaaaaaaa-1', 1); // inside "one"
    await tester.pump(const Duration(milliseconds: 300));
    expect(layout(key.currentState!.currentContent()), '[voice]\none\ntwo\nthree\n');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dropping a recording where it already is changes nothing', (tester) async {
    final key = await open(tester, threeParagraphs());
    changes.clear();
    key.currentState!.moveVoiceToOffset('aaaaaaaa-1', 4);
    await tester.pump(const Duration(milliseconds: 300));
    expect(layout(key.currentState!.currentContent()), 'one\n[voice]\ntwo\nthree\n');
    expect(changes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a moved recording keeps its name, length and bars', (tester) async {
    final key = await open(tester, {
      ...threeParagraphs(),
      'voices': {
        'aaaaaaaa-1': {'label': 'Price', 'duration': 12000, 'mime': 'audio/mp4', 'wave': [10, 80, 30]}
      },
    });
    key.currentState!.moveVoiceToOffset('aaaaaaaa-1', 10);
    await tester.pump(const Duration(milliseconds: 300));
    final v = (key.currentState!.currentContent()['voices'] as Map)['aaaaaaaa-1'] as Map;
    expect(v['label'], 'Price');
    expect(v['wave'], [10, 80, 30]);
    await tester.pumpWidget(const SizedBox());
  });
}
