/// KaiBankAlertService — drains the phone's bank-alert queue into the ledger.
///
/// The Android half captures enrolled senders at arrival into a durable,
/// append-only queue, because the ordinary notification store keeps twenty per
/// app in memory and a ledger cannot be lossy. This half drains that queue and
/// runs each alert through [KaiLedgerIngest].
///
/// ── Where the boundaries are ────────────────────────────────────────────────
///
/// Kotlin catches and keeps. It does not interpret: no amounts, no direction,
/// no merchant. All of that is pure Dart, so the rules that decide what enters
/// a ledger can be tested without a phone in the room.
///
/// Dart decides but does not trust. The sender arrives from the notification's
/// own title, which is spoofable, so the enrolment check runs again here. Two
/// layers agreeing is not redundancy — the Kotlin list keeps junk out of the
/// durable queue, and the Dart list is what actually gates confirmation.
library;

import 'dart:async';

import '../../logic/ledger_ingest.dart';
import 'kai_cash_statement_parser.dart';

/// One drain, summarised. Never carries message text — this is what gets
/// logged, and an operations journal is not allowed to hold an SMS.
class KaiBankAlertDrain {
  const KaiBankAlertDrain({
    required this.seen,
    required this.confirmed,
    required this.pending,
    required this.unparsed,
    required this.reasons,
  });

  final int seen;
  final int confirmed;
  final int pending;
  final int unparsed;

  /// reasonCode → count. Says WHY rows did not land without saying what they
  /// were, so a ledger that is missing something can still explain itself.
  final Map<String, int> reasons;

  Map<String, dynamic> toJson() => {
        'seen': seen,
        'confirmed': confirmed,
        'pending': pending,
        'unparsed': unparsed,
        'reasons': reasons,
      };
}

/// What the platform hands back. Kept as its own type so the pure path can be
/// exercised with a list literal instead of a MethodChannel.
typedef KaiRawAlert = Map<String, Object?>;

class KaiBankAlertService {
  KaiBankAlertService({
    required this.ingest,
    required this.drainAlerts,
    required this.onCandidate,
  });

  final KaiLedgerIngest ingest;

  /// Supplied by the caller so this class never touches a platform channel
  /// directly, and so tests are a one-line fake.
  final Future<List<KaiRawAlert>> Function() drainAlerts;

  /// Where an accepted row goes. Called for confirmed AND pending candidates —
  /// a pending row still belongs in the ledger, unselected, waiting. Dropping
  /// it would make an incomplete ledger look complete.
  final Future<void> Function(KaiCashImportCandidate candidate, bool confirmed)
      onCandidate;

  /// Fingerprints already handed on. Guards the one case clear-on-read cannot:
  /// a drain that succeeded on the phone and failed on the way to storage, then
  /// retried.
  final Set<String> _seenFingerprints = <String>{};

  Future<KaiBankAlertDrain> drainOnce() async {
    final List<KaiRawAlert> raw;
    try {
      raw = await drainAlerts();
    } catch (error) {
      // A failed drain is not an empty drain. The queue is still on the phone;
      // saying "0 alerts" here would be a lie that looks like good news.
      return const KaiBankAlertDrain(
        seen: 0,
        confirmed: 0,
        pending: 0,
        unparsed: 0,
        reasons: {'drain_failed': 1},
      );
    }

    var confirmed = 0;
    var pending = 0;
    var unparsed = 0;
    final reasons = <String, int>{};

    for (final row in raw) {
      final alert = _toAlert(row);
      if (alert == null) {
        unparsed++;
        reasons['malformed_alert'] = (reasons['malformed_alert'] ?? 0) + 1;
        continue;
      }

      final outcome = ingest.ingest(alert);
      reasons[outcome.reasonCode] = (reasons[outcome.reasonCode] ?? 0) + 1;

      final candidate = outcome.candidate;
      if (candidate == null) {
        unparsed++;
        continue;
      }
      if (!_seenFingerprints.add(candidate.fingerprint)) {
        reasons['duplicate'] = (reasons['duplicate'] ?? 0) + 1;
        continue;
      }

      await onCandidate(candidate, outcome.autoConfirmed);
      if (outcome.autoConfirmed) {
        confirmed++;
      } else {
        pending++;
      }
    }

    return KaiBankAlertDrain(
      seen: raw.length,
      confirmed: confirmed,
      pending: pending,
      unparsed: unparsed,
      reasons: reasons,
    );
  }

  static KaiBankAlert? _toAlert(KaiRawAlert row) {
    final sender = row['sender']?.toString().trim() ?? '';
    final text = row['text']?.toString() ?? '';
    final millis = row['receivedAt'];
    if (sender.isEmpty || text.trim().isEmpty) return null;
    final at = millis is int
        ? DateTime.fromMillisecondsSinceEpoch(millis)
        : millis is num
            ? DateTime.fromMillisecondsSinceEpoch(millis.toInt())
            : null;
    if (at == null) return null;
    return KaiBankAlert(sender: sender, body: text, receivedAt: at);
  }
}
