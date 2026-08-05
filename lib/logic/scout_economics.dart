// scout_economics.dart — the bandit, but aware that attempts cost money.
//
// ── What scout_learning.dart gets right, and the one thing it misses ───────
//
// `rankMarkets()` treats every attempt as costing the same. It doesn't. A
// market that dies at the harvest gate costs a couple of searches; one that
// dies at build costs hours of tokens and a day of work. UCB1 scores them
// identically, so a market that fails cheaply and often is punished exactly as
// hard as one that fails expensively and often.
//
// That's backwards. Cheap failure is the resource the whole loop runs on. The
// scout's actual objective is not "highest survival rate" — it is "most
// survivals per pound", and those rank differently often enough to matter:
//
//   Market A: 50% survival, £2/attempt  → a survival costs £4
//   Market B: 60% survival, £9/attempt  → a survival costs £15
//
// Plain UCB1 picks B. B is nearly four times worse. With £20 to spend, A
// returns five survivals and B returns two.
//
// ── Why this is a separate file ────────────────────────────────────────────
//
// `scout_learning.dart` is not frozen, but it is tested and working, and it was
// written to answer a specific question Sadeq asked ("turn this into machine
// learning"). Bolting an economic term onto it would entangle two ideas that
// are easier to verify apart. This file composes with it rather than editing
// it: same arms, same UCB1 shape, different reward denominator.
//
// ── The normalisation problem, and the honest fix ──────────────────────────
//
// UCB1's exploration bonus is calibrated for rewards in [0,1]. Survivals-per-
// pound is unbounded, so feeding it in raw would let a single cheap fluke
// dominate the ranking forever. So efficiency is normalised against the best
// arm observed — making it relative rather than absolute, which is all the
// ranking needs, and keeps the exploration term meaningful.
//
// ── The floor that stops it being penny-wise ───────────────────────────────
//
// Optimising purely for cost-per-survival has an obvious degenerate solution:
// prefer markets so cheap to scout that nothing real is ever attempted. So an
// arm that has NEVER produced a survival is not allowed to rank on efficiency
// at all — infinite cost per survival is not a small number, and treating
// "£0.10 per attempt, zero results" as efficient is how a loop optimises itself
// into doing nothing carefully.
//
// Pure: one import (dart:math, for sqrt/log). Deterministic.
library;

import 'dart:math' as math;

/// A market arm with its economics attached.
///
/// Deliberately mirrors `MarketArm` in scout_learning.dart rather than
/// importing it — these two files stay independently provable, and the caller
/// adapts between them in one line.
class CostedArm {
  final String market;
  final int attempts;
  final int survivals;
  final int sales;

  /// Everything ever spent scouting this market, in account currency.
  final double totalCost;

  /// Everything this market has ever returned.
  final double totalRevenue;

  const CostedArm({
    required this.market,
    this.attempts = 0,
    this.survivals = 0,
    this.sales = 0,
    this.totalCost = 0,
    this.totalRevenue = 0,
  });

  double get costPerAttempt => attempts <= 0 ? 0 : totalCost / attempts;

  /// Cost of buying one surviving candidate here. Infinite when none has ever
  /// survived — which is the truth, not an inconvenience to be smoothed away.
  double get costPerSurvival =>
      survivals <= 0 ? double.infinity : totalCost / survivals;

  double get costPerSale => sales <= 0 ? double.infinity : totalCost / sales;

  /// The number that ends every argument: money out minus money in.
  double get net => totalRevenue - totalCost;

  /// Return on spend. 1.0 means it broke even.
  double get roi => totalCost <= 0 ? 0 : totalRevenue / totalCost;

  /// Has this arm ever produced anything at all?
  bool get hasProduced => survivals > 0 || sales > 0;
}

/// A ranked market, with the arithmetic exposed so the choice can be argued
/// with rather than merely obeyed.
class CostedChoice {
  final String market;
  final double score;
  final double efficiencyTerm;
  final double exploreTerm;
  final double costPerSurvival;
  final int attempts;

  const CostedChoice({
    required this.market,
    required this.score,
    required this.efficiencyTerm,
    required this.exploreTerm,
    required this.costPerSurvival,
    required this.attempts,
  });

  String get rationale {
    if (attempts == 0) return 'never scouted — cost unknown, worth one look';
    if (costPerSurvival.isInfinite) {
      return '$attempts attempt(s), nothing has ever survived here';
    }
    return 'a surviving candidate costs about '
        '${costPerSurvival.toStringAsFixed(2)} here';
  }
}

