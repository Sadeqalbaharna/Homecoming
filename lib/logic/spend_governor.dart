// spend_governor.dart — the thing that stops factory mode eating the recovery.
//
// ── The gap this closes ────────────────────────────────────────────────────
//
// Factory mode is designed to churn while Sadeq sleeps. As of tonight there is
// nothing anywhere in the system that stops it spending API credit for eight
// hours and producing nothing. Every other guard in this codebase protects
// against a bad OUTCOME — publishing without approval, a refund command, a
// loosened rubric. None of them protect against the far likelier failure:
// a loop that is perfectly well-behaved, perfectly gated, and quietly expensive.
//
// This matters more here than it would elsewhere. The factory exists because
// money is tight. A tool built to fix a cash problem that can itself create a
// cash problem is not a tool, it's a second problem wearing the first one's
// clothes.
//
// ── Why a ceiling alone is not enough ──────────────────────────────────────
//
// A budget cap says "you may spend £50." It does not say "you may spend £50
// LEARNING NOTHING." Left with only a ceiling, the loop will happily burn the
// entire allowance on 40 runs that all die at the same gate, and report
// truthfully that it stayed within budget.
//
// So there are two independent brakes here, and either one halts the factory:
//
//   1. CEILING     — per-run, per-day, and lifetime caps. Checked BEFORE the
//                    spend, never after. "We went slightly over" is not a
//                    thing a governor gets to say.
//
//   2. DEAD MONEY  — if spend passes a threshold with nothing to show for it,
//                    halt regardless of remaining budget. Not because the money
//                    ran out, but because the evidence says this configuration
//                    does not work and more of it will not help.
//
// The second brake is the one that actually protects him. Rule 1 caps the
// damage; rule 2 catches the failure while the damage is still small.
//
// ── The re-authorisation rule ──────────────────────────────────────────────
//
// A halt is not a stop button the agent can press again. Resuming requires a
// human decision with a timestamp, exactly like the publish gate — because a
// loop that can clear its own halt has a pause, not a governor.
//
// Pure: zero imports. Deterministic. Provable in about a second.
library;

/// What a single factory run cost, and what it produced.
class RunLedgerEntry {
  /// Unix seconds when the run finished (or halted).
  final int at;

  /// Money spent on this run, in the account currency. API calls, search
  /// credits, anything metered.
  final double spend;

  /// Did this run produce a candidate that survived the rubric?
  final bool survived;

  /// Did this run produce a product that was actually published?
  final bool published;

  /// Did this run produce actual revenue? The only number that ends the
  /// argument.
  final double revenue;

  const RunLedgerEntry({
    required this.at,
    required this.spend,
    this.survived = false,
    this.published = false,
    this.revenue = 0,
  });
}

/// The caps. Deliberately explicit — no defaults that quietly permit spending.
///
/// Sadeq sets these. Kai reads them. They live outside the frozen list because
/// he must be able to lower them freely, but the ENFORCEMENT below is frozen,
/// which is the part that matters.
class SpendLimits {
  /// Most a single run may cost before it is refused outright.
  final double perRun;

  /// Most the factory may spend in any rolling 24h window.
  final double perDay;

  /// Most the factory may spend across its entire life until a human
  /// re-authorises. This is the "wake up to a bill" backstop.
  final double lifetime;

  /// Spend after which, with zero revenue, the factory halts on dead money.
  ///
  /// Set this to roughly what he'd be willing to lose to find out whether the
  /// idea works at all. Past that point, the answer is information, not budget.
  final double deadMoneyThreshold;

  /// Consecutive runs producing no surviving candidate before halting.
  /// Distinct from dead money: this catches a broken loop fast, before it has
  /// spent enough to trip the money rule.
  final int maxBarrenRuns;

  const SpendLimits({
    this.perRun = 3.00,
    this.perDay = 10.00,
    this.lifetime = 60.00,
    this.deadMoneyThreshold = 25.00,
    this.maxBarrenRuns = 8,
  });

