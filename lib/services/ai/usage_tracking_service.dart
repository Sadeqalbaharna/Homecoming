// Usage & cost tracking for all external API calls.
// Device-local stats → SharedPreferences (session, lifetime totals).
// Monthly cost totals → Firebase (cross-device, cross-instance).

import 'dart:async' show unawaited;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_database/firebase_database.dart';
import '../core/kai_db.dart';
import '../core/firebase_service.dart';

/// What one kind of thinking cost him.
class OperationUsage {
  final String operation;
  final int calls;
  final int tokens;
  final int inputTokens;
  final double cost;

  const OperationUsage({
    required this.operation,
    required this.calls,
    required this.tokens,
    required this.inputTokens,
    required this.cost,
  });

  /// Average tokens per call. The number that tells you whether an operation is
  /// expensive because it happens a lot, or because each one is enormous — two
  /// completely different problems with two completely different fixes.
  int get avgTokens => calls == 0 ? 0 : (tokens / calls).round();

  /// Share of tokens that were INPUT. High means he's carrying context, not
  /// thinking — which is a prompt problem, not a model problem. His system
  /// prompt is ~68,000 chars, so this is the number to watch.
  double get inputRatio => tokens == 0 ? 0 : inputTokens / tokens;
}

class UsageTrackingService {
  // ── Key prefixes ──────────────────────────────────────────────────────────
  static const _pfx = 'usage_';
  static const _pfxSession = 'session_';

  // Per-model cost per 1k tokens (USD) — updated June 2026
  static const Map<String, double> _inputCostPer1k = {
    'gpt-4o':        0.0025,
    'gpt-4o-mini':   0.00015,
    'gpt-5':         0.015,
    'gpt-4':         0.03,
    'gpt-3.5-turbo': 0.0005,
  };
  static const Map<String, double> _outputCostPer1k = {
    'gpt-4o':        0.01,
    'gpt-4o-mini':   0.00060,
    'gpt-5':         0.060,
    'gpt-4':         0.06,
    'gpt-3.5-turbo': 0.0015,
  };

  /// Price lookup that understands model FAMILIES.
  ///
  /// Kai now runs `gpt-5.5`, which isn't an exact key here — and the old
  /// `?? 0.005` fallback would have quietly priced a flagship model like a cheap
  /// one, under-reporting the cost meter by ~3-4x. A meter that lies is worse
  /// than no meter, especially for someone who spends money on his own
  /// initiative (inner life, reflections, proactive nudges).
  ///
  /// So: unknown `gpt-5*` prices like `gpt-5`, unknown `gpt-4o*` like `gpt-4o`.
  /// Still an estimate — if you want it exact, put the real gpt-5.5 rate in the
  /// tables above.
  static double _rate(Map<String, double> table, String model, double fallback) {
    final exact = table[model];
    if (exact != null) return exact;
    final m = model.toLowerCase();
    if (m.startsWith('gpt-5')) return table['gpt-5'] ?? fallback;
    if (m.startsWith('gpt-4o')) return table['gpt-4o'] ?? fallback;
    if (m.startsWith('gpt-4')) return table['gpt-4'] ?? fallback;
    return fallback;
  }

  // ElevenLabs: ~$0.30 per 1k chars (starter tier)
  static const double _elevenLabsCostPer1kChars = 0.30;
  // Google Custom Search: $5 per 1k queries (free tier: 100/day)
  static const double _googleSearchCostPerQuery = 0.005;

