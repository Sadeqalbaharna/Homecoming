// AI Configuration — API keys and voice settings
// Extracted from ai_service.dart to remove circular-import risk.

import 'package:shared_preferences/shared_preferences.dart';
import '../core/secure_storage_service.dart';

/// Holds all API keys (loaded on-demand from secure storage) and voice settings.
class AIConfig {
  static final _secureStorage = SecureStorageService();

  // In-memory key cache for performance
  static String? _cachedOpenAIKey;
  static String? _cachedElevenLabsKey;
  static String? _cachedGoogleKey;
  static String? _cachedGoogleCseId;
  static String? _cachedAnthropicKey;

  static Future<String> getOpenAIKey() async {
    if (_cachedOpenAIKey != null) return _cachedOpenAIKey!;
    _cachedOpenAIKey = await _secureStorage.getOpenAIKey() ?? '';
    return _cachedOpenAIKey!;
  }

  static Future<String> getElevenLabsKey() async {
    if (_cachedElevenLabsKey != null) return _cachedElevenLabsKey!;
    _cachedElevenLabsKey = await _secureStorage.getElevenLabsKey() ?? '';
    return _cachedElevenLabsKey!;
  }

  static Future<String> getGoogleKey() async {
    if (_cachedGoogleKey != null) return _cachedGoogleKey!;
    _cachedGoogleKey = await _secureStorage.getGoogleKey() ?? '';
    return _cachedGoogleKey!;
  }

  static Future<String> getGoogleCseId() async {
    if (_cachedGoogleCseId != null) return _cachedGoogleCseId!;
    _cachedGoogleCseId = await _secureStorage.getGoogleCseId() ?? '';
    return _cachedGoogleCseId!;
  }

  static Future<String> getAnthropicKey() async {
    if (_cachedAnthropicKey != null) return _cachedAnthropicKey!;
    _cachedAnthropicKey = await _secureStorage.getAnthropicKey() ?? '';
    return _cachedAnthropicKey!;
  }

  /// Clear cached keys (call after the user updates keys in Settings).
  static void clearCache() {
    _cachedOpenAIKey = null;
    _cachedElevenLabsKey = null;
    _cachedGoogleKey = null;
    _cachedGoogleCseId = null;
    _cachedAnthropicKey = null;
  }

  // ElevenLabs voice settings
  static const String elevenlabsVoiceId = String.fromEnvironment(
      'ELEVENLABS_VOICE_ID',
      defaultValue: 'rjyk3ukVFAi8OdkRXxK2');
  static const String elevenlabsModelId = String.fromEnvironment(
      'ELEVENLABS_MODEL_ID',
      defaultValue: 'eleven_monolingual_v1');

  static const Map<String, Map<String, String>> availableVoices = {
    'kai_default': {
      'id': 'rjyk3ukVFAi8OdkRXxK2',
      'name': 'Kai (Default)',
      'description': 'Warm, friendly, conversational',
    },
    'kai_alt': {
      'id': 'Ke5IEaBOPxAcw6fm0mO6',
      'name': 'Kai (Alternative)',
      'description': 'Mature, expressive, engaging',
    },
  };

  static Future<String> getSelectedVoiceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_voice_id') ?? elevenlabsVoiceId;
  }

  static Future<void> setSelectedVoiceId(String voiceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_voice_id', voiceId);
  }
}
