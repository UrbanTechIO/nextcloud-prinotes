import 'dart:math' as math;
import 'dart:ui';

/// How the upright camera picture sits in the scan panel. The picture is scaled to cover the panel, so
/// whatever does not fit is cropped away; text there must not be read, because the user cannot see it.
class ScanView {
  final Size panel;
  final Size image;

  late final double scale = math.max(panel.width / image.width, panel.height / image.height);
  late final Offset _offset = Offset((panel.width - image.width * scale) / 2, (panel.height - image.height * scale) / 2);

  ScanView({required this.panel, required this.image});

  /// The part of the picture that shows in the panel, in picture coordinates.
  Rect get visibleInImage => Rect.fromLTRB(
        -_offset.dx / scale,
        -_offset.dy / scale,
        (panel.width - _offset.dx) / scale,
        (panel.height - _offset.dy) / scale,
      );

  /// A rectangle in the picture, placed on the panel.
  Rect toPanel(Rect r) => Rect.fromLTRB(
        r.left * scale + _offset.dx,
        r.top * scale + _offset.dy,
        r.right * scale + _offset.dx,
        r.bottom * scale + _offset.dy,
      );

  /// A rectangle on the panel (such as the reading window), in picture coordinates.
  Rect windowInImage(Rect r) => Rect.fromLTRB(
        (r.left - _offset.dx) / scale,
        (r.top - _offset.dy) / scale,
        (r.right - _offset.dx) / scale,
        (r.bottom - _offset.dy) / scale,
      );

  /// True when [line] lies (almost) completely inside [window]; both in picture coordinates.
  bool isInside(Rect line, Rect window) {
    final area = line.width * line.height;
    if (area <= 0) return false;
    final overlap = line.intersect(window);
    if (overlap.width <= 0 || overlap.height <= 0) return false;
    return overlap.width * overlap.height / area >= 0.9;
  }
}
