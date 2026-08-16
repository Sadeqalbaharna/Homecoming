/// KaiLedgerPipeline — the pipes between the phone and the ledger.
///
/// Everything either side of this already existed and could not reach the
/// other: the Android listener captures enrolled bank alerts into a durable
/// queue, and `KaiPersonalCashStore` holds the ledger. Nothing joined them.
///
/// ── What this owns, and deliberately does not ───────────────────────────────
///
/// It owns SEQUENCE: push the enrolment list down, drain the queue, ingest,
/// deduplicate, append, save. Every decision inside those steps belongs to the
/// pure units — `KaiLedgerSources` decides who may be read, `KaiLedgerIngest`
/// decides what a message means, `KaiLedgerDeduper` decides whether it is new.
/// This file must stay boring enough that a bug in it is obvious.
///
/// ── Two properties that matter more than throughput ─────────────────────────
///
/// Nothing lands approved unless a rule Sadeq wrote says so. Everything else
/// appends as `approved: false` — present in the ledger, visible, waiting. A
/// pending row that is dropped makes an incomplete ledger look complete, which
/// is the failure this whole path exists to prevent.
///
/// A failed drain is not an empty drain. If the phone refuses, the queue is
/// still on the phone, and reporting zero would be a lie shaped like good news.
library;

import 'dart:async';

import '../../logic/ledger_identity.dart';
import '../../logic/ledger_ingest.dart';
import '../../logic/ledger_sources.dart';
import 'kai_cash_statement_parser.dart';

/// One run, summarised. Counts and reason codes only — this is what gets
/// logged, and a journal may not hold the contents of an SMS.
class KaiLedgerRun {
  const KaiLedgerRun({
    required this.drained,
    required this.appended,
    required this.autoApproved,
    required this.duplicates,
    required this.unreadable,
    required this.reasons,
    this.failure,
  });

  final int drained;
  final int appended;
  final int autoApproved;
  final int duplicates;
  final int unreadable;
  final Map<String, int> reasons;

  /// Set when the drain itself failed. Distinct from `drained == 0`, which
  /// means the phone had nothing.
  final String? failure;

  bool get ok => failure == null;

  Map<String, dynamic> toJson() => {
        'drained': drained,
        'appended': appended,
        'autoApproved': autoApproved,
        'duplicates': duplicates,
        'unreadable': unreadable,
        'reasons': reasons,
        if (failure != null) 'failure': failure,
      };
}

/// A ledger row, in the shape the pipeline hands over.
///
/// Kept as a plain record so this file does not import the 3,900-line card
/// widget. The caller adapts it to `KaiCashTransaction`, which owns its own id
/// scheme and month bucketing.
class KaiLedgerRow {
  const KaiLedgerRow({
    required this.candidate,
    required this.approved,
    required this.balance,
  });

  final KaiCashImportCandidate candidate;

  /// True only when an enrolled sender met a rule Sadeq wrote.
  final bool approved;

  /// What the bank said the balance was afterwards, when it said. This is what
  /// lets the ledger check itself later; without it a row is still a row, just
  /// not one that can prove anything.
  final KaiBalanceReading? balance;
}

class KaiLedgerPipeline {
  KaiLedgerPipeline({
    required this.sources,
    required this.rules,
    required this.pushSenders,
    required this.drainAlerts,
    required this.append,
  });

  final KaiLedgerSources sources;
  final List<KaiAutoConfirmRule> rules;

  /// Sends the enrolment list to the phone's capture filter.
  ///
  /// Called before every drain, not once at startup: the phone's copy is
  /// persisted and could be stale from an older build, and re-pushing an
  /// unchanged list costs nothing. Dart owns the list; the phone holds a copy.
  final Future<void> Function(List<String> senders) pushSenders;

  final Future<List<Map<String, Object?>>> Function() drainAlerts;

  /// Where accepted rows go. Called for approved AND pending.
  final Future<void> Function(List<KaiLedgerRow> rows) append;

  /// Survives across runs so a drain that succeeded on the phone but failed on
  /// the way to storage cannot double-post when it is retried.
  final KaiLedgerDeduper _deduper = KaiLedgerDeduper();

  Future<KaiLedgerRun> runOnce() async {
    // An empty registry reads nothing. Pushing that down explicitly matters:
    // it is also how revocation reaches the phone.
    await pushSenders(sources.smsFilter);

    final List<Map<String, Object?>> raw;
    try {
      raw = await drainAlerts();
    } catch (error) {
      return KaiLedgerRun(
        drained: 0,
        appended: 0,
        autoApproved: 0,
        duplicates: 0,
        unreadable: 0,
        reasons: const {},
        failure: error.runtimeType.toString(),
      );
    }

    final ingest = KaiLedgerIngest(
      // The phone filtered on its copy of the list; this filters on the
      // authority. Two layers with different jobs, not redundancy: the phone
      // keeps junk out of its durable queue, and this decides confirmation.
      trustedSenders:
          sources.smsFilter.map((s) => s.toUpperCase()).toSet(),
      rules: rules,
    );

    final rows = <KaiLedgerRow>[];
    final reasons = <String, int>{};
    var duplicates = 0;
    var unreadable = 0;
    var autoApproved = 0;

    for (final entry in raw) {
      final alert = _toAlert(entry);
      if (alert == null) {
        unreadable++;
        reasons['malformed_alert'] = (reasons['malformed_alert'] ?? 0) + 1;
        continue;
      }

      final outcome = ingest.ingest(alert);
      reasons[outcome.reasonCode] = (reasons[outcome.reasonCode] ?? 0) + 1;

      final candidate = outcome.candidate;
      if (candidate == null) {
        unreadable++;
        continue;
      }

      final balance = KaiLedgerIngest.readBalance(alert);
      final identity = KaiTransactionIdentity.of(
        account: balance?.account,
        balanceAfter: balance?.balance,
        amount: candidate.amount,
        direction: candidate.direction,
      );

      if (!_deduper.admit(candidate, identity)) {
        duplicates++;
        reasons['duplicate'] = (reasons['duplicate'] ?? 0) + 1;
        continue;
      }

      if (outcome.autoConfirmed) autoApproved++;
      rows.add(KaiLedgerRow(
        candidate: candidate,
        approved: outcome.autoConfirmed,
        balance: balance,
      ));
    }

    // One append for the whole run, so a ledger is never observed half-written.
    if (rows.isNotEmpty) await append(rows);

    return KaiLedgerRun(
      drained: raw.length,
      appended: rows.length,
      autoApproved: autoApproved,
      duplicates: duplicates,
      unreadable: unreadable,
      reasons: reasons,
    );
  }

  /// The sender comes from the notification title, which is spoofable — hence
  /// the enrolment check downstream. Shape errors are refused here.
  static KaiBankAlert? _toAlert(Map<String, Object?> row) {
    final sender = row['sender']?.toString().trim() ?? '';
    final text = row['text']?.toString() ?? '';
    final millis = row['receivedAt'];
    if (sender.isEmpty || text.trim().isEmpty) return null;
    if (millis is! num) return null;
    return KaiBankAlert(
      sender: sender,
      body: text,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(millis.toInt()),
    );
  }
}
