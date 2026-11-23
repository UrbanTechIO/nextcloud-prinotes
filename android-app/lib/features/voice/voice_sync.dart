import 'dart:io';
import 'dart:typed_data';

import 'voice_content.dart';
import 'voice_store.dart';

/// The server side of voice recordings, as the sync needs it.
abstract class VoiceApi {
  Future<void> upload(String id, File file, String mime);

  /// The recording's audio, or null when the server does not have it.
  Future<Uint8List?> download(String id);

  Future<void> delete(String id);
}

/// Keeps this phone's recordings and the server's in step. Every step is independent and none of them throws:
/// what cannot be done now (no connection) is simply tried again on the next sync.
class VoiceSync {
  /// A recording nobody uses is deleted only after this long, so one that was just made (its note not yet
  /// saved) or one brought back by Undo is never lost.
  static const grace = Duration(hours: 1);

  final VoiceStore store;
  final VoiceApi api;
  final DateTime Function() clock;
  VoiceSync(this.store, this.api, {DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  /// [notes] are the content of every note on the phone (trashed and hidden ones too); null when they could
  /// not be read, in which case nothing is downloaded or deleted.
  Future<void> run({required List<String>? notes}) async {
    // 1. Recordings made here go up first.
    for (final id in store.pendingUploads()) {
      try {
        final file = store.find(id);
        if (file == null) continue;
        await api.upload(id, file, _mimeOf(file));
        store.markUploaded(id);
      } catch (_) {}
    }
    if (notes == null) return;

    final used = <String, String>{};
    for (final n in notes) {
      used.addAll(voiceMimesIn(n));
    }

    // 2. Recordings the notes use but this phone does not have yet.
    for (final e in used.entries) {
      if (store.find(e.key) != null) continue;
      try {
        final bytes = await api.download(e.key);
        if (bytes != null) await store.saveDownloaded(e.key, e.value, bytes);
      } catch (_) {}
    }

    // 3. Recordings no note uses any more.
    for (final id in store.localIds()) {
      if (used.containsKey(id)) continue;
      final added = store.addedAt(id);
      if (added == null || clock().difference(added) < grace) continue;
      try {
        await api.delete(id);
        await store.remove(id);
      } catch (_) {}
    }
  }

  static String _mimeOf(File f) {
    final p = f.path.toLowerCase();
    if (p.endsWith('.webm')) return 'audio/webm';
    if (p.endsWith('.ogg')) return 'audio/ogg';
    if (p.endsWith('.mp3')) return 'audio/mpeg';
    if (p.endsWith('.aac')) return 'audio/aac';
    return 'audio/mp4';
  }
}
