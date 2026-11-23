import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/features/scan/scan_view.dart';

void main() {
  // Upright camera picture 720 x 1280, shown cover-fit in a 360 x 340 panel: scale 0.5, the picture is
  // 360 x 640 on screen and the middle 340 of the 640 rows are visible (rows 150..490).
  final view = ScanView(panel: const Size(360, 340), image: const Size(720, 1280));

  test('the picture fills the panel and is cropped top and bottom', () {
    expect(view.scale, closeTo(0.5, 1e-9));
    expect(view.visibleInImage.left, closeTo(0, 1e-9));
    expect(view.visibleInImage.right, closeTo(720, 1e-9));
    expect(view.visibleInImage.top, closeTo(300, 1e-9));
    expect(view.visibleInImage.bottom, closeTo(980, 1e-9));
  });

  test('a rectangle in the picture is placed on the panel', () {
    final r = view.toPanel(const Rect.fromLTWH(100, 400, 200, 40));
    expect(r.left, closeTo(50, 1e-9));
    expect(r.top, closeTo(400 * 0.5 - 150, 1e-9));
    expect(r.width, closeTo(100, 1e-9));
    expect(r.height, closeTo(20, 1e-9));
  });

  test('the reading window in panel coordinates becomes a rectangle in the picture and back', () {
    const window = Rect.fromLTRB(20, 40, 340, 280);
    final inPicture = view.windowInImage(window);
    expect(inPicture.left, closeTo(40, 1e-9));
    expect(inPicture.top, closeTo((40 + 150) * 2, 1e-9));
    final back = view.toPanel(inPicture);
    expect(back.left, closeTo(window.left, 1e-9));
    expect(back.bottom, closeTo(window.bottom, 1e-9));
  });

  test('only a line that is inside the reading window counts', () {
    const window = Rect.fromLTRB(20, 40, 340, 280);
    final w = view.windowInImage(window);
    expect(view.isInside(const Rect.fromLTWH(100, 700, 300, 60), w), isTrue);
    expect(view.isInside(const Rect.fromLTWH(100, 10, 300, 60), w), isFalse); // above the view, cropped away
    expect(view.isInside(const Rect.fromLTWH(100, 1100, 300, 60), w), isFalse); // below
    expect(view.isInside(const Rect.fromLTWH(-200, 700, 300, 60), w), isFalse); // mostly off the left
  });

  test('a line only just touching the window edge is out', () {
    const window = Rect.fromLTRB(20, 40, 340, 280);
    final w = view.windowInImage(window);
    expect(view.isInside(Rect.fromLTWH(100, w.top - 55, 300, 60), w), isFalse);
  });
}
