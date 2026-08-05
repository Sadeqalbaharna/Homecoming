// evidence_ledger.dart — memory of what was already tried, and when it expires.
//
// ── Two opposite failures, one cause ───────────────────────────────────────
//
// The scout currently has no memory of individual attempts, only aggregate
// counts on a bandit arm. That produces two failure modes that look like
// opposites but come from the same missing piece:
//
//   1. AMNESIA — run 12 re-scouts a market that runs 3, 6 and 9 already killed
//      for the same reason, pays the full search cost again, and reaches the
//      identical conclusion. Expensive, and invisible in the metrics: the
//      convergence curve reads "flat", not "repeating itself".
//
//   2. PERMANENT WRITE-OFF — the opposite reflex. A market killed once on
//      saturation is avoided forever. But saturation is a fact about a specific
//      month. Competitors fold. Categories open. A conclusion from eleven
//      months ago is being treated as a law of nature.
//
// Both come from having no notion of when a finding stops being true.
//
// ── Evidence has a half-life, and it differs by kind ───────────────────────
//
// This is the actual insight, and it is not arbitrary — the shelf lives below
// come from how fast the underlying fact can change:
//
//   • "Nobody pays for this category"    — slow. Categories that don't
//     monetise rarely start. ~2 years.
//   • "No distribution channel exists"   — slow-ish. New marketplaces are
//     rare. ~1 year.
//   • "Saturated, N competitors"         — FAST. A competitor count is a
//     snapshot, and the most perishable claim the scout makes. ~4 months.
//   • "Couldn't harvest any evidence"    — fastest, and it's mostly a fact
//     about the SEARCH rather than the market. Kai's harvesting improves; a
//     market that yielded nothing in March may yield plenty now. ~3 months.
//   • "I couldn't support or explain it" — expires on the operator, not the
//     clock. Handled separately below.
//
// ── The operatorFit exception ──────────────────────────────────────────────
//
// operatorFit is the axis Sadeq forced into the rubric because he refused to
// sell what he doesn't understand. A kill on that axis does NOT expire with
// time — it expires when he learns the domain or finds someone who has. So it
// never goes stale on its own, and re-scouting requires a stated reason. That
// is the correct asymmetry: time heals market facts, not competence.
//
// Pure: zero imports. Deterministic. Provable in about a second.
library;

/// Why an attempt died. Mirrors `KillCause` in scout_learning.dart by design;
/// kept local so this file stays independently provable.
enum KillKind {
  noEvidence,
  saturated,
  noChannel,
  noMonetization,
  operatorFit,
  other,
}

/// Shelf life in days, by kill kind. The heart of the module.
const Map<KillKind, int> kShelfLifeDays = {
  KillKind.noEvidence: 90,
  KillKind.saturated: 120,
  KillKind.noChannel: 365,
  KillKind.noMonetization: 730,
  KillKind.operatorFit: -1, // never expires on time alone
  KillKind.other: 180,
};

/// One recorded attempt against one market.
class ScoutRecord {
  final String market;
  final KillKind killedBy;

  /// Unix seconds when this conclusion was reached.
  final int at;

  /// The citations that supported it. A record with none is an opinion, and
  /// is treated as such below.
  final List<String> citations;

  /// Free-text note — what specifically was found.
  final String note;

  const ScoutRecord({
    required this.market,
    required this.killedBy,
    required this.at,
    this.citations = const [],
    this.note = '',
  });

  /// A conclusion with no citation cannot go stale, because it was never
  /// fresh. It carries no weight in the decision below.
  bool get isCited => citations.isNotEmpty;

  int ageDays(int nowUnix) {
    final secs = nowUnix - at;
    return secs <= 0 ? 0 : secs ~/ 86400;
  }

  bool isStale(int nowUnix) {
    final shelf = kShelfLifeDays[killedBy] ?? 180;
    if (shelf < 0) return false; // operatorFit: time does not heal it
    return ageDays(nowUnix) >= shelf;
  }

  /// Confidence this finding still holds, decaying linearly to zero across its
  /// shelf life. Linear rather than exponential on purpose — it is easier to
  /// explain, and there is nothing in the data to justify a fancier curve.
  double confidence(int nowUnix) {
    if (!isCited) return 0;
    final shelf = kShelfLifeDays[killedBy] ?? 180;
    if (shelf < 0) return 1.0;
    final age = ageDays(nowUnix);
    if (age >= shelf) return 0;
    return 1.0 - (age / shelf);
  }
}

/// What to do about a market, next time it comes up.
enum ScoutAdvice {
  /// Never looked at it. Go.
  neverScouted,

  /// Looked, killed, and the finding still holds. Don't pay again.
  skipStillValid,

  /// Looked, killed, but the finding has expired. Worth another look.
  rescoutStale,

  /// Killed repeatedly for the same reason and still within shelf life. The
  /// strongest skip there is.
  skipRepeatedly,

  /// Killed on operatorFit. Only Sadeq can clear this one.
  blockedOnOperator,
}

class MarketAdvice {
  final String market;
  final ScoutAdvice advice;
  final String reason;

