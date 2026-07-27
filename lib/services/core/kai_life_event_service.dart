// Append-only evidence ledger for Kai's lived history.
// Events record what happened; interpretations and identity remain derived.
library;

import 'kai_db.dart';

enum KaiLifeEventKind {
  expectation,
  choice,
  actionOutcome,
  correction,
  commitmentMade,
  commitmentFulfilled,
  commitmentBroken,
  relationshipMoment,
  identityRevision,
}

enum KaiLifeEventSource {
  toolReceipt,
  traceReceipt,
  conversationRecord,
  legacyAdapter,
}

class KaiLifeEvent {
  final String id;
  final KaiLifeEventKind kind;
  final KaiLifeEventSource source;
  final int occurredAt;
  final int recordedAt;
  final String observation;
  final String choice;

  /// The meaningful option Kai did not take. Required before a choice can
  /// count as evidence of an earned value.
  final String foregoneAlternative;

  /// A small, explicit opportunity-cost score (1-10), not emotional intensity.
  final int choiceCost;

  /// Candidate values enacted by this choice; never identity claims by itself.
  final List<String> valueSignals;
  final String outcome;
  final String provisionalMeaning;
  final Map<String, int> affectDelta;

  /// Evidence-backed relationship changes. Kept separate from affect so a
  /// strong mood cannot manufacture closeness or trust.
  final Map<String, int> relationshipDelta;
  final List<String> tags;
  final List<String> evidenceIds;
  final List<String> linkedEventIds;
  final double confidence;

  const KaiLifeEvent({
    required this.id,
    required this.kind,
    required this.source,
    required this.occurredAt,
    required this.recordedAt,
    this.observation = '',
    this.choice = '',
    this.foregoneAlternative = '',
    this.choiceCost = 0,
    this.valueSignals = const [],
    this.outcome = '',
    this.provisionalMeaning = '',
    this.affectDelta = const {},
    this.relationshipDelta = const {},
    this.tags = const [],
    this.evidenceIds = const [],
    this.linkedEventIds = const [],
    this.confidence = 0,
  });

  Map<String, dynamic> toMap() => {
        'kind': kind.name,
        'source': source.name,
        'occurredAt': occurredAt,
        'recordedAt': recordedAt,
        'observation': observation,
        'choice': choice,
        'foregoneAlternative': foregoneAlternative,
        'choiceCost': choiceCost,
        'valueSignals': valueSignals,
        'outcome': outcome,
        'provisionalMeaning': provisionalMeaning,
        'affectDelta': affectDelta,
        'relationshipDelta': relationshipDelta,
        'tags': tags,
        'evidenceIds': evidenceIds,
        'linkedEventIds': linkedEventIds,
        'confidence': confidence,
        'schemaVersion': 1,
      };

  static KaiLifeEvent? fromMap(String id, Object? value) {
    if (value is! Map) return null;
    final kind = KaiLifeEventKind.values.where(
      (candidate) => candidate.name == value['kind'],
    );
    final source = KaiLifeEventSource.values.where(
      (candidate) => candidate.name == value['source'],
    );
    if (kind.isEmpty || source.isEmpty) return null;
    return KaiLifeEvent(
      id: id,
      kind: kind.first,
      source: source.first,
      occurredAt: (value['occurredAt'] as num?)?.toInt() ?? 0,
      recordedAt: (value['recordedAt'] as num?)?.toInt() ?? 0,
      observation: (value['observation'] as String?)?.trim() ?? '',
      choice: (value['choice'] as String?)?.trim() ?? '',
      foregoneAlternative:
          (value['foregoneAlternative'] as String?)?.trim() ?? '',
      choiceCost: ((value['choiceCost'] as num?)?.toInt() ?? 0).clamp(0, 10),
      valueSignals: _strings(value['valueSignals']),
      outcome: (value['outcome'] as String?)?.trim() ?? '',
      provisionalMeaning:
          (value['provisionalMeaning'] as String?)?.trim() ?? '',
      affectDelta: _intMap(value['affectDelta']),
      relationshipDelta: _intMap(value['relationshipDelta']),
      tags: _strings(value['tags']),
      evidenceIds: _strings(value['evidenceIds']),
      linkedEventIds: _strings(value['linkedEventIds']),
      confidence:
          ((value['confidence'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
    );
  }

  static Map<String, int> _intMap(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        entry.key.toString(): (entry.value as num?)?.toInt() ?? 0,
    };
  }

  static List<String> _strings(Object? value) => value is List
      ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false)
      : const [];
}

class KaiLifeEventAdmission {
  final bool admitted;
  final String reason;

