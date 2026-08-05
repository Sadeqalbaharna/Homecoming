// replay.dart — arithmetic over the corpus, instead of adjectives.
//
// ── The finding this answers ─────────────────────────────────────────────────
//
// "You're not missing telemetry, you're missing arithmetic."
//
// Every number in the 2026-07-16 scorecard — memory formation, retrieval hit
// rate, overclaim rate, wasted tool calls, setup-to-GPT-send time — was already
// being printed by BrainDebugService on every single turn. Nobody added them up,
// because the traces lived in a RAM list of ten that died on quit. Now they
// persist (TraceStoreService), so this is the part that reads them.
//
// ── Design: pure over decoded rows ───────────────────────────────────────────
//
// Every function here takes `List<Map<String, dynamic>>` and returns a value.
// No IO, no Flutter, no path_provider. That means the analysis is testable with
// synthetic rows — which matters, because the whole point of this file is to
// stop me from making confident claims that turn out to be misread output.
//
// I have earned that constraint. On the night this was written I ran
// `dart analyze`, grepped for `error •` when the format is `error - `, got zero
// matches, and announced "Zero errors, everything compiles." There were 250.
//
// ── n is small forever ───────────────────────────────────────────────────────
//
// One person, a few dozen turns a day. There will never be statistics here. So
// these are counts and ratios over a CENSUS, reported with the denominator
// attached, and never a percentage without an n beside it. A rate of "100%" that
// means two out of two should look like two out of two.
library;

// ── Metrics ─────────────────────────────────────────────────────────────────

class Scorecard {
  final int turns;
  final int memoriesFormed;
  final int retrievalsWithSomethingUsable;
  final int retrievalsAttempted;
  final int graphConsulted;
  final int routedTurns;
  final int highConfidenceRoutes;
  final int toolCallsRecorded;
  final int successfulToolCalls;
  final int failedToolCalls;
  final int recoveredReplies;
  final int postProcessErrors;
  final int jobsClosed;
  final int overclaims;
  final int jobsClosedWithProof;
  final int wastedToolCalls;
  final int totalToolCalls;
  final int turnsWithCost;
  final int totalInputTokens;
  final int totalOutputTokens;
  final double totalCostUsd;
  final int turnsWithMood;
  final int totalMoodEnergy;
  final int totalMoodFocus;
  final int confidenceDips;
  final int playfulnessSpikes;
  /// Actually measures prompt setup time: startTime -> "Sending to GPT".
  /// It is not real first-token latency until traces record token arrival.
  final List<int> timeToGptSendMs;

  const Scorecard({
    required this.turns,
    required this.memoriesFormed,
    required this.retrievalsWithSomethingUsable,
    required this.retrievalsAttempted,
    required this.graphConsulted,
    required this.routedTurns,
    required this.highConfidenceRoutes,
    required this.toolCallsRecorded,
    required this.successfulToolCalls,
    required this.failedToolCalls,
    required this.recoveredReplies,
    required this.postProcessErrors,
    required this.jobsClosed,
    required this.overclaims,
    required this.jobsClosedWithProof,
    required this.wastedToolCalls,
    required this.totalToolCalls,
    required this.turnsWithCost,
    required this.totalInputTokens,
    required this.totalOutputTokens,
    required this.totalCostUsd,
    required this.turnsWithMood,
    required this.totalMoodEnergy,
    required this.totalMoodFocus,
    required this.confidenceDips,
    required this.playfulnessSpikes,
    required List<int> timeToFirstTokenMs,
  }) : timeToGptSendMs = timeToFirstTokenMs;

  /// Back-compat shim for older tests/callers. Prefer [timeToGptSendMs].
  List<int> get timeToFirstTokenMs => timeToGptSendMs;

  int get medianTimeToGptSend {
    if (timeToGptSendMs.isEmpty) return 0;
    final s = [...timeToGptSendMs]..sort();
    return s[s.length ~/ 2];
  }

  /// Back-compat shim. This is setup-to-GPT-send, not true first token latency.
  int get medianTimeToFirstToken => medianTimeToGptSend;

  int get totalTokens => totalInputTokens + totalOutputTokens;

  double get averageCostUsd => turnsWithCost == 0 ? 0 : totalCostUsd / turnsWithCost;

  int get averageTokens => turnsWithCost == 0 ? 0 : (totalTokens / turnsWithCost).round();

  int get averageMoodEnergy =>
      turnsWithMood == 0 ? 0 : (totalMoodEnergy / turnsWithMood).round();

  int get averageMoodFocus =>
      turnsWithMood == 0 ? 0 : (totalMoodFocus / turnsWithMood).round();

  /// Always "k of n". Never a bare percentage — 100% that means 2/2 should look
  /// like 2/2, or it will get quoted at somebody as though it meant something.
  static String ratio(int k, int n) => n == 0 ? '— (no data)' : '$k of $n';

