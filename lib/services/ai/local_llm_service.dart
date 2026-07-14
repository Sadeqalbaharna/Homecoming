// LocalLLMService
// Routes background brain work (extraction, consolidation, DMN) to a locally
// running Ollama instance — zero token cost for all housekeeping tasks.
//
// Auto-discovery: when called with no saved endpoint, scans the local WiFi
// subnet for port 11434, verifies it's Ollama, and caches the result. If the
// laptop goes to sleep and the endpoint goes stale, a background re-scan is
// triggered automatically so the next call succeeds.
//
// Architecture: every method returns null on ANY failure. Callers always fall
// back to OpenAI on null — local is completely transparent to the rest of the app.
//
// Qwen3 modes:
//   /no_think prefix → disables chain-of-thought. Use for JSON extraction.
//                       Clean, fast, no <think>…</think> noise.
//   (no prefix)      → enables light CoT. Use for DMN thought generation.

library;

import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'ai_config.dart';

class LocalLLMService {
  static final LocalLLMService _instance = LocalLLMService._internal();
  factory LocalLLMService() => _instance;
  LocalLLMService._internal();

  final _dio = Dio();

  /// Default model — must match what you have pulled in Ollama.
  static const defaultModel = 'qwen3:8b';

  /// In-memory cache of a discovered endpoint (survives between complete() calls).
  static String? _discoveredEndpoint;

  /// Guard against concurrent scans.
  static bool _isDiscovering = false;
  static Completer<String?>? _discoveryCompleter;

  // ── Public: inference ──────────────────────────────────────────────────────