  const KaiLifeEventAdmission._(this.admitted, this.reason);
  const KaiLifeEventAdmission.admitted() : this._(true, 'admitted');
  const KaiLifeEventAdmission.refused(String reason) : this._(false, reason);
}

KaiLifeEventAdmission admitKaiLifeEvent(KaiLifeEvent event) {
  if (!RegExp(r'^[A-Za-z0-9_-]{3,120}$').hasMatch(event.id)) {
    return const KaiLifeEventAdmission.refused('invalid event id');
  }
  if (event.occurredAt <= 0 || event.recordedAt < event.occurredAt) {
    return const KaiLifeEventAdmission.refused('invalid event time');
  }
  if (event.observation.trim().isEmpty &&
      event.choice.trim().isEmpty &&
      event.outcome.trim().isEmpty) {
    return const KaiLifeEventAdmission.refused('event contains no experience');
  }
  if (event.evidenceIds.isEmpty ||
      event.evidenceIds.any((id) => !_trustedEvidence(id))) {
    return const KaiLifeEventAdmission.refused('trusted evidence is required');
  }
  if (event.confidence < 0.2 || event.confidence > 1) {
    return const KaiLifeEventAdmission.refused('confidence is not admissible');
  }
  if (event.kind == KaiLifeEventKind.expectation && event.outcome.isNotEmpty) {
    return const KaiLifeEventAdmission.refused(
      'expectation cannot contain its future outcome',
    );
  }
  if ((event.kind == KaiLifeEventKind.actionOutcome ||
          event.kind == KaiLifeEventKind.commitmentFulfilled ||
          event.kind == KaiLifeEventKind.commitmentBroken) &&
      event.outcome.trim().length < 8) {
    return const KaiLifeEventAdmission.refused('outcome evidence is too thin');
  }
  if (event.relationshipDelta.isNotEmpty) {
    const allowed = {
      'familiarity',
      'epistemicTrust',
      'emotionalSafety',
      'reciprocity',
      'repairConfidence',
    };
    if (event.kind != KaiLifeEventKind.relationshipMoment ||
        event.relationshipDelta.keys.any((key) => !allowed.contains(key)) ||
        event.relationshipDelta.values
            .any((value) => value == 0 || value.abs() > 5)) {
      return const KaiLifeEventAdmission.refused(
        'relationship change is not admissible',
      );
    }
  }
  return const KaiLifeEventAdmission.admitted();
}

bool _trustedEvidence(String id) =>
    id.startsWith('tool:') ||
    id.startsWith('trace:') ||
    id.startsWith('conversation:') ||
    id.startsWith('legacy:');

KaiLifeEvent lifeEventFromLegacyAutobiography({
  required String legacyKind,
  required String storageId,
  required String choice,
  required String outcome,
  required String meaning,
  required List<String> evidenceIds,
  required double confidence,
  required int occurredAt,
  required int recordedAt,
}) {
  final kind = switch (legacyKind) {
    'commitment' => KaiLifeEventKind.commitmentMade,
    'identityRevision' => KaiLifeEventKind.identityRevision,
    'correctedBelief' => KaiLifeEventKind.correction,
    _ => KaiLifeEventKind.actionOutcome,
  };
  final source = evidenceIds.any((id) => id.startsWith('tool:'))
      ? KaiLifeEventSource.toolReceipt
      : KaiLifeEventSource.traceReceipt;
  return KaiLifeEvent(
    id: 'autobiography_$storageId',
    kind: kind,
    source: source,
    occurredAt: occurredAt,
    recordedAt: recordedAt < occurredAt ? occurredAt : recordedAt,
    observation: outcome,
    choice: choice,
    outcome: outcome,
    provisionalMeaning: meaning,
    evidenceIds: evidenceIds,
    linkedEventIds: const [],
    confidence: confidence,
    tags: [legacyKind],
  );
}

class KaiLifeEventService {
  KaiLifeEventService._();
  static final KaiLifeEventService instance = KaiLifeEventService._();

  String _path(String personaId) => 'kai/$personaId/life_events';

  /// Immutable by contract: an existing event id is never overwritten.
  Future<KaiLifeEventAdmission> append(
    String personaId,
    KaiLifeEvent event,
  ) async {
    final admission = admitKaiLifeEvent(event);
    if (!admission.admitted) return admission;
    try {
      final ref = KaiDb.instance.ref('${_path(personaId)}/${event.id}');
      if ((await ref.get()).exists) {
        return const KaiLifeEventAdmission.refused('event already exists');
      }
      await ref.set(event.toMap());
      return const KaiLifeEventAdmission.admitted();
    } catch (_) {
      return const KaiLifeEventAdmission.refused('persistence failed');
    }
  }

  Future<List<KaiLifeEvent>> recent(String personaId, {int limit = 30}) async {
    if (limit <= 0) return const [];
    try {
      final snapshot =
          await KaiDb.instance.ref(_path(personaId)).limitToLast(limit).get();
      if (snapshot.value is! Map) return const [];
      final out = <KaiLifeEvent>[];
      (snapshot.value as Map).forEach((key, value) {
        final event = KaiLifeEvent.fromMap(key.toString(), value);
        if (event != null && admitKaiLifeEvent(event).admitted) out.add(event);
      });
      out.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return out.take(limit).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
