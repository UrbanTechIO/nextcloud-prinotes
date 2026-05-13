import 'dart:convert';
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/local/database.dart';
import '../../providers/notes_provider.dart';

class NoteCard extends ConsumerWidget {
  final Note note;
  final VoidCallback onTap;
  final bool isListView;
  final bool isSelected;
  final VoidCallback? onLongPress;

  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    this.isListView = false,
    this.isSelected = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(noteTagsProvider(note.id));
    final tags = tagsAsync.valueOrNull ?? [];

    Color? noteColor;
    if (note.color != null) {
      try {
        noteColor = Color(int.parse(note.color!.replaceAll('#', 'FF'), radix: 16));
      } catch (_) {}
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBorderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: noteColor != null
                  ? noteColor.withOpacity(isDark ? 0.18 : 0.10)
                  : Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: noteColor?.withOpacity(0.55) ?? defaultBorderColor,
                width: noteColor != null ? 1.5 : 1,
              ),
              boxShadow: noteColor != null
                  ? [
                      BoxShadow(
                        color: noteColor.withOpacity(0.45),
                        blurRadius: 10,
                        spreadRadius: 1,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: isListView
                ? _buildListLayout(context, tags, noteColor)
                : _buildGridLayout(context, tags, noteColor),
          ),
          // Selection overlay
          if (isSelected)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          // Selection checkmark top-left
          if (isSelected)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 14, color: Colors.white),
              ),
            ),
          // Hidden note indicator top-right
          if (note.isHidden)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.visibility_off, size: 13, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  // ── Content preview helpers ─────────────────────────────────────────────────

  /// Returns the base64 data URI of the first image, or null.
  /// Always returns null for locked notes to keep content hidden.
  String? _firstImageData() {
    if (note.isLocked) return null;
    try {
      final data = jsonDecode(note.content) as Map<String, dynamic>;

      // quill-1.0 format (written by flutter_quill editor)
      if (data['version'] == 'quill-1.0') {
        final ops = data['delta'] as List? ?? [];
        final images = (data['images'] as Map?)?.cast<String, dynamic>() ?? {};
        for (final raw in ops) {
          final op = raw as Map;
          final insert = op['insert'];
          if (insert is Map && insert['image'] is String) {
            final id = insert['image'] as String;
            final img = (images[id] as Map?)?.cast<String, dynamic>();
            return img?['data'] as String?;
          }
        }
        return null;
      }

      // v2.0 format
      final images = data['images'] as List?;
      if (images != null && images.isNotEmpty) {
        return (images.first as Map)['data'] as String?;
      }
      // v1.0 blocks format
      final blocks = data['blocks'] as List?;
      if (blocks != null) {
        for (final b in blocks) {
          final block = b as Map;
          if (block['type'] == 'image') return block['data'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Returns the raw strokes list from v2.0 content, or null.
  /// Always returns null for locked notes.
  List<Map<String, dynamic>>? _parseStrokes() {
    if (note.isLocked) return null;
    try {
      final data = jsonDecode(note.content) as Map<String, dynamic>;
      final strokes = data['strokes'] as List?;
      if (strokes != null && strokes.isNotEmpty) {
        return strokes.map((s) => Map<String, dynamic>.from(s as Map)).toList();
      }
    } catch (_) {}
    return null;
  }

  Widget _imageThumbnail(String dataUri, {double height = 90, double? width}) {
    try {
      final comma = dataUri.indexOf(',');
      final b64 = comma >= 0 ? dataUri.substring(comma + 1) : dataUri;
      final bytes = base64Decode(b64);
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          height: height,
          width: width,
          fit: BoxFit.cover,
          cacheHeight: 180,
          gaplessPlayback: true,
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildGridLayout(BuildContext context, List<Tag> tags, Color? noteColor) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title — always at top ─────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  note.isLocked
                      ? (note.title.isEmpty ? 'Locked Note' : note.title)
                      : (note.title.isEmpty ? 'Untitled' : note.title),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (note.isPinned)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.push_pin_rounded, size: 13, color: Colors.blue),
                ),
            ],
          ),

          const SizedBox(height: 6),

          // ── Content snapshot — fills available space, fades at bottom ──────
          Expanded(
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.5, 0.65, 1.0],
                colors: [Colors.white, Color(0x33FFFFFF), Colors.transparent],
              ).createShader(bounds),
              blendMode: BlendMode.dstIn,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: _buildContentSnapshot(context),
                ),
              ),
            ),
          ),

          const SizedBox(height: 6),

          // ── Tags + date at bottom ─────────────────────────────────────────
          if (tags.isNotEmpty) ...[
            Wrap(
              spacing: 4,
              children: tags.take(2).map((t) => _buildTagChip(t)).toList(),
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              Text(
                _formatDate(note.updatedAt),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
              ),
              if (note.isLocked) ...[
                const Spacer(),
                Icon(Icons.lock_rounded, size: 13, color: Colors.orange.shade300),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Renders a mini snapshot of note content — text with basic styling +
  /// images inline — clipped to whatever space the card provides.
  Widget _buildContentSnapshot(BuildContext context) {
    if (note.isLocked) {
      return Center(
        child: Icon(Icons.lock_rounded, size: 32, color: Colors.orange.withOpacity(0.3)),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white70 : Colors.black87;
    final mutedColor = isDark ? Colors.white38 : Colors.black45;

    final items = <Widget>[];

    try {
      final data = jsonDecode(note.content) as Map<String, dynamic>;

      if (data['version'] == 'quill-1.0') {
        // Flutter quill delta format
        final ops = data['delta'] as List? ?? [];
        final images = (data['images'] as Map?)?.cast<String, dynamic>() ?? {};

        // Accumulate text/inline ops per line then emit a widget per \n
        final lineText = StringBuffer();
        String? lineListAttr;

        void flushLine() {
          final raw = lineText.toString();
          if (raw.isNotEmpty) {
            String prefix = '';
            switch (lineListAttr) {
              case 'bullet':   prefix = '• ';
              case 'ordered':  prefix = '1. ';
              case 'checked':  prefix = '☑ ';
              case 'unchecked': prefix = '☐ ';
            }
            items.add(Text(
              '$prefix$raw',
              style: TextStyle(fontSize: 8, color: textColor, height: 1.35),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ));
          }
          lineText.clear();
          lineListAttr = null;
        }

        for (final raw in ops) {
          final op = raw as Map;
          final insert = op['insert'];
          final attrs = (op['attributes'] as Map?)?.cast<String, dynamic>();

          if (insert is Map && insert['image'] is String) {
            // Image embed — flush pending text, show thumbnail
            flushLine();
            final id = insert['image'] as String;
            final img = (images[id] as Map?)?.cast<String, dynamic>();
            final imgData = img?['data'] as String?;
            if (imgData != null && imgData.isNotEmpty) {
              final rotation = (img?['rotation'] as num?)?.toDouble() ?? 0.0;
              items.add(const SizedBox(height: 4));
              items.add(_snapImageRotated(imgData, rotation));
            }
          } else if (insert is String) {
            int start = 0;
            for (int i = 0; i < insert.length; i++) {
              if (insert[i] == '\n') {
                if (i > start) lineText.write(insert.substring(start, i));
                lineListAttr = attrs?['list'] as String?;
                flushLine();
                start = i + 1;
              }
            }
            if (start < insert.length) lineText.write(insert.substring(start));
          }
        }
        // Flush any trailing text without a newline
        if (lineText.isNotEmpty) flushLine();
      } else if (data['version'] == '2.0') {
        for (final raw in (data['paragraphs'] as List? ?? [])) {
          final p = raw as Map;
          final style = p['style'] as String? ?? 'normal';
          final text = p['text'] as String? ?? '';
          if (text.isEmpty) {
            items.add(const SizedBox(height: 3));
            continue;
          }
          double fs;
          FontWeight fw;
          String prefix = '';
          switch (style) {
            case 'h1': fs = 11; fw = FontWeight.w700;
            case 'h2': fs = 10; fw = FontWeight.w700;
            case 'h3': fs = 9;  fw = FontWeight.w600;
            case 'bullet':   fs = 8; fw = FontWeight.normal; prefix = '• ';
            case 'numbered': fs = 8; fw = FontWeight.normal;
            case 'checklist':
              fs = 8; fw = FontWeight.normal;
              prefix = (p['checked'] == true) ? '☑ ' : '☐ ';
            default: fs = 8; fw = FontWeight.normal;
          }
          items.add(Text(
            '$prefix$text',
            style: TextStyle(fontSize: fs, fontWeight: fw, color: textColor, height: 1.35),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ));
        }

        for (final raw in (data['images'] as List? ?? [])) {
          final imgData = (raw as Map)['data'] as String?;
          if (imgData != null) {
            items.add(const SizedBox(height: 4));
            items.add(_snapImage(imgData));
          }
        }

        final strokes = (data['strokes'] as List?)
            ?.map((s) => Map<String, dynamic>.from(s as Map))
            .toList();
        if (strokes != null && strokes.isNotEmpty) {
          items.add(const SizedBox(height: 4));
          items.add(SizedBox(
            height: 80,
            width: double.infinity,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _StrokePreviewPainter(
                  strokes: strokes,
                  background: Theme.of(context).cardColor,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ));
        }
      } else {
        // v1.0 blocks
        for (final raw in (data['blocks'] as List? ?? [])) {
          final b = raw as Map;
          final type = b['type'] as String? ?? '';
          switch (type) {
            case 'paragraph':
            case 'quote':
              final text = (b['content'] as List? ?? [])
                  .map((s) => (s as Map)['text'] ?? '').join();
              if (text.isNotEmpty) {
                items.add(Text(text,
                  style: TextStyle(fontSize: 8, color: textColor, height: 1.35),
                  maxLines: 4, overflow: TextOverflow.ellipsis));
              }
            case 'heading':
              final text = (b['content'] as List? ?? [])
                  .map((s) => (s as Map)['text'] ?? '').join();
              final lvl = b['level'] as int? ?? 1;
              final fs = lvl == 1 ? 11.0 : lvl == 2 ? 10.0 : 9.0;
              if (text.isNotEmpty) {
                items.add(Text(text,
                  style: TextStyle(fontSize: fs, fontWeight: FontWeight.w700,
                      color: textColor, height: 1.35),
                  maxLines: 2, overflow: TextOverflow.ellipsis));
              }
            case 'list':
              for (final item in (b['items'] as List? ?? [])) {
                final text = (item as Map)['text'] as String? ?? '';
                final bullet = (b['ordered'] == true) ? '1. ' : '• ';
                if (text.isNotEmpty) {
                  items.add(Text('$bullet$text',
                    style: TextStyle(fontSize: 8, color: textColor, height: 1.35),
                    maxLines: 2, overflow: TextOverflow.ellipsis));
                }
              }
            case 'checklist':
              for (final item in (b['items'] as List? ?? [])) {
                final m = item as Map;
                final text = m['text'] as String? ?? '';
                final mark = (m['checked'] == true) ? '☑ ' : '☐ ';
                if (text.isNotEmpty) {
                  items.add(Text('$mark$text',
                    style: TextStyle(fontSize: 8, color: textColor, height: 1.35),
                    maxLines: 2, overflow: TextOverflow.ellipsis));
                }
              }
            case 'image':
            case 'drawing':
              final imgData = b['data'] as String?;
              if (imgData != null && imgData.isNotEmpty) {
                final rotation = (b['rotation'] as num?)?.toDouble() ?? 0.0;
                items.add(const SizedBox(height: 4));
                items.add(_snapImageRotated(imgData, rotation));
              }
          }
        }
      }
    } catch (_) {
      // Plain text fallback
      final preview = note.preview;
      if (preview != null && preview.isNotEmpty) {
        return Text(preview,
          style: TextStyle(fontSize: 8, color: textColor, height: 1.4),
          overflow: TextOverflow.fade);
      }
    }

    if (items.isEmpty) {
      return Text('Empty note',
        style: TextStyle(fontSize: 8, color: mutedColor, fontStyle: FontStyle.italic));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: items
          .map((w) => Padding(padding: const EdgeInsets.only(bottom: 2), child: w))
          .toList(),
    );
  }

  Widget _snapImage(String dataUri) {
    try {
      final comma = dataUri.indexOf(',');
      final b64 = comma >= 0 ? dataUri.substring(comma + 1) : dataUri;
      final bytes = base64Decode(b64);
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          bytes,
          width: double.infinity,
          fit: BoxFit.cover,
          cacheHeight: 160,
          gaplessPlayback: true,
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  /// Like [_snapImage] but applies the saved rotation angle.
  /// The card preview is already faded/clipped at the bottom so we don't
  /// need to worry about the rotated corners overflowing the card boundary.
  Widget _snapImageRotated(String dataUri, double rotation) {
    final img = _snapImage(dataUri);
    if (rotation == 0.0) return img;
    return Transform.rotate(angle: rotation, child: img);
  }

  Widget _buildListLayout(BuildContext context, List<Tag> tags, Color? noteColor) {
    final imageData = _firstImageData();
    final hasDrawing = !note.isLocked && imageData == null && (_parseStrokes()?.isNotEmpty ?? false);
    final previewText = note.isLocked ? null : note.preview;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          // ── Text section ───────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title.isEmpty ? 'Untitled' : note.title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (previewText != null && previewText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(previewText,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ] else if (hasDrawing) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.draw_outlined, size: 12, color: Colors.indigo.shade300),
                      const SizedBox(width: 3),
                      Text('Drawing', style: TextStyle(fontSize: 12, color: Colors.indigo.shade300)),
                    ],
                  ),
                ],
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: tags.take(3).map((t) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _buildTagChip(t),
                  )).toList()),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ── Right section: thumbnail + date + icons ─────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (imageData != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: _imageThumbnail(imageData, height: 52, width: 52),
                ),
                const SizedBox(height: 4),
              ],
              Text(_formatDate(note.updatedAt),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (note.isPinned) const Icon(Icons.push_pin_rounded, size: 14, color: Colors.blue),
                  if (note.isLocked) const Icon(Icons.lock_rounded, size: 14, color: Colors.orange),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(Tag tag) {
    Color? chipColor;
    if (tag.color != null) {
      try {
        chipColor = Color(int.parse(tag.color!.replaceAll('#', 'FF'), radix: 16));
      } catch (_) {}
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (chipColor ?? Colors.blue).withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(tag.name,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: chipColor ?? Colors.blue,
        )),
    );
  }

  String _formatDate(int ts) {
    if (ts == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.month}/${d.day}/${d.year}';
  }
}

// ── Scaled stroke preview painter ────────────────────────────────────────────

class _StrokePreviewPainter extends CustomPainter {
  final List<Map<String, dynamic>> strokes;
  final Color background;

  const _StrokePreviewPainter({required this.strokes, required this.background});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = background,
    );
    if (strokes.isEmpty) return;

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final s in strokes) {
      if (s['eraser'] == true) continue;
      for (final p in (s['pts'] as List? ?? [])) {
        final x = (p[0] as num).toDouble();
        final y = (p[1] as num).toDouble();
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
    if (minX == double.infinity) return;

    const pad = 8.0;
    final scale = min(
      (size.width - pad * 2) / (maxX - minX).clamp(1, double.infinity),
      (size.height - pad * 2) / (maxY - minY).clamp(1, double.infinity),
    );
    final dx = pad - minX * scale;
    final dy = pad - minY * scale;

    for (final s in strokes) {
      if (s['eraser'] == true) continue;
      final pts = s['pts'] as List? ?? [];
      if (pts.isEmpty) continue;

      Color color = Colors.black;
      try {
        color = Color(int.parse((s['color'] as String).replaceAll('0x', ''), radix: 16));
      } catch (_) {}

      final strokeWidth = ((s['width'] as num?)?.toDouble() ?? 2.0) * scale;
      final path = Path();
      path.moveTo((pts[0][0] as num) * scale + dx, (pts[0][1] as num) * scale + dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo((pts[i][0] as num) * scale + dx, (pts[i][1] as num) * scale + dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth.clamp(0.5, 4.0)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
