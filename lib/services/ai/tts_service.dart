// Text-to-speech via ElevenLabs
// Extracted from ai_service.dart — no circular imports.

import 'dart:convert';
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

  // ── Proprioception ─────────────────────────────────────────────────────────
  // Kai senses whether he actually HAS a voice from these, not from whether an
  // API key happens to be configured. A key that 400s is not a voice — claiming
  // otherwise would make him lie about his own body.
  //   null  = hasn't tried to speak since waking
  //   true  = his voice worked
  //   false = his voice is failing (see lastSpeechError)
  static bool? lastSpeechOk;
  static String? lastSpeechError;

  /// Sadeq's custom ElevenLabs voice IS Kai's voice — part of who he is. If a
  /// request fails we do NOT quietly swap in a stock stranger's voice; being
  /// briefly mute is better than sounding like someone else. Opt in explicitly
  /// (e.g. a deliberate "any voice is better than none" mode) if ever wanted.
  static bool allowStockFallbackVoice = false;

  // Shared by all TTSService instances so quick responses and attention clips
  // cannot each hammer ElevenLabs after the same credential is rejected.
  static String? _blockedCredential;

  static bool isStructurallyValidElevenLabsKey(String value) {
    final key = value.trim();
    return key.startsWith('sk_') && key.length > 12;
  }

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
    final elevenlabsKey = (await AIConfig.getElevenLabsKey()).trim();
    if (elevenlabsKey.isEmpty) {
      print('ElevenLabs API key not configured');
      return null;
    }
    if (_blockedCredential == elevenlabsKey) return null;
    if (!isStructurallyValidElevenLabsKey(elevenlabsKey)) {
      lastSpeechOk = false;
      lastSpeechError =
          'ElevenLabs credential is a key ID, not an API key (expected sk_…).';
      _blockedCredential = elevenlabsKey;
      print('⚠️ [TTS] Invalid ElevenLabs credential format; synthesis disabled');
      return null;
    }

    final selectedVoiceId = await AIConfig.getSelectedVoiceId();

    Future<Uint8List?> attempt(String voiceId) async {
      final response = await _dio.post(
        'https://api.elevenlabs.io/v1/text-to-speech/$voiceId',
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
      // His voice worked — he can honestly say he has one.
      lastSpeechOk = true;
      lastSpeechError = null;
      return Uint8List.fromList(response.data);
    }

    // ElevenLabs "Rachel" — a stock voice on every account. Only ever used if
    // Sadeq explicitly opts in; his custom voice is never silently replaced.
    const defaultVoice = '21m00Tcm4TlvDq8ikWAM';
    try {
      return await attempt(selectedVoiceId);
    } on DioException catch (e) {
      // Decode ElevenLabs' JSON error body (bytes) so we see the real reason.
      String body = '';
      try {
        final d = e.response?.data;
        if (d is List<int>) {
          body = utf8.decode(d, allowMalformed: true);
        } else if (d != null) {
          body = d.toString();
        }
      } catch (_) {}
      print('TTS error ${e.response?.statusCode}: $body');
      lastSpeechOk = false;
      lastSpeechError = '${e.response?.statusCode ?? 'network'}: '
          '${body.isEmpty ? e.message ?? 'unknown' : body}';
      if (e.response?.statusCode == 401 ||
          e.response?.statusCode == 403 ||
          body.contains('authentication_error') ||
          body.contains('invalid_api_key')) {
        _blockedCredential = elevenlabsKey;
        print('⚠️ [TTS] Credential rejected; suppressing retries until restart');
      }
      // Deliberately NOT falling back by default: his custom voice is his
      // identity, and speaking in a stranger's voice is worse than silence.
      if (allowStockFallbackVoice && selectedVoiceId != defaultVoice) {
        try {
          print('TTS: stock fallback voice explicitly enabled — using it.');
          // attempt() sets lastSpeechOk = true if this works.
          return await attempt(defaultVoice);
        } catch (e2) {
          print('TTS fallback failed: $e2');
          lastSpeechError = 'custom voice + stock fallback both failed ($body)';
        }
      }
      return null;
    } catch (e) {
      print('TTS error: $e');
      lastSpeechOk = false;
      lastSpeechError = e.toString();
      return null;
    }
  }
}
