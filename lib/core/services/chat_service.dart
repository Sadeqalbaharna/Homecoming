// lib/core/services/chat_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';

/// ===== API config via --dart-define =====
const String kBaseUrl =
    String.fromEnvironment('API_BASE_URL', defaultValue: '');
const String kApiKey =
    String.fromEnvironment('API_KEY_VALUE', defaultValue: '');

String _sanitizeBaseUrl(String raw) {
  final u = raw.trim();
  if (u.isEmpty) {
    throw ArgumentError(
        'API_BASE_URL is not set. Launch Flutter with --dart-define=API_BASE_URL=https://<host>');
  }
  return u.replaceAll(RegExp(r'/+$'), '');
}

/* =============================== DATA MODELS & SERVICE ============================ */

class ChatReply {
  final String reply;
  final String? ttsBase64;
  final String? mp3Path;
  final Map raw;
  ChatReply(
      {required this.reply, required this.raw, this.ttsBase64, this.mp3Path});
}

class AgentState {
  final Map<String, dynamic> personalityCurrent; // 0..1000
  final Map<String, dynamic> moodCurrent; // 0..100
  final Map<String, dynamic> affinityCurrent; // intimacy/physicality 0..100
  final String? mbti;
  final Map<String, dynamic>? labels; // personality_labels, mood_labels
  final String? summary;

  AgentState({
    required this.personalityCurrent,
    required this.moodCurrent,
    required this.affinityCurrent,
    this.mbti,
    this.labels,
    this.summary,
  });

  factory AgentState.fromJson(
    Map<String, dynamic> pc,
    Map<String, dynamic> mc,
    Map<String, dynamic> ps,
    Map<String, dynamic> ac,
  ) {
    return AgentState(
      personalityCurrent: pc,
      moodCurrent: mc,
      affinityCurrent: ac,
      mbti: ps['mbti'] as String?,
      labels: (ps['labels'] as Map?)?.cast<String, dynamic>(),
      summary: ps['summary'] as String?,
    );
  }
}

class ChatService {
  ChatService()
      : _dio = Dio(
          BaseOptions(
            baseUrl: _sanitizeBaseUrl(kBaseUrl),
            headers: {
              'x-api-key': kApiKey,
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 60),
            validateStatus: (c) => c != null && c >= 200 && c < 600,
          ),
        );
  final Dio _dio;

  // DEV pane snapshots
  static Map<String, String>? lastChatDebug;
  static Map<String, String>? lastTtsDebug;
  static Map<String, String>? lastSearchDebug;

  // persona config cache
  final Map<String, Map<String, dynamic>> _personaConfigCache = {};

  // ----- retry helpers -----
  static const List<Duration> _retryDelays = [
    Duration(milliseconds: 400),
    Duration(seconds: 1),
    Duration(seconds: 3),
  ];

