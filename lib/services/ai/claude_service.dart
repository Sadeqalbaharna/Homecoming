// ClaudeService
//
// A first-class "brain" backed by Anthropic's Messages API, sitting alongside
// the OpenAI path and the (currently dormant) local Ollama brain. Kai uses it
// for deep reasoning the framework was authored for — personality drift — and
// for coding jobs delegated from the main GPT tool loop.
//
// Contract (matches LocalLLMService): every call returns null on ANY failure —
// missing key, network error, API error, empty content — so callers can
// transparently fall back to OpenAI. Claude is never a hard dependency; if no
// Anthropic key is configured, the app behaves exactly as before.
//
// Models (June 2026): opus = deepest reasoning, sonnet = fast + strong (coding),
// haiku = cheapest. Override per call as needed.

library;

import 'dart:convert';
import 'package:dio/dio.dart';
import 'ai_config.dart';
import 'usage_tracking_service.dart';
import '../core/cortex_activity_bus.dart';

/// Result of a Claude completion.
class ClaudeResult {
  final String text;
  final int inputTokens;
  final int outputTokens;
  const ClaudeResult({
    required this.text,
    this.inputTokens = 0,
    this.outputTokens = 0,
  });
}

/// Claude failed, but in a way callers may want to surface instead of treating
/// as a normal fallback. Contemplate mode especially should not quietly print
/// "the Architect fell silent" when the real problem is an invalid key/model.
class ClaudeException implements Exception {
  final String message;
  const ClaudeException(this.message);

  @override
  String toString() => message;
}

class ClaudeService {
  static final ClaudeService _instance = ClaudeService._internal();
  factory ClaudeService() => _instance;
  ClaudeService._internal();

  final _dio = Dio();

  // ── Models ─────────────────────────────────────────────────────────────────
  static const String opus   = 'claude-opus-4-8';
  // Keep this as the model id we actually send to Anthropic. If Claude fails,
  // callers like contemplate now surface the real API error instead of hiding it
  // behind "the Architect fell silent".
  static const String sonnet = 'claude-sonnet-4-6';
  static const String haiku  = 'claude-haiku-4-5-20251001';

  static const String _endpoint = 'https://api.anthropic.com/v1/messages';
  static const String _version  = '2023-06-01';

  /// True when an Anthropic key is configured (so callers can decide whether to
  /// even attempt Claude before doing prep work).
  Future<bool> isAvailable() async =>
      (await AIConfig.getAnthropicKey()).isNotEmpty;

  /// Single-turn convenience wrapper.
  Future<ClaudeResult?> complete({
    required String prompt,
    String? system,
    String model = sonnet,
    int maxTokens = 1024,
    double? temperature,
    String operation = 'chat',
  }) {
    return completeMessages(
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      system: system,
      model: model,
      maxTokens: maxTokens,
      temperature: temperature,
      operation: operation,
    );
  }

