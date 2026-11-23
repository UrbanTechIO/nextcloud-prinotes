import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// The recordings kept on this phone, so they play offline. One audio file per recording, named by its id,
/// plus two small marker files: `<id>.up` (the server has it) and `<id>.t` (when it arrived, in ms).
class VoiceStore {
  final Directory dir;
  final DateTime Function() clock;
  VoiceStore(this.dir, {DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  static VoiceStore? _shared;

  /// The store in the app's own storage.
  static Future<VoiceStore> shared() async {
    if (_shared != null) return _shared!;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/voices');
    if (!d.existsSync()) d.createSync(recursive: true);
    return _shared = VoiceStore(d);
  }

  static const _markers = {'up', 't'};

  static String _extFor(String mime) {
    final m = mime.toLowerCase();
    if (m.contains('webm')) return 'webm';
    if (m.contains('ogg') || m.contains('opus')) return 'ogg';
    if (m.contains('mpeg') || m.contains('mp3')) return 'mp3';
    if (m.contains('aac') && !m.contains('mp4')) return 'aac';
    return 'm4a';
  }

  File _marker(String id, String ext) => File('${dir.path}/$id.$ext');

  Iterable<MapEntry<String, String>> _entries() sync* {
    for (final e in dir.listSync().whereType<File>()) {
      final name = e.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      if (dot <= 0) continue;
      yield MapEntry(name.substring(0, dot), name.substring(dot + 1));
    }
  }

  /// The audio file of a recording, or null when it is not on this phone.
  File? find(String id) {
    for (final e in _entries()) {
      if (e.key == id && !_markers.contains(e.value)) return File('${dir.path}/${e.key}.${e.value}');
    }
    return null;
  }

  /// Takes a freshly recorded file into the store. It waits for upload until [markUploaded].
  Future<File> adopt(File recorded, String id, String mime) async {
    final target = File('${dir.path}/$id.${_extFor(mime)}');
    if (target.existsSync()) await target.delete();
    File stored;
    try {
      stored = await recorded.rename(target.path);
    } on FileSystemException {
      stored = await recorded.copy(target.path); // another storage volume: copy instead
      await recorded.delete();
    }
    await _marker(id, 't').writeAsString('${clock().millisecondsSinceEpoch}');
    return stored;
  }

  /// Keeps a recording fetched from the server. The server already has it.
  Future<File> saveDownloaded(String id, String mime, Uint8List bytes) async {
    final f = File('${dir.path}/$id.${_extFor(mime)}');
    await f.writeAsBytes(bytes, flush: true);
    await _marker(id, 't').writeAsString('${clock().millisecondsSinceEpoch}');
    markUploaded(id);
    return f;
  }

  void markUploaded(String id) => _marker(id, 'up').writeAsStringSync('1');
  bool isUploaded(String id) => _marker(id, 'up').existsSync();

  /// When this phone got the recording.
  DateTime? addedAt(String id) {
    final t = _marker(id, 't');
    if (!t.existsSync()) return null;
    final ms = int.tryParse(t.readAsStringSync());
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Every recording on this phone.
  Set<String> localIds() => {for (final e in _entries()) if (!_markers.contains(e.value)) e.key};

  /// Recordings made here that the server does not have yet.
  List<String> pendingUploads() => [for (final id in localIds()) if (!isUploaded(id)) id]..sort();

  /// Deletes the audio and its markers.
  Future<void> remove(String id) async {
    final audio = find(id);
    if (audio != null) await audio.delete();
    for (final m in _markers) {
      final f = _marker(id, m);
      if (f.existsSync()) await f.delete();
    }
  }
}
