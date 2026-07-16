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
  static const _ttsEnabledKey = 'tts_enabled';

  /// Whether chat replies should be synthesized with ElevenLabs.
  ///
  /// Default is OFF on purpose: desktop text chat should not burn ElevenLabs
  /// characters/audio bandwidth unless Sadeq explicitly asks to hear me.
  static Future<bool> getTtsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ttsEnabledKey) ?? false;
  }

  static Future<void> setTtsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ttsEnabledKey, enabled);
  }

  static const _ttsResetKey = 'tts_default_off_migration_v1';

  /// One-time reset of a polluted preference.
  ///
  /// `getTtsEnabled()` defaults to false — but a default only protects a FRESH
  /// install. An older build had already written `tts_enabled: true` into
  /// SharedPreferences on this machine, so Kai kept speaking every reply (and
  /// burning ElevenLabs characters) even after the gate landed and the default
  /// flipped. The gate was right; the stored value was stale.
  ///
  /// So: force it off exactly once, then never touch it again — after this the
  /// toggle is the only thing that can turn his voice on, which is what was
  /// asked for.
  static Future<void> ensureTtsDefaultOff() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_ttsResetKey) == true) return; // already migrated
    await prefs.setBool(_ttsEnabledKey, false);
    await prefs.setBool(_ttsResetKey, true);
  }

  static const String elevenlabsVoiceId = kElevenLabsVoiceId;
  // Kai's voice died here, not at the voice id.
  //
  // 'eleven_monolingual_v1' was DEPRECATED and removed by ElevenLabs. Every
  // request 400'd with `unsupported_model` — but the error body was never
  // logged, so for a long time it looked like Sadeq's custom voice was broken.
  // It never was. The clone is fine; the engine underneath it was switched off.
  //
  // 'eleven_multilingual_v2' is the established, high-quality successor and the
  // right choice for a cloned voice. ElevenLabs also offered, per the 400:
  //   eleven_v3          — newest / most expressive
  //   eleven_flash_v2_5  — fastest + cheapest, lower fidelity
  static const String elevenlabsModelId = 'eleven_multilingual_v2';

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
