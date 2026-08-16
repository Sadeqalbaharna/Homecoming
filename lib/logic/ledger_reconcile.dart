// ledger_reconcile — the ledger checks itself against the bank.
//
// ── Why a derived balance is not a balance ──────────────────────────────────
//
// The cash card computes totalIncome - totalExpenses. That is the only thing it
// CAN do from rows alone, and it has one failure mode that never announces
// itself: miss a single transaction and every balance from then on is wrong by
// that amount, permanently, while continuing to add up perfectly.
//
// A ledger that is quietly wrong is worse than one that is obviously empty,
// because you act on it.
//
// The fix is already arriving for free. Bank alerts carry the balance —
// "...Bal: BHD 500.000" — so every transaction notification is also an
// independent, authoritative, point-in-time statement of truth. Two numbers
// from two sources:
//
//   OBSERVED  what the bank says. Point-in-time, authoritative, self-correcting.
//   DERIVED   what the rows sum to. Complete only if nothing was missed.
//
// ── The gap is the product ──────────────────────────────────────────────────
//
// The difference between them is the most useful number in the whole ledger,
// because it is exactly the amount that is unaccounted for. Not an estimate of
// error — the error itself, in dinars.
//
// So this does not "correct" the ledger. It ANCHORS on the last thing the bank
// said, predicts forward using only the rows since then, and reports the
// discrepancy when the next observation lands. Each new alert re-anchors, so
// drift can never accumulate past one interval, and a missing transaction shows
// up as a number rather than as a silence.
//
// Nothing here edits a row. Reconciliation reports; a human decides. A system
// that silently invented a "missing transaction" row to make the sums work
// would be forging its own evidence.
//
// Pure, deterministic, no imports beyond the candidate type.

import '../services/core/kai_cash_statement_parser.dart';

/// What the bank said the balance was, and when.
class KaiBalanceObservation {
  const KaiBalanceObservation({
    required this.account,
    required this.balance,
    required this.at,
    this.source = '',
  });

  /// Whatever identifies the account in the alert — usually the last four
  /// digits. Reconciliation is per-account: two accounts sharing a running
  /// total is how a healthy current account hides an overdrawn one.
  final String account;

  final double balance;
  final DateTime at;
  final String source;
}

/// One account's answer to "do my rows agree with my bank".
class KaiAccountReconciliation {
  const KaiAccountReconciliation({
    required this.account,
    required this.anchorBalance,
    required this.anchoredAt,
    required this.movementSinceAnchor,
    required this.predictedBalance,
    this.latestObservedBalance,
    this.gap,
    required this.rowsSinceAnchor,
    this.ambiguousSameDayRows = 0,
  });

  final String account;

  /// The last balance the bank stated before the current one.
  final double anchorBalance;
  final DateTime anchoredAt;

  /// Income minus expenses across the rows recorded since the anchor.
  final double movementSinceAnchor;

  /// What the rows say the balance should now be.
  final double predictedBalance;

  /// What the bank most recently said. Null when there is only one observation,
  /// which is not a failure — it is simply the first anchor.
  final double? latestObservedBalance;

  /// observed − predicted. Null until there is something to compare against.
  ///
  /// Negative means money left that no row explains. Positive means money
  /// arrived that no row explains. Both are worth saying out loud; only the
  /// first one is usually a missing transaction rather than a missing payslip.
  final double? gap;

  final int rowsSinceAnchor;

  /// Rows dated the same day as the anchor observation.
  ///
  /// ── An approximation, reported rather than hidden ─────────────────────────
  ///
  /// A statement line carries a DATE and no time, so a row dated the same day
  /// as the anchor could have happened either side of it. Counting it risks
  /// double-counting something the anchor balance already included; excluding
  /// it risks missing genuine same-day activity. Both produce a phantom gap,
  /// just with opposite signs.
  ///
  /// They are counted, because an observation at 09:00 genuinely precedes a
  /// purchase at 15:00 and that is the commoner case. But the count is surfaced
  /// so a caller can say "the 12 BHD gap may be these two same-day rows"
  /// instead of asserting money went missing.
  ///
  /// Alert-sourced rows have a real timestamp; it is the candidate type that
  /// stores date-only. Widening that would remove this ambiguity entirely.
  final int ambiguousSameDayRows;

  /// True when the gap is small enough to be explained by the ambiguity above.
  bool get gapMayBeSameDayTiming =>
      !reconciled && ambiguousSameDayRows > 0;

  /// Rounded to fils, because a floating-point tail is not a discrepancy.
  bool get reconciled => gap == null || gap!.abs() < 0.005;

  String get verdict {
    if (gap == null) return 'anchored';
    if (reconciled) return 'reconciled';
    return gap! < 0 ? 'unexplained_outflow' : 'unexplained_inflow';
  }
}

class KaiLedgerReconciler {
  /// Reconcile one account.
  ///
  /// [observations] and [rows] may arrive in any order; both are sorted here so
  /// a caller cannot produce a wrong answer by handing them over unsorted.
  static KaiAccountReconciliation? reconcile({
    required String account,
    required List<KaiBalanceObservation> observations,
    required List<KaiCashImportCandidate> rows,
  }) {
    final mine = observations.where((o) => o.account == account).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    if (mine.isEmpty) return null;

    // The anchor is the SECOND-most-recent observation, so the most recent one
    // is left to be checked against. With only one observation there is nothing
    // to check yet and it simply becomes the anchor.
    final anchor = mine.length == 1 ? mine.last : mine[mine.length - 2];
    final latest = mine.length == 1 ? null : mine.last;

    // Rows strictly after the anchor and no later than the observation being
    // checked. A row timestamped after the latest observation belongs to the
    // NEXT interval — counting it here would manufacture a gap that is really
    // just a transaction the bank has not reported a balance for yet.
    final upperBound = latest?.at;
    var movement = 0.0;
    var counted = 0;
    var ambiguous = 0;
    for (final row in rows) {
      final at = _rowDate(row);
      if (at == null) continue;
      if (!at.isAfter(anchor.at)) continue;
      if (upperBound != null && at.isAfter(upperBound)) continue;
      movement += row.direction == KaiCashImportDirection.income
          ? row.amount
          : -row.amount;
      counted++;
      if (_sameDay(at, anchor.at)) ambiguous++;
    }

    final predicted = anchor.balance + movement;
    return KaiAccountReconciliation(
      account: account,
      anchorBalance: anchor.balance,
      anchoredAt: anchor.at,
      movementSinceAnchor: movement,
      predictedBalance: predicted,
      latestObservedBalance: latest?.balance,
      gap: latest == null ? null : latest.balance - predicted,
      rowsSinceAnchor: counted,
      ambiguousSameDayRows: ambiguous,
    );
  }

  /// Every account that has been observed at least once.
  static List<String> accountsIn(List<KaiBalanceObservation> observations) {
    final seen = <String>{};
    for (final o in observations) {
      if (o.account.trim().isNotEmpty) seen.add(o.account);
    }
    final out = seen.toList()..sort();
    return out;
  }

  /// A row's date only counts to the day, because that is all a statement line
  /// carries. Alert-sourced rows are same-day by construction, so this is
  /// lossless for them and merely coarse for imports.
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime? _rowDate(KaiCashImportCandidate row) {
    final parts = row.date.split('-');
    if (parts.length < 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    // End of day: a row dated the same day as an observation is treated as
    // having happened before it. The alternative silently excludes every
    // transaction on the anchor day.
    return DateTime(y, m, d, 23, 59, 59);
  }
}