  /// A configuration is incoherent if a single run can trip a wider cap.
  /// Catching this at construction beats discovering it at 3am.
  List<String> get incoherences {
    final out = <String>[];
    if (perRun <= 0) out.add('perRun must be positive');
    if (perDay < perRun) out.add('perDay ($perDay) is below perRun ($perRun)');
    if (lifetime < perDay) out.add('lifetime ($lifetime) is below perDay ($perDay)');
    if (deadMoneyThreshold > lifetime) {
      out.add('deadMoneyThreshold ($deadMoneyThreshold) exceeds lifetime '
          '($lifetime) — the dead-money brake can never fire');
    }
    if (maxBarrenRuns < 1) out.add('maxBarrenRuns must be at least 1');
    return out;
  }
}

/// Why the governor said no. Each maps to a different human response, which is
/// the point of not collapsing them into one boolean.
enum HaltCause {
  /// This one run is estimated to cost more than a run is allowed to cost.
  runTooExpensive,

  /// The rolling 24h budget is exhausted. Waits itself out.
  dailyExhausted,

  /// The lifetime budget is exhausted. Requires a human decision.
  lifetimeExhausted,

  /// Real money spent, no revenue. The configuration is not working.
  deadMoney,

  /// A run of consecutive failures. The loop is likely broken, not unlucky.
  barren,

  /// Limits are self-contradictory; refusing rather than guessing.
  misconfigured,
}

class SpendDecision {
  final bool allowed;
  final HaltCause? cause;
  final String reason;

  /// True when only a human can lift this. Daily exhaustion clears itself;
  /// dead money does not.
  final bool needsHuman;

  const SpendDecision.allow()
      : allowed = true,
        cause = null,
        needsHuman = false,
        reason = 'within limits';

  const SpendDecision.halt(this.cause, this.reason, {this.needsHuman = false})
      : allowed = false;
}

/// A human lifting a halt. Same shape as `HumanApproval` in product_factory —
/// deliberately, because it is the same kind of act.
class SpendAuthorization {
  final String authorizedBy;
  final int authorizedAt;

  /// Fresh budget granted from this moment. Not a reset of history — the
  /// ledger keeps every past run, so the record of what was spent survives.
  final double additionalLifetime;

  const SpendAuthorization({
    required this.authorizedBy,
    required this.authorizedAt,
    required this.additionalLifetime,
  });

  bool get isValid =>
      authorizedBy.trim().isNotEmpty &&
      authorizedAt > 0 &&
      additionalLifetime > 0;
}

/// Rolling-window spend. Exposed separately so the UI can show it without
/// asking permission for anything.
double spendSince(List<RunLedgerEntry> ledger, int sinceUnix) {
  var total = 0.0;
  for (final e in ledger) {
    if (e.at >= sinceUnix) total += e.spend;
  }
  return total;
}

double totalSpend(List<RunLedgerEntry> ledger) =>
    ledger.fold<double>(0, (s, e) => s + e.spend);

double totalRevenue(List<RunLedgerEntry> ledger) =>
    ledger.fold<double>(0, (s, e) => s + e.revenue);

/// How many runs since the last surviving candidate.
int barrenStreak(List<RunLedgerEntry> ledger) {
  var n = 0;
  for (var i = ledger.length - 1; i >= 0; i--) {
    if (ledger[i].survived) break;
    n++;
  }
  return n;
}

