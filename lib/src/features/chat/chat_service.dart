// lib/services/chat_service.dart
import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Provider you already had — keep using it.
/// Configure API_BASE_URL and API_KEY via --dart-define or .env loader.
final chatServiceProvider = Provider<ChatService>((ref) {
  final baseUrl = const String.fromEnvironment('API_BASE_URL'); // e.g. http://10.0.2.2:5000
  final apiKey  = const String.fromEnvironment('API_KEY');      // your x-api-key
  return ChatService(baseUrl, apiKey);
});

/// Model for a chat response (now includes TTS)
class ChatReply {
  final String kaiResponse;
  final String? ttsBase64;
  final String? mbti;
  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? mood;
  final String? summary;
  final List<dynamic>? tags;
  final Map<String, dynamic> raw;

  ChatReply({
    required this.kaiResponse,
    required this.raw,
    this.ttsBase64,
    this.mbti,
    this.profile,
    this.mood,
    this.summary,
    this.tags,
  });

  factory ChatReply.fromJson(Map<String, dynamic> data) {
    return ChatReply(
      kaiResponse: (data['kai_response'] ?? data['reply'] ?? '') as String,
      ttsBase64: data['tts_base64'] as String?,
      mbti: data['kai_mbti'] as String?,
      profile: data['kai_profile'] as Map<String, dynamic>?,
      mood: data['kai_mood'] as Map<String, dynamic>?,
      summary: data['kai_summary'] as String?,
      tags: data['tags'] as List<dynamic>?,
      raw: data,
    );
  }
}

class ChatService {
  final String baseUrl;
  final String apiKey;
  final Dio _dio;

  ChatService(this.baseUrl, this.apiKey)
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            headers: {
              'x-api-key': apiKey,
              'Content-Type': 'application/json',
            },
            // optional: increase if TTS payloads get chunky
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
          ),
        );

  /// Sends a plain text message to /chat.
  /// Server should now include tts_base64 if you added the block I gave you.
  Future<ChatReply> send(String text) async {
    final r = await _dio.post(
      '/chat',
      data: {
        'text': text,
        'actor_type': 'agent',
        'source': 'app',
      },
    );

    if (r.statusCode != 200) {
      throw Exception('Failed to get reply: ${r.statusCode} ${r.statusMessage}');
    }

    final data = (r.data as Map).cast<String, dynamic>();
    return ChatReply.fromJson(data);
  }

  /// If you decide to keep using /voice (audio upload), add a method like:
  /// Future<ChatReply> sendVoiceBase64(String audioB64) async { ... }
}
