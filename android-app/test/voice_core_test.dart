import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/features/voice/voice_content.dart';
import 'package:prinotes/features/voice/voice_store.dart';
import 'package:prinotes/features/voice/voice_sync.dart';

/// A server that keeps recordings in memory and can be made to fail.
class FakeVoiceApi implements VoiceApi {
  final Map<String, Uint8List> server = {};
  bool offline = false;
  final calls = <String>[];

  @override
  Future<void> upload(String id, File file, String mime) async {
    calls.add('up $id');
    if (offline) throw const SocketException('offline');
    server[id] = await file.readAsBytes();
  }

  @override
  Future<Uint8List?> download(String id) async {
    calls.add('down $id');
    if (offline) throw const SocketException('offline');
    return server[id];
  }

  @override
  Future<void> delete(String id) async {
    calls.add('del $id');
    if (offline) throw const SocketException('offline');
    server.remove(id);
  }
}

String noteWith(List<String> ids) =>
    '{"version":"quill-1.0","delta":[{"insert":"hi\\n"}],"images":{},"strokes":[],"voices":{${ids.map((i) => '"$i":{"label":"Voice note","duration":5000,"mime":"audio/mp4"}').join(',')}}}';

DateTime now = DateTime(2026, 11, 23, 12);

void main() {
  late Directory tmp;
  late VoiceStore store;

  setUp(() async {
    now = DateTime(2026, 11, 23, 12);
    tmp = await Directory.systemTemp.createTemp('voice_test');
    store = VoiceStore(tmp, clock: () => now);
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<File> recorded(String name, List<int> bytes) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(bytes);
    return f;
  }

  group('note content', () {
    test('the recordings a note uses are found from its content', () {
      expect(voiceIdsIn(noteWith(['aaaaaaaa-1', 'bbbbbbbb-2'])), {'aaaaaaaa-1', 'bbbbbbbb-2'});
    });

    test('a note without recordings, or with unreadable content, uses none', () {
      expect(voiceIdsIn('{"version":"quill-1.0","delta":[]}'), isEmpty);
      expect(voiceIdsIn('not json'), isEmpty);
      expect(voiceIdsIn(''), isEmpty);
      expect(voiceIdsIn(null), isEmpty);
    });

    test('the type of each recording is read from the note', () {
      expect(voiceMimesIn(noteWith(['aaaaaaaa-1'])), {'aaaaaaaa-1': 'audio/mp4'});
    });

    test('a new recording gets a label with the time, a length and a type', () {
      final meta = newVoiceMeta(durationMs: 4200, mime: 'audio/mp4', at: DateTime(2026, 11, 23, 9, 5));
      expect(meta['label'], 'Voice note 09:05');
      expect(meta['duration'], 4200);
      expect(meta['mime'], 'audio/mp4');
    });

    test('lengths are shown as minutes and seconds', () {
      expect(formatVoiceLength(0), '0:00');
      expect(formatVoiceLength(4200), '0:04');
      expect(formatVoiceLength(65000), '1:05');
      expect(formatVoiceLength(3725000), '62:05');
    });
  });

  group('local store', () {
    test('a recording moves into the store and can be found again by its id', () async {
      final f = await recorded('rec.m4a', [1, 2, 3]);
      await store.adopt(f, 'aaaaaaaa-1', 'audio/mp4');
      expect(store.find('aaaaaaaa-1'), isNotNull);
      expect(await store.find('aaaaaaaa-1')!.readAsBytes(), [1, 2, 3]);
      expect(store.find('bbbbbbbb-2'), isNull);
    });

    test('a new recording waits for upload until it is marked uploaded', () async {
      await store.adopt(await recorded('r.m4a', [1]), 'aaaaaaaa-1', 'audio/mp4');
      expect(store.pendingUploads(), ['aaaaaaaa-1']);
      store.markUploaded('aaaaaaaa-1');
      expect(store.pendingUploads(), isEmpty);
      expect(store.isUploaded('aaaaaaaa-1'), isTrue);
    });

    test('a downloaded recording is stored as already uploaded', () async {
      await store.saveDownloaded('cccccccc-3', 'audio/webm', Uint8List.fromList([9, 9]));
      expect(store.pendingUploads(), isEmpty);
      expect(await store.find('cccccccc-3')!.readAsBytes(), [9, 9]);
    });

    test('removing a recording removes the file and its marks', () async {
      await store.adopt(await recorded('r.m4a', [1]), 'aaaaaaaa-1', 'audio/mp4');
      store.markUploaded('aaaaaaaa-1');
      await store.remove('aaaaaaaa-1');
      expect(store.find('aaaaaaaa-1'), isNull);
      expect(store.isUploaded('aaaaaaaa-1'), isFalse);
      expect(store.localIds(), isEmpty);
    });

    test('the store lists the recordings it holds', () async {
      await store.adopt(await recorded('a.m4a', [1]), 'aaaaaaaa-1', 'audio/mp4');
      await store.saveDownloaded('cccccccc-3', 'audio/webm', Uint8List.fromList([2]));
      expect(store.localIds(), {'aaaaaaaa-1', 'cccccccc-3'});
    });
  });

  group('sync', () {
    late FakeVoiceApi api;
    late VoiceSync sync;

    setUp(() {
      api = FakeVoiceApi();
      sync = VoiceSync(store, api, clock: () => now);
    });

    test('a new recording is uploaded once, then left alone', () async {
      await store.adopt(await recorded('r.m4a', [1, 2]), 'aaaaaaaa-1', 'audio/mp4');
      await sync.run(notes: [noteWith(['aaaaaaaa-1'])]);
      expect(api.server['aaaaaaaa-1'], [1, 2]);
      api.calls.clear();
      await sync.run(notes: [noteWith(['aaaaaaaa-1'])]);
      expect(api.calls, isEmpty);
    });

    test('offline: the recording stays queued and goes up on the next sync', () async {
      await store.adopt(await recorded('r.m4a', [1]), 'aaaaaaaa-1', 'audio/mp4');
      api.offline = true;
      await sync.run(notes: [noteWith(['aaaaaaaa-1'])]); // must not throw
      expect(store.pendingUploads(), ['aaaaaaaa-1']);
      api.offline = false;
      await sync.run(notes: [noteWith(['aaaaaaaa-1'])]);
      expect(api.server.containsKey('aaaaaaaa-1'), isTrue);
      expect(store.pendingUploads(), isEmpty);
    });

    test('a recording made on another device is downloaded when a note uses it', () async {
      api.server['dddddddd-4'] = Uint8List.fromList([7, 7, 7]);
      await sync.run(notes: [noteWith(['dddddddd-4'])]);
      expect(await store.find('dddddddd-4')!.readAsBytes(), [7, 7, 7]);
      expect(store.isUploaded('dddddddd-4'), isTrue);
    });

    test('a recording is downloaded only once', () async {
      api.server['dddddddd-4'] = Uint8List.fromList([7]);
      await sync.run(notes: [noteWith(['dddddddd-4'])]);
      api.calls.clear();
      await sync.run(notes: [noteWith(['dddddddd-4'])]);
      expect(api.calls, isEmpty);
    });

    test('a recording the server does not have is skipped without an error', () async {
      await sync.run(notes: [noteWith(['eeeeeeee-5'])]);
      expect(store.find('eeeeeeee-5'), isNull);
    });

    test('offline: downloads wait and nothing throws', () async {
      api.server['dddddddd-4'] = Uint8List.fromList([7]);
      api.offline = true;
      await sync.run(notes: [noteWith(['dddddddd-4'])]);
      expect(store.find('dddddddd-4'), isNull);
    });

    test('a recording no note uses is deleted here and on the server after the grace period', () async {
      await store.adopt(await recorded('r.m4a', [1]), 'aaaaaaaa-1', 'audio/mp4');
      await sync.run(notes: [noteWith(['aaaaaaaa-1'])]);
      now = now.add(const Duration(hours: 3));
      await sync.run(notes: [noteWith([])]);
      expect(store.find('aaaaaaaa-1'), isNull);
      expect(api.server.containsKey('aaaaaaaa-1'), isFalse);
    });

    test('a brand new recording is not deleted before its note has been saved', () async {
      await store.adopt(await recorded('r.m4a', [1]), 'aaaaaaaa-1', 'audio/mp4');
      await sync.run(notes: [noteWith([])]); // the note is not saved yet
      expect(store.find('aaaaaaaa-1'), isNotNull);
      expect(api.server.containsKey('aaaaaaaa-1'), isTrue);
    });

    test('a recording used by any note, trashed ones included, is kept', () async {
      await store.adopt(await recorded('r.m4a', [1]), 'aaaaaaaa-1', 'audio/mp4');
      await sync.run(notes: [noteWith(['aaaaaaaa-1'])]);
      now = now.add(const Duration(days: 3));
      await sync.run(notes: [noteWith([]), noteWith(['aaaaaaaa-1'])]);
      expect(store.find('aaaaaaaa-1'), isNotNull);
    });

    test('if the server cannot be reached the unused recording stays and is deleted on a later sync', () async {
      await store.adopt(await recorded('r.m4a', [1]), 'aaaaaaaa-1', 'audio/mp4');
      await sync.run(notes: [noteWith(['aaaaaaaa-1'])]);
      now = now.add(const Duration(hours: 3));
      api.offline = true;
      await sync.run(notes: [noteWith([])]);
      expect(store.find('aaaaaaaa-1'), isNotNull);
      api.offline = false;
      await sync.run(notes: [noteWith([])]);
      expect(store.find('aaaaaaaa-1'), isNull);
      expect(api.server.containsKey('aaaaaaaa-1'), isFalse);
    });

    test('with no notes read at all nothing is ever deleted', () async {
      await store.adopt(await recorded('r.m4a', [1]), 'aaaaaaaa-1', 'audio/mp4');
      await sync.run(notes: [noteWith(['aaaaaaaa-1'])]);
      now = now.add(const Duration(days: 9));
      await sync.run(notes: null);
      expect(store.find('aaaaaaaa-1'), isNotNull);
    });
  });
}