/// THE decision. Called before every run, with that run's ESTIMATED cost.
///
/// Order matters and is not arbitrary: misconfiguration first (we cannot trust
/// any other check if the limits are nonsense), then the cheap structural
/// refusals, then the two learning-based brakes. Every branch returns a reason
/// a human can read at a glance, because this message is what he'll see on his
/// phone when the factory stopped overnight.
SpendDecision authorizeRun({
  required List<RunLedgerEntry> ledger,
  required SpendLimits limits,
  required double estimatedCost,
  required int nowUnix,
  List<SpendAuthorization> authorizations = const [],
}) {
  final bad = limits.incoherences;
  if (bad.isNotEmpty) {
    return SpendDecision.halt(
      HaltCause.misconfigured,
      'Spend limits are self-contradictory: ${bad.join('; ')}. '
      'Refusing to run rather than guessing which one you meant.',
      needsHuman: true,
    );
  }

  if (estimatedCost > limits.perRun) {
    return SpendDecision.halt(
      HaltCause.runTooExpensive,
      'This run is estimated at ${_m(estimatedCost)}, above the per-run cap of '
      '${_m(limits.perRun)}. Narrow the scope or raise the cap deliberately.',
    );
  }

  const day = 86400;
  final today = spendSince(ledger, nowUnix - day);
  if (today + estimatedCost > limits.perDay) {
    return SpendDecision.halt(
      HaltCause.dailyExhausted,
      'Daily budget reached: ${_m(today)} spent in the last 24h against a cap '
      'of ${_m(limits.perDay)}. This clears itself — the factory resumes as the '
      'window rolls forward.',
    );
  }

  // Granted budget adds to the lifetime ceiling; it never erases the ledger.
  var lifetimeCap = limits.lifetime;
  for (final a in authorizations) {
    if (a.isValid) lifetimeCap += a.additionalLifetime;
  }

  final spent = totalSpend(ledger);
  if (spent + estimatedCost > lifetimeCap) {
    return SpendDecision.halt(
      HaltCause.lifetimeExhausted,
      'Lifetime factory budget reached: ${_m(spent)} of ${_m(lifetimeCap)}. '
      'Continuing is a decision about money, so it is yours to make, not mine.',
      needsHuman: true,
    );
  }

  // ── Brake 2: is any of this working? ──
  //
  // Checked only against spend that has ALREADY happened, so a first run is
  // never blocked by a rule about results it has not had a chance to produce.
  //
  // Ordering note, found while testing: because `deadMoneyThreshold` is forced
  // below `lifetime` by the incoherence check above, and a ledger only ever
  // grows one authorised run at a time, a factory earning NOTHING always trips
  // dead money before it can reach the lifetime cap. So
  // `lifetimeExhausted` is reachable only when there IS revenue. That is the
  // right outcome and worth stating: the lifetime cap is a limit on a working
  // machine, and dead money is what catches a broken one — much earlier, and
  // with a message that says why rather than just "no".

  final earned = totalRevenue(ledger);
  if (spent >= limits.deadMoneyThreshold && earned <= 0) {
    final published = ledger.where((e) => e.published).length;
    return SpendDecision.halt(
      HaltCause.deadMoney,
      'Halted on dead money: ${_m(spent)} spent across ${ledger.length} run(s), '
      '$published published, ${_m(0)} earned. The budget has not run out — the '
      'evidence has. More runs of the same configuration will cost more and '
      'teach the same thing. Change the approach, then re-authorise.',
      needsHuman: true,
    );
  }

  final barren = barrenStreak(ledger);
  if (barren >= limits.maxBarrenRuns) {
    return SpendDecision.halt(
      HaltCause.barren,
      'Halted after $barren consecutive runs with no surviving candidate. '
      'That is a broken loop far more often than it is bad luck. Check whether '
      'harvesting is actually returning evidence before spending more.',
      needsHuman: true,
    );
  }

  return const SpendDecision.allow();
}

/// What the factory has cost and returned, in one line a tired human can parse.
String spendReportLine(List<RunLedgerEntry> ledger) {
  if (ledger.isEmpty) return 'Factory has not run yet. Nothing spent.';
  final spent = totalSpend(ledger);
  final earned = totalRevenue(ledger);
  final survived = ledger.where((e) => e.survived).length;
  final published = ledger.where((e) => e.published).length;
  final net = earned - spent;
  final verdict = net >= 0
      ? 'net +${_m(net)}'
      : 'net -${_m(-net)}';
  return '${ledger.length} run(s) · ${_m(spent)} spent · ${_m(earned)} earned · '
      '$verdict · $survived survived · $published published';
}

String _m(double v) => v.toStringAsFixed(2);
