// scout_learning.dart — the part that actually converges.
//
// ── What this is, and what it honestly is not ───────────────────────────────
//
// Sadeq: "turn this process into machine learning, I want him to hone closer
// and closer to success every run."
//
// It cannot be gradient descent. GPT-5.5 and Claude ship with frozen weights;
// nothing Kai experiences edits a parameter, so he does not become *smarter*
// through failure and never will without fine-tuning. Saying otherwise would
// be a comfortable lie.
//
// But intelligence is not the only thing that can improve. A POLICY can — which
// market to search, in what order, and which check to run first — and learning
// a policy from outcomes is real machine learning, from the bandit family
// rather than the neural one. It provably converges, and it runs in pure Dart
// with no model involved at all.
//
// ── The insight that makes it work: don't wait for sales ───────────────────
//
// Calibration (scout_calibration.dart) learns from revenue, which needs a
// shipped product, 7 days of data and 3 completed runs. If that were the only
// signal, a scout failing at stage 1 would learn nothing, forever, at full
// price per attempt.
//
// But every failed scout is ALREADY a labelled example: "market X, evidence
// approach Y → died on headroom." That is a reward signal available on every
// single run. Treat each market as a bandit arm, pull it by scouting it, and
// the reward is whether any candidate survived.
//
// ── Why UCB1 rather than Thompson sampling ─────────────────────────────────
//
// Thompson sampling needs a random draw, which makes behaviour unreproducible
// and untestable. UCB1 is deterministic: the same history always produces the
// same next choice. Given everything else here is verified by exhaustive
// tests, a stochastic policy would be the one component nobody could check.
//
// UCB1 scores each arm as:  mean_reward + sqrt(2 * ln(total_pulls) / pulls)
//
// The first term exploits what worked. The second is an uncertainty bonus that
// decays as an arm is tried more — so untried markets get explored, repeatedly
// failed markets fade, and a market that failed once is not written off forever.
// That is "honing closer" expressed as arithmetic.
//
// Pure: zero imports. Deterministic. Provable in about a second.
library;

import 'dart:math' as math;

/// Which gate killed an attempt. This is the label on the training example —
/// "it failed" teaches nothing, "it failed on headroom" teaches where to look.
enum KillCause {
  /// No citable evidence could be harvested at all.
  noEvidence,

  /// Evidence existed but the market is already served.
  saturated,

  /// No channel with existing traffic.
  noChannel,

  /// Nobody pays for this category.
  noMonetization,

  /// The operator could not explain or support it.
  operatorFit,

  /// Buildable, sellable, but nothing shipped for another reason.
  other,
}

/// One market's accumulated history. A bandit arm.
class MarketArm {
  final String market;

  /// How many times this market has been scouted.
  final int attempts;

  /// How many of those produced a surviving candidate.
  final int survivals;

  /// How many produced a product that actually SOLD. The real reward, when it
  /// eventually exists — weighted far above mere survival.
  final int sales;

  /// Why attempts here died, counted by cause.
  final Map<KillCause, int> kills;

  const MarketArm({
    required this.market,
    this.attempts = 0,
    this.survivals = 0,
    this.sales = 0,
    this.kills = const {},
  });

  /// Reward in [0,1]. A sale is worth far more than a survival, because a
  /// candidate that merely passed the rubric has not proved anything yet.
  double get meanReward {
    if (attempts <= 0) return 0;
    final r = (survivals * 0.3) + (sales * 1.0);
    final capped = r / attempts;
    return capped > 1.0 ? 1.0 : capped;
  }

  MarketArm recordAttempt({bool survived = false, bool sold = false, KillCause? killedBy}) {
    final k = Map<KillCause, int>.from(kills);
    if (killedBy != null) k[killedBy] = (k[killedBy] ?? 0) + 1;
    return MarketArm(
      market: market,
      attempts: attempts + 1,
      survivals: survivals + (survived ? 1 : 0),
      sales: sales + (sold ? 1 : 0),
      kills: k,
    );
  }
}

/// A market ranked for the next attempt, with the arithmetic exposed so the
/// choice is auditable rather than mysterious.
class MarketChoice {
  final String market;
  final double score;
  final double exploitTerm;
  final double exploreTerm;
  final int attempts;

  const MarketChoice({
    required this.market,
    required this.score,
    required this.exploitTerm,
    required this.exploreTerm,
    required this.attempts,
  });

  /// Why this market is being suggested — "never tried" reads very differently
  /// from "worked twice before", and Kai should be able to say which it is.
  String get rationale => attempts == 0
      ? 'never scouted — pure exploration'
      : exploreTerm > exploitTerm
          ? 'thin history ($attempts attempt(s)) — still worth exploring'
          : 'best observed return so far (${(exploitTerm * 100).toStringAsFixed(0)}%)';
}