  String report() {
    final b = StringBuffer('── KAI SCORECARD ──  $turns turns\n');
    b.writeln('memory formed              ${ratio(memoriesFormed, turns)}');
    b.writeln('retrieval found something  '
        '${ratio(retrievalsWithSomethingUsable, retrievalsAttempted)}');
    b.writeln('graph consulted            ${ratio(graphConsulted, turns)}');
    b.writeln('route selected             ${ratio(routedTurns, turns)}');
    b.writeln('  …high confidence         ${ratio(highConfidenceRoutes, routedTurns)}');
    b.writeln('tool outcomes recorded     ${ratio(toolCallsRecorded, totalToolCalls)}');
    b.writeln('  …successful              ${ratio(successfulToolCalls, toolCallsRecorded)}');
    b.writeln('  …failed/blocked          ${ratio(failedToolCalls, toolCallsRecorded)}');
    b.writeln('recovered replies          ${ratio(recoveredReplies, turns)}');
    b.writeln('post-process errors        $postProcessErrors');
    b.writeln('jobs closed                $jobsClosed');
    b.writeln('  …overclaimed             ${ratio(overclaims, jobsClosed)}');
    b.writeln('  …with real proof         ${ratio(jobsClosedWithProof, jobsClosed)}');
    b.writeln('wasted tool calls          ${ratio(wastedToolCalls, totalToolCalls)}');
    b.writeln('cost tracked               ${ratio(turnsWithCost, turns)}');
    b.writeln('  …total                   \$${totalCostUsd.toStringAsFixed(6)}');
    b.writeln('  …avg / costed turn       \$${averageCostUsd.toStringAsFixed(6)}');
    b.writeln('  …avg tokens              $averageTokens');
    b.writeln('mood tracked               ${ratio(turnsWithMood, turns)}');
    b.writeln('  …avg energy              $averageMoodEnergy');
    b.writeln('  …avg focus               $averageMoodFocus');
    b.writeln('  …confidence dips         $confidenceDips');
    b.writeln('  …playfulness spikes      $playfulnessSpikes');
    b.writeln('median time to GPT send    ${medianTimeToGptSend}ms');
    return b.toString();
  }
}

class EfficiencySlice {
  final String label;
  final int turns;
  final int costedTurns;
  final int manifestTurns;
  final int latencyTurns;
  final int toolTrimTurns;
  final int promptComponentTurns;
  final int totalInputTokens;
  final int totalOutputTokens;
  final int totalTokens;
  final int totalSchemaTokens;
  final int totalToolTrimTokensSaved;
  final int totalToolTrimCompactedResults;
  final int totalToolTrimHardCappedResults;
  final double totalCostUsd;
  final Map<String, int> promptComponentChars;
  final int nonSystemInputTurns;
  final Map<String, int> nonSystemInputChars;
  /// Actually measures prompt setup time: startTime -> "Sending to GPT".
  /// It is not real first-token latency until traces record token arrival.
  final List<int> timeToGptSendMs;

  const EfficiencySlice({
    required this.label,
    required this.turns,
    required this.costedTurns,
    required this.manifestTurns,
    required this.latencyTurns,
    required this.toolTrimTurns,
    required this.promptComponentTurns,
    required this.totalInputTokens,
    required this.totalOutputTokens,
    required this.totalTokens,
    required this.totalSchemaTokens,
    required this.totalToolTrimTokensSaved,
    required this.totalToolTrimCompactedResults,
    required this.totalToolTrimHardCappedResults,
    required this.totalCostUsd,
    required this.promptComponentChars,
    required this.nonSystemInputTurns,
    required this.nonSystemInputChars,
    required List<int> timeToFirstTokenMs,
  }) : timeToGptSendMs = timeToFirstTokenMs;

  int get averageInputTokens =>
      costedTurns == 0 ? 0 : (totalInputTokens / costedTurns).round();

  int get averageOutputTokens =>
      costedTurns == 0 ? 0 : (totalOutputTokens / costedTurns).round();

  int get averageTokens => costedTurns == 0 ? 0 : (totalTokens / costedTurns).round();

  int get averageSchemaTokens =>
      manifestTurns == 0 ? 0 : (totalSchemaTokens / manifestTurns).round();

  int get inputTokenSharePercent =>
      totalTokens == 0 ? 0 : (totalInputTokens * 100 / totalTokens).round();

  int get outputTokenSharePercent =>
      totalTokens == 0 ? 0 : (totalOutputTokens * 100 / totalTokens).round();

  int get schemaShareOfInputPercent =>
      totalInputTokens == 0 ? 0 : (totalSchemaTokens * 100 / totalInputTokens).round();

  int get averageToolTrimTokensSaved => toolTrimTurns == 0
      ? 0
      : (totalToolTrimTokensSaved / toolTrimTurns).round();

  /// Back-compat shim for older tests/callers. Prefer [timeToGptSendMs].
  List<int> get timeToFirstTokenMs => timeToGptSendMs;

  int get averageTimeToGptSendMs => latencyTurns == 0
      ? 0
      : (timeToGptSendMs.reduce((a, b) => a + b) / latencyTurns).round();

