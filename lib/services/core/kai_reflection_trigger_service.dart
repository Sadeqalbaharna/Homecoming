// Cheap deterministic gate deciding which lived events deserve reflection.
library;

import 'kai_db.dart';
import 'kai_life_event_service.dart';

enum KaiReflectionTriggerKind {
  correction,
  expectationViolation,
  commitmentOutcome,
  relationshipRupture,
  relationshipRepair,
  repeatedFailure,
  identityRevision,
}

class KaiReflectionCandidate {
  final String id;
  final KaiReflectionTriggerKind kind;
  final List<String> eventIds;
  final double priority;
  final List<String> reasons;
  final int queuedAt;

  const KaiReflectionCandidate({
    required this.id,
    required this.kind,
    required this.eventIds,
    required this.priority,
    required this.reasons,
    required this.queuedAt,
  });

  Map<String, dynamic> toMap() => {
        'kind': kind.name,
        'eventIds': eventIds,
        'priority': priority,
        'reasons': reasons,
        'queuedAt': queuedAt,
        'status': 'pending',
      };

  static KaiReflectionCandidate? fromMap(String id, Object? value) {
    if (value is! Map || value['status'] == 'completed') return null;
    final kinds = KaiReflectionTriggerKind.values.where(
      (candidate) => candidate.name == value['kind'],
    );
    if (kinds.isEmpty) return null;
    final eventIds = value['eventIds'] is List
        ? (value['eventIds'] as List)
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    if (eventIds.isEmpty) return null;
    return KaiReflectionCandidate(
      id: id,
      kind: kinds.first,
      eventIds: eventIds,
      priority: ((value['priority'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
      reasons: value['reasons'] is List
          ? (value['reasons'] as List)
              .map((item) => item.toString())
              .toList(growable: false)
          : const [],
      queuedAt: (value['queuedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

KaiReflectionCandidate? reflectionCandidateFor(
  KaiLifeEvent event, {
  int similarRecentFailures = 0,
}) {
  KaiReflectionTriggerKind? kind;
  var priority = 0.0;
  final reasons = <String>[];
  switch (event.kind) {
    case KaiLifeEventKind.correction:
      kind = KaiReflectionTriggerKind.correction;
      priority = 0.9;
      reasons.add('a confident belief or explanation was corrected');
      break;
    case KaiLifeEventKind.expectation:
      return null; // reflect only after an outcome exists
    case KaiLifeEventKind.commitmentBroken:
      kind = KaiReflectionTriggerKind.commitmentOutcome;
      priority = 0.92;
      reasons.add('a self-authored commitment was broken');
      break;
    case KaiLifeEventKind.commitmentFulfilled:
      kind = KaiReflectionTriggerKind.commitmentOutcome;
      priority = 0.64;
      reasons.add('a self-authored commitment reached a real outcome');
      break;
    case KaiLifeEventKind.relationshipMoment:
      final rupture = event.tags.contains('rupture');
      final repair = event.tags.contains('repair');
      if (!rupture && !repair) return null;
      kind = rupture
          ? KaiReflectionTriggerKind.relationshipRupture
          : KaiReflectionTriggerKind.relationshipRepair;
      priority = rupture ? 0.9 : 0.78;
      reasons.add(rupture
          ? 'a relationship expectation was ruptured'
          : 'a prior relationship rupture was repaired');
      break;
    case KaiLifeEventKind.identityRevision:
      kind = KaiReflectionTriggerKind.identityRevision;
      priority = 1;
      reasons.add('purpose or identity changed');
      break;
    case KaiLifeEventKind.actionOutcome:
    case KaiLifeEventKind.choice:
      if (event.linkedEventIds.isNotEmpty &&
          event.kind == KaiLifeEventKind.actionOutcome) {
        kind = KaiReflectionTriggerKind.expectationViolation;
        priority = 0.76;
        reasons
            .add('an outcome can now be compared with an earlier expectation');
      } else if (similarRecentFailures >= 3 && event.tags.contains('failure')) {
        kind = KaiReflectionTriggerKind.repeatedFailure;
        priority = 0.84;
        reasons.add('the same failure pattern has recurred');
      } else {
        return null;
      }
      break;
    case KaiLifeEventKind.commitmentMade:
      return null;
  }
  final affectMagnitude =
      event.affectDelta.values.fold<int>(0, (sum, value) => sum + value.abs());
  if (affectMagnitude >= 12) {
    priority = (priority + 0.06).clamp(0, 1);
    reasons.add('the event carried strong affective change');
  }
  return KaiReflectionCandidate(
    id: 'candidate_${event.id}',
    kind: kind,
    eventIds: [event.id, ...event.linkedEventIds],
    priority: priority,
    reasons: reasons,
    queuedAt: event.recordedAt,
  );
}

class KaiReflectionTriggerService {
  KaiReflectionTriggerService._();
  static final KaiReflectionTriggerService instance =
      KaiReflectionTriggerService._();

  String _path(String personaId) => 'kai/$personaId/reflection_queue';

  Future<bool> consider(String personaId, KaiLifeEvent event) async {
    final candidate = reflectionCandidateFor(event);
    if (candidate == null) return false;
    try {
      final ref = KaiDb.instance.ref('${_path(personaId)}/${candidate.id}');
      if ((await ref.get()).exists) return false;
      await ref.set(candidate.toMap());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<KaiReflectionCandidate>> pending(
    String personaId, {
    int limit = 8,
  }) async {
    if (limit <= 0) return const [];
    try {
      final snapshot = await KaiDb.instance.ref(_path(personaId)).get();
      if (snapshot.value is! Map) return const [];
      final out = <KaiReflectionCandidate>[];
      (snapshot.value as Map).forEach((key, value) {
        final candidate = KaiReflectionCandidate.fromMap(key.toString(), value);
        if (candidate != null) out.add(candidate);
      });
      out.sort((a, b) {
        final priority = b.priority.compareTo(a.priority);
        return priority != 0 ? priority : a.queuedAt.compareTo(b.queuedAt);
      });
      return out.take(limit).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> complete(
    String personaId,
    String candidateId,
    String reflectionId,
  ) async {
    try {
      await KaiDb.instance
          .ref('${_path(personaId)}/$candidateId')
          .update({'status': 'completed', 'reflectionId': reflectionId});
    } catch (_) {}
  }
}
