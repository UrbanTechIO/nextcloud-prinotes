import 'dart:typed_data';
import 'dart:ui' as ui;

/// Width divided by height of a picture, as it is shown upright (the phone's rotation flag is applied).
/// Null when the bytes are not a picture.
Future<double?> imageAspect(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width;
    final h = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    return h == 0 ? null : w / h;
  } catch (_) {
    return null;
  }
}

/// The size a new picture gets in a note: [maxWidth] wide, the picture's own shape, and never taller than
/// [maxHeight] (a tall picture gets narrower instead of being squashed).
ui.Size pictureSize({required double maxWidth, required double aspect, double maxHeight = 600}) {
  final width = maxWidth < maxHeight * aspect ? maxWidth : maxHeight * aspect;
  return ui.Size(width, width / aspect);
}
