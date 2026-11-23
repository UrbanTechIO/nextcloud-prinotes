import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'flying_lines.dart';
import 'live_scan_filter.dart';
import 'scan_view.dart';
import 'text_reader.dart';

enum ScanMode { live, snap }

/// The camera half of the scan screen. Live mode reads text continuously and sends each new line up into the
/// note; Snap mode takes one photo, shows the text it found for a check, and inserts it on request.
class ScanPanel extends StatefulWidget {
  /// Called with text to add to the note (one line in Live, the whole text in Snap).
  final void Function(String text) onText;
  final VoidCallback onClose;
  final TextReader? reader;

  const ScanPanel({super.key, required this.onText, required this.onClose, this.reader});

  @override
  State<ScanPanel> createState() => _ScanPanelState();
}

class _ScanPanelState extends State<ScanPanel> {
  late final TextReader _reader = widget.reader ?? MlKitTextReader();
  final _flying = GlobalKey<FlyingLinesState>();
  final _filter = LiveScanFilter();

  CameraController? _camera;
  String? _problem;
  ScanMode _mode = ScanMode.live;
  bool _busy = false;
  DateTime _lastRead = DateTime.fromMillisecondsSinceEpoch(0);
  String? _snapText; // text found in the photo, waiting for Insert or Retake
  bool _reading = false;

  // Live reading: what to draw over the camera, and the lines waiting to float into the note.
  Size _panelSize = Size.zero;
  List<_Mark> _marks = const [];
  final List<String> _queue = [];
  Timer? _drain;

  @override
  void initState() {
    super.initState();
    _start();
    // At most one new line leaves the camera about every half second, so the note fills calmly.
    _drain = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_queue.isEmpty || _mode != ScanMode.live) return;
      final line = _queue.removeAt(0);
      _flying.currentState?.launch(line, () => widget.onText(line));
    });
  }

  /// Where on the panel the text is read: a frame inside the camera view, clear of the hint and the buttons.
  static Rect windowFor(Size panel) => Rect.fromLTRB(20, 44, panel.width - 20, panel.height - 84);

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _problem = 'No camera found.');
        return;
      }
      final back = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
      await _applyMode();
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied = e.code.toLowerCase().contains('permission');
      setState(() => _problem = denied
          ? 'Allow camera access for PriNotes in the phone settings to scan.'
          : 'The camera could not start (${e.code}).');
    }
  }

  Future<void> _applyMode() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    if (_mode == ScanMode.live) {
      if (!cam.value.isStreamingImages) await cam.startImageStream(_onFrame);
    } else if (cam.value.isStreamingImages) {
      await cam.stopImageStream();
    }
  }

  void _onFrame(CameraImage image) {
    final cam = _camera;
    if (cam == null || _busy || _mode != ScanMode.live) return;
    final now = DateTime.now();
    if (now.difference(_lastRead).inMilliseconds < 450) return;
    _lastRead = now;
    _busy = true;
    _reader.readFrame(image, cam.description, cam.value.deviceOrientation).then((frame) {
      if (!mounted || _mode != ScanMode.live) return;
      _handleFrame(frame);
    }).catchError((_) {}).whenComplete(() => _busy = false);
  }

  /// Keeps only the text inside the reading window, feeds it to the filter, and marks each line on screen.
  void _handleFrame(FrameText frame) {
    if (frame.imageSize.isEmpty || _panelSize.isEmpty) return;
    final view = ScanView(panel: _panelSize, image: frame.imageSize);
    final window = view.windowInImage(windowFor(_panelSize));
    final inside = [for (final l in frame.lines) if (view.isInside(l.box, window)) l];
    _queue.addAll(_filter.accept([for (final l in inside) l.text]));
    final marks = [
      for (final l in inside)
        if (LiveScanFilter.usable(l.text))
          _Mark(
            view.toPanel(l.box),
            _filter.isAdded(l.text)
                ? _MarkState.added
                : _filter.framesSeen(l.text) > 0
                    ? _MarkState.waiting
                    : _MarkState.seen,
          ),
    ];
    setState(() => _marks = marks);
  }

  Future<void> _setMode(ScanMode mode) async {
    if (mode == _mode) return;
    _queue.clear();
    setState(() {
      _mode = mode;
      _snapText = null;
      _marks = const [];
    });
    await _applyMode();
  }

  Future<void> _snap() async {
    final cam = _camera;
    if (cam == null || _reading) return;
    setState(() => _reading = true);
    try {
      final photo = await cam.takePicture();
      final text = (await _reader.readFile(photo.path)).trim();
      if (!mounted) return;
      setState(() => _snapText = text.isEmpty ? '' : text);
    } catch (_) {
      if (mounted) setState(() => _snapText = '');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  void dispose() {
    _drain?.cancel();
    final cam = _camera;
    _camera = null;
    if (cam != null) {
      () async {
        try {
          if (cam.value.isStreamingImages) await cam.stopImageStream();
        } catch (_) {}
        await cam.dispose();
      }();
    }
    if (widget.reader == null) _reader.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      _panelSize = box.biggest;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: _preview(),
            ),
          ),
          // The reading window and the lines found in it
          if (_mode == ScanMode.live && _problem == null && _camera != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _ReadingPainter(windowFor(box.biggest), _marks)),
              ),
            ),
          // Controls
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    SegmentedButton<ScanMode>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: ScanMode.live, label: Text('Live')),
                        ButtonSegment(value: ScanMode.snap, label: Text('Snap')),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) => _setMode(s.first),
                    ),
                    const Spacer(),
                    if (_mode == ScanMode.snap && _snapText == null)
                      _Shutter(busy: _reading, onTap: _snap),
                    const Spacer(),
                    FilledButton(onPressed: widget.onClose, child: const Text('Done')),
                  ],
                ),
              ),
            ),
          ),
          if (_mode == ScanMode.live && _problem == null)
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                    child: Text('Keep the text inside the frame', style: TextStyle(color: scheme.onSurface.withOpacity(0.9), fontSize: 13)),
                  ),
                ),
              ),
            ),
          if (_snapText != null)
            Positioned.fill(
              child: SnapResultBox(
                text: _snapText!,
                onRetake: () => setState(() => _snapText = null),
                onInsert: (t) {
                  widget.onText(t);
                  setState(() => _snapText = null);
                },
              ),
            ),
          Positioned.fill(child: FlyingLines(key: _flying, rise: box.maxHeight + 140)),
        ],
      );
    });
  }

  Widget _preview() {
    if (_problem != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_problem!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
        ),
      );
    }
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final size = cam.value.previewSize!;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          // The preview size is reported in landscape; the picture is shown upright.
          width: size.height,
          height: size.width,
          child: CameraPreview(cam),
        ),
      ),
    );
  }
}

