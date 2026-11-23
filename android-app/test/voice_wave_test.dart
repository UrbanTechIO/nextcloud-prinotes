import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/features/voice/voice_content.dart';
import 'package:prinotes/features/voice/voice_wave.dart';

void main() {
  group('resampleWave', () {
    test('a recording becomes a fixed number of bars from 0 to 100', () {
      final levels = List<double>.generate(500, (i) => (i % 50) / 50);
      final w = resampleWave(levels);
      expect(w.length, waveBars);
      expect(w.every((v) => v >= 0 && v <= 100), isTrue);
    });

    test('the loudest part reaches the top, so a quiet recording still shows its shape', () {
      final w = resampleWave(List<double>.filled(200, 0.3));
      expect(w.reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(90));
    });

    test('silence stays low and does not get blown up into noise', () {
      final w = resampleWave(List<double>.filled(200, 0.01));
      expect(w.reduce((a, b) => a > b ? a : b), lessThan(10));
    });

    test('loud then quiet keeps the order: loud bars first, quiet bars last', () {
      final levels = [...List<double>.filled(100, 0.9), ...List<double>.filled(100, 0.1)];
      final w = resampleWave(levels);
      expect(w.first, greaterThan(w.last));
      expect(w[5], greaterThan(60));
      expect(w[waveBars - 5], lessThan(40));
    });

    test('a very short recording gives fewer samples than bars and still fills every bar', () {
      final w = resampleWave([0.2, 0.8, 0.5]);
      expect(w.length, waveBars);
    });

    test('nothing recorded gives no bars', () {
      expect(resampleWave([]), isEmpty);
    });
  });

  group('showing a recording', () {
    test('saved bars are shown as they are, from 0 to 1', () {
      final w = barsToShow({'wave': [0, 50, 100]});
      expect(w, [0.0, 0.5, 1.0]);
    });

    test('a recording without saved bars (made before waves existed) shows a flat row', () {
      final w = barsToShow({'label': 'old'});
      expect(w.length, waveBars);
      expect(w.toSet().length, 1);
    });

    test('broken saved bars fall back to the flat row', () {
      expect(barsToShow({'wave': 'nope'}).length, waveBars);
      expect(barsToShow({'wave': []}).length, waveBars);
    });
  });

  group('recorder bars', () {
    test('the live bars keep the newest levels on the right and drop the oldest', () {
      var live = <double>[];
      for (var i = 1; i <= 5; i++) {
        live = pushLevel(live, i / 10, max: 3);
      }
      expect(live, [0.3, 0.4, 0.5]);
    });
  });

  group('note content', () {
    test('a new recording saves its bars', () {
      final meta = newVoiceMeta(durationMs: 1000, mime: 'audio/mp4', wave: [1, 2, 3]);
      expect(meta['wave'], [1, 2, 3]);
    });

    test('without bars the note has no wave field', () {
      expect(newVoiceMeta(durationMs: 1000, mime: 'audio/mp4').containsKey('wave'), isFalse);
    });
  });
}
