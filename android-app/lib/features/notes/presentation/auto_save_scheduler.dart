import 'dart:async';

/// Saves unsaved changes on a fixed interval instead of after every edit.
///
/// The timer starts at the FIRST change after a save and is not pushed back by later edits, so steady
/// typing is still saved once per [interval]. [flush] saves right away (leaving the editor, app going to
/// the background). A failed save, or an edit made while a save runs, stays unsaved and is retried on the
/// next interval.
///
/// With a [snapshot] callback (a string that changes whenever the note's content changes), nothing is
/// written while the note is identical to the last saved version: typing something and undoing it does
/// not rewrite the note or change its modified time. Call [setBaseline] once the note has loaded.
class AutoSaveScheduler {
  final Duration interval;
  final Future<void> Function() save;
  final String Function()? snapshot;
  String? _baseline;

  Timer? _timer;
  bool _dirty = false;
  bool _saving = false;
  bool _disposed = false;

  AutoSaveScheduler({required this.interval, required this.save, this.snapshot});

  bool get dirty => _dirty;

  /// Remembers the current content as "what is saved", e.g. right after the note was loaded.
  void setBaseline() => _baseline = snapshot?.call();

  void markDirty() {
    if (_disposed) return;
    _dirty = true;
    if (_saving) return; // rescheduled when the running save finishes
    _timer ??= Timer(interval, _onTimer);
  }

  void _onTimer() {
    _timer = null;
    _run();
  }

  /// Saves now if there is anything unsaved, and cancels the pending timer.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_dirty) await _run();
  }

  Future<void> _run() async {
    if (!_dirty || _saving) return;
    final snap = snapshot?.call();
    if (snap != null && snap == _baseline) {
      _dirty = false; // changed and changed back: nothing to write
      return;
    }
    _saving = true;
    _dirty = false;
    try {
      await save();
      if (snap != null) _baseline = snap;
    } catch (_) {
      _dirty = true;
    } finally {
      _saving = false;
      if (_dirty && !_disposed) _timer ??= Timer(interval, _onTimer);
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