/// UCB1 exploration constant. 2.0 is the textbook value; lower explores less.
const double kExplorationWeight = 2.0;

/// Rank markets for the next attempt, best first.
///
/// Unpulled arms are ranked ABOVE everything, because UCB1's bonus is infinite
/// at zero pulls — you cannot know a market is bad until you have looked once.
List<MarketChoice> rankMarkets(List<MarketArm> arms) {
  if (arms.isEmpty) return const [];
  final totalPulls = arms.fold<int>(0, (s, a) => s + a.attempts);

  final out = <MarketChoice>[];
  for (final a in arms) {
    if (a.attempts == 0) {
      out.add(MarketChoice(
        market: a.market,
        score: double.infinity,
        exploitTerm: 0,
        exploreTerm: double.infinity,
        attempts: 0,
      ));
      continue;
    }
    final exploit = a.meanReward;
    final explore = totalPulls <= 1
        ? 0.0
        : math.sqrt((kExplorationWeight * math.log(totalPulls)) / a.attempts);
    out.add(MarketChoice(
      market: a.market,
      score: exploit + explore,
      exploitTerm: exploit,
      exploreTerm: explore,
      attempts: a.attempts,
    ));
  }

  out.sort((x, y) {
    if (x.score == y.score) return x.market.compareTo(y.market); // stable
    return y.score.compareTo(x.score);
  });
  return out;
}

/// Which gate to evaluate FIRST, cheapest-rejection-first.
///
/// This is the other half of converging, and the less obvious one. If headroom
/// kills 70% of candidates, then checking headroom before spending searches on
/// monetisation and feasibility makes every failure cheaper. Learning to fail
/// FASTER buys more attempts per pound, which moves you toward a hit just as
/// surely as picking better markets does.
List<KillCause> checkOrder(List<MarketArm> arms) {
  final totals = <KillCause, int>{};
  for (final a in arms) {
    a.kills.forEach((c, n) => totals[c] = (totals[c] ?? 0) + n);
  }
  final causes = KillCause.values.toList()
    ..sort((x, y) {
      final nx = totals[x] ?? 0;
      final ny = totals[y] ?? 0;
      if (nx == ny) return x.index.compareTo(y.index); // stable
      return ny.compareTo(nx);
    });
  return causes;
}

/// Is the scout actually getting better, or just busier?
///
/// Compares the survival rate of the most recent attempts against the earlier
/// ones. This is the honest scoreboard for the whole exercise: if this does not
/// climb, the loop is expensive repetition wearing the costume of learning.
class Convergence {
  final double earlyRate;
  final double recentRate;
  final int totalAttempts;

  const Convergence({
    required this.earlyRate,
    required this.recentRate,
    required this.totalAttempts,
  });

  bool get improving => recentRate > earlyRate;

  /// Null when there is not enough history to say anything honest.
  String? get verdict {
    if (totalAttempts < 6) return null;
    if (improving) {
      return 'Converging: survival rate ${(earlyRate * 100).toStringAsFixed(0)}% '
          '→ ${(recentRate * 100).toStringAsFixed(0)}% across $totalAttempts attempts.';
    }
    if (recentRate == earlyRate) {
      return 'Flat at ${(recentRate * 100).toStringAsFixed(0)}% across '
          '$totalAttempts attempts — the policy is not learning. Change the '
          'harvest approach, not the standard.';
    }
    return 'Getting WORSE: ${(earlyRate * 100).toStringAsFixed(0)}% → '
        '${(recentRate * 100).toStringAsFixed(0)}%. Recent markets are worse '
        'than the early ones; stop widening and revisit what worked.';
  }
}

/// Measure convergence from an ordered attempt log (oldest first).
/// Each entry is simply whether that attempt produced a surviving candidate.
Convergence measureConvergence(List<bool> attemptsOldestFirst) {
  final n = attemptsOldestFirst.length;
  if (n == 0) {
    return const Convergence(earlyRate: 0, recentRate: 0, totalAttempts: 0);
  }
  final half = n ~/ 2;
  if (half == 0) {
    final r = attemptsOldestFirst.first ? 1.0 : 0.0;
    return Convergence(earlyRate: r, recentRate: r, totalAttempts: n);
  }
  final early = attemptsOldestFirst.take(half);
  final recent = attemptsOldestFirst.skip(n - half);
  double rate(Iterable<bool> xs) =>
      xs.isEmpty ? 0 : xs.where((b) => b).length / xs.length;
  return Convergence(
    earlyRate: rate(early),
    recentRate: rate(recent),
    totalAttempts: n,
  );
}
