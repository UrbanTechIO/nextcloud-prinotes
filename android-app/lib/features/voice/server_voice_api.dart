import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../data/remote/api_client.dart';
import 'voice_sync.dart';

/// Voice recordings on the Nextcloud server (PriNotes/voice in the user's Files).
class ServerVoiceApi implements VoiceApi {
  final ApiClient api;
  ServerVoiceApi(this.api);

  @override
  Future<void> upload(String id, File file, String mime) async {
    final form = FormData.fromMap({
      'id': id,
      'file': await MultipartFile.fromFile(file.path, filename: file.uri.pathSegments.last, contentType: DioMediaType.parse(mime)),
    });
    await api.postForm('/voices', form);
  }

  @override
  Future<Uint8List?> download(String id) async {
    final bytes = await api.getBytes('/voices/$id');
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(String id) => api.delete('/voices/$id');
}