  /// Back-compat shim. This is setup-to-GPT-send, not true first token latency.
  int get averageTimeToFirstTokenMs => averageTimeToGptSendMs;

  double get averageCostUsd => costedTurns == 0 ? 0 : totalCostUsd / costedTurns;

  List<MapEntry<String, int>> get topPromptComponents {
    final entries = promptComponentChars.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  int averagePromptComponentChars(String name) => promptComponentTurns == 0
      ? 0
      : ((promptComponentChars[name] ?? 0) / promptComponentTurns).round();

  List<MapEntry<String, int>> get topNonSystemInputs {
    final entries = nonSystemInputChars.entries
        .where((entry) => entry.key != 'messageCount')
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  int averageNonSystemInputChars(String name) => nonSystemInputTurns == 0
      ? 0
      : ((nonSystemInputChars[name] ?? 0) / nonSystemInputTurns).round();
}

class EfficiencySummary {
  final int window;
  final EfficiencySlice previous;
  final EfficiencySlice recent;
  final Map<String, EfficiencySlice> previousByRoute;
  final Map<String, EfficiencySlice> recentByRoute;

  const EfficiencySummary({
    required this.window,
    required this.previous,
    required this.recent,
    required this.previousByRoute,
    required this.recentByRoute,
  });

  double? get tokenReduction =>
      _reduction(previous.averageTokens, recent.averageTokens);

  double? get schemaReduction =>
      _reduction(previous.averageSchemaTokens, recent.averageSchemaTokens);

  double? get latencyReduction => _reduction(
        previous.averageTimeToGptSendMs,
        recent.averageTimeToGptSendMs,
      );

  double? get costReduction =>
      _reduction(previous.averageCostUsd, recent.averageCostUsd);

  String report() {
    final b = StringBuffer('── KAI EFFICIENCY ── last $window vs previous $window turns\n');
    b.writeln('tokens/turn        ${_delta(tokenReduction)}  '
        '${previous.averageTokens} → ${recent.averageTokens}');
    b.writeln('schema tokens      ${_delta(schemaReduction)}  '
        '${previous.averageSchemaTokens} → ${recent.averageSchemaTokens}');
    b.writeln('recent token mix   '
        '${recent.averageInputTokens} in / ${recent.averageOutputTokens} out; '
        'schema ${recent.schemaShareOfInputPercent}% of input');
    b.writeln('tool-loop saved    '
        '${recent.averageToolTrimTokensSaved} tok/trimmed turn  '
        '(${recent.totalToolTrimCompactedResults} compacted, '
        '${recent.totalToolTrimHardCappedResults} capped)');
    if (recent.promptComponentTurns > 0) {
      b.writeln('prompt slabs       avg chars/turn over ${recent.promptComponentTurns} traced turn(s)');
      for (final entry in recent.topPromptComponents.take(12)) {
        final avgChars = recent.averagePromptComponentChars(entry.key);
        final approxTokens = (avgChars / 4).round();
        b.writeln('  • ${entry.key}: $avgChars chars (~$approxTokens tok)');
      }
    } else {
      b.writeln('prompt slabs       not tracked in this window');
    }
    if (recent.nonSystemInputTurns > 0) {
      b.writeln('non-system input   avg chars/call over ${recent.nonSystemInputTurns} measured call(s)');
      for (final entry in recent.topNonSystemInputs.take(7)) {
        final avgChars = recent.averageNonSystemInputChars(entry.key);
        final approxTokens = (avgChars / 4).round();
        b.writeln('  • ${entry.key}: $avgChars chars (~$approxTokens tok)');
      }
    } else {
      b.writeln('non-system input   not tracked in this window');
    }
    b.writeln('GPT-send lag       ${_delta(latencyReduction)}  '
        '${previous.averageTimeToGptSendMs}ms → ${recent.averageTimeToGptSendMs}ms');
    b.writeln('cost/turn          ${_delta(costReduction)}  '
        '\$${previous.averageCostUsd.toStringAsFixed(6)} → '
        '\$${recent.averageCostUsd.toStringAsFixed(6)}');
    if (recentByRoute.isNotEmpty) {
      b.writeln('recent routes');
      for (final entry in recentByRoute.entries) {
        final s = entry.value;
        b.writeln('  • ${entry.key}: ${s.turns} turns, '
            '${s.averageTokens} tok, ${s.averageSchemaTokens} schema, '
            '${s.averageTimeToGptSendMs}ms to GPT');
      }
    }
    return b.toString();
  }
}

// ── Row helpers. The trace shape is BrainDebugTrace.toJson(). ────────────────
// ── Row helpers. The trace shape is BrainDebugTrace.toJson(). ────────────────

List<Map<String, dynamic>> _steps(Map<String, dynamic> row) {
  final s = row['steps'];
  if (s is! List) return const [];
  return s.whereType<Map<String, dynamic>>().toList();
}

bool _anyStep(Map<String, dynamic> row, bool Function(Map<String, dynamic>) f) =>
    _steps(row).any(f);

String _desc(Map<String, dynamic> step) =>
    (step['description'] as String?)?.toLowerCase() ?? '';

/// Time from the first step to the step where GPT was actually called.
///
/// This is the number that went 12.1s -> 7.06s when the setup phase was
/// parallelised. It is measured, not asserted, because the last time it was
/// asserted the claim was "~4.7s" and the truth was 8.7s.
int? timeToGptSend(Map<String, dynamic> row) {
  final steps = _steps(row);
  if (steps.isEmpty) return null;
  final start = DateTime.tryParse(row['startTime'] as String? ?? '');
  if (start == null) return null;
  for (final s in steps) {
    if (_desc(s).contains('sending to gpt')) {
      final t = DateTime.tryParse(s['timestamp'] as String? ?? '');
      if (t != null) return t.difference(start).inMilliseconds;
    }
  }
  return null;
}

/// Back-compat shim. This is setup-to-GPT-send, not true first token latency.
int? timeToFirstToken(Map<String, dynamic> row) => timeToGptSend(row);

/// Did this turn actually lay down a memory?
///
/// Baseline on 2026-07-16: 0 of 5. Every trace ended
/// "🧠 [Brain] Skipped low-salience exchange (neutral, intensity N)" because
/// salience was gated on emotion alone and a night of building things together
/// scored neutral/1.
bool formedMemory(Map<String, dynamic> row) =>
    _anyStep(row, (s) => _desc(s).contains('keeping (')) ||
    (!_anyStep(row, (s) => _desc(s).contains('skipped')) &&
        _anyStep(row, (s) => _desc(s).contains('extract')));

/// Did retrieval clear the 0.28 threshold and hand him anything?
/// Baseline: 2 of 5. Three turns he answered as a charming stranger.
bool retrievalUsable(Map<String, dynamic> row) => _anyStep(row, (s) {
      final d = s['data'];
      if (d is! Map) return false;
      final used = d['used'];
      return used is num && used > 0;
    });

bool retrievalAttempted(Map<String, dynamic> row) =>
    _anyStep(row, (s) => _desc(s).contains('memory'));

/// Did the knowledge graph path actually run?
///
/// This used to be identical to [retrievalUsable] because graph activation was
/// downstream of transcript retrieval clearing 0.28. That coupling was the
/// bug: Kai could have useful graph knowledge and never ask it unless vector
/// recall found a usable transcript fragment first.
///
/// AIService now logs an explicit step when graph activation runs directly from
/// Sadeq's message. Measure that event, not the old proxy, or replay will keep
/// reporting Phase 3 as absent even after the app is doing the right thing.
bool graphConsulted(Map<String, dynamic> row) =>
    _anyStep(row, (s) => _desc(s).contains('graph consulted directly'));

bool routed(Map<String, dynamic> row) =>
    (row['route'] as String? ?? '').trim().isNotEmpty;

bool highConfidenceRoute(Map<String, dynamic> row) {
  final confidence = row['routeConfidence'];
  return confidence is num && confidence >= 0.75;
}

num _numField(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

int promptInputTokens(Map<String, dynamic> row) =>
    _numField(row, 'promptInputTokens').round();

int promptOutputTokens(Map<String, dynamic> row) =>
    _numField(row, 'promptOutputTokens').round();

double promptCostUsd(Map<String, dynamic> row) =>
    _numField(row, 'promptCostUsd').toDouble();

int manifestApproxTokens(Map<String, dynamic> row) =>
    _numField(row, 'manifestApproxTokens').round();

int manifestSchemaChars(Map<String, dynamic> row) =>
    _numField(row, 'manifestSchemaChars').round();

int toolTrimApproxTokensSaved(Map<String, dynamic> row) =>
    _numField(row, 'toolTrimApproxTokensSaved').round();

int assistantToolCallArgApproxTokensSaved(Map<String, dynamic> row) =>
    _numField(row, 'assistantToolCallArgApproxTokensSaved').round();

int toolTrimCompactedResults(Map<String, dynamic> row) =>
    _numField(row, 'toolTrimCompactedResults').round();

int toolTrimHardCappedResults(Map<String, dynamic> row) =>
    _numField(row, 'toolTrimHardCappedResults').round();

Map<String, int> promptComponentChars(Map<String, dynamic> row) {
  final raw = row['promptComponentChars'];
  if (raw is! Map) return const {};
  return raw.map((key, value) {
    final count = value is num ? value.round() : int.tryParse('$value') ?? 0;
    return MapEntry(key.toString(), count);
  })..removeWhere((_, value) => value <= 0);
}

bool promptComponentsTracked(Map<String, dynamic> row) =>
    promptComponentChars(row).isNotEmpty;

Map<String, int> nonSystemInputChars(Map<String, dynamic> row) {
  final raw = row['nonSystemInputChars'];
  if (raw is! Map) return const {};
  return raw.map((key, value) {
    final count = value is num ? value.round() : int.tryParse('$value') ?? 0;
    return MapEntry(key.toString(), count);
  })..removeWhere((_, value) => value <= 0);
}

/// Tiny focused receipt for the current token dragon: newest traced turns by
/// route, without the lifetime spend ledger that makes `usage_report` too loud.
String inputBreakdownReport(List<Map<String, dynamic>> rows,
    {String? route, int limit = 6}) {
  final filtered = rows
      .where((row) {
        final rowRoute = (row['route'] ?? '').toString();
        return route == null || route.isEmpty || rowRoute == route;
      })
      .toList()
      .reversed
      .take(limit)
      .toList();

  if (filtered.isEmpty) {
    return route == null || route.isEmpty
        ? 'No traced turns found for input breakdown.'
        : 'No traced turns found for route "$route".';
  }

  final b = StringBuffer('── INPUT BREAKDOWN ── ${filtered.length} newest');
  if (route != null && route.isNotEmpty) b.write(' route=$route');
  b.writeln();

  for (final row in filtered) {
    final id = (row['id'] ?? '').toString();
    final rowRoute = (row['route'] ?? 'unknown').toString();
    final inputTokens = promptInputTokens(row);
    final systemTokens = (promptComponentChars(row)['systemPromptTotal'] ?? 0) ~/ 4;
    final schemaTokens = manifestApproxTokens(row);
    final nonSystem = nonSystemInputChars(row);
    final nonSystemChars = nonSystem.values.fold<int>(0, (sum, value) => value + sum);
    final nonSystemTokens = nonSystemChars ~/ 4;
    final iterations = _numField(row, 'iterationCount').round();
    final rawUnattributedTokens =
        inputTokens - systemTokens - schemaTokens - nonSystemTokens;
    final unattributedTokens =
        rawUnattributedTokens < 0 ? 0 : rawUnattributedTokens;
    final overcountNote = rawUnattributedTokens < 0 ? ' (clamped overcount)' : '';

    b.writeln('${id.isEmpty ? '(no id)' : id}  route=$rowRoute  '
        'input=$inputTokens tok  system≈$systemTokens  schema≈$schemaTokens  '
        'non-system≈$nonSystemTokens  '
        'unattributed≈$unattributedTokens$overcountNote  '
        'iterations=$iterations');

    if (nonSystem.isEmpty) {
      b.writeln('  non-system buckets: not tracked — remaining input is repeated message/tool replay or uninstrumented send path');
    } else {
      final grouped = <String, int>{};
      for (final entry in nonSystem.entries) {
        final key = entry.key;
        final prefix = key.contains('.') ? key.split('.').first : 'legacy';
        grouped[prefix] = (grouped[prefix] ?? 0) + entry.value;
      }
      final groups = grouped.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in groups) {
        b.writeln('  ${('${entry.key}.*').padRight(28)} ${entry.value} chars ≈${entry.value ~/ 4} tok');
      }

      final buckets = nonSystem.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in buckets.take(10)) {
        b.writeln('    ${entry.key.padRight(26)} ${entry.value} chars ≈${entry.value ~/ 4} tok');
      }
    }

    final saved = toolTrimApproxTokensSaved(row);
    if (saved > 0) {
      b.writeln('  tool result trim saved≈$saved tok '
          '(compacted ${toolTrimCompactedResults(row)}, hard-capped ${toolTrimHardCappedResults(row)})');
    }
    final argSaved = assistantToolCallArgApproxTokensSaved(row);
    if (argSaved > 0) {
      b.writeln('  assistant tool-call arg trim saved≈$argSaved tok');
    }
  }

  return b.toString().trimRight();
}

bool nonSystemInputTracked(Map<String, dynamic> row) =>
    nonSystemInputChars(row).isNotEmpty;

bool toolTrimTracked(Map<String, dynamic> row) =>
    toolTrimApproxTokensSaved(row) > 0 ||
    assistantToolCallArgApproxTokensSaved(row) > 0 ||
    toolTrimCompactedResults(row) > 0 ||
    toolTrimHardCappedResults(row) > 0;

bool manifestTracked(Map<String, dynamic> row) =>
    manifestApproxTokens(row) > 0 || manifestSchemaChars(row) > 0;

bool costTracked(Map<String, dynamic> row) =>
    promptInputTokens(row) > 0 || promptOutputTokens(row) > 0 || promptCostUsd(row) > 0;

Map<String, int> moodCurrent(Map<String, dynamic> row) {
  final raw = row['moodCurrent'];
  if (raw is! Map) return const {};
  return raw.map(
    (key, value) => MapEntry(key.toString(), (value as num?)?.round() ?? 0),
  );
}

Map<String, int> moodDelta(Map<String, dynamic> row) {
  final raw = row['moodDelta'];
  if (raw is! Map) return const {};
  return raw.map(
    (key, value) => MapEntry(key.toString(), (value as num?)?.round() ?? 0),
  );
}

bool moodTracked(Map<String, dynamic> row) => moodCurrent(row).isNotEmpty;

int _moodValue(Map<String, int> mood, String key) =>
    mood[key] ?? mood[key.toLowerCase()] ?? mood[key.toUpperCase()] ?? 0;

bool confidenceDipped(Map<String, dynamic> row) {
  final delta = moodDelta(row);
  if (delta.isNotEmpty) return _moodValue(delta, 'confidence') < 0;
  final mood = moodCurrent(row);
  return mood.isNotEmpty && _moodValue(mood, 'confidence') < 40;
}

bool playfulnessSpiked(Map<String, dynamic> row) {
  final delta = moodDelta(row);
  if (delta.isNotEmpty) return _moodValue(delta, 'playfulness') > 0;
  final mood = moodCurrent(row);
  return mood.isNotEmpty && _moodValue(mood, 'playfulness') > 70;
}

List<Map<String, dynamic>> structuredToolCalls(Map<String, dynamic> row) {
  final calls = row['toolCalls'];
  if (calls is! List) return const [];
  return calls.whereType<Map<String, dynamic>>().toList();
}

String _toolOutcome(Map<String, dynamic> call) =>
    (call['outcome'] as String? ?? '').toLowerCase().trim();

bool _toolSucceeded(Map<String, dynamic> call) {
  final outcome = _toolOutcome(call);
  return outcome == 'passed' ||
      outcome == 'success' ||
      outcome == 'ok' ||
      outcome == 'done';
}

bool _toolFailed(Map<String, dynamic> call) {
  final outcome = _toolOutcome(call);
  return outcome == 'failed' ||
      outcome == 'error' ||
      outcome == 'blocked' ||
      outcome == 'rejected' ||
      outcome == 'unknown';
}

bool _truthy(dynamic value) => value == true || value == 'true' || value == 1;

bool _stepLooksLikePostProcessError(Map<String, dynamic> step) {
  final d = _desc(step);
  final data = step['data'];
  final dataText = data is Map ? data.toString().toLowerCase() : '';
  final text = '$d $dataText';

  return text.contains('post-process') &&
          (text.contains('error') ||
              text.contains('fail') ||
              text.contains('recover')) ||
      text.contains('tts failed') ||
      text.contains('tag extraction failed') ||
      text.contains('debug extraction failed') ||
      text.contains('recoveredreply') ||
      text.contains('recovered reply') ||
      text.contains('fallback response') ||
      text.contains('error_occurred');
}

bool recoveredReply(Map<String, dynamic> row) {
  final response = (row['finalResponse'] as String? ?? '').toLowerCase();
  return response.contains('error_occurred') ||
      _anyStep(row, (s) {
        final data = s['data'];
        return _stepLooksLikePostProcessError(s) ||
            data is Map &&
                (_truthy(data['recoveredReply']) ||
                    _truthy(data['recovered']) ||
                    _truthy(data['fallback']));
      });
}

int postProcessErrors(Map<String, dynamic> row) =>
    _steps(row).where(_stepLooksLikePostProcessError).length;

bool closedJob(Map<String, dynamic> row) =>
    (row['finalResponse'] as String? ?? '').isNotEmpty &&
    _anyStep(row, (s) => _desc(s).contains('job_done'));

/// The second opinion disagreed with a "this is done" claim.
/// Baseline: 2 of 2. He overclaimed on every job he closed.
bool overclaimed(Map<String, dynamic> row) =>
    (row['finalResponse'] as String? ?? '')
        .contains("other half of me isn't convinced") ||
    _anyStep(row, (s) => _desc(s).contains("isn't convinced"));

/// Did he run the tests before saying it was finished?
/// Baseline: 0 of 2 — run_tests did not exist. This is the level-4 gate.
bool closedWithProof(Map<String, dynamic> row) =>
    closedJob(row) && _anyStep(row, (s) => _desc(s).contains('run_tests'));

/// Tool calls that errored, were blocked, or failed to match.
///
/// Baseline: 11 of 46 — nine consecutive `old_string not found` from the
/// two-space gutter, plus two `edit_file` blocks from new_string:"" being read
/// as a missing argument. Both were the tooling's fault, not his.
int wastedToolCalls(Map<String, dynamic> row) => _steps(row).where((s) {
      final d = _desc(s);
      return d.contains('not found in') ||
          d.contains('blocked') ||
          d.contains('appears') && d.contains('times in') ||
          d.contains('tool error');
    }).length;

int toolCalls(Map<String, dynamic> row) =>
    _steps(row).where((s) => _desc(s).contains('calling tool')).length;

Scorecard score(List<Map<String, dynamic>> rows) {
  var mem = 0, usable = 0, attempted = 0, graph = 0;
  var routedTurns = 0, confidentRoutes = 0;
  var structuredTools = 0, successfulTools = 0, failedTools = 0;
  var recovered = 0, postErrors = 0;
  var jobs = 0, over = 0, proof = 0, wasted = 0, tools = 0;
  var costedTurns = 0, inputTokens = 0, outputTokens = 0;
  var costUsd = 0.0;
  var moodTurns = 0, moodEnergy = 0, moodFocus = 0;
  var confidenceDips = 0, playfulnessSpikes = 0;
  final ttft = <int>[];

  for (final r in rows) {
    if (formedMemory(r)) mem++;
    if (retrievalAttempted(r)) {
      attempted++;
      if (retrievalUsable(r)) usable++;
    }
    if (graphConsulted(r)) graph++;
    if (routed(r)) routedTurns++;
    if (highConfidenceRoute(r)) confidentRoutes++;

    final calls = structuredToolCalls(r);
    structuredTools += calls.length;
    successfulTools += calls.where(_toolSucceeded).length;
    failedTools += calls.where(_toolFailed).length;
    if (recoveredReply(r)) recovered++;
    postErrors += postProcessErrors(r);

    if (closedJob(r)) {
      jobs++;
      if (overclaimed(r)) over++;
      if (closedWithProof(r)) proof++;
    }
    wasted += wastedToolCalls(r);
    tools += calls.isNotEmpty ? calls.length : toolCalls(r);
    if (costTracked(r)) {
      costedTurns++;
      inputTokens += promptInputTokens(r);
      outputTokens += promptOutputTokens(r);
      costUsd += promptCostUsd(r);
    }
    if (moodTracked(r)) {
      final mood = moodCurrent(r);
      moodTurns++;
      moodEnergy += _moodValue(mood, 'energy');
      moodFocus += _moodValue(mood, 'focus');
      if (confidenceDipped(r)) confidenceDips++;
      if (playfulnessSpiked(r)) playfulnessSpikes++;
    }
    final t = timeToGptSend(r);
    if (t != null) ttft.add(t);
  }

  return Scorecard(
    turns: rows.length,
    memoriesFormed: mem,
    retrievalsWithSomethingUsable: usable,
    retrievalsAttempted: attempted,
    graphConsulted: graph,
    routedTurns: routedTurns,
    highConfidenceRoutes: confidentRoutes,
    toolCallsRecorded: structuredTools,
    successfulToolCalls: successfulTools,
    failedToolCalls: failedTools,
    recoveredReplies: recovered,
    postProcessErrors: postErrors,
    jobsClosed: jobs,
    overclaims: over,
    jobsClosedWithProof: proof,
    wastedToolCalls: wasted,
    totalToolCalls: tools,
    turnsWithCost: costedTurns,
    totalInputTokens: inputTokens,
    totalOutputTokens: outputTokens,
    totalCostUsd: costUsd,
    turnsWithMood: moodTurns,
    totalMoodEnergy: moodEnergy,
    totalMoodFocus: moodFocus,
    confidenceDips: confidenceDips,
    playfulnessSpikes: playfulnessSpikes,
    timeToFirstTokenMs: ttft,
  );
}

String route(Map<String, dynamic> row) {
  final raw = (row['route'] as String? ?? '').trim();
  return raw.isEmpty ? 'unknown' : raw;
}

double? _reduction(num previous, num recent) {
  if (previous <= 0) return null;
  return ((previous - recent) / previous) * 100;
}

String _delta(double? value) {
  if (value == null) return '—';
  final arrow = value >= 0 ? '↓' : '↑';
  return '$arrow ${value.abs().round()}%';
}

EfficiencySlice _efficiencySlice(String label, List<Map<String, dynamic>> rows) {
  var costedTurns = 0;
  var manifestTurns = 0;
  var latencyTurns = 0;
  var toolTrimTurns = 0;
  var promptComponentTurns = 0;
  var nonSystemInputTurns = 0;
  var totalInputTokens = 0;
  var totalOutputTokens = 0;
  var totalTokens = 0;
  var totalSchemaTokens = 0;
  var totalToolTrimTokensSaved = 0;
  var totalToolTrimCompactedResults = 0;
  var totalToolTrimHardCappedResults = 0;
  var totalCost = 0.0;
  final componentChars = <String, int>{};
  final nonSystemChars = <String, int>{};
  final latencies = <int>[];

  for (final r in rows) {
    if (costTracked(r)) {
      costedTurns++;
      final input = promptInputTokens(r);
      final output = promptOutputTokens(r);
      totalInputTokens += input;
      totalOutputTokens += output;
      totalTokens += input + output;
      totalCost += promptCostUsd(r);
    }
    if (manifestTracked(r)) {
      manifestTurns++;
      totalSchemaTokens += manifestApproxTokens(r);
    }
    final latency = timeToGptSend(r);
    if (latency != null && latency > 0) {
      latencyTurns++;
      latencies.add(latency);
    }
    if (toolTrimTracked(r)) {
      toolTrimTurns++;
      totalToolTrimTokensSaved += toolTrimApproxTokensSaved(r);
      totalToolTrimCompactedResults += toolTrimCompactedResults(r);
      totalToolTrimHardCappedResults += toolTrimHardCappedResults(r);
    }
    final components = promptComponentChars(r);
    if (components.isNotEmpty) {
      promptComponentTurns++;
      for (final entry in components.entries) {
        componentChars[entry.key] = (componentChars[entry.key] ?? 0) + entry.value;
      }
    }
    final nonSystem = nonSystemInputChars(r);
    if (nonSystem.isNotEmpty) {
      nonSystemInputTurns++;
      for (final entry in nonSystem.entries) {
        nonSystemChars[entry.key] = (nonSystemChars[entry.key] ?? 0) + entry.value;
      }
    }
  }

  return EfficiencySlice(
    label: label,
    turns: rows.length,
    costedTurns: costedTurns,
    manifestTurns: manifestTurns,
    latencyTurns: latencyTurns,
    toolTrimTurns: toolTrimTurns,
    promptComponentTurns: promptComponentTurns,
    totalInputTokens: totalInputTokens,
    totalOutputTokens: totalOutputTokens,
    totalTokens: totalTokens,
    totalSchemaTokens: totalSchemaTokens,
    totalToolTrimTokensSaved: totalToolTrimTokensSaved,
    totalToolTrimCompactedResults: totalToolTrimCompactedResults,
    totalToolTrimHardCappedResults: totalToolTrimHardCappedResults,
    totalCostUsd: totalCost,
    promptComponentChars: componentChars,
    nonSystemInputTurns: nonSystemInputTurns,
    nonSystemInputChars: nonSystemChars,
    timeToFirstTokenMs: latencies,
  );
}

Map<String, EfficiencySlice> _efficiencyByRoute(
  String label,
  List<Map<String, dynamic>> rows,
) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    grouped.putIfAbsent(route(row), () => <Map<String, dynamic>>[]).add(row);
  }
  return {
    for (final entry in grouped.entries)
      entry.key: _efficiencySlice('$label:${entry.key}', entry.value),
  };
}

