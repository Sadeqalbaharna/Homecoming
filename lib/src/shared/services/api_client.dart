import 'package:dio/dio.dart';

/// Reads your dart-defines:
///   --dart-define=API_BASE_URL=...
///   --dart-define=API_KEY=...
const _baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
const _apiKey  = String.fromEnvironment('API_KEY', defaultValue: '');

Dio makeDio() {
  final dio = Dio(BaseOptions(
    baseUrl: _baseUrl.isEmpty ? 'http://localhost:5000' : _baseUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'Content-Type': 'application/json',
      if (_apiKey.isNotEmpty) 'x-api-key': _apiKey,
    },
  ));

  // Simple log interceptor (optional, handy while wiring up)
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (o, h) {
      // print('[HTTP] ${o.method} ${o.uri}');
      h.next(o);
    },
    onError: (e, h) {
      // print('[HTTP:ERR] ${e.response?.statusCode} ${e.message}');
      h.next(e);
    },
  ));
  return dio;
}