class _Shutter extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _Shutter({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          width: 56,
          height: 56,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
          child: busy
              ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
              : Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
        ),
      );
}

/// The text found in a photo, editable, with Retake and Insert.
class SnapResultBox extends StatefulWidget {
  final String text;
  final VoidCallback onRetake;
  final void Function(String text) onInsert;
  const SnapResultBox({super.key, required this.text, required this.onRetake, required this.onInsert});

  @override
  State<SnapResultBox> createState() => _SnapResultBoxState();
}

class _SnapResultBoxState extends State<SnapResultBox> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final empty = widget.text.isEmpty;
    return Container(
      color: Colors.black.withOpacity(0.88),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 70),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(empty ? 'No text found' : 'Text found', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Expanded(
            child: TextField(
              controller: _ctrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Nothing was read. Try again with the text in view and in focus.',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(onPressed: widget.onRetake, child: const Text('Retake')),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  final t = _ctrl.text.trim();
                  if (t.isNotEmpty) widget.onInsert(t);
                },
                child: const Text('Insert'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _MarkState { seen, waiting, added }

class _Mark {
  final Rect box;
  final _MarkState state;
  const _Mark(this.box, this.state);
}

/// Draws the reading window (corner brackets) and a box round every line found in it: white while it is only
/// seen, yellow while it is being checked, green once it is in the note.
class _ReadingPainter extends CustomPainter {
  final Rect window;
  final List<_Mark> marks;
  _ReadingPainter(this.window, this.marks);

  @override
  void paint(Canvas canvas, Size size) {
    final bracket = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const len = 26.0;
    for (final c in [window.topLeft, window.topRight, window.bottomLeft, window.bottomRight]) {
      final dx = c.dx == window.left ? 1.0 : -1.0;
      final dy = c.dy == window.top ? 1.0 : -1.0;
      canvas.drawLine(c, c + Offset(dx * len, 0), bracket);
      canvas.drawLine(c, c + Offset(0, dy * len), bracket);
    }
    for (final m in marks) {
      final color = switch (m.state) {
        _MarkState.added => Colors.greenAccent,
        _MarkState.waiting => Colors.amber,
        _MarkState.seen => Colors.white54,
      };
      final rect = RRect.fromRectAndRadius(m.box.inflate(2), const Radius.circular(4));
      canvas.drawRRect(rect, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
      if (m.state == _MarkState.added) {
        canvas.drawRRect(rect, Paint()..color = Colors.greenAccent.withOpacity(0.12));
      }
    }
  }

  @override
  bool shouldRepaint(_ReadingPainter old) => old.marks != marks || old.window != window;
}
