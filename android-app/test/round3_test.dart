import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/data/local/database.dart';
import 'package:prinotes/features/notes/data/image_size.dart';
import 'package:prinotes/features/notes/presentation/widgets/note_page_editor.dart';
import 'package:prinotes/features/todo/reminders/reminder_settings.dart';
import 'package:prinotes/features/todo/reminders/reminder_signature.dart';

// A 30 x 60 picture (a portrait one).
const portraitPng =
    'iVBORw0KGgoAAAANSUhEUgAAAB4AAAA8CAIAAAD+Np3IAAAAMElEQVR4nO3MsQ0AAAwCIP9/2l5hupAwkyYjq1etVqvVarVarVar1Wq1Wq1Wq/tVH8vxAWKq2xQJAAAAAElFTkSuQmCC';

Future<int> addNote(AppDatabase db, {bool trashed = false, bool hidden = false}) async {
  final id = await db.into(db.notes).insert(NotesCompanion.insert(
        title: const Value('n'),
        content: const Value('{}'),
        createdAt: 1,
        updatedAt: 1,
        isTrashed: Value(trashed),
      ));
  if (hidden) await db.setNoteHidden(id, hidden: true);
  return id;
}

void main() {
  group('trash count', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('counts the notes in the trash and nothing else', () async {
      await addNote(db);
      await addNote(db, trashed: true);
      await addNote(db, trashed: true);
      expect(await db.watchTrashCount().first, 2);
    });

    test('hidden notes in the trash are counted only while the vault is open', () async {
      await addNote(db, trashed: true);
      await addNote(db, trashed: true, hidden: true);
      expect(await db.watchTrashCount().first, 1);
      expect(await db.watchTrashCount(showHidden: true).first, 2);
    });

    test('an empty trash counts zero', () async {
      expect(await db.watchTrashCount().first, 0);
    });
  });

  group('picture shape', () {
    testWidgets('the shape of a picture is read from the picture itself', (tester) async {
      final aspect = await tester.runAsync(() => imageAspect(base64Decode(portraitPng)));
      expect(aspect, closeTo(0.5, 1e-9));
    });

    testWidgets('something that is not a picture has no shape', (tester) async {
      final aspect = await tester.runAsync(() => imageAspect(base64Decode('AAAA')));
      expect(aspect, isNull);
    });

    testWidgets('a portrait picture is added tall, not forced into a wide frame', (tester) async {
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
                  {'insert': 'hi\n'}
                ],
                'images': <String, dynamic>{},
                'strokes': <dynamic>[],
              },
              onChanged: (_) {},
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      key.currentState!.addImage('data:image/png;base64,$portraitPng', aspect: 0.5);
      final images = key.currentState!.currentContent()['images'] as Map;
      final img = images.values.first as Map;
      expect((img['width'] as num) / (img['height'] as num), closeTo(0.5, 1e-9));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('without a known shape the old wide default stays', (tester) async {
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
                  {'insert': 'hi\n'}
                ],
                'images': <String, dynamic>{},
                'strokes': <dynamic>[],
              },
              onChanged: (_) {},
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      key.currentState!.addImage('data:image/png;base64,$portraitPng');
      final img = (key.currentState!.currentContent()['images'] as Map).values.first as Map;
      expect((img['width'] as num) / (img['height'] as num), closeTo(4 / 3, 1e-9));
      await tester.pumpWidget(const SizedBox());
    });

    test('a very tall picture gets narrower instead of being squashed', () {
      final tall = pictureSize(maxWidth: 200, aspect: 0.1);
      expect(tall.height, lessThanOrEqualTo(600));
      expect(tall.width / tall.height, closeTo(0.1, 1e-9));
      final normal = pictureSize(maxWidth: 200, aspect: 0.5);
      expect(normal.width, closeTo(200, 1e-9));
      expect(normal.height, closeTo(400, 1e-9));
    });
  });

  group('Nextcloud reminders are off unless the user turns them on', () {
    test('no setting yet means off', () {
      expect(nextcloudRemindersOn(null), isFalse);
      expect(nextcloudRemindersOn(<String, dynamic>{}), isFalse);
      expect(nextcloudRemindersOn('not a map'), isFalse);
    });

    test('only an explicit true turns them on', () {
      expect(nextcloudRemindersOn({'todo_nextcloud_reminders': 'true'}), isTrue);
      expect(nextcloudRemindersOn({'todo_nextcloud_reminders': 'false'}), isFalse);
      expect(nextcloudRemindersOn({'todo_nextcloud_reminders': 'maybe'}), isFalse);
    });

    test('the old setting no longer counts (it defaulted to on)', () {
      expect(nextcloudRemindersOn({'todo_nextcloud_notifications': 'true'}), isFalse);
    });
  });

  group('alarm signature', () {
    Todo todo({int id = 1, int? remindAt = 100, bool done = false, bool deleted = false, String title = 'a'}) => Todo(
          id: id,
          remoteId: null,
          listLocalId: 1,
          title: title,
          note: null,
          isDone: done,
          doneAt: null,
          dueDate: null,
          remindAt: remindAt,
          reminderSent: false,
          repeatRule: null,
          isImportant: false,
          steps: '[]',
          sortOrder: 0,
          createdAt: 1,
          updatedAt: 1,
          version: 1,
          isSynced: true,
          hasLocalChanges: false,
          isDeleted: deleted,
        );

    test('the same tasks give the same signature', () {
      expect(reminderSignature([todo(), todo(id: 2)]), reminderSignature([todo(), todo(id: 2)]));
    });

    test('a changed reminder time, a finished or deleted task, or a new title changes it', () {
      final base = reminderSignature([todo()]);
      expect(reminderSignature([todo(remindAt: 200)]), isNot(base));
      expect(reminderSignature([todo(done: true)]), isNot(base));
      expect(reminderSignature([todo(deleted: true)]), isNot(base));
      expect(reminderSignature([todo(title: 'b')]), isNot(base));
    });

    test('tasks without a reminder, or only other changes, do not change it', () {
      expect(reminderSignature([todo(remindAt: null)]), reminderSignature([todo(remindAt: null, title: 'zzz')]));
    });
  });
}