  /// Multi-turn completion. [messages] is a list of
  /// {'role': 'user'|'assistant', 'content': '...'} maps (Anthropic format —
  /// the system prompt is passed separately, not as a message).
  Future<ClaudeResult?> completeMessages({
    required List<Map<String, String>> messages,
    String? system,
    String model = sonnet,
    int maxTokens = 1024,
    double? temperature,
    String operation = 'chat',
  }) async {
    final key = await AIConfig.getAnthropicKey();
    if (key.isEmpty) return null;

    // Light the right (Claude) hemisphere in the cortex viz.
    CortexActivityBus.instance.brain(CortexBrain.claude);

    try {
      final res = await _dio.post(
        _endpoint,
        options: Options(headers: {
          'x-api-key': key,
          'anthropic-version': _version,
          'content-type': 'application/json',
        }),
        data: {
          'model': model,
          'max_tokens': maxTokens,
          // Unlike OpenAI, Anthropic does NOT cache automatically — you must
          // mark a breakpoint or you pay full input price on every call, even
          // for a byte-identical system prompt. The block-array form with
          // cache_control caches everything up to and including the system
          // prompt (tools included). Reads cost ~10% of normal input price;
          // the one-time write costs ~125%. Any repeated caller wins.
          if (system != null && system.isNotEmpty)
            'system': [
              {
                'type': 'text',
                'text': system,
                'cache_control': {'type': 'ephemeral'},
              }
            ],
          if (temperature != null) 'temperature': temperature,
          'messages': messages,
        },
      );

      final data = res.data as Map<String, dynamic>;
      // Anthropic returns content as a list of blocks; concatenate the text ones.
      final blocks = (data['content'] as List?) ?? const [];
      final text = blocks
          .whereType<Map>()
          .where((b) => b['type'] == 'text')
          .map((b) => (b['text'] as String?) ?? '')
          .join('\n')
          .trim();

      final usage = data['usage'] as Map<String, dynamic>?;
      final inTok  = (usage?['input_tokens']  as num?)?.toInt() ?? 0;
      final outTok = (usage?['output_tokens'] as num?)?.toInt() ?? 0;
      final cacheRead =
          (usage?['cache_read_input_tokens'] as num?)?.toInt() ?? 0;
      final cacheWrite =
          (usage?['cache_creation_input_tokens'] as num?)?.toInt() ?? 0;
      _printCacheUsage(operation, usage);
      if (inTok > 0 || outTok > 0 || cacheRead > 0 || cacheWrite > 0) {
        UsageTrackingService.trackAnthropic(
          model: model,
          inputTokens: inTok,
          outputTokens: outTok,
          cacheReadTokens: cacheRead,
          cacheCreationTokens: cacheWrite,
          operation: operation,
        ).catchError((_) {});
      }

      if (text.isEmpty) return null;
      return ClaudeResult(text: text, inputTokens: inTok, outputTokens: outTok);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      final detail = body is Map && body['error'] is Map
          ? (body['error']['message'] ?? body['error']).toString()
          : (body?.toString() ?? e.message ?? e.toString());
      final msg = status == null
          ? 'Claude $operation failed: $detail'
          : 'Claude $operation failed ($status): $detail';
      // ignore: avoid_print
      print('WARN [ClaudeService] $msg');
      throw ClaudeException(msg);
    } catch (e) {
      // ignore: avoid_print
      print('WARN [ClaudeService] $operation failed: $e');
      throw ClaudeException('Claude $operation failed: $e');
    }
  }

