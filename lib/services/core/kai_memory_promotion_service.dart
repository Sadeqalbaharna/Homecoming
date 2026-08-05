// kai_memory_promotion_service.dart — legacy memory triage, dry-run first.
//
// ── What this does and what it refuses to do ────────────────────────────────
//
// Memories written before scoping existed parse as `legacyUnscoped` and are
// visible only to trusted desktop/mobile. Correct, and it leaves Messenger Kai
// with almost no history. This service triages that backlog.
//
// It NEVER mutates or deletes a source row. Not once, not "just the scope
// field", not behind a flag. Every output is a NEW record in a SEPARATE tree:
//
//     memory/embeddings/{persona}/{id}    ← read only, always
//     memory/promotions/{persona}/{id}    ← everything this service writes
//
// Rollback is therefore "delete the promotions tree" — one operation, no
// reconstruction, no backup to restore. That property is the whole design, and
// it is why there is no `mutateScope` method here to be tempted by later.
//
// ── Why proposals are not applications ──────────────────────────────────────
//
// The deterministic prefilter only ever NARROWS (see memory_classifier.dart):
// it can say "this is unmistakably technical", never "this is personal". So the
// only thing this service can conclude on its own is that a memory should be
// hidden from friend surfaces — which cannot leak, and is safe to apply.
//
// WIDENING a legacy row to relationship/sharedLife is the operation that
// exposes it to Messenger, and nothing here does it. Those rows come back as
// `unclear` and stay legacyUnscoped until a human or a reviewed model pass
// decides. A memory recalled in the wrong room cannot be un-recalled.
//
// ── Reading the report ──────────────────────────────────────────────────────
//
// `unclear` being the largest bucket is the EXPECTED outcome, not a failure.
// The prefilter exists to remove the obvious cheaply so a model pass has a
// smaller, more ambiguous pile to work on — and the report tells you whether
// that model pass is even worth building.
//
// The gate before anything is applied is the sample in [MemoryTriageReport.
// technicalSamples] read by eye, not the counts. Confidence numbers are the
// classifier grading its own homework.

import '../../logic/memory_classifier.dart';
import 'kai_db.dart';
import 'kai_memory_types.dart';

class MemoryTriageEntry {
  const MemoryTriageEntry({
    required this.shardId,
    required this.summary,
    required this.verdict,
    required this.reason,
    required this.signals,
  });

  final String shardId;
  final String summary;
  final MemoryPrefilterVerdict verdict;
  final String reason;
  final List<String> signals;

  /// The proposal record. `provenance: promoted` and `sourceShardId` are what
  /// make this traceable back to the row it describes — and what let a reader
  /// tell a proposal from an original at a glance.
  Map<String, dynamic> toProposal({required int nowMs}) => {
        'sourceShardId': shardId,
        'proposedScope': KaiMemoryScope.privateCore.name,
        'provenance': KaiMemoryProvenance.promoted.name,
        'reason': reason,
        'signals': signals,
        'classifierVersion': kMemoryClassifierVersion,
        'status': 'proposed',
        'createdAt': nowMs,
      };
}

class MemoryTriageReport {
  const MemoryTriageReport({
    required this.totalRows,
    required this.legacyRows,
    required this.technical,
    required this.unclear,
    required this.proposalsWritten,
  });

  /// Every row in the embeddings tree, scoped or not.
  final int totalRows;

  /// Rows parsing as legacyUnscoped — the only ones this service considers.
  final int legacyRows;

  final List<MemoryTriageEntry> technical;
  final List<MemoryTriageEntry> unclear;

  /// Zero on a dry run, by construction.
  final int proposalsWritten;

  /// A handful of technical calls to read by eye. This is the actual gate.
  List<MemoryTriageEntry> get technicalSamples => technical.take(10).toList();

