import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// One line of text found in a camera frame: its text and where it is in the upright picture.
class ScanLine {
  final String text;
  final Rect box;
  const ScanLine(this.text, this.box);
}

/// Everything read from one camera frame, with the size of the upright picture the boxes refer to.
class FrameText {
  final Size imageSize;
  final List<ScanLine> lines;
  const FrameText(this.imageSize, this.lines);
}

/// Reads text out of a camera frame or a photo. The scan screen only knows this interface, so tests give it
/// a fake one.
abstract class TextReader {
  /// The lines of text in one live camera frame, top to bottom.
  Future<FrameText> readFrame(CameraImage image, CameraDescription camera, DeviceOrientation orientation);

  /// All the text in a photo, one paragraph per line.
  Future<String> readFile(String path);

  Future<void> close();
}

/// On-device reader (Google ML Kit, Latin script). Works offline.
class MlKitTextReader implements TextReader {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  static const _turns = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  Future<FrameText> readFrame(CameraImage image, CameraDescription camera, DeviceOrientation orientation) async {
    final input = _inputFrom(image, camera, orientation);
    if (input == null) return const FrameText(Size.zero, []);
    final result = await _recognizer.processImage(input);
    // The boxes come back in the upright picture, so a sideways sensor swaps width and height.
    final sideways = input.metadata!.rotation == InputImageRotation.rotation90deg ||
        input.metadata!.rotation == InputImageRotation.rotation270deg;
    final size = sideways ? Size(image.height.toDouble(), image.width.toDouble()) : Size(image.width.toDouble(), image.height.toDouble());
    final lines = <ScanLine>[
      for (final block in result.blocks)
        for (final line in block.lines)
          // A line the recogniser is unsure of is more likely junk than text.
          if (line.confidence == null || line.confidence! >= 0.5) ScanLine(line.text, line.boundingBox),
    ]..sort((a, b) => a.box.top.compareTo(b.box.top));
    return FrameText(size, lines);
  }

  @override
  Future<String> readFile(String path) async {
    final result = await _recognizer.processImage(InputImage.fromFilePath(path));
    return [for (final block in result.blocks) block.text].join('\n');
  }

  @override
  Future<void> close() => _recognizer.close();

  InputImage? _inputFrom(CameraImage image, CameraDescription camera, DeviceOrientation orientation) {
    final turn = _turns[orientation] ?? 0;
    final degrees = camera.lensDirection == CameraLensDirection.front
        ? (camera.sensorOrientation + turn) % 360
        : (camera.sensorOrientation - turn + 360) % 360;
    final rotation = InputImageRotationValue.fromRawValue(degrees);
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (rotation == null || format != InputImageFormat.nv21 || image.planes.length != 1) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format!,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }
}
