// ledger_identity — one payment, however many times the bank mentions it.
//
// ── The problem two channels create ─────────────────────────────────────────
//
// Al Salam sends a Transaction Notification by EMAIL and the same bank texts an
// SMS. Both describe one payment. The candidate fingerprint includes the source
// — "alert:no-reply@alsalambank.com" versus "alert:ALSALAM" — so the same
// money produces two different fingerprints and two ledger rows. Every
// transaction doubled, and the reconciler would then report a gap the size of
// the whole day's spending.
//
// ── Why the obvious key is dangerous ────────────────────────────────────────
//
// The tempting key is date + amount + merchant. From Sadeq's actual inbox:
//
//   BHD 1.500 at THE COFFEE BEAN TEA ... Bal: BHD 330.732 on 08/08 at 10:40
//   BHD 1.500 at THE COFFEE BEAN TEA ... Bal: BHD 329.232 on 08/08 at 12:06
//
// Two genuine coffees, same amount, same merchant, same day. That key would
// merge them and silently eat 1.500 BHD — and silent loss is the exact failure
// this whole ledger path exists to prevent. Over-deduplication is worse than
// under-deduplication: a double row is visible and correctable, a missing one
// looks like it never happened.
//
// ── What actually distinguishes a payment ───────────────────────────────────
//
// The BALANCE AFTER. It is unique per movement on an account by construction —
// two payments cannot leave the same account at the same balance — and both the
// SMS and the email about one payment quote the SAME resulting balance, because
// they are describing the same ledger event at the bank.
//
// So: account + balance-after is the identity, with amount and direction as
// corroboration. Not the channel, not the wording, not the time the message
// happened to arrive.
//
// When an alert carries no balance, there is no safe identity and the row keeps
// its own. A possible duplicate is left for a human rather than guessed at.
//
// Pure and deterministic.

import '../services/core/kai_cash_statement_parser.dart';

/// The identity of a payment, independent of which pipe reported it.
class KaiTransactionIdentity {
  const KaiTransactionIdentity._(this.key, this.confident);

  /// Stable across channels. Empty when no identity could be established.
  final String key;

  /// True when the identity rests on a balance the bank stated. False means
  /// the row is only identified by its own contents, so a cross-channel
  /// duplicate cannot be detected and must not be assumed away.
  final bool confident;

  static const none = KaiTransactionIdentity._('', false);

  /// Build from what an alert reported.
  ///
  /// [account] and [balanceAfter] come from the bank's own words. Amount and
  /// direction corroborate: if two alerts agree on the account and resulting
  /// balance but disagree on the amount, something is wrong and they should NOT
  /// collapse into one row.
  static KaiTransactionIdentity of({
    required String? account,
    required double? balanceAfter,
    required double amount,
    required KaiCashImportDirection direction,
  }) {
    final acct = account?.trim() ?? '';
    if (acct.isEmpty || acct == 'unknown' || balanceAfter == null) {
      return none;
    }
    // Fils precision. A balance is money, not a float, and 330.7200000001 is
    // the same balance as 330.720.
    final bal = balanceAfter.toStringAsFixed(3);
    final amt = amount.toStringAsFixed(3);
    return KaiTransactionIdentity._(
      '$acct|$bal|$amt|${direction.name}',
      true,
    );
  }
}

/// Collapses alerts that describe the same payment, however they arrived.
class KaiLedgerDeduper {
  final Map<String, String> _identityToRow = {};
  final Set<String> _rowFingerprints = <String>{};

  /// Register a candidate. Returns true when it is new and should be recorded.
  ///
  /// Two independent guards, because they catch different failures:
  ///
  ///   * IDENTITY catches the same payment arriving by SMS and by email. It
  ///     needs the bank's balance and is skipped when there isn't one.
  ///   * FINGERPRINT catches the same MESSAGE arriving twice — Android
  ///     redelivering a notification, or a drain retried after a failed write.
  ///     It always applies.
  ///
  /// An alert with no balance therefore still gets duplicate protection against
  /// itself, just not across channels. That is the honest limit: it will show
  /// two rows rather than quietly show one.
  bool admit(KaiCashImportCandidate candidate, KaiTransactionIdentity identity) {
    // Identity first. Adding the fingerprint before this check recorded the
    // rejected duplicate anyway, so `recorded` counted rows that were never
    // admitted — a counter that disagrees with the ledger it describes.
    if (identity.confident && _identityToRow.containsKey(identity.key)) {
      return false;
    }
    if (!_rowFingerprints.add(candidate.fingerprint)) return false;
    if (identity.confident) _identityToRow[identity.key] = candidate.fingerprint;
    return true;
  }

  /// Whether this payment has already been recorded under any channel.
  bool hasSeen(KaiTransactionIdentity identity) =>
      identity.confident && _identityToRow.containsKey(identity.key);

  int get recorded => _rowFingerprints.length;
}
