// product_scout.dart — the scoring spine of Kai's product-gap scouting.
//
// ── Why this is CODE and not a directive ─────────────────────────────────────
//
// The method itself (harvest → score → spec → build → ship) lives in
// KAI_PRODUCT_SCOUT_METHOD.md, and a prompt could describe all of it. But a
// prompt is advice, and advice is exactly what he talks himself out of when a
// candidate feels exciting. We already learned this shape once: the sentience
// ladder needed CapabilityState in the TYPE SYSTEM, because "grade yourself
// honestly" as an instruction produced 7/7.
//
// So the part that must not bend is here, as deterministic functions:
//
//   • no citable evidence            → noDefensibleGap (not "weak" — REFUSED)
//   • one source cited three times   → still one source
//   • market-size articles alone     → proves nothing
//   • no distribution channel        → killed, however good the idea is
//   • saturated market               → killed, however strong the demand
//
// A scout that never comes back empty-handed is not a scout, it's a horoscope
// with a business plan. `noticing.dart` refuses to invent observations about a
// clean graph; this refuses to invent opportunities in a served market.
//
// Pure: zero imports. Provable in about a second.
library;

/// Where a claim came from. Ranked by how hard it is to fool yourself with.
enum EvidenceKind {
  /// Someone actually paid, and this is the price. The hardest evidence there is.
  paidPrice,

  /// Units, reviews, or buyers — demand that left a countable trace.
  salesCount,

  /// How many competitors already exist. The saturation signal.
  competitorCount,

  /// A 1–3 star review, a GitHub issue, a forum thread. A complaint IS a gap
  /// statement, written by someone who cared enough to type it.
  complaint,

  /// A public revenue figure. Proves the category monetises at all.
  revenueReport,

  /// "The market is worth $50M." The weakest signal there is: it describes a
  /// category, never an opening. Context only — never a gap on its own.
  marketSize,
}

/// One citable fact. No URL, no evidence.
class Evidence {
  final EvidenceKind kind;

  /// URL or otherwise checkable origin. Blank means it isn't evidence.
  final String source;

  /// What it actually says, in plain language.
  final String claim;

  /// The number, when there is one (price, count, revenue).
  final num? value;

  const Evidence({
    required this.kind,
    required this.source,
    required this.claim,
    this.value,
  });

  /// Unsourced claims are opinions wearing evidence's coat.
  bool get isCitable => source.trim().isNotEmpty;

  /// Market-size trivia can support a case but can never BE one.
  bool get isSubstantive => kind != EvidenceKind.marketSize;

  bool get counts => isCitable && isSubstantive;
}

/// The four axes. ALL are scored 0–5, higher is always better.
enum Axis {
  /// Does a channel with existing traffic already exist? Scored FIRST, because
  /// it silently kills more products than any other axis and is the one every
  /// builder skips. A great product with no channel is a hobby.
  distribution,

  /// Is anyone already paying, and at what price? An empty category is usually
  /// empty for a reason.
  monetization,

  /// ROOM TO COMPETE — the inverse of how crowded it is. 5 = wide open,
  /// 0 = eight funded incumbents. Named for the direction that helps you, so
  /// "higher is better" holds across all four.
  headroom,

  /// Shippable in under two weeks on the stack already owned?
  feasibility,

  /// CAN SADEQ EXPLAIN THIS TO A STRANGER WITHOUT ME?
  ///
  /// Added after a real failure. The first candidate this scout picked was
  /// extracted from his own repository — technically strong, evidence-backed,
  /// and he killed it himself with one sentence: "I don't understand it, and I
  /// feel weird selling something I don't understand."
  ///
  /// He was right, and nothing else on this rubric would have caught it. A
  /// product the seller cannot explain is one he cannot write copy for, cannot
  /// answer a support email about, cannot decide the next version of, and
  /// cannot honestly recommend. Buildable is not the same as sellable BY HIM.
  ///
  /// 5 = he could explain it to a stranger in a pub and answer follow-ups.
  /// 0 = it came out of the codebase and he'd be forwarding every question.
  ///
  /// ── NOT a permanent gate. A TRUST DIAL. ──────────────────────────────────
  ///
  /// The first version of this axis was a hard structural kill, and that was an
  /// over-correction from a single failure. Sadeq caught it immediately: "the
  /// whole point of the factory is that it's autonomous, it should churn
  /// products while I sleep, many of which I will not be able to understand."
  ///
  /// He's right. A factory capped at its owner's comprehension is not a factory.
  /// But he's also right that the FIRST products must be ones he can judge,
  /// because until the machine has a track record, his understanding is the only
  /// instrument available for telling a good call from a lucky one.
  ///
  /// So the required floor starts high and FALLS as the scout earns evidence —
  /// the same ladder Kai climbs for his own capabilities: nothing is granted,
  /// everything is earned. See [operatorFitFloor].
  operatorFit,
}

