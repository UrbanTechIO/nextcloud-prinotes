/// Decides which of the lines the camera reads should be added to the note during a live scan.
///
/// The camera reads the same page many times a second and the reading flickers, so a line is added only when
/// it has been read (nearly) the same way in [framesNeeded] frames in a row, and never again once it is in
/// the note.
class LiveScanFilter {
  /// How alike two readings must be to count as the same line (0 to 1).
  static const double sameLine = 0.8;

  final int framesNeeded;
  LiveScanFilter({this.framesNeeded = 3});

  List<_Candidate> _waiting = [];
  final List<String> _added = [];

  /// Gives the lines of one camera frame (top to bottom) and returns the ones to add to the note now.
  List<String> accept(List<String> lines) {
    final frame = [for (final l in lines) if (_usable(l)) l.trim()];
    final next = <_Candidate>[];
    final fresh = <String>[];
    for (final line in frame) {
      final key = _key(line);
      if (_added.any((a) => _alike(a, key))) continue;
      if (next.any((c) => _alike(c.key, key))) continue;
      final before = _waiting.where((c) => _alike(c.key, key));
      final seen = (before.isEmpty ? 0 : before.first.frames) + 1;
      if (seen >= framesNeeded) {
        fresh.add(line);
        _added.add(key);
      } else {
        next.add(_Candidate(key, seen));
      }
    }
    _waiting = next;
    return fresh;
  }

  /// True when this line (or one that reads almost the same) is already in the note.
  bool isAdded(String line) {
    final key = _key(line);
    return _added.any((a) => _alike(a, key));
  }

  /// In how many frames in a row this line has been read so far (0 when it is not being watched).
  int framesSeen(String line) {
    final key = _key(line);
    for (final c in _waiting) {
      if (_alike(c.key, key)) return c.frames;
    }
    return 0;
  }

  /// Forgets what was added and what was seen.
  void reset() {
    _waiting = [];
    _added.clear();
  }

  static final _letters = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// Very short lines and lines that are mostly marks are camera noise, not text.
  static bool usable(String line) => _usable(line);

  static bool _usable(String line) {
    final t = line.trim();
    final solid = t.replaceAll(RegExp(r'\s'), '');
    if (solid.length < 3) return false;
    final letters = _letters.allMatches(solid).length;
    return letters >= 3 && letters / solid.length >= 0.5;
  }

  static String _key(String line) =>
      line.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  static bool _alike(String a, String b) {
    if (a == b) return true;
    final longest = a.length > b.length ? a.length : b.length;
    if (longest == 0) return false;
    return 1 - _distance(a, b) / longest >= sameLine;
  }

  /// Edit distance between two strings.
  static int _distance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final best = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
        cur[j] = best;
      }
      prev = cur;
    }
    return prev[b.length];
  }
}

class _Candidate {
  final String key;
  final int frames;
  _Candidate(this.key, this.frames);
}
