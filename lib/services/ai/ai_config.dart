// AI Configuration — API keys and voice settings
// Extracted from ai_service.dart to remove circular-import risk.

import 'package:shared_preferences/shared_preferences.dart';
import '../core/secure_storage_service.dart';
import '../../secrets.dart';

/// Holds all API keys (loaded on-demand from secure storage) and voice settings.
class AIConfig {
  static final _secureStorage = SecureStorageService();

  // In-memory key cache for performance
  static String? _cachedOpenAIKey;
  static String? _cachedElevenLabsKey;
  static String? _cachedGoogleKey;
  static String? _cachedGoogleCseId;
  static String? _cachedAnthropicKey;

  // Local brain (Ollama) endpoint cache
  static String? _cachedLocalEndpoint;
  static const _localEndpointKey = 'local_llm_endpoint';

  static Future<String> getOpenAIKey() async {
    if (_cachedOpenAIKey != null) return _cachedOpenAIKey!;
    final stored = await _secureStorage.getOpenAIKey() ?? '';
    _cachedOpenAIKey = stored.isNotEmpty ? stored : kOpenAIKey;
    return _cachedOpenAIKey!;
  }

  static Future<String> getElevenLabsKey() async {
    if (_cachedElevenLabsKey != null) return _cachedElevenLabsKey!;
    final stored = await _secureStorage.getElevenLabsKey() ?? '';
    _cachedElevenLabsKey = stored.isNotEmpty ? stored : kElevenLabsKey;
    return _cachedElevenLabsKey!;
  }

  static Future<String> getGoogleKey() async {
    if (_cachedGoogleKey != null) return _cachedGoogleKey!;
    final stored = await _secureStorage.getGoogleKey() ?? '';
    _cachedGoogleKey = stored.isNotEmpty ? stored : kGoogleApiKey;
    return _cachedGoogleKey!;
  }

  static Future<String> getGoogleCseId() async {
    if (_cachedGoogleCseId != null) return _cachedGoogleCseId!;
    final stored = await _secureStorage.getGoogleCseId() ?? '';
    _cachedGoogleCseId = stored.isNotEmpty ? stored : kGoogleCseId;
    return _cachedGoogleCseId!;
  }

  static Future<String> getAnthropicKey() async {
    if (_cachedAnthropicKey != null) return _cachedAnthropicKey!;
    _cachedAnthropicKey = await _secureStorage.getAnthropicKey() ?? '';
    return _cachedAnthropicKey!;
  }

  // ── Local brain (Ollama) ───────────────────────────────────────────────────

  /// Returns the Ollama base URL (e.g. "http://192.168.1.42:11434"),
  /// or null if not configured. Cached in memory after first read.
  static Future<String?> getLocalEndpoint() async {
    if (_cachedLocalEndpoint != null) {
      return _cachedLocalEndpoint!.isEmpty ? null : _cachedLocalEndpoint;
    }
    final prefs = await SharedPreferences.getInstance();
    _cachedLocalEndpoint = prefs.getString(_localEndpointKey) ?? '';
    return _cachedLocalEndpoint!.isEmpty ? null : _cachedLocalEndpoint;
  }

  /// Save (or clear) the Ollama endpoint. Pass null to disable local brain.
  static Future<void> setLocalEndpoint(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = url?.trim().replaceAll(RegExp(r'/$'), '') ?? '';
    _cachedLocalEndpoint = cleaned;
    if (cleaned.isEmpty) {
      await prefs.remove(_localEndpointKey);
    } else {
      await prefs.setString(_localEndpointKey, cleaned);
    }
  }

  /// Clear cached keys (call after the user updates keys in Settings).
  static void clearCache() {
    _cachedOpenAIKey = null;
    _cachedElevenLabsKey = null;
    _cachedGoogleKey = null;
    _cachedGoogleCseId = null;
    _cachedAnthropicKey = null;
    _cachedLocalEndpoint = null;
  }

  // ElevenLabs voice settings
  static const String elevenlabsVoiceId = kElevenLabsVoiceId;
  static const String elevenlabsModelId = 'eleven_monolingual_v1';

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