const double kExploreWeight = 2.0;

/// Rank markets by survivals-per-pound rather than survivals-per-attempt.
///
/// Unpulled arms rank first, as in plain UCB1 — you cannot know a market's
/// economics until you have paid for one look at it.
List<CostedChoice> rankByEfficiency(List<CostedArm> arms) {
  if (arms.isEmpty) return const [];

  final totalPulls = arms.fold<int>(0, (s, a) => s + a.attempts);

  // Normaliser: the best finite efficiency observed anywhere. Only arms that
  // have actually produced something are eligible to set the bar.
  var bestEff = 0.0;
  for (final a in arms) {
    if (!a.hasProduced) continue;
    final cps = a.costPerSurvival;
    if (cps.isInfinite || cps <= 0) continue;
    final eff = 1.0 / cps;
    if (eff > bestEff) bestEff = eff;
  }

  final out = <CostedChoice>[];
  for (final a in arms) {
    if (a.attempts == 0) {
      out.add(CostedChoice(
        market: a.market,
        score: double.infinity,
        efficiencyTerm: 0,
        exploreTerm: double.infinity,
        costPerSurvival: double.infinity,
        attempts: 0,
      ));
      continue;
    }

    // The floor: never produced anything ⇒ efficiency is zero, however cheap.
    var eff = 0.0;
    if (a.hasProduced && bestEff > 0) {
      final cps = a.costPerSurvival;
      if (!cps.isInfinite && cps > 0) {
        eff = (1.0 / cps) / bestEff; // in (0,1]
      }
    }

    final explore = totalPulls <= 1
        ? 0.0
        : math.sqrt((kExploreWeight * math.log(totalPulls)) / a.attempts);

    out.add(CostedChoice(
      market: a.market,
      score: eff + explore,
      efficiencyTerm: eff,
      exploreTerm: explore,
      costPerSurvival: a.costPerSurvival,
      attempts: a.attempts,
    ));
  }

  out.sort((x, y) {
    if (x.score == y.score) return x.market.compareTo(y.market);
    return y.score.compareTo(x.score);
  });
  return out;
}

/// How much would need to be spent, at current observed rates, to buy one more
/// surviving candidate anywhere?
///
/// This is the single most useful number for deciding whether to keep going,
/// and it is not currently computed anywhere in the system. If the answer is
/// larger than a product has ever earned, the loop is uneconomic no matter how
/// elegantly it converges.
double costOfNextSurvival(List<CostedArm> arms) {
  var best = double.infinity;
  for (final a in arms) {
    final c = a.costPerSurvival;
    if (c < best) best = c;
  }
  return best;
}

/// The blunt verdict on the whole enterprise.
class EconomicVerdict {
  final double spent;
  final double earned;
  final double nextSurvivalCost;
  final int totalAttempts;

  const EconomicVerdict({
    required this.spent,
    required this.earned,
    required this.nextSurvivalCost,
    required this.totalAttempts,
  });

  double get net => earned - spent;
  bool get profitable => net > 0;

  /// Null while there is genuinely not enough history to judge.
  String? get verdict {
    if (totalAttempts < 3) return null;
    if (profitable) {
      return 'Profitable: ${earned.toStringAsFixed(2)} earned against '
          '${spent.toStringAsFixed(2)} spent across $totalAttempts attempts.';
    }
    if (earned <= 0) {
      final next = nextSurvivalCost.isInfinite
          ? 'unknown — nothing has ever survived'
          : nextSurvivalCost.toStringAsFixed(2);
      return 'No revenue yet. ${spent.toStringAsFixed(2)} spent across '
          '$totalAttempts attempts; next surviving candidate costs about $next. '
          'That number, not the convergence curve, is what says whether to '
          'continue.';
    }
    return 'Losing money: ${earned.toStringAsFixed(2)} earned against '
        '${spent.toStringAsFixed(2)} spent. Narrowing to the cheapest producing '
        'market beats widening.';
  }
}

EconomicVerdict economics(List<CostedArm> arms) {
  var spent = 0.0;
  var earned = 0.0;
  var attempts = 0;
  for (final a in arms) {
    spent += a.totalCost;
    earned += a.totalRevenue;
    attempts += a.attempts;
  }
  return EconomicVerdict(
    spent: spent,
    earned: earned,
    nextSurvivalCost: costOfNextSurvival(arms),
    totalAttempts: attempts,
  );
}
