import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/features/voice/voice_recorder.dart';

class FakeMic implements VoiceRecorderEngine {
  bool allowed = true;
  bool failStart = false;
  String? startedAt;
  final log = <String>[];
  final levels = StreamController<double>.broadcast();

  @override
  Future<bool> hasPermission() async => allowed;
  @override
  Future<void> start(String path) async {
    if (failStart) throw Exception('mic busy');
    startedAt = path;
    log.add('start');
  }

  @override
  Future<void> pause() async => log.add('pause');
  @override
  Future<void> resume() async => log.add('resume');
  @override
  Future<String?> stop() async {
    log.add('stop');
    return startedAt;
  }

  @override
  Future<void> cancel() async => log.add('cancel');
  @override
  Stream<double> get level => levels.stream;
  @override
  Future<void> dispose() async => log.add('dispose');
}

void main() {
  late Directory tmp;
  late FakeMic mic;
  RecordedVoice? result;
  var closed = false;
  var clockNow = DateTime(2026, 11, 23, 12);

  /// Moves the recorder's clock and the app's timers forward together.
  Future<void> advance(WidgetTester tester, Duration d) async {
    clockNow = clockNow.add(d);
    await tester.pump(d);
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('rec');
    mic = FakeMic();
    result = null;
    closed = false;
    clockNow = DateTime(2026, 11, 23, 12);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<RecordedVoice>(
                  context: context,
                  builder: (_) => VoiceRecorderSheet(engine: mic, tempDir: tmp, now: () => clockNow),
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('recording starts at once and the timer runs', (tester) async {
    await open(tester);
    expect(mic.log, ['start']);
    expect(find.text('Recording'), findsOneWidget);
    await advance(tester, const Duration(seconds: 3));
    expect(find.text('0:03'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('voice-cancel')));
    await tester.pumpAndSettle();
  });

  testWidgets('Add to note ends the recording and hands the file back with its length', (tester) async {
    await open(tester);
    await advance(tester, const Duration(seconds: 4));
    await tester.tap(find.byKey(const ValueKey('voice-add')));
    await tester.pumpAndSettle();
    expect(mic.log, containsAllInOrder(['start', 'stop']));
    expect(closed, isTrue);
    expect(result, isNotNull);
    expect(result!.file.path, mic.startedAt);
    expect(result!.durationMs, inInclusiveRange(3800, 4400));
    expect(result!.mime, 'audio/mp4');
  });

  testWidgets('pause stops the timer and resume carries on', (tester) async {
    await open(tester);
    await advance(tester, const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('voice-pause')));
    await tester.pump();
    expect(find.text('Paused'), findsOneWidget);
    await advance(tester, const Duration(seconds: 5));
    expect(find.text('0:02'), findsOneWidget, reason: 'the time does not move while paused');
    await tester.tap(find.byKey(const ValueKey('voice-pause')));
    await tester.pump();
    expect(mic.log, containsAllInOrder(['pause', 'resume']));
    await advance(tester, const Duration(seconds: 1));
    expect(find.text('0:03'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('voice-cancel')));
    await tester.pumpAndSettle();
  });

  testWidgets('Cancel throws the recording away and adds nothing', (tester) async {
    await open(tester);
    await advance(tester, const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('voice-cancel')));
    await tester.pumpAndSettle();
    expect(mic.log, contains('cancel'));
    expect(mic.log, isNot(contains('stop')));
    expect(result, isNull);
    expect(closed, isTrue);
  });

  testWidgets('a recording of a fraction of a second is not kept', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('voice-add')));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(closed, isTrue);
  });

  testWidgets('without the microphone permission it says so and records nothing', (tester) async {
    mic.allowed = false;
    await open(tester);
    expect(find.textContaining('Allow the microphone'), findsOneWidget);
    expect(mic.log, isNot(contains('start')));
    final add = tester.widget<FilledButton>(find.byKey(const ValueKey('voice-add')));
    expect(add.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('voice-cancel')));
    await tester.pumpAndSettle();
  });

  testWidgets('if the microphone cannot start it says so', (tester) async {
    mic.failStart = true;
    await open(tester);
    expect(find.textContaining('could not start'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('voice-cancel')));
    await tester.pumpAndSettle();
  });

  testWidgets('it stops by itself at the longest allowed length', (tester) async {
    await open(tester);
    await advance(tester, maxVoiceLength + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(mic.log, contains('stop'));
    expect(result, isNotNull);
  });

  testWidgets('the recorder draws bars that move with the voice, newest on the right', (tester) async {
    await open(tester);
    mic.levels.add(0.2);
    mic.levels.add(0.9);
    await advance(tester, const Duration(milliseconds: 300));
    final wave = tester.widget<LiveWave>(find.byKey(const ValueKey('voice-live-wave')));
    expect(wave.levels.length, 2);
    expect(wave.levels.last, 0.9);
    await tester.tap(find.byKey(const ValueKey('voice-cancel')));
    await tester.pumpAndSettle();
  });

  testWidgets('the bars stop while paused', (tester) async {
    await open(tester);
    mic.levels.add(0.5);
    await advance(tester, const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('voice-pause')));
    await tester.pump();
    mic.levels.add(0.7);
    await advance(tester, const Duration(milliseconds: 300));
    final wave = tester.widget<LiveWave>(find.byKey(const ValueKey('voice-live-wave')));
    expect(wave.levels, [0.5]);
    await tester.tap(find.byKey(const ValueKey('voice-cancel')));
    await tester.pumpAndSettle();
  });

  testWidgets('the finished recording carries its bars for the note', (tester) async {
    await open(tester);
    for (var i = 0; i < 40; i++) {
      mic.levels.add(i.isEven ? 0.8 : 0.2);
      await advance(tester, const Duration(milliseconds: 120));
    }
    await tester.tap(find.byKey(const ValueKey('voice-add')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.wave.length, 60);
    expect(result!.wave.reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(90));
  });

  testWidgets('a recording with no loudness readings still gets added, with no bars', (tester) async {
    await open(tester);
    await advance(tester, const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('voice-add')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.wave, isEmpty);
  });
}
