// lib/chat_service.dart
import 'dart:async';
import 'dart:convert' show base64;
import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Global provider so we can override it in main.dart with a real instance.
final chatServiceProvider = Provider<ChatService>(
  (ref) => throw UnimplementedError('chatServiceProvider must be overridden in main.dart'),
  name: 'chatServiceProvider',
);

String _sanitizeBaseUrl(String url) =>
    url.endsWith('/') ? url.substring(0, url.length - 1) : url;

class ChatService {
  // ---- Env (provided at build via --dart-define) ----
  static const String kBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');
  static const String kApiKey =
      String.fromEnvironment('API_KEY_VALUE', defaultValue: '');

  // ---- Instance config ----
  final String baseUrl;
  final String apiKey;
  final Dio _dio;

  // ---- Tiny debug snapshots for your DEV pane (optional) ----
  Map<String, String>? lastChatDebug;
  Map<String, String>? lastTtsDebug;
  Map<String, String>? lastDiagDebug;

  ChatService({String? baseUrlOverride, String? apiKeyOverride})
      : baseUrl = _sanitizeBaseUrl(baseUrlOverride ?? kBaseUrl),
        apiKey = apiKeyOverride ?? kApiKey,
        _dio = Dio(
          BaseOptions(
            baseUrl: _sanitizeBaseUrl(baseUrlOverride ?? kBaseUrl),
            headers: {
              'x-api-key': apiKeyOverride ?? kApiKey,
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 60),
            validateStatus: (c) => c != null && c >= 200 && c < 600,
          ),
        );

  // ---------- Retry helpers (null‑safe) ----------
  static const List<Duration> _retryDelays = <Duration>[
    Duration(milliseconds: 400),
    Duration(seconds: 1),
    Duration(seconds: 3),
  ];

  bool _isRetryable(Object e, [int? status]) {
    if (status == 502 || status == 503 || status == 504) return true;
    if (e is DioException) {
      return e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.unknown;
    }
    return false;
  }

  Future<Response<dynamic>> _withRetry(
      Future<Response<dynamic>> Function() send) async {
    Response<dynamic>? lastResponse;
    Object? lastError;

    for (int i = 0; i <= _retryDelays.length; i++) {
      try {
        final res = await send();
        final sc = res.statusCode ?? 0;
        if (!_isRetryable(Object(), sc)) return res; // success or non‑retryable
        lastResponse = res; // retryable 5xx → remember and retry
      } catch (e) {
        if (!_isRetryable(e)) rethrow; // non‑retryable → surface
        lastError = e;                  // retryable network exception
      }
      if (i < _retryDelays.length) {
        await Future.delayed(_retryDelays[i]);
      }
    }

    if (lastResponse != null) return lastResponse;

    if (lastError is DioException) {
      final de = lastError as DioException;
      throw Exception('Network error after retries: ${de.type} ${de.message ?? ''}');
    }
    throw Exception('Network error after retries: ${lastError ?? 'unknown'}');
  }

  Map<String, String> _debugFromResponse(Response res) {
    final headers =
        res.headers.map.map((k, v) => MapEntry(k, v.join(','))).toString();
    String bodySnippet = '';
    try {
      bodySnippet =
          res.data is String ? (res.data as String) : (res.data?.toString() ?? '');
    } catch (_) {}
    if (bodySnippet.length > 300) bodySnippet = bodySnippet.substring(0, 300);
    return {
      'status': '${res.statusCode}',
      'content-type': res.headers.value('content-type') ?? '',
      'headers': headers,
      'body (first 300 chars)': bodySnippet,
    };
  }

  // ---------- Warm‑up (call once at startup) ----------
  Future<void> warmUp() async {
    try {
      final res = await _withRetry(() => _dio.get(
            '/diag',
            options: Options(
              sendTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
            ),
          ));
      lastDiagDebug = _debugFromResponse(res);
    } catch (_) {
      // best effort
    }
  }

  // ---------- API calls ----------
  Future<Map<String, dynamic>> sendText(
    String text, {
    String actorType = 'agent',
    String source = 'app',
    String? model,
    bool? adaptUser,
    int? ctxTurns,
  }) async {
    final res = await _withRetry(() => _dio.post('/chat', data: {
          'text': text,
          'actor_type': actorType,
          'source': source,
          if (model != null) 'model': model,
          if (adaptUser != null) 'adapt_user': adaptUser,
          if (ctxTurns != null) 'ctx_turns': ctxTurns,
        }));
    lastChatDebug = _debugFromResponse(res);
    return (res.data as Map).cast<String, dynamic>();
  }

  /// Returns raw MP3 bytes decoded from base64. Empty list if TTS disabled.
  Future<List<int>> synthesizeTTS(String text) async {
    final res = await _withRetry(() => _dio.post('/tts', data: {'text': text}));
    lastTtsDebug = _debugFromResponse(res);
    final map = (res.data as Map).cast<String, dynamic>();
    final b64 = (map['tts_base64'] as String?) ?? (map['audio_b64'] as String?);
    if (b64 == null || b64.isEmpty) return const <int>[];
    return base64.decode(b64);
  }

  Future<Map<String, dynamic>> fetchAgentState({String actorType = 'agent'}) async {
    final res = await _withRetry(
      () => _dio.get('/get_state', queryParameters: {'actor_type': actorType}),
    );
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<void> setStateRemote({
    required Map<String, num> personality,
    required Map<String, num> mood,
    required Map<String, num> affinity,
    String actorType = 'agent',
  }) async {
    final res = await _withRetry(() => _dio.post('/set_state', data: {
          'actor_type': actorType,
          'personality_current': personality,
          'mood_current': mood,
          'affinity_current': affinity,
        }));
    if (res.statusCode != 200) {
      throw Exception('set_state ${res.statusCode}: ${res.data}');
    }
  }
}
