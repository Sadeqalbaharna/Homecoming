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

  /// Synthesize [text] via ElevenLabs and return raw MP3 bytes, or null on error.
  Future<Uint8List?> synthesizeTTS(String text) async {
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
            'stability': 0.6,
            'similarity_boost': 0.75,
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