  String summarize() {
    final buffer = StringBuffer()
      ..writeln('Legacy memory triage (classifier v$kMemoryClassifierVersion)')
      ..writeln('  rows total:        $totalRows')
      ..writeln('  legacyUnscoped:    $legacyRows')
      ..writeln('  → technical:       ${technical.length} '
          '(would narrow to privateCore)')
      ..writeln('  → unclear:         ${unclear.length} '
          '(stay legacyUnscoped — needs a human or a model pass)')
      ..writeln('  proposals written: $proposalsWritten');

    if (technicalSamples.isNotEmpty) {
      buffer
          .writeln('\n  Sample technical calls — read these before applying:');
      for (final entry in technicalSamples) {
        final clipped = entry.summary.length > 90
            ? '${entry.summary.substring(0, 90)}…'
            : entry.summary;
        buffer.writeln('    • [${entry.reason}] $clipped');
      }
    }
    return buffer.toString();
  }
}

/// Bump when the signal lists change, so proposals from an older pass are
/// distinguishable from a newer one rather than silently comparable.
const int kMemoryClassifierVersion = 1;

class KaiMemoryPromotionService {
  KaiMemoryPromotionService._();
  static final KaiMemoryPromotionService instance =
      KaiMemoryPromotionService._();

  /// Classify the legacy backlog.
  ///
  /// [dryRun] defaults to TRUE and must be passed `false` explicitly. A triage
  /// pass whose default writes is one accidental invocation away from a
  /// migration nobody reviewed.
  ///
  /// Even with `dryRun: false`, this writes only to `memory/promotions/…` —
  /// source rows are untouched in every mode.
  Future<MemoryTriageReport> triage(
    String personaId, {
    bool dryRun = true,
    Map<String, dynamic>? rowsForTest,
  }) async {
    final rows = rowsForTest ?? await _loadRows(personaId);

    final technical = <MemoryTriageEntry>[];
    final unclear = <MemoryTriageEntry>[];
    var legacyRows = 0;

    rows.forEach((shardId, raw) {
      if (raw is! Map) return;

      // Only legacy rows are in scope. An already-classified memory is somebody
      // else's decision and this pass does not revisit it.
      if (parseKaiMemoryScope(raw['scope']) != KaiMemoryScope.legacyUnscoped) {
        return;
      }
      legacyRows++;

      final summary = raw['summary']?.toString() ?? '';
      final decision = classifyLegacyMemory(summary);
      final entry = MemoryTriageEntry(
        shardId: shardId,
        summary: summary,
        verdict: decision.verdict,
        reason: decision.reason,
        signals: decision.signals,
      );

      if (decision.isTechnical) {
        technical.add(entry);
      } else {
        unclear.add(entry);
      }
    });

    var written = 0;
    if (!dryRun && technical.isNotEmpty) {
      written = await _writeProposals(personaId, technical);
    }

    return MemoryTriageReport(
      totalRows: rows.length,
      legacyRows: legacyRows,
      technical: technical,
      unclear: unclear,
      proposalsWritten: written,
    );
  }

  Future<Map<String, dynamic>> _loadRows(String personaId) async {
    try {
      final snap =
          await KaiDb.instance.ref('memory/embeddings/$personaId').get();
      final value = snap.value;
      if (value is! Map) return {};
      return value.map((key, v) => MapEntry(key.toString(), v));
    } catch (e) {
      print('⚠️ [MemoryPromotion] could not read embeddings: $e');
      return {};
    }
  }

  /// Writes proposals only. Keyed by source shard id so a re-run overwrites its
  /// own previous proposal for that row instead of accumulating duplicates.
  Future<int> _writeProposals(
    String personaId,
    List<MemoryTriageEntry> entries,
  ) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var written = 0;
    for (final entry in entries) {
      try {
        await KaiDb.instance
            .ref('memory/promotions/$personaId/${entry.shardId}')
            .set(entry.toProposal(nowMs: nowMs));
        written++;
      } catch (e) {
        print('⚠️ [MemoryPromotion] proposal write failed '
            'for ${entry.shardId}: $e');
      }
    }
    return written;
  }
}
