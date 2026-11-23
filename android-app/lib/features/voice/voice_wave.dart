import 'dart:math' as math;

/// How many bars a recording is drawn with.
const waveBars = 60;

/// Turns the loudness samples taken while recording (0 to 1) into [bars] numbers from 0 to 100, saved in the
/// note. The loudest part always reaches the top, so a quiet recording still shows its shape, but pure
/// silence stays low.
List<int> resampleWave(List<double> levels, {int bars = waveBars}) {
  if (levels.isEmpty) return [];
  final n = levels.length;
  final means = <double>[];
  for (var i = 0; i < bars; i++) {
    final from = (i * n / bars).floor().clamp(0, n - 1);
    final to = math.max(from + 1, ((i + 1) * n / bars).ceil()).clamp(from + 1, n);
    var sum = 0.0;
    var peak = 0.0;
    for (var j = from; j < to; j++) {
      sum += levels[j];
      peak = math.max(peak, levels[j]);
    }
    // Half the average, half the peak: speech looks like speech, not like a smear.
    means.add((sum / (to - from)) * 0.5 + peak * 0.5);
  }
  final top = means.reduce(math.max);
  final scale = 1 / math.max(top, 0.25);
  return [for (final m in means) (m * scale * 100).round().clamp(0, 100)];
}

/// The bars of a recording as 0 to 1. A recording made before waves existed has none saved: a flat row is
/// shown for it (the real shape is not known).
List<double> barsToShow(Map<String, dynamic> meta, {int bars = waveBars}) {
  final w = meta['wave'];
  if (w is List && w.isNotEmpty && w.every((v) => v is num)) {
    return [for (final v in w) (v as num).toDouble().clamp(0, 100) / 100];
  }
  return List<double>.filled(bars, 0.3);
}

/// Adds the newest level to the live bars and drops the oldest ones, keeping at most [max].
List<double> pushLevel(List<double> live, double level, {int max = 48}) {
  final next = [...live, level];
  return next.length > max ? next.sublist(next.length - max) : next;
}
