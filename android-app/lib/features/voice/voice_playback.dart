import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// What the voice tiles need from an audio player. Tests give them a fake one.
abstract class VoicePlayer {
  Stream<Duration> get position;

  /// True while the sound is playing, false when paused or stopped.
  Stream<bool> get playing;

  /// Fires when the audio reaches its end.
  Stream<void> get completed;

  Future<void> load(File file);

  /// Starts playing. On the real player this only finishes when the sound ends, so never wait for it.
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Future<void> stop();
  Future<void> dispose();
}

class JustAudioVoicePlayer implements VoicePlayer {
  final AudioPlayer _p = AudioPlayer();

  @override
  Stream<Duration> get position => _p.positionStream;
  @override
  Stream<bool> get playing => _p.playingStream;
  @override
  Stream<void> get completed => _p.processingStateStream.where((s) => s == ProcessingState.completed);

  @override
  Future<void> load(File file) => _p.setFilePath(file.path);
  @override
  Future<void> play() => _p.play();
  @override
  Future<void> pause() => _p.pause();
  @override
  Future<void> seek(Duration to) => _p.seek(to);
  @override
  Future<void> stop() => _p.stop();
  @override
  Future<void> dispose() => _p.dispose();
}

/// One player for the whole app, so that starting a recording stops the one that was playing.
/// What the tiles show comes from the player itself (is it playing, where is it), not from guesses.
class VoicePlayback extends ChangeNotifier {
  VoicePlayback._(this._factory);

  static VoicePlayback shared = VoicePlayback._(JustAudioVoicePlayer.new);

  /// For tests: a playback that uses [factory] to make its player.
  @visibleForTesting
  factory VoicePlayback.withPlayer(VoicePlayer Function() factory) => VoicePlayback._(factory);

  final VoicePlayer Function() _factory;
  VoicePlayer? _player;
  final List<StreamSubscription<dynamic>> _subs = [];
  final StreamController<Duration> _position = StreamController<Duration>.broadcast();
  String? _currentId;
  bool _isPlaying = false;

  /// The recording that is loaded (playing or paused), or null.
  String? get currentId => _currentId;
  bool isPlaying(String id) => _currentId == id && _isPlaying;

  /// Where the current recording is, as it plays.
  Stream<Duration> get position => _position.stream;

  void _forgetPlayer() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
  }

  /// Play, or pause when [id] is already playing. Playing another recording stops the current one.
  Future<void> toggle(String id, File file, {Duration? startAt}) async {
    final player = _player ??= _factory();
    if (_currentId == id) {
      if (_isPlaying) {
        await player.pause();
      } else {
        if (startAt != null) await player.seek(startAt);
        unawaited(player.play());
      }
      return;
    }
    _forgetPlayer();
    _currentId = id;
    _isPlaying = false;
    notifyListeners();
    await player.load(file);
    if (startAt != null) await player.seek(startAt);
    _subs
      ..add(player.playing.listen((p) {
        if (_isPlaying == p) return;
        _isPlaying = p;
        notifyListeners();
      }))
      ..add(player.position.listen(_position.add))
      ..add(player.completed.listen((_) async {
        await player.pause();
        await player.seek(Duration.zero);
        _position.add(Duration.zero);
      }));
    unawaited(player.play());
  }

  Future<void> seek(String id, Duration to) async {
    if (_currentId == id) await _player?.seek(to);
  }

  /// Stops and forgets the current recording (it was deleted, or the screen closed).
  Future<void> stop() async {
    _forgetPlayer();
    await _player?.stop();
    _currentId = null;
    _isPlaying = false;
    notifyListeners();
  }
}