  /// Run a chat completion on the local Ollama model.
  ///
  /// [think] — when false (default), prepends /no_think so Qwen3 skips
  /// chain-of-thought. Set true for DMN wandering where reasoning helps.
  ///
  /// Returns the content string, or null if local is unavailable.
  /// Callers must fall back to OpenAI on null.
  Future<String?> complete({
    required String system,
    required String user,
    int maxTokens = 500,
    bool jsonMode = false,
    bool think = false,
    String? model,
  }) async {
    // Resolve endpoint: saved > in-memory discovered
    String? endpoint = await AIConfig.getLocalEndpoint();
    endpoint ??= _discoveredEndpoint;
    if (endpoint == null || endpoint.isEmpty) return null;

    try {
      final prefix = think ? '' : '/no_think\n';
      final response = await _dio.post(
        '$endpoint/v1/chat/completions',
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 60),
        ),
        data: {
          'model': model ?? defaultModel,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user',   'content': '$prefix$user'},
          ],
          'max_tokens': maxTokens,
          'temperature': 0.3,
          'stream': false,
          if (jsonMode) 'response_format': {'type': 'json_object'},
        },
      );
      final content =
          (response.data['choices'] as List)[0]['message']['content'] as String?
              ?? '';
      final cleaned = _stripThinkBlock(content);
      if (cleaned.isEmpty) return null;
      print('🤖 [Local] Handled by Qwen (${model ?? defaultModel})');
      return cleaned;
    } on DioException catch (e) {
      final type = e.type;
      if (type == DioExceptionType.connectionError ||
          type == DioExceptionType.connectionTimeout) {
        // Laptop went to sleep or changed IP — kick off background re-discovery
        print('🤖 [Local] Endpoint unreachable — triggering background re-scan');
        _discoveredEndpoint = null;
        discoverOllama().catchError((_) {});
      } else {
        print('🤖 [Local] Error (${e.response?.statusCode}) — falling back: ${e.message}');
      }
      return null;
    } catch (e) {
      print('🤖 [Local] Unexpected error — falling back: $e');
      return null;
    }
  }

  // ── Public: discovery ──────────────────────────────────────────────────────

  /// Scan the local WiFi network for an Ollama instance.
  ///
  /// Flow:
  ///   1. Check in-memory cached endpoint — if still alive, return immediately.
  ///   2. Check saved endpoint from settings — if alive, cache & return.
  ///   3. Scan all 254 hosts on the local /24 subnet, port 11434.
  ///      First host that responds with Ollama models wins.
  ///
  /// Concurrent scans are deduplicated — callers share a single in-flight scan.
  /// Found endpoint is persisted to SharedPreferences.
  Future<String?> discoverOllama({
    void Function(String message)? onProgress,
  }) async {
    // 1. In-memory cache
    if (_discoveredEndpoint != null) {
      onProgress?.call('Checking cached endpoint…');
      final models = await listModels(_discoveredEndpoint!);
      if (models != null) {
        onProgress?.call('✓ Still connected at $_discoveredEndpoint');
        return _discoveredEndpoint;
      }
      print('🔍 [Discovery] Cached endpoint stale — rescanning');
      _discoveredEndpoint = null;
    }

    // 2. Saved endpoint
    final saved = await AIConfig.getLocalEndpoint();
    if (saved != null && saved.isNotEmpty) {
      onProgress?.call('Checking saved endpoint…');
      final models = await listModels(saved);
      if (models != null) {
        _discoveredEndpoint = saved;
        onProgress?.call('✓ Found at $saved');
        return saved;
      }
    }

    // 3. Subnet scan — deduplicate concurrent callers
    if (_isDiscovering) {
      onProgress?.call('Scan already in progress…');
      return _discoveryCompleter?.future;
    }
    _isDiscovering = true;
    _discoveryCompleter = Completer<String?>();

    try {
      onProgress?.call('Scanning local network for Ollama…');
      final result = await _scanLocalNetwork(onProgress: onProgress);
      if (result != null) {
        _discoveredEndpoint = result;
        await AIConfig.setLocalEndpoint(result);
        onProgress?.call('✓ Found at $result');
        print('🔍 [Discovery] Ollama discovered at $result — saved');
      } else {
        onProgress?.call('Not found — make sure Ollama is running on your laptop');
      }
      _discoveryCompleter!.complete(result);
      return result;
    } catch (e) {
      print('🔍 [Discovery] Scan error: $e');
      _discoveryCompleter!.complete(null);
      return null;
    } finally {
      _isDiscovering = false;
    }
  }

  /// Ping an Ollama server and return the list of available model names,
  /// or null if unreachable within 5 seconds.
  Future<List<String>?> listModels(String endpoint) async {
    try {
      final response = await _dio.get(
        '$endpoint/api/tags',
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final models = (response.data['models'] as List? ?? [])
          .map((m) => (m as Map)['name'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      return models;
    } catch (_) {
      return null;
    }
  }

  // ── Private: network scanning ──────────────────────────────────────────────

  Future<String?> _scanLocalNetwork({
    void Function(String)? onProgress,
  }) async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (!_isPrivateIP(ip)) continue;

          final parts = ip.split('.');
          if (parts.length != 4) continue;
          final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';

          onProgress?.call('Scanning $subnet.0/24…');
          final found = await _raceSubnet(subnet);
          if (found != null) return found;
        }
      }
    } catch (e) {
      print('🔍 [Discovery] _scanLocalNetwork error: $e');
    }
    return null;
  }

  /// Probe all 254 hosts on a /24 subnet concurrently.
  /// Returns the first endpoint that answers as Ollama, or null.
  Future<String?> _raceSubnet(String subnet) async {
    final completer = Completer<String?>();
    var pending = 254;

    void onResult(String? result) {
      if (result != null && !completer.isCompleted) {
        completer.complete(result);
        return;
      }
      pending--;
      if (pending <= 0 && !completer.isCompleted) {
        completer.complete(null);
      }
    }

    for (int i = 1; i <= 254; i++) {
      _probeHost('$subnet.$i')
          .then(onResult)
          .catchError((_) => onResult(null));
    }

    return completer.future;
  }

  /// TCP-probe a single host on port 11434.
  /// If the port is open, confirm via /api/tags that it's Ollama.
  /// Returns the full endpoint URL or null.
  Future<String?> _probeHost(String ip) async {
    try {
      // Fast TCP probe — ECONNREFUSED returns immediately on closed ports,
      // so only open ports consume the 300 ms timeout.
      final socket = await Socket.connect(
        ip,
        11434,
        timeout: const Duration(milliseconds: 300),
      );
      socket.destroy();

      // Port is open — verify it's Ollama
      final endpoint = 'http://$ip:11434';
      final models = await listModels(endpoint);
      if (models != null) {
        print('🔍 [Discovery] Ollama at $endpoint — models: ${models.join(", ")}');
        return endpoint;
      }
    } catch (_) {
      // Connection refused or timeout — normal for the 240+ hosts without Ollama
    }
    return null;
  }

  static bool _isPrivateIP(String ip) {
    if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true;
    final parts = ip.split('.');
    if (parts.length == 4 && parts[0] == '172') {
      final second = int.tryParse(parts[1]) ?? 0;
      return second >= 16 && second <= 31;
    }
    return false;
  }

  // ── Private: helpers ───────────────────────────────────────────────────────

  static String _stripThinkBlock(String text) {
    return text
        .replaceAll(
            RegExp(r'<think>[\s\S]*?</think>\s*', caseSensitive: false), '')
        .trim();
  }
}