/// Compare the latest [window] trace rows against the [window] rows immediately
/// before them. This is the explicit version of the tiny dashboard meter: what
/// did cost, schema tax, and setup-to-GPT-send lag do relative to the last
/// comparable batch?
EfficiencySummary efficiencySummary(
  List<Map<String, dynamic>> rows, {
  int window = 8,
}) {
  final safeWindow = window < 1 ? 1 : window;
  final windowed = rows.length > safeWindow * 2
      ? rows.sublist(rows.length - (safeWindow * 2))
      : rows;
  final split = windowed.length <= safeWindow ? 0 : windowed.length - safeWindow;
  final previousRows = windowed.take(split).toList();
  final recentRows = windowed.skip(split).toList();

  return EfficiencySummary(
    window: safeWindow,
    previous: _efficiencySlice('previous', previousRows),
    recent: _efficiencySlice('recent', recentRows),
    previousByRoute: _efficiencyByRoute('previous', previousRows),
    recentByRoute: _efficiencyByRoute('recent', recentRows),
  );
}

// ── What replay is FOR ──────────────────────────────────────────────────────
//
// The scorecard is descriptive. This is the part that makes a change
// falsifiable: take a decision function, run it over every row, and diff the
// outcome against what actually happened.
//
// The motivating failure: the salience gate — the function deciding what Kai
// remembers — was rewritten on the evidence of FIVE traces from one evening, and
// its test hardcodes `intensity: 4` lifted from one of them. That is fitting the
// model to the test set and then offering the test set as proof. With a corpus,
// the honest question is answerable in seconds, for free, deterministically:
//
//   "over the last N turns, what does the new gate keep that the old one
//    dropped, and is any of it junk?"

