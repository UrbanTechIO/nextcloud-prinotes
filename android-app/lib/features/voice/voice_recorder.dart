import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'voice_content.dart';
import 'voice_wave.dart';

/// What the recorder sheet needs from the microphone. Tests give it a fake one.
abstract class VoiceRecorderEngine {
  /// Asks for the microphone permission when needed. False when the user said no.
  Future<bool> hasPermission();
  Future<void> start(String path);
  Future<void> pause();
  Future<void> resume();

  /// Ends the recording and returns the file path, or null when nothing was recorded.
  Future<String?> stop();

  /// Ends the recording and throws the audio away.
  Future<void> cancel();

  /// Loudness from 0 (quiet) to 1 (loud), while recording.
  Stream<double> get level;
  Future<void> dispose();
}

/// The phone's microphone, recorded as AAC in an .m4a file: about 0.5 MB a minute, mono.
class RecordEngine implements VoiceRecorderEngine {
  final AudioRecorder _rec = AudioRecorder();

  @override
  Future<bool> hasPermission() => _rec.hasPermission();

  @override
  Future<void> start(String path) => _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 24000, numChannels: 1),
        path: path,
      );

  @override
  Future<void> pause() => _rec.pause();
  @override
  Future<void> resume() => _rec.resume();
  @override
  Future<String?> stop() => _rec.stop();
  @override
  Future<void> cancel() => _rec.cancel();

  @override
  Stream<double> get level => _rec.onAmplitudeChanged(const Duration(milliseconds: 120)).map((a) => ((a.current + 50) / 50).clamp(0.0, 1.0));

  @override
  Future<void> dispose() => _rec.dispose();
}

/// A finished recording, before it is added to the note.
class RecordedVoice {
  final File file;
  final int durationMs;
  final String mime;

  /// The recording's shape as bars from 0 to 100 (empty when no loudness was read).
  final List<int> wave;
  const RecordedVoice(this.file, this.durationMs, {this.mime = 'audio/mp4', this.wave = const []});
}

/// The longest recording the sheet allows.
const maxVoiceLength = Duration(minutes: 30);

/// Opens the recorder. Returns the recording when the user taps Add, or null when they cancel.
Future<RecordedVoice?> showVoiceRecorder(BuildContext context, {VoiceRecorderEngine? engine}) {
  return showModalBottomSheet<RecordedVoice>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => VoiceRecorderSheet(engine: engine ?? RecordEngine()),
  );
}

enum _Phase { starting, recording, paused, denied, failed }

class VoiceRecorderSheet extends StatefulWidget {
  final VoiceRecorderEngine engine;
  final Directory? tempDir; // tests
  final DateTime Function()? now; // tests
  const VoiceRecorderSheet({super.key, required this.engine, this.tempDir, this.now});

  @override
  State<VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<VoiceRecorderSheet> {
  _Phase _phase = _Phase.starting;
  final _clock = _RunClock();
  Timer? _tick;
  StreamSubscription<double>? _levelSub;
  List<double> _live = []; // the bars on screen, newest last
  final List<double> _all = []; // every reading, for the saved shape
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _clock.now = widget.now ?? DateTime.now;
    _begin();
  }