enum Verdict {
  /// Not enough real evidence to make ANY claim. The honest empty hand.
  noDefensibleGap,

  /// Evidence exists, but a structural axis fails. Dead regardless of appeal.
  killed,

  /// Survives, but nothing about it is compelling.
  weak,

  /// Survives every gate with evidence behind it.
  strong,
}

class Candidate {
  final String name;
  final String market;
  final List<Evidence> evidence;

  /// Axis → 0..5. A missing axis scores 0; silence is not a pass.
  final Map<Axis, int> scores;

  const Candidate({
    required this.name,
    required this.market,
    this.evidence = const [],
    this.scores = const {},
  });

  int score(Axis a) {
    final v = scores[a];
    if (v == null) return 0;
    return v < 0 ? 0 : (v > 5 ? 5 : v);
  }

  /// Evidence that is both sourced and substantive.
  List<Evidence> get realEvidence =>
      evidence.where((e) => e.counts).toList(growable: false);

  /// Three quotes off one page is ONE source. This is the stranger test's
  /// cousin: independent corroboration, not volume.
  int get distinctSources =>
      realEvidence.map((e) => _origin(e.source)).toSet().length;

  static String _origin(String url) {
    var s = url.trim().toLowerCase();
    for (final p in const ['https://', 'http://', 'www.']) {
      if (s.startsWith(p)) s = s.substring(p.length);
    }
    final slash = s.indexOf('/');
    return slash == -1 ? s : s.substring(0, slash);
  }
}

class ScoutResult {
  final Candidate candidate;
  final Verdict verdict;

  /// Why — always populated, including for `strong`, so a pass is auditable too.
  final List<String> reasons;

  const ScoutResult({
    required this.candidate,
    required this.verdict,
    required this.reasons,
  });

  bool get survives =>
      verdict == Verdict.weak || verdict == Verdict.strong;
}

/// Minimum independent sources before a candidate may be discussed at all.
const int kMinDistinctSources = 2;

/// Minimum substantive facts. Two facts from two sources is the floor.
const int kMinEvidence = 2;

/// At or below this on a structural axis, the candidate dies.
const int kStructuralFloor = 2;

/// Every axis must clear this for `strong`.
const int kStrongFloor = 3;

/// How much Sadeq must personally understand a product before it may ship.
///
/// This is the autonomy dial, and it only moves one way: earned.
///
///   • Unproven scout (fewer than [kProvenRunsForAutonomy] completed runs):
///     floor 3. He has to be able to explain it, because his judgement is the
///     only working instrument for telling a good call from a lucky one.
///
///   • Proven AND well-calibrated: floor 1. The machine's track record now
///     substitutes for his personal understanding — which is the entire point
///     of building it. It may ship things he could not have picked himself.
///
///   • Proven but MIS-calibrated: stays at 3. A scout that keeps being wrong
///     does not get more rope for having been wrong more times.
///
/// Note the floor never reaches 0. Something has to remain explicable to
/// *someone*, or nobody can answer a customer, write the listing, or decide
/// what the next version is.
const int kProvenRunsForAutonomy = 4;

int operatorFitFloor({
  required int completedRuns,
  required bool wellCalibrated,
}) {
  if (completedRuns >= kProvenRunsForAutonomy && wellCalibrated) return 1;
  return 3;
}