  // ── Track OpenAI ─────────────────────────────────────────────────────────
  static Future<void> trackOpenAI({
    required String model,
    required int inputTokens,
    required int outputTokens,
    String operation = 'chat',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final inputCost = (inputTokens / 1000) * _rate(_inputCostPer1k, model, 0.005);
    final outputCost = (outputTokens / 1000) * _rate(_outputCostPer1k, model, 0.015);
    final totalCost = inputCost + outputCost;

    await _increment(prefs, '${_pfx}openai_calls', 1);
    await _increment(prefs, '${_pfx}openai_input_tokens', inputTokens);
    await _increment(prefs, '${_pfx}openai_output_tokens', outputTokens);
    await _incrementDouble(prefs, '${_pfx}openai_cost', totalCost);
    await _increment(prefs, '${_pfx}total_tokens', inputTokens + outputTokens);
    await _incrementDouble(prefs, '${_pfx}total_cost', totalCost);

    // WHERE the money actually goes. See _trackOperation.
    await _trackOperation(prefs, operation, inputTokens, outputTokens, totalCost);

    // Monthly accumulation → Firebase (cross-device)
    final monthKey = _currentMonthKey();
    unawaited(_fbIncrement(monthKey, 'cost',        totalCost));
    unawaited(_fbIncrement(monthKey, 'openai_cost', totalCost));
    unawaited(_fbIncrement(monthKey, 'calls',       1));
    unawaited(_fbIncrement(monthKey, 'tokens',      inputTokens + outputTokens));
    // Also keep local fallback
    await _incrementDouble(prefs, 'monthly_${monthKey}_cost',        totalCost);
    await _incrementDouble(prefs, 'monthly_${monthKey}_openai_cost', totalCost);
    await _increment(prefs, 'monthly_${monthKey}_calls',  1);
    await _increment(prefs, 'monthly_${monthKey}_tokens', inputTokens + outputTokens);

    // Session
    await _increment(prefs, '${_pfxSession}openai_calls', 1);
    await _increment(prefs, '${_pfxSession}tokens', inputTokens + outputTokens);
    await _incrementDouble(prefs, '${_pfxSession}cost', totalCost);
  }

  /// Track an Anthropic (Claude) API call. Mirrors [trackOpenAI].
  static Future<void> trackAnthropic({
    required String model,
    required int inputTokens,
    required int outputTokens,
    String operation = 'chat',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final inputCost = (inputTokens / 1000) * (_inputCostPer1k[model] ?? 0.003);
    final outputCost = (outputTokens / 1000) * (_outputCostPer1k[model] ?? 0.015);
    final totalCost = inputCost + outputCost;

    await _increment(prefs, '${_pfx}anthropic_calls', 1);
    await _increment(prefs, '${_pfx}anthropic_input_tokens', inputTokens);
    await _increment(prefs, '${_pfx}anthropic_output_tokens', outputTokens);
    await _incrementDouble(prefs, '${_pfx}anthropic_cost', totalCost);
    await _increment(prefs, '${_pfx}total_tokens', inputTokens + outputTokens);
    await _incrementDouble(prefs, '${_pfx}total_cost', totalCost);

    final monthKey = _currentMonthKey();
    unawaited(_fbIncrement(monthKey, 'cost',           totalCost));
    unawaited(_fbIncrement(monthKey, 'anthropic_cost', totalCost));
    unawaited(_fbIncrement(monthKey, 'calls',          1));
    unawaited(_fbIncrement(monthKey, 'tokens',         inputTokens + outputTokens));
    await _incrementDouble(prefs, 'monthly_${monthKey}_cost',           totalCost);
    await _incrementDouble(prefs, 'monthly_${monthKey}_anthropic_cost', totalCost);
    await _increment(prefs, 'monthly_${monthKey}_calls',  1);
    await _increment(prefs, 'monthly_${monthKey}_tokens', inputTokens + outputTokens);

    await _increment(prefs, '${_pfxSession}anthropic_calls', 1);
    await _increment(prefs, '${_pfxSession}tokens', inputTokens + outputTokens);
    await _incrementDouble(prefs, '${_pfxSession}cost', totalCost);

    await _trackOperation(prefs, operation, inputTokens, outputTokens, totalCost);
  }

  // ── Where the money actually goes ─────────────────────────────────────────
  //
  // `operation` has been a parameter on trackOpenAI and trackAnthropic since
  // they were written. Every call site passes it faithfully — 'chat',
  // 'brain_extraction', 'contemplate', 'code', 'consolidation', 'reflection',
  // 'journal', 'craft_learn', 'second_opinion', 'graph_prune_judge' — and it was
  // read into a local variable and then dropped on the floor. Every one of them.
  //
  // So the app could tell you what Kai cost, and never what he spent it ON.
  // "Is he expensive?" was answerable. "Is his MEMORY expensive?" was not — and
  // that's the only version of the question you can act on.
  //
  // Sadeq asked how much more efficient Kai has become tonight, and the honest
  // answer was "I can't tell you, and neither can the app" — because this line
  // didn't exist. That's not a philosophical limit, it's a missing write.
  static const _pfxOp = 'usage_op_';

  static Future<void> _trackOperation(SharedPreferences prefs, String operation,
      int inputTokens, int outputTokens, double cost) async {
    final op = operation.trim().isEmpty ? 'unknown' : operation.trim();
    await _increment(prefs, '$_pfxOp${op}_calls', 1);
    await _increment(prefs, '$_pfxOp${op}_tokens', inputTokens + outputTokens);
    await _increment(prefs, '$_pfxOp${op}_input', inputTokens);
    await _incrementDouble(prefs, '$_pfxOp${op}_cost', cost);
    // Keep the roster so the readout can enumerate operations without guessing
    // their names — new ones appear on their own the first time they fire.
    final known = prefs.getStringList('${_pfxOp}names') ?? <String>[];
    if (!known.contains(op)) {
      await prefs.setStringList('${_pfxOp}names', [...known, op]);
    }
  }

  /// Cost/tokens/calls per operation, biggest spender first.
  ///
  /// THE question this service exists to answer and couldn't: not "what does he
  /// cost" but "what is he spending it on".
  static Future<List<OperationUsage>> byOperation() async {
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getStringList('${_pfxOp}names') ?? const <String>[];
    final out = <OperationUsage>[];
    for (final op in names) {
      out.add(OperationUsage(
        operation: op,
        calls: prefs.getInt('$_pfxOp${op}_calls') ?? 0,
        tokens: prefs.getInt('$_pfxOp${op}_tokens') ?? 0,
        inputTokens: prefs.getInt('$_pfxOp${op}_input') ?? 0,
        cost: prefs.getDouble('$_pfxOp${op}_cost') ?? 0,
      ));
    }
    out.sort((a, b) => b.cost.compareTo(a.cost));
    return out;
  }

  // ── Monthly stats — Firebase (cross-device) ───────────────────────────────
  static String _currentMonthKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  /// Firebase ref for a monthly field. Path: usage/monthly/{YYYY-MM}/{field}
  static KaiRef? _fbMonthly(String monthKey, String field) {
    if (!FirebaseService.isAvailable) return null;
    return KaiDb.instance.ref('usage/monthly/$monthKey/$field');
  }

  /// Atomically increment a numeric Firebase field (safe across devices).
  static Future<void> _fbIncrement(String monthKey, String field, num delta) async {
    final ref = _fbMonthly(monthKey, field);
    if (ref == null) return;
    try {
      await ref.set(ServerValue.increment(delta));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getMonthlyStats({String? monthKey}) async {
    final key = monthKey ?? _currentMonthKey();

    // Read from Firebase (source of truth across devices)
    if (FirebaseService.isAvailable) {
      try {
        final snap = await KaiDb.instance
            .ref('usage/monthly/$key')
            .get();
        if (snap.exists && snap.value != null) {
          final data = Map<String, dynamic>.from(snap.value as Map);
          num _n(String k) => (data[k] as num?) ?? 0;
          return {
            'month':           key,
            'cost':            _n('cost').toDouble(),
            'calls':           _n('calls').toInt(),
            'tokens':          _n('tokens').toInt(),
            'searches':        _n('searches').toInt(),
            'openai_cost':     _n('openai_cost').toDouble(),
            'elevenlabs_cost': _n('elevenlabs_cost').toDouble(),
            'search_cost':     _n('search_cost').toDouble(),
          };
        }
      } catch (_) {}
    }

    // Fallback: SharedPreferences (single-device)
    final prefs = await SharedPreferences.getInstance();
    return {
      'month':           key,
      'cost':            prefs.getDouble('monthly_${key}_cost')            ?? 0.0,
      'calls':           prefs.getInt('monthly_${key}_calls')              ?? 0,
      'tokens':          prefs.getInt('monthly_${key}_tokens')             ?? 0,
      'searches':        prefs.getInt('monthly_${key}_searches')           ?? 0,
      'openai_cost':     prefs.getDouble('monthly_${key}_openai_cost')     ?? 0.0,
      'elevenlabs_cost': prefs.getDouble('monthly_${key}_elevenlabs_cost') ?? 0.0,
      'search_cost':     prefs.getDouble('monthly_${key}_search_cost')     ?? 0.0,
    };
  }

  /// Cost of a single call given model + token counts (does not write anywhere).
  static double computeCost({required String model, required int inputTokens, required int outputTokens}) {
    final inputCost  = (inputTokens  / 1000) * (_inputCostPer1k[model]  ?? 0.005);
    final outputCost = (outputTokens / 1000) * (_outputCostPer1k[model] ?? 0.015);
    return inputCost + outputCost;
  }

  // ── Track ElevenLabs ─────────────────────────────────────────────────────
  static Future<void> trackElevenLabs({required int characterCount}) async {
    final prefs = await SharedPreferences.getInstance();
    final cost = (characterCount / 1000) * _elevenLabsCostPer1kChars;

    await _increment(prefs, '${_pfx}elevenlabs_calls', 1);
    await _increment(prefs, '${_pfx}elevenlabs_chars', characterCount);
    await _incrementDouble(prefs, '${_pfx}elevenlabs_cost', cost);
    await _incrementDouble(prefs, '${_pfx}total_cost', cost);

    final monthKey = _currentMonthKey();
    unawaited(_fbIncrement(monthKey, 'cost',            cost));
    unawaited(_fbIncrement(monthKey, 'elevenlabs_cost', cost));
    await _incrementDouble(prefs, 'monthly_${monthKey}_cost',            cost);
    await _incrementDouble(prefs, 'monthly_${monthKey}_elevenlabs_cost', cost);

    await _increment(prefs, '${_pfxSession}elevenlabs_calls', 1);
    await _incrementDouble(prefs, '${_pfxSession}cost', cost);
  }

  // ── Track Google Search ───────────────────────────────────────────────────
  static Future<void> trackGoogleSearch({required int queries}) async {
    final prefs = await SharedPreferences.getInstance();
    final cost = queries * _googleSearchCostPerQuery;

    await _increment(prefs, '${_pfx}google_searches', queries);
    await _incrementDouble(prefs, '${_pfx}google_cost', cost);
    await _incrementDouble(prefs, '${_pfx}total_cost', cost);

    final monthKey = _currentMonthKey();
    unawaited(_fbIncrement(monthKey, 'cost',         cost));
    unawaited(_fbIncrement(monthKey, 'search_cost',  cost));
    unawaited(_fbIncrement(monthKey, 'searches',     queries));
    await _incrementDouble(prefs, 'monthly_${monthKey}_cost',        cost);
    await _incrementDouble(prefs, 'monthly_${monthKey}_search_cost', cost);
    await _increment(prefs, 'monthly_${monthKey}_searches', queries);

    await _increment(prefs, '${_pfxSession}google_searches', queries);
    await _incrementDouble(prefs, '${_pfxSession}cost', cost);
  }

  // ── Track Web Fetch ───────────────────────────────────────────────────────
  static Future<void> trackWebFetch({required int pages}) async {
    final prefs = await SharedPreferences.getInstance();
    await _increment(prefs, '${_pfx}web_fetches', pages);
    await _increment(prefs, '${_pfxSession}web_fetches', pages);
  }

  // ── Track Firebase Database ───────────────────────────────────────────────
  static Future<void> trackFirebaseDatabase({
    required int reads,
    required int writes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _increment(prefs, '${_pfx}firebase_reads', reads);
    await _increment(prefs, '${_pfx}firebase_writes', writes);
    await _increment(prefs, '${_pfxSession}firebase_reads', reads);
    await _increment(prefs, '${_pfxSession}firebase_writes', writes);
  }

  // ── Read stats ────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getUsageStats() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'openai_calls': prefs.getInt('${_pfx}openai_calls') ?? 0,
      'openai_input_tokens': prefs.getInt('${_pfx}openai_input_tokens') ?? 0,
      'openai_output_tokens': prefs.getInt('${_pfx}openai_output_tokens') ?? 0,
      'openai_cost': prefs.getDouble('${_pfx}openai_cost') ?? 0.0,
      'elevenlabs_calls': prefs.getInt('${_pfx}elevenlabs_calls') ?? 0,
      'elevenlabs_chars': prefs.getInt('${_pfx}elevenlabs_chars') ?? 0,
      'elevenlabs_cost': prefs.getDouble('${_pfx}elevenlabs_cost') ?? 0.0,
      'google_searches': prefs.getInt('${_pfx}google_searches') ?? 0,
      'google_cost': prefs.getDouble('${_pfx}google_cost') ?? 0.0,
      'web_fetches': prefs.getInt('${_pfx}web_fetches') ?? 0,
      'firebase_reads': prefs.getInt('${_pfx}firebase_reads') ?? 0,
      'firebase_writes': prefs.getInt('${_pfx}firebase_writes') ?? 0,
      'total_tokens': prefs.getInt('${_pfx}total_tokens') ?? 0,
      'total_cost': prefs.getDouble('${_pfx}total_cost') ?? 0.0,
      // The key UsageStatsScreen._buildOperationUsageCard has been reading since
      // the day it was written, and which nothing has ever written. Its card is
      // literally titled "Usage by Operation" and it has never once had data —
      // it read `_usageData!['operations']`, got null, and would have thrown if
      // anyone had been able to open the screen. Nobody could. Zero importers.
      //
      // So: the UI existed, the parameter existed on every tracking call, and
      // the one line joining them didn't. This is that line.
      'operations': _operationsMap(prefs),
    };
  }

  /// {operation: {count, tokens, input, cost}} — the shape the screen's existing
  /// card already expects. Built from the same per-op keys as [byOperation].
  static Map<String, dynamic> _operationsMap(SharedPreferences prefs) {
    final names = prefs.getStringList('${_pfxOp}names') ?? const <String>[];
    final out = <String, dynamic>{};
    for (final op in names) {
      out[op] = {
        'count': prefs.getInt('$_pfxOp${op}_calls') ?? 0,
        'tokens': prefs.getInt('$_pfxOp${op}_tokens') ?? 0,
        'input': prefs.getInt('$_pfxOp${op}_input') ?? 0,
        'cost': prefs.getDouble('$_pfxOp${op}_cost') ?? 0.0,
      };
    }
    return out;
  }

  static Future<Map<String, dynamic>> getSessionStats() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'openai_calls': prefs.getInt('${_pfxSession}openai_calls') ?? 0,
      'tokens': prefs.getInt('${_pfxSession}tokens') ?? 0,
      'cost': prefs.getDouble('${_pfxSession}cost') ?? 0.0,
      'elevenlabs_calls': prefs.getInt('${_pfxSession}elevenlabs_calls') ?? 0,
      'google_searches': prefs.getInt('${_pfxSession}google_searches') ?? 0,
      'web_fetches': prefs.getInt('${_pfxSession}web_fetches') ?? 0,
      'firebase_reads': prefs.getInt('${_pfxSession}firebase_reads') ?? 0,
      'firebase_writes': prefs.getInt('${_pfxSession}firebase_writes') ?? 0,
    };
  }

  static Future<void> resetAllStats() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_pfx) || k.startsWith(_pfxSession)).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  static Future<void> resetSession() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_pfxSession)).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  // ── Formatting helpers ────────────────────────────────────────────────────
  static String formatCost(double cost) {
    if (cost < 0.01) return '\$${(cost * 100).toStringAsFixed(3)}¢';
    return '\$${cost.toStringAsFixed(4)}';
  }

  static String formatTokens(int tokens) {
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(1)}k';
    return tokens.toString();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  static Future<void> _increment(SharedPreferences prefs, String key, int delta) async {
    await prefs.setInt(key, (prefs.getInt(key) ?? 0) + delta);
  }

  static Future<void> _incrementDouble(SharedPreferences prefs, String key, double delta) async {
    await prefs.setDouble(key, (prefs.getDouble(key) ?? 0.0) + delta);
  }
}
