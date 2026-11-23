import 'dart:convert';

/// Voice recordings live in the note's content next to the pictures:
///   "voices": { "<id>": { "label": "Voice note 09:05", "duration": 4200, "mime": "audio/mp4" } }
/// and in the text as an embed `{"insert": {"voice": "<id>"}}`. The audio itself is a separate file.

Map<String, dynamic>? _voices(String? contentJson) {
  if (contentJson == null || contentJson.isEmpty) return null;
  try {
    final c = jsonDecode(contentJson);
    final v = c is Map ? c['voices'] : null;
    return v is Map ? Map<String, dynamic>.from(v) : null;
  } catch (_) {
    return null;
  }
}

/// The ids of the recordings a note uses.
Set<String> voiceIdsIn(String? contentJson) => _voices(contentJson)?.keys.toSet() ?? <String>{};

/// Recording id → its audio type, as the note says.
Map<String, String> voiceMimesIn(String? contentJson) {
  final v = _voices(contentJson);
  if (v == null) return {};
  return {
    for (final e in v.entries) e.key: (e.value is Map ? (e.value['mime'] as String?) : null) ?? 'audio/mp4',
  };
}

String _two(int n) => n.toString().padLeft(2, '0');

/// What a new recording is saved as in the note.
Map<String, dynamic> newVoiceMeta({required int durationMs, required String mime, DateTime? at, List<int>? wave}) {
  final t = at ?? DateTime.now();
  return {
    'label': 'Voice note ${_two(t.hour)}:${_two(t.minute)}',
    'duration': durationMs,
    'mime': mime,
    if (wave != null && wave.isNotEmpty) 'wave': wave,
  };
}

/// 4200 becomes "0:04", 65000 becomes "1:05".
String formatVoiceLength(int ms) {
  final s = (ms / 1000).floor();
  return '${s ~/ 60}:${_two(s % 60)}';
}
