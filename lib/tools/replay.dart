// replay.dart — arithmetic over the corpus, instead of adjectives.
//
// ── The finding this answers ─────────────────────────────────────────────────
//
// "You're not missing telemetry, you're missing arithmetic."
//
// Every number in the 2026-07-16 scorecard — memory formation, retrieval hit
// rate, overclaim rate, wasted tool calls, time to first token — was already
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
  final int jobsClosed;
  final int overclaims;
  final int jobsClosedWithProof;
  final int wastedToolCalls;
  final int totalToolCalls;
  final List<int> timeToFirstTokenMs;

  const Scorecard({
    required this.turns,
    required this.memoriesFormed,
    required this.retrievalsWithSomethingUsable,
    required this.retrievalsAttempted,
    required this.graphConsulted,
    required this.jobsClosed,
    required this.overclaims,
    required this.jobsClosedWithProof,
    required this.wastedToolCalls,
    required this.totalToolCalls,
    required this.timeToFirstTokenMs,
  });

  int get medianTimeToFirstToken {
    if (timeToFirstTokenMs.isEmpty) return 0;
    final s = [...timeToFirstTokenMs]..sort();
    return s[s.length ~/ 2];
  }

  /// Always "k of n". Never a bare percentage — 100% that means 2/2 should look
  /// like 2/2, or it will get quoted at somebody as though it meant something.
  static String ratio(int k, int n) => n == 0 ? '— (no data)' : '$k of $n';

  String report() {
    final b = StringBuffer('── KAI SCORECARD ──  $turns turns\n');
    b.writeln('memory formed              ${ratio(memoriesFormed, turns)}');
    b.writeln('retrieval found something  '
        '${ratio(retrievalsWithSomethingUsable, retrievalsAttempted)}');
    b.writeln('graph consulted            ${ratio(graphConsulted, turns)}');
    b.writeln('jobs closed                $jobsClosed');
    b.writeln('  …overclaimed             ${ratio(overclaims, jobsClosed)}');
    b.writeln('  …with real proof         ${ratio(jobsClosedWithProof, jobsClosed)}');
    b.writeln('wasted tool calls          ${ratio(wastedToolCalls, totalToolCalls)}');
    b.writeln('median time to 1st token   ${medianTimeToFirstToken}ms');
    return b.toString();
  }
}

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
int? timeToFirstToken(Map<String, dynamic> row) {
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

/// The graph only gets consulted if a transcript search clears 0.28 FIRST —
/// spreadActivation sits inside `if (memoriesUsed.isNotEmpty)`. So this is
/// currently identical to retrievalUsable, and that identity IS the level-5
/// blocker. When Phase 3 lands and the graph is queried from the message
/// directly, these two numbers must come apart. If they don't, Phase 3 didn't
/// work.
bool graphConsulted(Map<String, dynamic> row) => retrievalUsable(row);

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
  var jobs = 0, over = 0, proof = 0, wasted = 0, tools = 0;
  final ttft = <int>[];

  for (final r in rows) {
    if (formedMemory(r)) mem++;
    if (retrievalAttempted(r)) {
      attempted++;
      if (retrievalUsable(r)) usable++;
    }
    if (graphConsulted(r)) graph++;
    if (closedJob(r)) {
      jobs++;
      if (overclaimed(r)) over++;
      if (closedWithProof(r)) proof++;
    }
    wasted += wastedToolCalls(r);
    tools += toolCalls(r);
    final t = timeToFirstToken(r);
    if (t != null) ttft.add(t);
  }

  return Scorecard(
    turns: rows.length,
    memoriesFormed: mem,
    retrievalsWithSomethingUsable: usable,
    retrievalsAttempted: attempted,
    graphConsulted: graph,
    jobsClosed: jobs,
    overclaims: over,
    jobsClosedWithProof: proof,
    wastedToolCalls: wasted,
    totalToolCalls: tools,
    timeToFirstTokenMs: ttft,
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
