// Secure Storage Service - Encrypted API key management using Android Keystore
//
// Keys are read from secure storage first; if empty, fall back to compile-time
// constants injected via --dart-define at build time (CI / GitHub Actions).
// This means a CI-built APK works without any manual key entry.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../secrets.dart';

// Compile-time defaults — sourced from lib/secrets.dart (gitignored).
// CI generates secrets.dart from GitHub secrets before building.
const _kBuiltInOpenAI     = kOpenAIKey;
const _kBuiltInElevenLabs = kElevenLabsKey;

/// Secure storage for API keys using device encryption
/// Keys are encrypted using Android Keystore (hardware-backed when available)
class SecureStorageService {
  // Singleton pattern
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();
  
  // Secure storage instance with Android-specific options
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true, // Use encrypted shared preferences
    ),
  );
  
  // Storage keys
  static const String _openaiKeyName = 'openai_api_key';
  static const String _elevenlabsKeyName = 'elevenlabs_api_key';
  static const String _googleKeyName = 'google_api_key';
  static const String _googleCseIdName = 'google_cse_id';
  static const String _anthropicKeyName = 'anthropic_api_key';

  // Cache keys in memory after first read (performance optimization)
  String? _cachedOpenAIKey;
  String? _cachedElevenLabsKey;
  String? _cachedGoogleKey;
  String? _cachedGoogleCseId;
  String? _cachedAnthropicKey;
  
  /// Initialize and check if keys exist
  Future<bool> hasKeys() async {
    try {
      final openaiKey = await getOpenAIKey();
      return openaiKey != null && openaiKey.isNotEmpty;
    } catch (e) {
      print('❌ Error checking for keys: $e');
      return false;
    }
  }
  
  /// Get OpenAI API Key (secure storage → built-in compile-time constant)
  Future<String?> getOpenAIKey() async {
    if (_cachedOpenAIKey != null) return _cachedOpenAIKey;
    try {
      final stored = await _storage.read(key: _openaiKeyName);
      _cachedOpenAIKey = (stored != null && stored.isNotEmpty)
          ? stored
          : (_kBuiltInOpenAI.isNotEmpty ? _kBuiltInOpenAI : null);
      return _cachedOpenAIKey;
    } catch (e) {
      print('❌ Error reading OpenAI key: $e');
      return _kBuiltInOpenAI.isNotEmpty ? _kBuiltInOpenAI : null;
    }
  }
  
  /// Set OpenAI API Key
  Future<void> setOpenAIKey(String key) async {
    try {
      await _storage.write(key: _openaiKeyName, value: key);
      _cachedOpenAIKey = key;
      print('✅ OpenAI key saved securely');
    } catch (e) {
      print('❌ Error saving OpenAI key: $e');
      rethrow;
    }
  }
  
  /// Get ElevenLabs API Key (secure storage → built-in compile-time constant)
  Future<String?> getElevenLabsKey() async {
    if (_cachedElevenLabsKey != null) return _cachedElevenLabsKey;
    try {
      final stored = await _storage.read(key: _elevenlabsKeyName);
      _cachedElevenLabsKey = (stored != null && stored.isNotEmpty)
          ? stored
          : (_kBuiltInElevenLabs.isNotEmpty ? _kBuiltInElevenLabs : null);
      return _cachedElevenLabsKey;
    } catch (e) {
      print('❌ Error reading ElevenLabs key: $e');
      return _kBuiltInElevenLabs.isNotEmpty ? _kBuiltInElevenLabs : null;
    }
  }
  
  /// Set ElevenLabs API Key
  Future<void> setElevenLabsKey(String key) async {
    try {
      await _storage.write(key: _elevenlabsKeyName, value: key);
      _cachedElevenLabsKey = key;
      print('✅ ElevenLabs key saved securely');
    } catch (e) {
      print('❌ Error saving ElevenLabs key: $e');
      rethrow;
    }
  }
  
  /// Get Google API Key
  Future<String?> getGoogleKey() async {
    if (_cachedGoogleKey != null) return _cachedGoogleKey;
    
    // Try compile-time constant first (from secrets.dart)
    const defineKey = kGoogleApiKey;
    if (defineKey.isNotEmpty) {
      _cachedGoogleKey = defineKey;
      print('✅ Google API Key loaded from secrets.dart');
      return _cachedGoogleKey;
    }
    
    // Fall back to secure storage
    try {
      _cachedGoogleKey = await _storage.read(key: _googleKeyName);
      return _cachedGoogleKey;
    } catch (e) {
      print('❌ Error reading Google key: $e');
      return null;
    }
  }
  
  /// Set Google API Key
  Future<void> setGoogleKey(String key) async {
    try {
      await _storage.write(key: _googleKeyName, value: key);
      _cachedGoogleKey = key;
      print('✅ Google key saved securely');
    } catch (e) {
      print('❌ Error saving Google key: $e');
      rethrow;
    }
  }
  
  /// Get Google CSE ID
  Future<String?> getGoogleCseId() async {
    if (_cachedGoogleCseId != null) return _cachedGoogleCseId;
    
    // Try compile-time constant first (from secrets.dart)
    const defineId = kGoogleCseId;
    if (defineId.isNotEmpty) {
      _cachedGoogleCseId = defineId;
      print('✅ Google CSE ID loaded from secrets.dart');
      return _cachedGoogleCseId;
    }
    
    // Fall back to secure storage
    try {
      _cachedGoogleCseId = await _storage.read(key: _googleCseIdName);
      return _cachedGoogleCseId;
    } catch (e) {
      print('❌ Error reading Google CSE ID: $e');
      return null;
    }
  }
  
  /// Set Google CSE ID
  Future<void> setGoogleCseId(String id) async {
    try {
      await _storage.write(key: _googleCseIdName, value: id);
      _cachedGoogleCseId = id;
      print('✅ Google CSE ID saved securely');
    } catch (e) {
      print('❌ Error saving Google CSE ID: $e');
      rethrow;
    }
  }
  
  /// Get Anthropic API Key
  Future<String?> getAnthropicKey() async {
    if (_cachedAnthropicKey != null) return _cachedAnthropicKey;
    try {
      _cachedAnthropicKey = await _storage.read(key: _anthropicKeyName);
      return _cachedAnthropicKey;
    } catch (e) {
      print('❌ Error reading Anthropic key: $e');
      return null;
    }
  }

  /// Set Anthropic API Key
  Future<void> setAnthropicKey(String key) async {
    try {
      await _storage.write(key: _anthropicKeyName, value: key);
      _cachedAnthropicKey = key;
      print('✅ Anthropic key saved securely');
    } catch (e) {
      print('❌ Error saving Anthropic key: $e');
      rethrow;
    }
  }

  /// Delete all stored keys (logout/reset)
  Future<void> deleteAllKeys() async {
    try {
      await _storage.deleteAll();
      _cachedOpenAIKey = null;
      _cachedElevenLabsKey = null;
      _cachedGoogleKey = null;
      _cachedGoogleCseId = null;
      _cachedAnthropicKey = null;
      print('✅ All keys deleted');
    } catch (e) {
      print('❌ Error deleting keys: $e');
      rethrow;
    }
  }
  
  /// Delete specific key
  Future<void> deleteKey(String keyType) async {
    try {
      String keyName;
      switch (keyType) {
        case 'openai':
          keyName = _openaiKeyName;
          _cachedOpenAIKey = null;
          break;
        case 'elevenlabs':
          keyName = _elevenlabsKeyName;
          _cachedElevenLabsKey = null;
          break;
        case 'google':
          keyName = _googleKeyName;
          _cachedGoogleKey = null;
          break;
        case 'google_cse':
          keyName = _googleCseIdName;
          _cachedGoogleCseId = null;
          break;
        default:
          throw Exception('Unknown key type: $keyType');
      }
      
      await _storage.delete(key: keyName);
      print('✅ $keyType key deleted');
    } catch (e) {
      print('❌ Error deleting $keyType key: $e');
      rethrow;
    }
  }
  
  /// Get all stored keys (for debugging - returns masked values)
  Future<Map<String, String>> getAllKeysMasked() async {
    final keys = <String, String>{};
    
    final openaiKey = await getOpenAIKey();
    if (openaiKey != null && openaiKey.isNotEmpty) {
      keys['OpenAI'] = _maskKey(openaiKey);
    }
    
    final elevenlabsKey = await getElevenLabsKey();
    if (elevenlabsKey != null && elevenlabsKey.isNotEmpty) {
      keys['ElevenLabs'] = _maskKey(elevenlabsKey);
    }
    
    final googleKey = await getGoogleKey();
    if (googleKey != null && googleKey.isNotEmpty) {
      keys['Google'] = _maskKey(googleKey);
    }
    
    final googleCseId = await getGoogleCseId();
    if (googleCseId != null && googleCseId.isNotEmpty) {
      keys['Google CSE'] = _maskKey(googleCseId);
    }
    
    return keys;
  }
  
  /// Mask API key for display (show first/last 4 chars)
  String _maskKey(String key) {
    if (key.length <= 8) return '****';
    return '${key.substring(0, 4)}...${key.substring(key.length - 4)}';
  }
  
  /// Check if a specific key exists
  Future<bool> hasKey(String keyType) async {
    try {
      String? value;
      switch (keyType) {
        case 'openai':
          value = await getOpenAIKey();
          break;
        case 'elevenlabs':
          value = await getElevenLabsKey();
          break;
        case 'google':
          value = await getGoogleKey();
          break;
        case 'google_cse':
          value = await getGoogleCseId();
          break;
        default:
          return false;
      }
      return value != null && value.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}
