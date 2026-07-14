// Text-to-speech via ElevenLabs
// Extracted from ai_service.dart — no circular imports.

import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'ai_config.dart';
import 'usage_tracking_service.dart';

/// Wraps ElevenLabs TTS synthesis.
class TTSService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
  ));

  /// Strip markdown and formatting symbols that would be read aloud literally.
  static String sanitizeForSpeech(String text) {
    return text
        // Bold / italic markers  ** __ * _
        .replaceAll(RegExp(r'\*{1,3}'), '')
        .replaceAll(RegExp(r'_{1,3}'), '')
        // Heading hashes at line start
        .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
        // Horizontal rules --- *** ___
        .replaceAll(RegExp(r'^[-*_]{3,}\s*$', multiLine: true), '')
        // Inline code and code blocks
        .replaceAll(RegExp(r'`{1,3}[^`]*`{1,3}'), '')
        // Markdown links [text](url) → text
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
        // Blockquote markers
        .replaceAll(RegExp(r'^>\s*', multiLine: true), '')
        // Em/en dashes used as bullet separators → pause
        .replaceAll(RegExp(r'\s*—\s*'), ', ')
        .replaceAll(RegExp(r'\s*–\s*'), ', ')
        // Double hyphens
        .replaceAll(RegExp(r'--+'), ', ')
        // Bullet/list markers at line start  • - * +
        .replaceAll(RegExp(r'^[•\-\*\+]\s+', multiLine: true), '')
        // Numbered list markers  1. 2. etc.
        .replaceAll(RegExp(r'^\d+\.\s+', multiLine: true), '')
        // Tilde strikethrough
        .replaceAll(RegExp(r'~~[^~]*~~'), '')
        // Collapse multiple spaces / blank lines
        .replaceAll(RegExp(r' {2,}'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// Synthesize [text] via ElevenLabs and return raw MP3 bytes, or null on error.
  ///
  /// Optional voice settings (ElevenLabs v1 API):
  /// - [stability]       0–1  Lower = more expressive / varied. Default 0.6.
  /// - [similarityBoost] 0–1  How closely to match the voice clone.  Default 0.75.
  /// - [style]           0–1  Style exaggeration (v2+ models). 0 = natural. Default 0.0.
  Future<Uint8List?> synthesizeTTS(
    String text, {
    double stability       = 0.6,
    double similarityBoost = 0.75,
    double style           = 0.0,
  }) async {
    text = sanitizeForSpeech(text);
    final elevenlabsKey = await AIConfig.getElevenLabsKey();
    if (elevenlabsKey.isEmpty) {
      print('ElevenLabs API key not configured');
      return null;
    }

    final selectedVoiceId = await AIConfig.getSelectedVoiceId();

    try {
      final response = await _dio.post(
        'https://api.elevenlabs.io/v1/text-to-speech/$selectedVoiceId',
        options: Options(
          headers: {
            'xi-api-key': elevenlabsKey,
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.bytes,
        ),
        data: {
          'text': text,
          'model_id': AIConfig.elevenlabsModelId,
          'voice_settings': {
            'stability':        stability,
            'similarity_boost': similarityBoost,
            'style':            style,
          },
        },
      );

      await UsageTrackingService.trackElevenLabs(characterCount: text.length);
      return Uint8List.fromList(response.data);
    } catch (e) {
      print('TTS error: $e');
      return null;
    }
  }
}
