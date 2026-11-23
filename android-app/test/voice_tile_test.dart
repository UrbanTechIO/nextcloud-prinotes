import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/features/voice/voice_playback.dart';
import 'package:prinotes/features/voice/voice_store.dart';
import 'package:prinotes/features/voice/voice_tile.dart';
import 'package:prinotes/features/voice/voice_waveform.dart';

class FakePlayer implements VoicePlayer {
  final pos = StreamController<Duration>.broadcast();
  final done = StreamController<void>.broadcast();
  final playingC = StreamController<bool>.broadcast();
  final log = <String>[];

  @override
  Stream<Duration> get position => pos.stream;
  @override
  Stream<bool> get playing => playingC.stream;
  @override
  Stream<void> get completed => done.stream;
  @override
  Future<void> load(File file) async => log.add('load ${file.uri.pathSegments.last}');
  @override
  Future<void> play() async {
    log.add('play');
    playingC.add(true);
  }

  @override
  Future<void> pause() async {
    log.add('pause');
    playingC.add(false);
  }
  @override
  Future<void> seek(Duration to) async => log.add('seek ${to.inMilliseconds}');
  @override
  Future<void> stop() async {
    log.add('stop');
    playingC.add(false);
  }
  @override
  Future<void> dispose() async {}
}

Map<String, dynamic> meta(int ms, [String label = 'Delivery date']) => {'label': label, 'duration': ms, 'mime': 'audio/mp4'};