/// Score one candidate. Deterministic and order-independent: the same inputs
/// always produce the same verdict, which is the entire point — an LLM that
/// grades its own ideas grades them generously.
ScoutResult scoreCandidate(
  Candidate c, {
  /// The current autonomy setting — see [operatorFitFloor]. Defaults to the
  /// cautious value, so a caller that forgets to pass it gets the safe
  /// behaviour rather than the permissive one.
  int operatorFitRequired = 3,
}) {
  final reasons = <String>[];

  final real = c.realEvidence;
  final unsourced = c.evidence.length - c.evidence.where((e) => e.isCitable).length;
  if (unsourced > 0) {
    reasons.add('$unsourced claim(s) had no source and were discarded.');
  }

  // ── Gate 1: structural kills. ──────────────────────────────────────────────
  //
  // THE BAR IS DELIBERATELY ASYMMETRIC, and this order is the whole reason.
  //
  // It ran the other way round first, and a Python port of this file caught it:
  // all three CodeCanyon facts came from codecanyon.net, so the one-domain rule
  // refused it as "no defensible gap" instead of killing it for saturation.
  // Requiring two independent sources to REJECT something means a scout keeps
  // bad ideas alive on a technicality — precisely backwards for a tool whose job
  // is to say no.
  //
  // So: ONE credible source is enough to decline. Corroboration is the price of
  // a YES, not a NO. Rejecting is cheap; claiming an opportunity is expensive.
  if (real.isNotEmpty) {
    final kills = <String>[];
    if (c.score(Axis.distribution) <= kStructuralFloor) {
      kills.add('No channel with existing traffic (distribution '
          '${c.score(Axis.distribution)}/5) — a product with no channel is a hobby.');
    }
    if (c.score(Axis.headroom) <= kStructuralFloor) {
      kills.add('Market already served (headroom ${c.score(Axis.headroom)}/5) — '
          'demand is not opportunity when incumbents are funded.');
    }
    if (c.score(Axis.operatorFit) < operatorFitRequired) {
      kills.add('Below the current autonomy setting: operatorFit '
          '${c.score(Axis.operatorFit)}/5, need $operatorFitRequired. '
          'While the scout is unproven, Sadeq has to be able to judge the '
          'product himself. This floor drops once the machine has a track '
          'record — it is a trust dial, not a ceiling.');
    }
    if (kills.isNotEmpty) {
      reasons.addAll(kills);
      return ScoutResult(candidate: c, verdict: Verdict.killed, reasons: reasons);
    }
  }

  // ── Gate 2: corroboration — the price of claiming an opportunity. ──────────
  if (real.length < kMinEvidence || c.distinctSources < kMinDistinctSources) {
    reasons.add(
        'Only ${real.length} substantive fact(s) across ${c.distinctSources} '
        'independent source(s); need $kMinEvidence across $kMinDistinctSources. '
        'No defensible gap — say so rather than inventing one.');
    return ScoutResult(
        candidate: c, verdict: Verdict.noDefensibleGap, reasons: reasons);
  }

  // ── Gate 3: strong requires every structural axis to clear, with
  // corroboration. operatorFit is governed by the autonomy dial: when the
  // machine earns a lower floor, it must not be quietly re-gated here at 3.
  final weakAxes = Axis.values
      .where((a) => c.score(a) < (a == Axis.operatorFit ? operatorFitRequired : kStrongFloor))
      .toList();
  if (weakAxes.isEmpty && real.length >= 3) {
    reasons.add('Clears every structural axis at $kStrongFloor+ and operatorFit '
        'at the current autonomy floor ($operatorFitRequired+) with ${real.length} facts '
        'across ${c.distinctSources} sources.');
    return ScoutResult(candidate: c, verdict: Verdict.strong, reasons: reasons);
  }

  reasons.add(weakAxes.isEmpty
      ? 'All axes clear but only ${real.length} substantive fact(s) — thin.'
      : 'Below $kStrongFloor on: ${weakAxes.map((a) => a.name).join(', ')}.');
  return ScoutResult(candidate: c, verdict: Verdict.weak, reasons: reasons);
}

/// Score a field of candidates, strongest first. Killed and refused entries are
/// RETAINED, not filtered — the record of what died and why is the part that
/// stops the same dead idea being re-proposed next month.
List<ScoutResult> scoutReport(
  List<Candidate> candidates, {
  int operatorFitRequired = 3,
}) {
  final out = candidates
      .map((c) => scoreCandidate(c, operatorFitRequired: operatorFitRequired))
      .toList();
  int rank(Verdict v) => switch (v) {
        Verdict.strong => 0,
        Verdict.weak => 1,
        Verdict.killed => 2,
        Verdict.noDefensibleGap => 3,
      };
  out.sort((a, b) {
    final r = rank(a.verdict).compareTo(rank(b.verdict));
    if (r != 0) return r;
    // Within a tier, more corroboration wins.
    return b.candidate.realEvidence.length
        .compareTo(a.candidate.realEvidence.length);
  });
  return out;
}

/// True when nothing survived. Kai must be able to report an empty hand as a
/// RESULT, not a failure — otherwise he'll manufacture a winner to have one.
bool noWinner(List<ScoutResult> report) => !report.any((r) => r.survives);