  /// Agentic tool-use loop (Anthropic tools protocol). Gives Claude a set of
  /// [tools] and an [onTool] executor; loops — send → if Claude asks for a tool,
  /// run it and feed the result back → repeat — until Claude produces a final
  /// answer or [maxIterations] is hit. Read-only by convention in Phase 1: the
  /// caller decides which tools exist, so nothing here can mutate anything the
  /// executor won't. Returns the final text, or null on failure/no key.
  Future<String?> completeWithTools({
    required String userPrompt,
    String? system,
    required List<Map<String, dynamic>> tools,
    required Future<String> Function(String name, Map<String, dynamic> input) onTool,
    String model = sonnet,
    int maxTokens = 4096,
    int maxIterations = 14,
    String operation = 'engineer',
  }) async {
    final key = await AIConfig.getAnthropicKey();
    if (key.isEmpty) return null;

    // Light the Claude (right) hemisphere for the whole exploration.
    CortexActivityBus.instance.brain(CortexBrain.claude, ms: 6000);

    final messages = <Map<String, dynamic>>[
      {'role': 'user', 'content': userPrompt},
    ];

    try {
      for (var iter = 0; iter < maxIterations; iter++) {
        final res = await _dio.post(
          _endpoint,
          options: Options(headers: {
            'x-api-key': key,
            'anthropic-version': _version,
            'content-type': 'application/json',
          }),
          data: {
            'model': model,
            'max_tokens': maxTokens,
            // See completeMessages: Anthropic caching is opt-in per request.
            // In THIS loop it matters most of all — every iteration re-sends
            // the system prompt, the full tool manifest, AND every previous
            // round's tool results at full price. A 14-iteration engineer job
            // used to pay for the same prefix 14 times over.
            if (system != null && system.isNotEmpty)
              'system': [
                {
                  'type': 'text',
                  'text': system,
                  'cache_control': {'type': 'ephemeral'},
                }
              ],
            'tools': tools,
            'messages': messages,
          },
        );

        final data = res.data as Map<String, dynamic>;
        final usage = data['usage'] as Map<String, dynamic>?;
        final inTok = (usage?['input_tokens'] as num?)?.toInt() ?? 0;
        final outTok = (usage?['output_tokens'] as num?)?.toInt() ?? 0;
        final cacheRead =
            (usage?['cache_read_input_tokens'] as num?)?.toInt() ?? 0;
        final cacheWrite =
            (usage?['cache_creation_input_tokens'] as num?)?.toInt() ?? 0;
        _printCacheUsage('$operation iter$iter', usage);
        if (inTok > 0 || outTok > 0 || cacheRead > 0 || cacheWrite > 0) {
          UsageTrackingService.trackAnthropic(
                  model: model,
                  inputTokens: inTok,
                  outputTokens: outTok,
                  cacheReadTokens: cacheRead,
                  cacheCreationTokens: cacheWrite,
                  operation: operation)
              .catchError((_) {});
        }

        final content = (data['content'] as List?) ?? const [];
        final stop = data['stop_reason'];
        final toolUses = content
            .whereType<Map>()
            .where((b) => b['type'] == 'tool_use')
            .toList();

        if (stop == 'tool_use' && toolUses.isNotEmpty) {
          // Echo the assistant's turn (text + tool_use blocks) back verbatim…
          messages.add({'role': 'assistant', 'content': content});
          // …then run each requested tool and return the results.
          final results = <Map<String, dynamic>>[];
          for (final tu in toolUses) {
            final name = (tu['name'] ?? '').toString();
            final input = Map<String, dynamic>.from((tu['input'] as Map?) ?? {});
            String out;
            try {
              out = await onTool(name, input);
            } catch (e) {
              out = 'Tool "$name" error: $e';
            }
            results.add({
              'type': 'tool_result',
              'tool_use_id': tu['id'],
              'content': out,
            });
          }
          // Moving breakpoint: mark the newest tool_result so the ENTIRE
          // conversation so far (system + tools + all previous rounds) is a
          // cache read on the next iteration, and only this round's results
          // are new tokens. Strip older markers first — Anthropic allows at
          // most 4 breakpoints per request, and a stale one per round would
          // blow past that by iteration 4.
          _stripCacheMarkers(messages);
          results.last['cache_control'] = {'type': 'ephemeral'};
          messages.add({'role': 'user', 'content': results});
          continue; // loop again with the tool results in context
        }

        // Final answer — concatenate any text blocks.
        final text = content
            .whereType<Map>()
            .where((b) => b['type'] == 'text')
            .map((b) => (b['text'] as String?) ?? '')
            .join('\n')
            .trim();
        return text.isEmpty ? '(no answer produced)' : text;
      }
      return 'Reached the exploration limit before finishing — try a narrower question.';
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ [ClaudeService] tool loop ($operation) failed: $e');
      return null;
    }
  }

  /// Remove every cache_control marker from prior turns so the single moving
  /// breakpoint in completeWithTools never exceeds Anthropic's 4-marker limit.
  static void _stripCacheMarkers(List<Map<String, dynamic>> messages) {
    for (final m in messages) {
      final c = m['content'];
      if (c is List) {
        for (final b in c) {
          if (b is Map) b.remove('cache_control');
        }
      }
    }
  }

  /// Cache visibility — the same rule as the OpenAI path: if this prints 0 on
  /// a warm repeated call, the prefix is mutating and nothing else will say so.
  ///
  /// (trackAnthropic now takes the cache tiers as parameters and prices them
  /// correctly — this print is the per-call receipt, the tracker is the ledger.)
  static void _printCacheUsage(String operation, Map<String, dynamic>? usage) {
    if (usage == null) return;
    final read = (usage['cache_read_input_tokens'] as num?)?.toInt() ?? 0;
    final wrote = (usage['cache_creation_input_tokens'] as num?)?.toInt() ?? 0;
    if (read > 0 || wrote > 0) {
      // ignore: avoid_print
      print('💾 [Claude cache] $operation: read $read cached tokens, '
          'wrote $wrote new to cache');
    }
  }

  /// Pulls the first JSON object out of a Claude reply — tolerant of ```json
  /// fences and surrounding prose. Returns null if nothing parses.
  static Map<String, dynamic>? extractJson(String text) {
    var t = text.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
    final m = fence.firstMatch(t);
    if (m != null) t = m.group(1)!.trim();
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    try {
      return jsonDecode(t.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
