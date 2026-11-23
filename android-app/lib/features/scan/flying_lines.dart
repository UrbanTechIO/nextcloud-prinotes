import 'package:flutter/material.dart';

/// Shows recognised text rising out of the camera towards the note. Each line is a small pill that floats up
/// and fades; when it has arrived, [launch]'s `onLanded` runs, which is where the text enters the note.
class FlyingLines extends StatefulWidget {
  /// How far up the pills travel, in pixels.
  final double rise;
  const FlyingLines({super.key, required this.rise});

  @override
  FlyingLinesState createState() => FlyingLinesState();
}

class _Flight {
  final int id;
  final String text;
  final double slot;
  _Flight(this.id, this.text, this.slot);
}

class FlyingLinesState extends State<FlyingLines> {
  static const duration = Duration(milliseconds: 900);
  final List<_Flight> _flights = [];
  int _next = 0;

  /// Sends [text] up from the camera. [onLanded] runs when it reaches the note.
  void launch(String text, VoidCallback onLanded) {
    final flight = _Flight(_next++, text, (_next % 3) / 3.0);
    setState(() => _flights.add(flight));
    Future.delayed(duration, () {
      onLanded();
      if (mounted) setState(() => _flights.removeWhere((f) => f.id == flight.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          for (final f in _flights)
            TweenAnimationBuilder<double>(
              key: ValueKey(f.id),
              tween: Tween(begin: 0, end: 1),
              duration: duration,
              curve: Curves.easeIn,
              builder: (context, t, child) => Positioned(
                bottom: 60 + widget.rise * t,
                left: 24 + 40 * f.slot,
                right: 24 + 40 * (1 - f.slot),
                child: Opacity(opacity: (1 - t * t).clamp(0.0, 1.0), child: child),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  f.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onPrimary, fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