  Future<void> _begin() async {
    try {
      if (!await widget.engine.hasPermission()) {
        if (mounted) setState(() => _phase = _Phase.denied);
        return;
      }
      final dir = widget.tempDir ?? await getTemporaryDirectory();
      await widget.engine.start('${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
      _clock.start();
      _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        if (_clock.elapsed >= maxVoiceLength) {
          _stopAndAdd();
          return;
        }
        setState(() {});
      });
      _levelSub = widget.engine.level.listen((l) {
        if (!mounted || _phase != _Phase.recording) return;
        _all.add(l);
        setState(() => _live = pushLevel(_live, l));
      });
      if (mounted) setState(() => _phase = _Phase.recording);
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  Future<void> _pauseOrResume() async {
    if (_phase == _Phase.recording) {
      await widget.engine.pause();
      _clock.stop();
      setState(() => _phase = _Phase.paused);
    } else if (_phase == _Phase.paused) {
      await widget.engine.resume();
      _clock.start();
      setState(() => _phase = _Phase.recording);
    }
  }

  Future<void> _stopAndAdd() async {
    if (_finishing) return;
    _finishing = true;
    _clock.stop();
    _tick?.cancel();
    final path = await widget.engine.stop();
    if (!mounted) return;
    if (path == null || _clock.elapsed.inMilliseconds < 300) {
      Navigator.pop(context); // nothing worth keeping
      return;
    }
    Navigator.pop(context, RecordedVoice(File(path), _clock.elapsed.inMilliseconds, wave: resampleWave(_all)));
  }

  Future<void> _cancel() async {
    if (_finishing) return;
    _finishing = true;
    _tick?.cancel();
    if (_phase == _Phase.recording || _phase == _Phase.paused) await widget.engine.cancel();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _levelSub?.cancel();
    if (!_finishing && (_phase == _Phase.recording || _phase == _Phase.paused)) widget.engine.cancel();
    widget.engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final problem = switch (_phase) {
      _Phase.denied => 'Allow the microphone for PriNotes in the phone settings to record.',
      _Phase.failed => 'The recorder could not start. Try again.',
      _ => null,
    };
    final live = _phase == _Phase.recording || _phase == _Phase.paused;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              problem ?? (_phase == _Phase.paused ? 'Paused' : _phase == _Phase.starting ? 'Starting…' : 'Recording'),
              style: TextStyle(fontSize: 14, color: scheme.onSurface.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              formatVoiceLength(_clock.elapsed.inMilliseconds),
              key: const ValueKey('voice-timer'),
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: 12),
            LiveWave(key: const ValueKey('voice-live-wave'), levels: _live, color: scheme.onSurface, paused: _phase == _Phase.paused),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(key: const ValueKey('voice-cancel'), onPressed: _cancel, child: const Text('Cancel')),
                if (live)
                  IconButton.filledTonal(
                    key: const ValueKey('voice-pause'),
                    iconSize: 28,
                    tooltip: _phase == _Phase.paused ? 'Resume' : 'Pause',
                    icon: Icon(_phase == _Phase.paused ? Icons.mic_rounded : Icons.pause_rounded),
                    onPressed: _pauseOrResume,
                  ),
                FilledButton(
                  key: const ValueKey('voice-add'),
                  onPressed: live ? _stopAndAdd : null,
                  child: const Text('Add to note'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A stopwatch that can be paused and resumed, on a clock that tests can replace.
class _RunClock {
  DateTime Function() now = DateTime.now;
  Duration _before = Duration.zero;
  DateTime? _since;

  void start() => _since ??= now();
  void stop() {
    if (_since != null) {
      _before += now().difference(_since!);
      _since = null;
    }
  }

  Duration get elapsed => _since == null ? _before : _before + now().difference(_since!);
}

/// The bars shown while recording: the newest loudness on the right, older ones moving to the left.
class LiveWave extends StatelessWidget {
  final List<double> levels;
  final Color color;
  final bool paused;
  const LiveWave({super.key, required this.levels, required this.color, this.paused = false});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        width: double.infinity,
        child: CustomPaint(painter: _LiveWavePainter(levels, paused ? color.withOpacity(0.35) : color)),
      );
}

class _LiveWavePainter extends CustomPainter {
  final List<double> levels;
  final Color color;
  _LiveWavePainter(this.levels, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    const barWidth = 3.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;
    final fit = (size.width / (barWidth + gap)).floor();
    final shown = levels.length > fit ? levels.sublist(levels.length - fit) : levels;
    var x = size.width - barWidth / 2;
    for (var i = shown.length - 1; i >= 0; i--) {
      final h = math.max(4.0, shown[i].clamp(0.0, 1.0) * size.height);
      canvas.drawLine(Offset(x, size.height / 2 - h / 2), Offset(x, size.height / 2 + h / 2), paint);
      x -= barWidth + gap;
    }
  }

  @override
  bool shouldRepaint(_LiveWavePainter old) => old.levels != levels || old.color != color;
}