  bool _isRetryable(Object e, [int? status]) {
    if (status == null && e is DioException) status = e.response?.statusCode;
    if (status != null && (status == 502 || status == 503 || status == 504)) {
      return true;
    }
    if (e is DioException &&
        (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.unknown)) {
      return true;
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
        if (!_isRetryable(Object(), sc)) return res;
        lastResponse = res;
      } catch (e) {
        if (!_isRetryable(e)) rethrow;
        lastError = e;
      }
      if (i < _retryDelays.length) {
        await Future.delayed(_retryDelays[i]);
      }
    }
    if (lastResponse != null) return lastResponse;
    if (lastError is DioException) {
      final de = lastError as DioException;
      throw Exception(
          'Network error after retries: ${de.type} ${de.message ?? ''}');
    }
    throw Exception('Network error after retries: ${lastError ?? 'unknown'}');
  }

  Map<String, dynamic> _clientTime() {
    final now = DateTime.now();
    return {
      'iso': now.toIso8601String(),
      'tz_offset_min': now.timeZoneOffset.inMinutes,
      'tz_name': now.timeZoneName,
      'platform': Platform.operatingSystem,
      'source': 'app',
    };
  }

  Future<void> pushClientTime({required String personaId}) async {
    try {
      final res = await _withRetry(
        () => _dio.post(
          '/client_time',
          data: _clientTime(),
          options: Options(headers: {'x-persona-id': personaId}),
        ),
      );
      lastSearchDebug = _debugFromResponse(res);
    } catch (_) {}
  }

  Future<void> warmUp({required String personaId}) async {
    try {
      final res = await _withRetry(() => _dio.get(
            '/diag',
            options: Options(
              headers: {'x-persona-id': personaId},
              sendTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
            ),
          ));
      lastChatDebug = _debugFromResponse(res);
    } catch (_) {}
  }

  // ----- persona bootstrap/config -----
  Future<void> bootstrapPersona(String personaId) async {
    try {
      final res = await _withRetry(() => _dio.post(
            '/bootstrap_persona',
            data: {'persona_id': personaId},
            options: Options(headers: {'x-persona-id': personaId}),
          ));
      lastSearchDebug = _debugFromResponse(res);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> fetchPersonaConfig(String personaId) async {
    if (_personaConfigCache.containsKey(personaId)) {
      return _personaConfigCache[personaId]!;
    }
    final res = await _withRetry(() => _dio.get(
          '/persona_config',
          queryParameters: {'persona_id': personaId},
          options: Options(headers: {'x-persona-id': personaId}),
        ));
    if (res.statusCode == 200 && res.data is Map) {
      final m = (res.data as Map).cast<String, dynamic>();
      _personaConfigCache[personaId] = m;
      return m;
    }
    throw Exception('persona_config ${res.statusCode}: ${res.data}');
  }

  // ----- chat/tts/state -----
  Future<ChatReply> sendText(
    String text, {
    String model = 'gpt-4o',
    bool adaptUser = false,
    int ctxTurns = 20,
    required String personaId,
  }) async {
    final res = await _withRetry(() => _dio.post(
          '/chat',
          data: {
            'text': text,
            'actor_type': 'agent',
            'source': 'app',
            'model': model,
            'adapt_user': adaptUser,
            'ctx_turns': ctxTurns,
            'client_time': _clientTime(),
            'persona_id': personaId,
          },
          options: Options(headers: {'x-persona-id': personaId}),
        ));
    lastChatDebug = _debugFromResponse(res);

    if (res.statusCode == 200 && res.data is Map) {
      final m = res.data as Map;
      final reply = (m['kai_response'] ?? m['reply'] ?? '').toString();
      final ttsB64 = (m['tts_base64'] ?? '').toString();
      String? mp3Path;
      if (ttsB64.isNotEmpty) {
        mp3Path = await _writeTempMp3(base64Decode(ttsB64));
      }
      return ChatReply(
        reply: reply,
        ttsBase64: ttsB64.isNotEmpty ? ttsB64 : null,
        mp3Path: mp3Path,
        raw: m,
      );
    }
    throw Exception('Chat ${res.statusCode}: ${res.data}');
  }

  Future<String> synthesizeTTS(String text, {required String personaId}) async {
    final res = await _withRetry(() => _dio.post(
          '/tts',
          data: {'text': text},
          options: Options(headers: {'x-persona-id': personaId}),
        ));
    lastTtsDebug = _debugFromResponse(res);
    if (res.statusCode == 200 && res.data is Map) {
      final b64 = (res.data['tts_base64'] ?? '').toString();
      if (b64.isEmpty) throw Exception('Missing tts_base64');
      return _writeTempMp3(base64Decode(b64));
    }
    throw Exception('TTS ${res.statusCode}: ${res.data}');
  }

  Future<AgentState> fetchAgentState({required String personaId}) async {
    final res = await _withRetry(() => _dio.get(
          '/get_state',
          queryParameters: {'actor_type': 'agent'},
          options: Options(headers: {'x-persona-id': personaId}),
        ));
    if (res.statusCode == 200 && res.data is Map) {
      final m = res.data as Map;
      final pc = (m['personality_current'] ?? {}) as Map;
      final mc = (m['mood_current'] ?? {}) as Map;
      final ps = (m['personality_summary'] ?? {}) as Map;
      final ac = (m['affinity_current'] ?? {}) as Map;
      return AgentState.fromJson(
        pc.cast<String, dynamic>(),
        mc.cast<String, dynamic>(),
        ps.cast<String, dynamic>(),
        ac.cast<String, dynamic>(),
      );
    }
    throw Exception('get_state ${res.statusCode}: ${res.data}');
  }

  Future<void> setStateRemote({
    required Map<String, num> personality,
    required Map<String, num> mood,
    required Map<String, num> affinity,
    String actorType = 'agent',
    required String personaId,
  }) async {
    final res = await _withRetry(() => _dio.post(
          '/set_state',
          data: {
            'actor_type': actorType,
            'personality_current': personality,
            'mood_current': mood,
            'affinity_current': affinity,
          },
          options: Options(headers: {'x-persona-id': personaId}),
        ));
    if (res.statusCode != 200) {
      throw Exception('set_state ${res.statusCode}: ${res.data}');
    }
  }

  // (available if server implements them; UI keeps them disabled)
  Future<void> initPersona(Map<String, dynamic> fullJson,
      {required String personaId}) async {
    final res = await _withRetry(
      () => _dio.post(
        '/persona/init',
        data: {'persona': fullJson},
        options: Options(headers: {'x-persona-id': personaId}),
      ),
    );
    if (res.statusCode != 200) {
      throw Exception('persona/init ${res.statusCode}: ${res.data}');
    }
  }

  Future<void> patchPersona(Map<String, dynamic> patch,
      {required String personaId}) async {
    final res = await _withRetry(
      () => _dio.post(
        '/persona/patch',
        data: {'patch': patch},
        options: Options(headers: {'x-persona-id': personaId}),
      ),
    );
    if (res.statusCode != 200) {
      throw Exception('persona/patch ${res.statusCode}: ${res.data}');
    }
  }

  Future<Map<String, dynamic>> selectPersonaSlice(
      {required List<String> tags, required String personaId}) async {
    final res = await _withRetry(
      () => _dio.post(
        '/persona/select',
        data: {'tags': tags},
        options: Options(headers: {'x-persona-id': personaId}),
      ),
    );
    if (res.statusCode == 200 && res.data is Map) {
      return (res.data as Map).cast<String, dynamic>();
    }
    throw Exception('persona/select ${res.statusCode}: ${res.data}');
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

  Future<String> _writeTempMp3(Uint8List bytes) async {
    final dir = Directory.systemTemp;
    final file =
        File('${dir.path}/kai_reply_${DateTime.now().millisecondsSinceEpoch}.mp3');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}

final chatService = ChatService();
