import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/features/scan/live_scan_filter.dart';

List<String> feed(LiveScanFilter f, List<String> lines, int times) {
  var out = <String>[];
  for (var i = 0; i < times; i++) {
    out = f.accept(lines);
  }
  return out;
}

void main() {
  test('a line is added only after it is read in three frames in a row', () {
    final f = LiveScanFilter();
    expect(f.accept(['Thank you for your order']), isEmpty);
    expect(f.accept(['Thank you for your order']), isEmpty);
    expect(f.accept(['Thank you for your order']), ['Thank you for your order']);
  });

  test('a line already added is not added again', () {
    final f = LiveScanFilter();
    expect(feed(f, ['Hello world today'], 3), ['Hello world today']);
    expect(f.accept(['Hello world today']), isEmpty);
    expect(f.accept(['Hello world today']), isEmpty);
  });

  test('a line that disappears for one frame starts counting again', () {
    final f = LiveScanFilter();
    f.accept(['Hello world today']);
    f.accept(['Hello world today']);
    f.accept(['Something else entirely']);
    expect(f.accept(['Hello world today']), isEmpty);
    expect(f.accept(['Hello world today']), isEmpty);
    expect(f.accept(['Hello world today']), ['Hello world today']);
  });

  test('a small reading mistake counts as the same line, both while waiting and after it is added', () {
    final f = LiveScanFilter();
    f.accept(['Your order has shipped']);
    f.accept(['Your 0rder has shipped']);
    expect(f.accept(['Your order has shipped.']), ['Your order has shipped.']);
    expect(f.accept(['Your 0rder has shipped']), isEmpty);
  });

  test('lines that flicker or change every frame are never added', () {
    final f = LiveScanFilter();
    expect(f.accept(['Random noise here']), isEmpty);
    expect(f.accept(['Something else entirely']), isEmpty);
    expect(f.accept(['Another thing again']), isEmpty);
    expect(f.accept(['Yet more different text']), isEmpty);
  });

  test('new lines come out in the order the camera read them, top to bottom', () {
    final f = LiveScanFilter();
    expect(feed(f, ['First line here', 'Second line here'], 3), ['First line here', 'Second line here']);
  });

  test('noise is ignored: very short lines and lines with hardly any letters', () {
    final f = LiveScanFilter();
    expect(feed(f, ['ab', '--- ... ---', '| | |'], 4), isEmpty);
  });

  test('the screen can ask how a line is doing: waiting, or already in the note', () {
    final f = LiveScanFilter();
    f.accept(['Hello world today']);
    expect(f.isAdded('Hello world today'), isFalse);
    expect(f.framesSeen('Hello world today'), 1);
    f.accept(['Hello world today']);
    expect(f.framesSeen('Hello world today'), 2);
    f.accept(['Hello world today']);
    expect(f.isAdded('Hello world today'), isTrue);
    expect(f.isAdded('Hello world todai'), isTrue); // same line, small misreading
    expect(f.isAdded('Something else entirely'), isFalse);
  });

  test('reset forgets everything', () {
    final f = LiveScanFilter();
    feed(f, ['Hello world today'], 3);
    f.reset();
    expect(f.isAdded('Hello world today'), isFalse);
    expect(feed(f, ['Hello world today'], 3), ['Hello world today']);
  });
}
