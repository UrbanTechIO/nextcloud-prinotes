import 'package:flutter/material.dart';

/// A recording drawn as bars. The part already played is in [playedColor]; the rest in [restColor].
/// Tapping or dragging on it asks to jump to that place ([onSeek] gets 0 to 1).
class VoiceWaveform extends StatelessWidget {
  /// Bar heights, 0 to 1.
  final List<double> bars;

  /// How much has been played, 0 to 1.
  final double progress;
  final Color playedColor;
  final Color restColor;
  final ValueChanged<double>? onSeek;
  final double height;

  const VoiceWaveform({
    super.key,
    required this.bars,
    required this.progress,
    required this.playedColor,
    required this.restColor,
    this.onSeek,
    this.height = 34,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      void seek(Offset local) {
        if (onSeek != null && width > 0) onSeek!((local.dx / width).clamp(0.0, 1.0));
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => seek(d.localPosition),
        onHorizontalDragStart: (d) => seek(d.localPosition),
        onHorizontalDragUpdate: (d) => seek(d.localPosition),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _WavePainter(bars, progress, playedColor, restColor)),
        ),
      );
    });
  }
}

class _WavePainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final Color played;
  final Color rest;
  _WavePainter(this.bars, this.progress, this.played, this.rest);

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final slot = size.width / bars.length;
    final barWidth = (slot * 0.62).clamp(1.5, 4.0);
    final paint = Paint()..strokeCap = StrokeCap.round..strokeWidth = barWidth;
    for (var i = 0; i < bars.length; i++) {
      final x = slot * i + slot / 2;
      final h = (bars[i].clamp(0.0, 1.0) * size.height).clamp(4.0, size.height);
      paint.color = (i + 0.5) / bars.length <= progress ? played : rest;
      canvas.drawLine(Offset(x, size.height / 2 - h / 2), Offset(x, size.height / 2 + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.bars != bars || old.progress != progress || old.played != played || old.rest != rest;
}
