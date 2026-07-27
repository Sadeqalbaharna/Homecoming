// Kai's own episodes: choices he made, what followed, and what they meant.
// Facts about Sadeq and the world stay in the knowledge graph.
library;

import 'kai_db.dart';
import 'kai_self_provenance.dart';
import 'kai_life_event_service.dart';
import 'kai_reflection_trigger_service.dart';
import 'kai_reflection_experiment_service.dart';

enum AutobiographicalEpisodeKind {
  commitment,
  identityRevision,
  completedAction,
  correctedBelief,
}

class AutobiographicalEpisode {
  final String id;
  final AutobiographicalEpisodeKind kind;
  final String choice;
  final String outcome;
  final String meaning;
  final SelfProvenance provenance;
  final int occurredAt;

  const AutobiographicalEpisode({
    required this.id,
    required this.kind,
    required this.choice,
    required this.outcome,
    required this.meaning,
    required this.provenance,
    required this.occurredAt,
  });

  bool get isGrounded => provenance.isGrounded;

  Map<String, dynamic> toMap() => {
        'kind': kind.name,
        'choice': choice,
        'outcome': outcome,
        'meaning': meaning,
        'evidenceIds': provenance.evidenceIds,
        'confidence': provenance.confidence,
        'occurredAt': occurredAt,
      };

  static AutobiographicalEpisode? fromMap(String id, Object? value) {
    if (value is! Map) return null;
    final choice = (value['choice'] as String?)?.trim() ?? '';
    final outcome = (value['outcome'] as String?)?.trim() ?? '';
    if (choice.isEmpty || outcome.isEmpty) return null;
    final evidence = (value['evidenceIds'] is List)
        ? (value['evidenceIds'] as List)
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    final kind = AutobiographicalEpisodeKind.values.firstWhere(
      (candidate) => candidate.name == value['kind'],
      orElse: () => AutobiographicalEpisodeKind.completedAction,
    );
    return AutobiographicalEpisode(
      id: id,
      kind: kind,
      choice: choice,
      outcome: outcome,
      meaning: (value['meaning'] as String?)?.trim() ?? '',
      provenance: SelfProvenance(
        source: evidence.isEmpty
            ? SelfClaimSource.persistedLegacy
            : SelfClaimSource.groundedRecord,
        evidenceIds: evidence,
        confidence:
            ((value['confidence'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
        recordedAt: (value['occurredAt'] as num?)?.toInt() ?? 0,
      ),
      occurredAt: (value['occurredAt'] as num?)?.toInt() ?? 0,
    );
  }
}

bool isAdmissibleEpisode(AutobiographicalEpisode episode) {
  if (episode.choice.trim().length < 8) return false;
  if (episode.outcome.trim().length < 8) return false;
  if (episode.occurredAt <= 0) return false;
  if (!episode.isGrounded) return false;
  return episode.provenance.evidenceIds.every(
    (id) => id.startsWith('tool:') || id.startsWith('trace:'),
  );
}

class KaiAutobiographyService {
  KaiAutobiographyService._();
  static final KaiAutobiographyService instance = KaiAutobiographyService._();

  String _path(String personaId) => 'kai/$personaId/autobiography';

  Future<bool> record(
    String personaId,
    AutobiographicalEpisode episode,
  ) async {
    if (!isAdmissibleEpisode(episode)) return false;
    try {
      final existing = await recent(personaId, limit: 30);
      final evidenceKey = episode.provenance.evidenceIds.join('|');
      if (existing.any(
        (item) => item.provenance.evidenceIds.join('|') == evidenceKey,
      )) {
        return false;
      }
      final storageId = DateTime.now().microsecondsSinceEpoch.toString();
      await KaiDb.instance
          .ref('${_path(personaId)}/$storageId')
          .set(episode.toMap());
      // Transitional dual-write. The old autobiography remains readable while
      // the append-only ledger becomes canonical. Failure here never destroys
      // the already-admitted episode and can be repaired by backfill.
      final lifeEvent = lifeEventFromLegacyAutobiography(
        legacyKind: episode.kind.name,
        storageId: storageId,
        choice: episode.choice,
        outcome: episode.outcome,
        meaning: episode.meaning,
        evidenceIds: episode.provenance.evidenceIds,
        confidence: episode.provenance.confidence,
        occurredAt: episode.occurredAt,
        recordedAt: episode.provenance.recordedAt,
      );
      final lifeAdmission =
          await KaiLifeEventService.instance.append(personaId, lifeEvent);
      if (lifeAdmission.admitted) {
        await KaiReflectionTriggerService.instance
            .consider(personaId, lifeEvent);
        await KaiReflectionExperimentService.instance
            .considerOutcome(personaId, lifeEvent);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<AutobiographicalEpisode>> recent(
    String personaId, {
    int limit = 4,
  }) async {
    if (limit <= 0) return const [];
    try {
      final snapshot =
          await KaiDb.instance.ref(_path(personaId)).limitToLast(limit).get();
      final value = snapshot.value;
      if (value is! Map) return const [];
      final episodes = <AutobiographicalEpisode>[];
      value.forEach((key, row) {
        final episode = AutobiographicalEpisode.fromMap(key.toString(), row);
        if (episode != null && episode.isGrounded) episodes.add(episode);
      });
      episodes.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return episodes.take(limit).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Idempotent migration adapter. Existing autobiography remains untouched;
  /// append() refuses an already-migrated deterministic event id.
  Future<int> backfillLifeLedger(
    String personaId, {
    int limit = 200,
  }) async {
    var migrated = 0;
    for (final episode in await recent(personaId, limit: limit)) {
      if (episode.id.isEmpty) continue;
      final admission = await KaiLifeEventService.instance.append(
        personaId,
        lifeEventFromLegacyAutobiography(
          legacyKind: episode.kind.name,
          storageId: episode.id,
          choice: episode.choice,
          outcome: episode.outcome,
          meaning: episode.meaning,
          evidenceIds: episode.provenance.evidenceIds,
          confidence: episode.provenance.confidence,
          occurredAt: episode.occurredAt,
          recordedAt: episode.provenance.recordedAt,
        ),
      );
      if (admission.admitted) migrated++;
    }
    return migrated;
  }
}