class ReplayDiff {
  final int total;
  final int changed;
  final List<String> examples; // userInput of changed rows, capped

  const ReplayDiff(
      {required this.total, required this.changed, required this.examples});

  String report(String what) {
    final b = StringBuffer('── REPLAY: $what\n');
    b.writeln('changed on ${Scorecard.ratio(changed, total)} turns');
    for (final e in examples) {
      b.writeln('  • "$e"');
    }
    return b.toString();
  }
}

/// Re-run a decision over the corpus and report where it differs.
///
/// [before] and [after] each take a row and return a label. Anything that is a
/// pure function of a row can be replayed this way — salience, routing, the
/// trim, the correction matcher.
ReplayDiff replay(
  List<Map<String, dynamic>> rows, {
  required String Function(Map<String, dynamic>) before,
  required String Function(Map<String, dynamic>) after,
  int maxExamples = 8,
}) {
  var changed = 0;
  final examples = <String>[];
  for (final r in rows) {
    String b, a;
    try {
      b = before(r);
      a = after(r);
    } catch (_) {
      // A row the decision can't parse is not a difference. Skip it rather than
      // counting a crash as a behaviour change.
      continue;
    }
    if (b != a) {
      changed++;
      if (examples.length < maxExamples) {
        final input = (r['userInput'] as String?) ?? '';
        examples.add(input.length > 60 ? '${input.substring(0, 60)}…' : input);
      }
    }
  }
  return ReplayDiff(total: rows.length, changed: changed, examples: examples);
}
