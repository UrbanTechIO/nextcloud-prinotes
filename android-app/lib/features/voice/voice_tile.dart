import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';

import 'voice_content.dart';
import 'voice_playback.dart';
import 'voice_store.dart';
import 'voice_wave.dart';
import 'voice_waveform.dart';

/// A recording inside a note: play / pause, a seek bar, the name, the time, and a delete button.
class VoiceTile extends StatefulWidget {
  final String id;
  final Map<String, dynamic> meta;
  final VoiceStore? store;
  final VoicePlayback playback;
  final void Function(String label) onRename;
  final VoidCallback onDelete;

  /// Fetches the recording from the server when this phone does not have it. Returns true when it arrived.
  final Future<bool> Function(String id, String mime)? onDownload;

  /// The recording was held and dragged, and let go at this point on the screen (so the note can move it there).
  final void Function(Offset globalPoint)? onDrop;

  const VoiceTile({
    super.key,
    required this.id,
    required this.meta,
    required this.store,
    required this.playback,
    required this.onRename,
    required this.onDelete,
    this.onDownload,
    this.onDrop,
  });

  @override
  State<VoiceTile> createState() => _VoiceTileState();
}

class _VoiceTileState extends State<VoiceTile> {
  StreamSubscription<Duration>? _posSub;
  Duration _pos = Duration.zero;
  bool _downloading = false;
  bool _failed = false;
  double _dragDy = 0;
  bool _dragging = false;

  int get _durationMs => (widget.meta['duration'] as num?)?.toInt() ?? 0;
  String get _mime => (widget.meta['mime'] as String?) ?? 'audio/mp4';
  String get _label => (widget.meta['label'] as String?) ?? 'Voice note';
  File? get _file => widget.store?.find(widget.id);
  bool get _mine => widget.playback.currentId == widget.id;

  @override
  void initState() {
    super.initState();
    widget.playback.addListener(_onPlayback);
    _listenPosition();
  }

  @override
  void dispose() {
    widget.playback.removeListener(_onPlayback);
    _posSub?.cancel();
    super.dispose();
  }

  void _onPlayback() {
    if (!mounted) return;
    _listenPosition();
    if (!_mine && _pos != Duration.zero) _pos = Duration.zero;
    setState(() {});
  }

  void _listenPosition() {
    if (_mine && _posSub == null) {
      _posSub = widget.playback.position.listen((p) {
        if (mounted && _mine) setState(() => _pos = p);
      });
    } else if (!_mine && _posSub != null) {
      _posSub?.cancel();
      _posSub = null;
    }
  }

  Future<void> _play() async {
    final f = _file;
    if (f == null) return;
    await widget.playback.toggle(widget.id, f);
  }

  /// Tap or drag on the bars: jump there. A recording that is not playing starts from that place.
  Future<void> _seek(double fraction) async {
    final f = _file;
    if (f == null || _durationMs == 0) return;
    final to = Duration(milliseconds: (fraction * _durationMs).round());
    if (_mine) {
      await widget.playback.seek(widget.id, to);
    } else {
      await widget.playback.toggle(widget.id, f, startAt: to);
    }
  }

  Future<void> _download() async {
    if (widget.onDownload == null) return;
    setState(() {
      _downloading = true;
      _failed = false;
    });
    final ok = await widget.onDownload!(widget.id, _mime);
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _failed = !ok;
    });
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: _label);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name this recording'),
        content: TextField(controller: c, autofocus: true, maxLength: 60),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) widget.onRename(name);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final have = _file != null;
    final playing = widget.playback.isPlaying(widget.id);
    final total = Duration(milliseconds: _durationMs);
    final shown = _mine ? _pos : Duration.zero;
    final fraction = total.inMilliseconds == 0 ? 0.0 : (shown.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    Widget button;
    if (have) {
      button = IconButton.filledTonal(
        key: const ValueKey('voice-play'),
        tooltip: playing ? 'Pause' : 'Play',
        icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        onPressed: _play,
      );
    } else if (_downloading) {
      button = const SizedBox(width: 48, height: 48, child: Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2.5)));
    } else {
      button = IconButton.filledTonal(
        key: const ValueKey('voice-download'),
        tooltip: 'Download',
        icon: const Icon(Icons.download_rounded),
        onPressed: widget.onDownload == null ? null : _download,
      );
    }

    final tile = Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        color: playing ? scheme.primaryContainer.withOpacity(0.6) : scheme.onSurface.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        boxShadow: _dragging ? const [BoxShadow(color: Colors.black45, blurRadius: 14, offset: Offset(0, 6))] : null,
      ),
      child: Row(
        children: [
          button,
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VoiceWaveform(
                  key: const ValueKey('voice-seek'),
                  bars: barsToShow(widget.meta),
                  progress: fraction,
                  playedColor: scheme.primary,
                  restColor: scheme.onSurface.withOpacity(0.28),
                  onSeek: have ? _seek : null,
                ),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _rename,
                        child: Text(
                          have ? _label : (_failed ? 'Not available yet. Try again when online.' : '$_label (not on this phone yet)'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: scheme.onSurface.withOpacity(0.75)),
                        ),
                      ),
                    ),
                    Text(
                      _mine ? '${formatVoiceLength(shown.inMilliseconds)} / ${formatVoiceLength(_durationMs)}' : formatVoiceLength(_durationMs),
                      style: TextStyle(fontSize: 12, color: scheme.onSurface.withOpacity(0.75)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('voice-delete'),
            tooltip: 'Remove recording',
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: scheme.onSurface.withOpacity(0.6)),
            onPressed: () async {
              if (widget.playback.currentId == widget.id) await widget.playback.stop();
              widget.onDelete();
            },
          ),
        ],
      ),
    );

    if (widget.onDrop == null) return tile;
    // Hold the recording for a moment, then drag it up or down between the lines of the note.
    return GestureDetector(
      onLongPressStart: (_) => setState(() {
        _dragging = true;
        _dragDy = 0;
        HapticFeedback.mediumImpact();
      }),
      onLongPressMoveUpdate: (d) => setState(() => _dragDy = d.offsetFromOrigin.dy),
      onLongPressEnd: (d) {
        setState(() {
          _dragging = false;
          _dragDy = 0;
        });
        widget.onDrop!(d.globalPosition);
      },
      onLongPressCancel: () => setState(() {
        _dragging = false;
        _dragDy = 0;
      }),
      child: Transform.translate(
        offset: Offset(0, _dragDy),
        child: Opacity(opacity: _dragging ? 0.92 : 1, child: tile),
      ),
    );
  }
}