  /// Highest surviving confidence among the records for this market.
  final double confidence;

  /// How many times this market has been killed, ever.
  final int priorKills;

  const MarketAdvice({
    required this.market,
    required this.advice,
    required this.reason,
    required this.confidence,
    required this.priorKills,
  });

  bool get shouldScout =>
      advice == ScoutAdvice.neverScouted || advice == ScoutAdvice.rescoutStale;
}

/// Should this market be scouted again right now?
///
/// Order matters: the operator block is checked first because it is the only
/// one a clock cannot clear, and letting a time rule overrule it would quietly
/// undo the axis Sadeq insisted on.
MarketAdvice adviseMarket({
  required String market,
  required List<ScoutRecord> allRecords,
  required int nowUnix,
}) {
  final mine =
      allRecords.where((r) => r.market.toLowerCase() == market.toLowerCase()).toList();

  if (mine.isEmpty) {
    return MarketAdvice(
      market: market,
      advice: ScoutAdvice.neverScouted,
      reason: 'no prior attempt on record',
      confidence: 0,
      priorKills: 0,
    );
  }

  final operatorBlocks =
      mine.where((r) => r.killedBy == KillKind.operatorFit).toList();
  if (operatorBlocks.isNotEmpty) {
    return MarketAdvice(
      market: market,
      advice: ScoutAdvice.blockedOnOperator,
      reason: 'killed on operator fit — you said you would not sell what you '
          'cannot explain. Time does not clear this one; learning the domain '
          'or finding someone who knows it does.',
      confidence: 1.0,
      priorKills: mine.length,
    );
  }

  // Best surviving evidence against re-scouting.
  ScoutRecord? strongest;
  var best = 0.0;
  for (final r in mine) {
    final c = r.confidence(nowUnix);
    if (c > best) {
      best = c;
      strongest = r;
    }
  }

  if (strongest == null || best <= 0) {
    final oldest = mine.map((r) => r.ageDays(nowUnix)).fold<int>(0, (a, b) => b > a ? b : a);
    return MarketAdvice(
      market: market,
      advice: ScoutAdvice.rescoutStale,
      reason: 'killed ${mine.length} time(s), but the newest finding has '
          'expired (oldest is $oldest days old). A competitor count is a '
          'snapshot, not a law — worth another look.',
      confidence: 0,
      priorKills: mine.length,
    );
  }

  // Bound to a non-nullable local: type promotion across a closure capture is
  // fragile, and this reads better than sprinkling `!` through the branch.
  final ScoutRecord top = strongest;

  // Same cause, more than once, still fresh: the strongest possible skip.
  final sameCause = mine.where((r) => r.killedBy == top.killedBy).length;
  if (sameCause >= 2) {
    return MarketAdvice(
      market: market,
      advice: ScoutAdvice.skipRepeatedly,
      reason: 'killed $sameCause times on ${top.killedBy.name}, most '
          'recently ${top.ageDays(nowUnix)} days ago. Scouting it again '
          'buys the same answer at full price.',
      confidence: best,
      priorKills: mine.length,
    );
  }

  return MarketAdvice(
    market: market,
    advice: ScoutAdvice.skipStillValid,
    reason: 'killed on ${top.killedBy.name} '
        '${top.ageDays(nowUnix)} days ago; that finding has not expired '
        'yet (confidence ${(best * 100).toStringAsFixed(0)}%).',
    confidence: best,
    priorKills: mine.length,
  );
}

/// Markets worth revisiting right now, most-expired first.
///
/// This is the queue that stops the scout only ever widening. Widening is what
/// it reaches for when stuck, and it is often the wrong move — a market killed
/// on a stale saturation count is a better bet than an untouched one nobody has
/// any evidence about at all.
List<MarketAdvice> revisitQueue({
  required List<ScoutRecord> allRecords,
  required int nowUnix,
}) {
  final markets = <String>{};
  for (final r in allRecords) {
    markets.add(r.market);
  }

  final out = <MarketAdvice>[];
  for (final m in markets) {
    final a = adviseMarket(market: m, allRecords: allRecords, nowUnix: nowUnix);
    if (a.advice == ScoutAdvice.rescoutStale) out.add(a);
  }

  out.sort((x, y) {
    if (x.priorKills == y.priorKills) return x.market.compareTo(y.market);
    return x.priorKills.compareTo(y.priorKills); // fewer past kills first
  });
  return out;
}

/// How much repeated work the ledger has prevented — the module's own scoreboard.
String savingsLine(List<ScoutRecord> allRecords, int nowUnix, double costPerScout) {
  final markets = <String>{};
  for (final r in allRecords) {
    markets.add(r.market);
  }
  var skips = 0;
  for (final m in markets) {
    final a = adviseMarket(market: m, allRecords: allRecords, nowUnix: nowUnix);
    if (!a.shouldScout) skips++;
  }
  final saved = skips * costPerScout;
  return '$skips market(s) currently skippable on existing evidence — about '
      '${saved.toStringAsFixed(2)} of repeated scouting avoided.';
}