void main() {
  late Directory tmp;
  late VoiceStore store;
  late FakePlayer player;
  late VoicePlayback playback;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('voice_tile');
    store = VoiceStore(tmp);
    File('${tmp.path}/aaaaaaaa-1.m4a').writeAsBytesSync([1]);
    File('${tmp.path}/bbbbbbbb-2.m4a').writeAsBytesSync([2]);
    player = FakePlayer();
    playback = VoicePlayback.withPlayer(() => player);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Widget tile(String id, Map<String, dynamic> m,
          {void Function(String)? onRename,
          VoidCallback? onDelete,
          Future<bool> Function(String, String)? onDownload,
          void Function(Offset)? onDrop}) =>
      VoiceTile(
        key: ValueKey('tile-$id'),
        id: id,
        meta: m,
        store: store,
        playback: playback,
        onRename: onRename ?? (_) {},
        onDelete: onDelete ?? () {},
        onDownload: onDownload,
        onDrop: onDrop,
      );

  Widget host(List<Widget> children) => MaterialApp(home: Scaffold(body: Column(children: children)));

  testWidgets('shows the name and the length', (tester) async {
    await tester.pumpWidget(host([tile('aaaaaaaa-1', meta(65000))]));
    expect(find.text('Delivery date'), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('play starts the recording and shows pause; tapping again pauses', (tester) async {
    await tester.pumpWidget(host([tile('aaaaaaaa-1', meta(10000))]));
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await tester.pump();
    await tester.pump();
    expect(player.log, ['load aaaaaaaa-1.m4a', 'play']);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await tester.pump();
    await tester.pump();
    expect(player.log.last, 'pause');
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('starting a second recording stops the first one', (tester) async {
    await tester.pumpWidget(host([tile('aaaaaaaa-1', meta(10000)), tile('bbbbbbbb-2', meta(8000), onRename: (_) {})]));
    await tester.tap(find.byKey(const ValueKey('voice-play')).first);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('voice-play')).last);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget, reason: 'only one is playing');
    expect(player.log.where((l) => l.startsWith('load')).toList(), ['load aaaaaaaa-1.m4a', 'load bbbbbbbb-2.m4a']);
  });

  testWidgets('the time follows the playback', (tester) async {
    await tester.pumpWidget(host([tile('aaaaaaaa-1', meta(10000))]));
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await tester.pump();
    await tester.pump();
    player.pos.add(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('0:02 / 0:10'), findsOneWidget);
  });

  testWidgets('when it reaches the end it goes back to the start, ready to play again', (tester) async {
    await tester.pumpWidget(host([tile('aaaaaaaa-1', meta(10000))]));
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await tester.pump();
    await tester.pump();
    player.done.add(null);
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(player.log, containsAllInOrder(['pause', 'seek 0']));
  });

  testWidgets('moving the bar seeks while it is the one playing', (tester) async {
    await tester.pumpWidget(host([tile('aaaaaaaa-1', meta(10000))]));
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await tester.pump();
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('voice-seek'))));
    await tester.pump();
    expect(player.log.any((l) => l.startsWith('seek ')), isTrue);
  });

  testWidgets('a recording that is not on this phone offers a download, and says so when it fails', (tester) async {
    var asked = 0;
    await tester.pumpWidget(host([
      tile('cccccccc-3', meta(5000, 'Price'), onDownload: (id, mime) async {
        asked++;
        return false;
      })
    ]));
    expect(find.textContaining('not on this phone yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-play')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('voice-download')));
    await tester.pump();
    await tester.pump();
    expect(asked, 1);
    expect(find.textContaining('Not available yet'), findsOneWidget);
  });

  testWidgets('delete asks the note to remove the recording and stops its playback', (tester) async {
    var deleted = 0;
    await tester.pumpWidget(host([tile('aaaaaaaa-1', meta(10000), onDelete: () => deleted++)]));
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('voice-delete')));
    await tester.pump();
    await tester.pump();
    expect(deleted, 1);
    expect(player.log, contains('stop'));
    expect(playback.currentId, isNull);
  });

  testWidgets('tapping the name lets you rename it', (tester) async {
    String? renamed;
    await tester.pumpWidget(host([tile('aaaaaaaa-1', meta(10000), onRename: (n) => renamed = n)]));
    await tester.tap(find.text('Delivery date'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Price and deposit');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(renamed, 'Price and deposit');
  });

  testWidgets('the recording is drawn from its saved bars', (tester) async {
    await tester.pumpWidget(host([tile('aaaaaaaa-1', {...meta(10000), 'wave': [10, 50, 100]})]));
    final w = tester.widget<VoiceWaveform>(find.byKey(const ValueKey('voice-seek')));
    expect(w.bars, [0.1, 0.5, 1.0]);
  });

  testWidgets('an older recording without saved bars shows a flat row of 60', (tester) async {
    await tester.pumpWidget(host([tile('aaaaaaaa-1', meta(10000))]));
    final w = tester.widget<VoiceWaveform>(find.byKey(const ValueKey('voice-seek')));
    expect(w.bars.length, 60);
    expect(w.bars.toSet().length, 1);
  });

  testWidgets('the played part of the bars grows as it plays', (tester) async {
    await tester.pumpWidget(host([tile('aaaaaaaa-1', {...meta(10000), 'wave': [50, 50, 50, 50]})]));
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await tester.pump();
    await tester.pump();
    player.pos.add(const Duration(seconds: 5));
    await tester.pump();
    final w = tester.widget<VoiceWaveform>(find.byKey(const ValueKey('voice-seek')));
    expect(w.progress, closeTo(0.5, 0.01));
  });

  testWidgets('tapping the bars of a recording that is not playing starts it from there', (tester) async {
    await tester.pumpWidget(host([tile('aaaaaaaa-1', meta(10000))]));
    final box = tester.getRect(find.byKey(const ValueKey('voice-seek')));
    await tester.tapAt(Offset(box.left + box.width * 0.5, box.center.dy));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(player.log.where((l) => l.startsWith('seek ')).length, 1);
    final ms = int.parse(player.log.firstWhere((l) => l.startsWith('seek ')).substring(5));
    expect(ms, inInclusiveRange(4500, 5500));
    expect(player.log, contains('play'));
  });

  testWidgets('holding a recording and dragging it tells the note where it was dropped', (tester) async {
    Offset? dropped;
    await tester.pumpWidget(host([tile('aaaaaaaa-1', meta(10000), onDrop: (p) => dropped = p)]));
    final start = tester.getCenter(find.byKey(const ValueKey('voice-play'))) + const Offset(150, 0);
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveBy(const Offset(0, 80));
    await g.moveBy(const Offset(0, 80));
    await g.up();
    await tester.pump();
    expect(dropped, isNotNull);
    expect(dropped!.dy, closeTo(start.dy + 160, 12));
  });

  testWidgets('a quick tap or swipe does not start a drag', (tester) async {
    Offset? dropped;
    await tester.pumpWidget(host([tile('aaaaaaaa-1', meta(10000), onDrop: (p) => dropped = p)]));
    final start = tester.getCenter(find.byKey(const ValueKey('voice-play'))) + const Offset(150, 0);
    await tester.dragFrom(start, const Offset(0, 100));
    await tester.pump();
    expect(dropped, isNull);
  });
}
