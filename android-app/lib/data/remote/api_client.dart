import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/app_constants.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  Dio? _dio;
  final _storage = const FlutterSecureStorage();

  Future<Dio> _getDio() async {
    if (_dio != null) return _dio!;

    final serverUrl = await _storage.read(key: AppConstants.serverUrlKey) ?? '';
    final username  = await _storage.read(key: AppConstants.usernameKey) ?? '';
    final password  = await _storage.read(key: AppConstants.appPasswordKey) ?? '';

    final credentials = base64Encode(utf8.encode('$username:$password'));

    _dio = Dio(BaseOptions(
      baseUrl: '$serverUrl${AppConstants.apiBase}',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Authorization': 'Basic $credentials',
        'OCS-APIRequest': 'true',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    _dio!.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) {
        // Invalidate cached client on auth failure so next call re-reads credentials
        if (error.response?.statusCode == 401 || error.response?.statusCode == 403) {
          _dio = null;
        }
        handler.next(error);
      },
    ));

    return _dio!;
  }

  void reset() => _dio = null;

  Future<dynamic> get(String path, {Map<String, dynamic>? params}) async {
    final dio = await _getDio();
    final response = await dio.get(path, queryParameters: params);
    return _unwrap(response.data);
  }

  Future<dynamic> post(String path, dynamic data) async {
    final dio = await _getDio();
    final response = await dio.post(path, data: data);
    return _unwrap(response.data);
  }

  Future<dynamic> put(String path, dynamic data) async {
    final dio = await _getDio();
    final response = await dio.put(path, data: data);
    return _unwrap(response.data);
  }

  Future<void> delete(String path, {Map<String, dynamic>? params}) async {
    final dio = await _getDio();
    await dio.delete(path, queryParameters: params);
  }

  Future<bool> testConnection(String serverUrl, String username, String password) async {
    try {
      final credentials = base64Encode(utf8.encode('$username:$password'));
      final testDio = Dio(BaseOptions(
        baseUrl: '$serverUrl${AppConstants.apiBase}',
        connectTimeout: const Duration(seconds: 10),
        headers: {
          'Authorization': 'Basic $credentials',
          'OCS-APIRequest': 'true',
        },
      ));
      await testDio.get(AppConstants.notebooksPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  dynamic _unwrap(dynamic data) {
    // Nextcloud OCS wraps responses: { ocs: { data: [...] } }
    if (data is Map && data.containsKey('ocs')) {
      return data['ocs']['data'];
    }
    return data;
  }
}
