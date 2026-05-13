import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class DrawingScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  const DrawingScreen({super.key, this.initialData});

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  final List<_Stroke> _strokes = [];
  final List<_Stroke> _undoStack = [];
  _Stroke? _current;

  Color _penColor = Colors.black;
  double _penSize = 8.0;
  bool _isEraser = false;
  String _bgColor = 'system'; // 'white' | 'dark' | 'system'
  bool _showGrid = false;
  bool _showDots = false;
  bool _showLines = false;
  final _repaintKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drawing Canvas'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Compact single-row toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. Current color dot — taps open full color picker dialog
                  GestureDetector(
                    onTap: _openColorPicker,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _penColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade400, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // 2. Pen / Eraser toggle
                  _toolButton(Icons.brush_outlined, !_isEraser,
                      () => setState(() => _isEraser = false)),
                  _toolButton(Icons.cleaning_services_outlined, _isEraser,
                      () => setState(() => _isEraser = true)),

                  const SizedBox(width: 4),

                  // 3. Size button — small circle showing pen size, taps open slider dialog
                  GestureDetector(
                    onTap: _openSizeDialog,
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      child: Container(
                        width: (_penSize / 40 * 24).clamp(4.0, 24.0),
                        height: (_penSize / 40 * 24).clamp(4.0, 24.0),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade600,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 4),

                  // 4. BG button — shows current bg color, taps open bottom sheet
                  GestureDetector(
                    onTap: _openBgSheet,
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: _bgColor == 'dark'
                            ? const Color(0xFF1E293B)
                            : _bgColor == 'system'
                                ? (Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF1E293B)
                                    : Colors.white)
                                : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: Icon(
                        Icons.format_color_fill,
                        size: 16,
                        color: _bgColor == 'dark' ? Colors.white : Colors.grey.shade700,
                      ),
                    ),
                  ),

                  const SizedBox(width: 6),

                  // 5. Grid FilterChip
                  _overlayChip('Grid', _showGrid, (v) {
                    setState(() {
                      _showGrid = v;
                      if (v) { _showDots = false; _showLines = false; }
                    });
                  }),
                  const SizedBox(width: 4),

                  // 6. Dots FilterChip
                  _overlayChip('Dots', _showDots, (v) {
                    setState(() {
                      _showDots = v;
                      if (v) { _showGrid = false; _showLines = false; }
                    });
                  }),
                  const SizedBox(width: 4),

                  // 7. Lines FilterChip
                  _overlayChip('Lines', _showLines, (v) {
                    setState(() {
                      _showLines = v;
                      if (v) { _showGrid = false; _showDots = false; }
                    });
                  }),

                  const SizedBox(width: 4),

                  // 8. Undo / Redo / Clear
                  _toolButton(Icons.undo, false, _undo),
                  _toolButton(Icons.redo, false, _redo),
                  _toolButton(Icons.delete_outline, false, _clear),
                ],
              ),
            ),
          ),

          // Canvas — always square (side = available width)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = constraints.maxWidth;
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return SingleChildScrollView(
                  child: Center(
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: RepaintBoundary(
                        key: _repaintKey,
                        child: Listener(
                          onPointerDown: _onDown,
                          onPointerMove: _onMove,
                          onPointerUp: _onUp,
                          child: CustomPaint(
                            painter: _CanvasPainter(
                              strokes: _strokes,
                              current: _current,
                              bgColor: _bgColor,
                              showGrid: _showGrid,
                              showDots: _showDots,
                              showLines: _showLines,
                              systemIsDark: isDark,
                              forExport: false,
                            ),
                            child: Container(color: Colors.transparent),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _overlayChip(String label, bool selected, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: onChanged,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _toolButton(IconData icon, bool active, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, size: 22),
      onPressed: onTap,
      color: active ? Theme.of(context).colorScheme.primary : Colors.grey,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  void _openColorPicker() {
    Color pickerColor = _penColor;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (c) => pickerColor = c,
            enableAlpha: false,
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                _penColor = pickerColor;
                _isEraser = false;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  void _openSizeDialog() {
    double size = _penSize;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pen size'),
        content: StatefulBuilder(
          builder: (ctx2, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: size,
                min: 1,
                max: 40,
                onChanged: (v) => setLocal(() => size = v),
              ),
              Text(size.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() => _penSize = size);
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _openBgSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              title: const Text('White'),
              selected: _bgColor == 'white',
              onTap: () {
                setState(() => _bgColor = 'white');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              title: const Text('Dark'),
              selected: _bgColor == 'dark',
              onTap: () {
                setState(() => _bgColor = 'dark');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.white, Color(0xFF1E293B)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
              ),
              title: const Text('System'),
              selected: _bgColor == 'system',
              onTap: () {
                setState(() => _bgColor = 'system');
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _resolveEraserColor() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_bgColor == 'dark') return const Color(0xFF1E293B);
    if (_bgColor == 'system') return isDark ? const Color(0xFF1E293B) : Colors.white;
    return Colors.white;
  }

  void _onDown(PointerDownEvent e) {
    final pos = _localPos(e.position);
    setState(() {
      _current = _Stroke(
        points: [pos],
        color: _isEraser ? _resolveEraserColor() : _penColor,
        size: _penSize,
        isEraser: _isEraser,
      );
    });
  }

  void _onMove(PointerMoveEvent e) {
    if (_current == null) return;
    setState(() => _current!.points.add(_localPos(e.position)));
  }

  void _onUp(PointerUpEvent e) {
    if (_current == null) return;
    setState(() {
      if (_current!.points.isNotEmpty) {
        _strokes.add(_current!);
        _undoStack.clear();
      }
      _current = null;
    });
  }

  Offset _localPos(Offset global) {
    final box = _repaintKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global) ?? global;
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _undoStack.add(_strokes.removeLast()));
  }

  void _redo() {
    if (_undoStack.isEmpty) return;
    setState(() => _strokes.add(_undoStack.removeLast()));
  }

  void _clear() {
    setState(() {
      _undoStack.addAll(_strokes);
      _strokes.clear();
    });
  }

  Future<void> _save() async {
    final boundary =
        _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      Navigator.pop(context);
      return;
    }

    // Resolve actual background for export
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final exportBgColor = _bgColor == 'system'
        ? (isDark ? 'dark' : 'white')
        : _bgColor;

    final size = boundary.size;
    final recorder = ui.PictureRecorder();
    final exportCanvas = Canvas(recorder);
    final painter = _CanvasPainter(
      strokes: _strokes,
      current: null,
      bgColor: exportBgColor,
      showGrid: _showGrid,
      showDots: _showDots,
      showLines: _showLines,
      systemIsDark: isDark,
      forExport: true,
    );
    painter.paint(exportCanvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (size.width * 2).round(),
      (size.height * 2).round(),
    );

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    final base64Str = 'data:image/png;base64,${base64Encode(bytes)}';

    if (mounted) {
      Navigator.pop(context, {
        'dataUrl': base64Str,
        'bgColor': exportBgColor,
        'width': size.width,
        'height': size.height,
      });
    }
  }
}

class _Stroke {
  final List<Offset> points;
  final Color color;
  final double size;
  final bool isEraser;

  _Stroke(
      {required this.points,
      required this.color,
      required this.size,
      required this.isEraser});
}

class _CanvasPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final _Stroke? current;
  final String bgColor; // 'white' | 'dark' | 'system'
  final bool showGrid;
  final bool showDots;
  final bool showLines;
  final bool systemIsDark;
  final bool forExport;

  static const _darkBg = Color(0xFF1E293B);

  _CanvasPainter({
    required this.strokes,
    this.current,
    required this.bgColor,
    this.showGrid = false,
    this.showDots = false,
    this.showLines = false,
    this.systemIsDark = false,
    this.forExport = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Resolve background fill colour
    final Color bg = bgColor == 'dark'
        ? _darkBg
        : bgColor == 'system'
            ? (systemIsDark ? _darkBg : Colors.white)
            : Colors.white;

    canvas.drawRect(rect, Paint()..color = bg);

    // Use saveLayer so BlendMode.clear works for eraser
    canvas.saveLayer(rect, Paint());

    final isDark = bg == _darkBg;
    final overlayColor =
        isDark ? const Color(0xFF334155) : Colors.grey.shade300;

    // Grid overlay
    if (showGrid) {
      final p = Paint()
        ..color = overlayColor
        ..strokeWidth = 0.5;
      for (double x = 0; x < size.width; x += 24) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      }
      for (double y = 0; y < size.height; y += 24) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      }
    }

    // Dots overlay
    if (showDots) {
      final p = Paint()..color = overlayColor;
      for (double x = 24; x < size.width; x += 24) {
        for (double y = 24; y < size.height; y += 24) {
          canvas.drawCircle(Offset(x, y), 1.5, p);
        }
      }
    }

    // Lines overlay — horizontal lines every 28px
    if (showLines) {
      final p = Paint()
        ..color = overlayColor
        ..strokeWidth = 0.5;
      for (double y = 28; y < size.height; y += 28) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      }
    }

    // Strokes
    for (final stroke in [...strokes, if (current != null) current!]) {
      _drawStroke(canvas, stroke);
    }

    canvas.restore();
  }

  void _drawStroke(Canvas canvas, _Stroke stroke) {
    if (stroke.points.length < 2) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.isEraser) {
      paint.blendMode = BlendMode.clear;
    }

    final path = Path()
      ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (int i = 1; i < stroke.points.length - 1; i++) {
      final mid = Offset(
        (stroke.points[i].dx + stroke.points[i + 1].dx) / 2,
        (stroke.points[i].dy + stroke.points[i + 1].dy) / 2,
      );
      path.quadraticBezierTo(
        stroke.points[i].dx,
        stroke.points[i].dy,
        mid.dx,
        mid.dy,
      );
    }
    path.lineTo(stroke.points.last.dx, stroke.points.last.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CanvasPainter old) => true;
}
