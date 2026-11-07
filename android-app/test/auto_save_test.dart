import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/features/notes/presentation/auto_save_scheduler.dart';

void main() {
  const interval = Duration(seconds: 60);

  testWidgets('saves once, 60 s after the first change, even while typing continues', (tester) async {
    var saves = 0;
    final s = AutoSaveScheduler(interval: interval, save: () async => saves++);
    s.markDirty();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 10));
      s.markDirty(); // keeps typing: must NOT push the save back
    }
    expect(saves, 0, reason: '50 s in, nothing saved yet');
    await tester.pump(const Duration(seconds: 11));
    expect(saves, 1);
    s.dispose();
  });

  testWidgets('a change after a save starts a new interval', (tester) async {
    var saves = 0;
    final s = AutoSaveScheduler(interval: interval, save: () async => saves++);
    s.markDirty();
    await tester.pump(interval);
    expect(saves, 1);
    expect(s.dirty, isFalse);
    s.markDirty();
    await tester.pump(const Duration(seconds: 59));
    expect(saves, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(saves, 2);
    s.dispose();
  });

  testWidgets('nothing is saved while nothing changed', (tester) async {
    var saves = 0;
    final s = AutoSaveScheduler(interval: interval, save: () async => saves++);
    await tester.pump(const Duration(minutes: 5));
    expect(saves, 0);
    s.dispose();
  });

  testWidgets('flush saves right away when dirty, and cancels the pending timer', (tester) async {
    var saves = 0;
    final s = AutoSaveScheduler(interval: interval, save: () async => saves++);
    s.markDirty();
    await s.flush();
    expect(saves, 1);
    expect(s.dirty, isFalse);
    await tester.pump(const Duration(minutes: 2));
    expect(saves, 1, reason: 'the old timer must not save a second time');
    s.dispose();
  });

  testWidgets('flush does nothing when there is nothing unsaved', (tester) async {
    var saves = 0;
    final s = AutoSaveScheduler(interval: interval, save: () async => saves++);
    await s.flush();
    expect(saves, 0);
    s.dispose();
  });

  testWidgets('an edit made while a save is running is saved by the next interval, not lost', (tester) async {
    var saves = 0;
    late AutoSaveScheduler s;
    s = AutoSaveScheduler(interval: interval, save: () async {
      saves++;
      if (saves == 1) s.markDirty(); // the user typed during the first save
    });
    s.markDirty();
    await tester.pump(interval);
    expect(saves, 1);
    expect(s.dirty, isTrue);
    await tester.pump(interval);
    expect(saves, 2);
    s.dispose();
  });

  testWidgets('dispose cancels the timer without saving', (tester) async {
    var saves = 0;
    final s = AutoSaveScheduler(interval: interval, save: () async => saves++);
    s.markDirty();
    s.dispose();
    await tester.pump(const Duration(minutes: 2));
    expect(saves, 0);
  });

  group('skipping identical content', () {
    testWidgets('does not save when the note is back to what was last saved', (tester) async {
      var saves = 0;
      var text = 'A';
      final s = AutoSaveScheduler(interval: interval, save: () async => saves++, snapshot: () => text);
      s.setBaseline();
      text = 'B';
      s.markDirty(); // typed something...
      text = 'A';   // ...then undid it
      await tester.pump(interval);
      expect(saves, 0, reason: 'nothing really changed, so the note must not be rewritten');
      expect(s.dirty, isFalse);
      s.dispose();
    });

    testWidgets('flush also skips an identical note', (tester) async {
      var saves = 0;
      var text = 'A';
      final s = AutoSaveScheduler(interval: interval, save: () async => saves++, snapshot: () => text);
      s.setBaseline();
      s.markDirty();
      await s.flush();
      expect(saves, 0);
      s.dispose();
    });

    testWidgets('saves a real change, and the saved version becomes the new baseline', (tester) async {
      var saves = 0;
      var text = 'A';
      final s = AutoSaveScheduler(interval: interval, save: () async => saves++, snapshot: () => text);
      s.setBaseline();
      text = 'B';
      s.markDirty();
      await tester.pump(interval);
      expect(saves, 1);
      text = 'A'; // back to the ORIGINAL text, which is now a real change from what is saved
      s.markDirty();
      await tester.pump(interval);
      expect(saves, 2);
      s.dispose();
    });

    testWidgets('without a baseline the first save always happens', (tester) async {
      var saves = 0;
      final s = AutoSaveScheduler(interval: interval, save: () async => saves++, snapshot: () => 'A');
      s.markDirty();
      await s.flush();
      expect(saves, 1);
      s.dispose();
    });
  });
}
