// Evidence-linked psychological reflection.
// A reflection proposes interpretations; only later events can validate them.
library;

import 'kai_db.dart';
import 'kai_life_event_service.dart';

enum KaiReflectionResolution { supported, revised, rejected }

class KaiReflectionHypothesis {
  final String claim;
  final List<String> evidenceFor;
  final List<String> evidenceAgainst;
  final double confidence;

  const KaiReflectionHypothesis({
    required this.claim,
    this.evidenceFor = const [],
    this.evidenceAgainst = const [],
    required this.confidence,
  });

  Map<String, dynamic> toMap() => {
        'claim': claim,
        'evidenceFor': evidenceFor,
        'evidenceAgainst': evidenceAgainst,
        'confidence': confidence,
      };

  static KaiReflectionHypothesis? fromMap(Object? value) {
    if (value is! Map) return null;
    final claim = (value['claim'] as String?)?.trim() ?? '';
    if (claim.isEmpty) return null;
    return KaiReflectionHypothesis(
      claim: claim,
      evidenceFor: _strings(value['evidenceFor']),
      evidenceAgainst: _strings(value['evidenceAgainst']),
      confidence:
          ((value['confidence'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
    );
  }
}

class KaiStructuredReflection {
  final String id;
  final List<String> eventIds;
  final String expectation;
  final String observedOutcome;
  final String intention;
  final String emotionalInfluence;
  final List<KaiReflectionHypothesis> hypotheses;
  final List<String> uncertainties;
  final String provisionalLesson;
  final String nextExperiment;
  final int createdAt;

  const KaiStructuredReflection({
    required this.id,
    required this.eventIds,
    required this.expectation,
    required this.observedOutcome,
    required this.intention,
    this.emotionalInfluence = '',
    required this.hypotheses,
    this.uncertainties = const [],
    required this.provisionalLesson,
    required this.nextExperiment,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'eventIds': eventIds,
        'expectation': expectation,
        'observedOutcome': observedOutcome,
        'intention': intention,
        'emotionalInfluence': emotionalInfluence,
        'hypotheses': hypotheses.map((item) => item.toMap()).toList(),
        'uncertainties': uncertainties,
        'provisionalLesson': provisionalLesson,
        'nextExperiment': nextExperiment,
        'createdAt': createdAt,
        'schemaVersion': 1,
      };

  static KaiStructuredReflection? fromMap(String id, Object? value) {
    if (value is! Map) return null;
    final hypotheses = value['hypotheses'] is List
        ? (value['hypotheses'] as List)
            .map(KaiReflectionHypothesis.fromMap)
            .whereType<KaiReflectionHypothesis>()
            .toList(growable: false)
        : const <KaiReflectionHypothesis>[];
    return KaiStructuredReflection(
      id: id,
      eventIds: _strings(value['eventIds']),
      expectation: (value['expectation'] as String?)?.trim() ?? '',
      observedOutcome: (value['observedOutcome'] as String?)?.trim() ?? '',
      intention: (value['intention'] as String?)?.trim() ?? '',
      emotionalInfluence:
          (value['emotionalInfluence'] as String?)?.trim() ?? '',
      hypotheses: hypotheses,
      uncertainties: _strings(value['uncertainties']),
      provisionalLesson: (value['provisionalLesson'] as String?)?.trim() ?? '',
      nextExperiment: (value['nextExperiment'] as String?)?.trim() ?? '',
      createdAt: (value['createdAt'] as num?)?.toInt() ?? 0,
    );
  }
}

class KaiReflectionValidation {
  final String id;
  final String reflectionId;
  final KaiReflectionResolution resolution;
  final List<String> outcomeEventIds;
  final String finding;
  final int validatedAt;

  const KaiReflectionValidation({
    required this.id,
    required this.reflectionId,
    required this.resolution,
    required this.outcomeEventIds,
    required this.finding,
    required this.validatedAt,
  });

  Map<String, dynamic> toMap() => {
        'reflectionId': reflectionId,
        'resolution': resolution.name,
        'outcomeEventIds': outcomeEventIds,
        'finding': finding,
        'validatedAt': validatedAt,
      };

  static KaiReflectionValidation? fromMap(String id, Object? value) {
    if (value is! Map) return null;
    final resolutions = KaiReflectionResolution.values
        .where((item) => item.name == value['resolution']);
    if (resolutions.isEmpty) return null;
    return KaiReflectionValidation(
      id: id,
      reflectionId: (value['reflectionId'] as String?)?.trim() ?? '',
      resolution: resolutions.first,
      outcomeEventIds: _strings(value['outcomeEventIds']),
      finding: (value['finding'] as String?)?.trim() ?? '',
      validatedAt: (value['validatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

class KaiReflectionAdmission {
  final bool admitted;
  final String reason;
  const KaiReflectionAdmission._(this.admitted, this.reason);
  const KaiReflectionAdmission.admitted() : this._(true, 'admitted');
  const KaiReflectionAdmission.refused(String reason) : this._(false, reason);
}

KaiReflectionAdmission admitReflectionValidation(
  KaiReflectionValidation validation, {
  required KaiStructuredReflection reflection,
  required List<KaiLifeEvent> outcomeEvents,
}) {
  if (!RegExp(r'^[A-Za-z0-9_-]{3,160}$').hasMatch(validation.id) ||
      validation.reflectionId != reflection.id ||
      validation.finding.trim().length < 12 ||
      validation.outcomeEventIds.isEmpty ||
      validation.validatedAt <= reflection.createdAt) {
    return const KaiReflectionAdmission.refused('validation is too thin');
  }
  final byId = {for (final event in outcomeEvents) event.id: event};
  if (validation.outcomeEventIds.any((id) => !byId.containsKey(id))) {
    return const KaiReflectionAdmission.refused('validation event is missing');
  }
  if (validation.outcomeEventIds
      .any((id) => byId[id]!.occurredAt <= reflection.createdAt)) {
    return const KaiReflectionAdmission.refused(
      'validation outcome must occur after reflection',
    );
  }
  return const KaiReflectionAdmission.admitted();
}

KaiReflectionAdmission admitStructuredReflection(
  KaiStructuredReflection reflection, {
  required Set<String> availableEventIds,
}) {
  if (!RegExp(r'^[A-Za-z0-9_-]{3,120}$').hasMatch(reflection.id)) {
    return const KaiReflectionAdmission.refused('invalid reflection id');
  }
  if (reflection.createdAt <= 0 || reflection.eventIds.isEmpty) {
    return const KaiReflectionAdmission.refused('cited experience is required');
  }
  if (reflection.eventIds.any((id) => !availableEventIds.contains(id))) {
    return const KaiReflectionAdmission.refused(
        'reflection cites missing event');
  }
  if (reflection.expectation.trim().length < 8 ||
      reflection.observedOutcome.trim().length < 8 ||
      reflection.intention.trim().length < 8) {
    return const KaiReflectionAdmission.refused(
      'expectation, outcome, and intention are required',
    );
  }
  if (reflection.hypotheses.length < 2) {
    return const KaiReflectionAdmission.refused(
      'reflection requires competing hypotheses',
    );
  }
  for (final hypothesis in reflection.hypotheses) {
    if (hypothesis.claim.trim().length < 8 ||
        hypothesis.confidence <= 0 ||
        hypothesis.confidence >= 1 ||
        hypothesis.evidenceFor.isEmpty) {
      return const KaiReflectionAdmission.refused('hypothesis is not grounded');
    }
    final cited = [...hypothesis.evidenceFor, ...hypothesis.evidenceAgainst];
    if (cited.any((id) => !availableEventIds.contains(id))) {
      return const KaiReflectionAdmission.refused(
        'hypothesis cites missing evidence',
      );
    }
  }
  if (reflection.provisionalLesson.trim().length < 12 ||
      reflection.nextExperiment.trim().length < 12) {
    return const KaiReflectionAdmission.refused(
      'lesson and future experiment are required',
    );
  }
  return const KaiReflectionAdmission.admitted();
}

class KaiStructuredReflectionService {
  KaiStructuredReflectionService._();
  static final KaiStructuredReflectionService instance =
      KaiStructuredReflectionService._();

  String _path(String personaId) => 'kai/$personaId/reflections';
  String _validationPath(String personaId) =>
      'kai/$personaId/reflection_validations';

  Future<KaiReflectionAdmission> propose(
    String personaId,
    KaiStructuredReflection reflection,
  ) async {
    final events =
        await KaiLifeEventService.instance.recent(personaId, limit: 200);
    final admission = admitStructuredReflection(
      reflection,
      availableEventIds: events.map((item) => item.id).toSet(),
    );
    if (!admission.admitted) return admission;
    try {
      final ref = KaiDb.instance.ref('${_path(personaId)}/${reflection.id}');
      if ((await ref.get()).exists) {
        return const KaiReflectionAdmission.refused(
            'reflection already exists');
      }
      await ref.set(reflection.toMap());
      return const KaiReflectionAdmission.admitted();
    } catch (_) {
      return const KaiReflectionAdmission.refused('persistence failed');
    }
  }

  Future<KaiReflectionAdmission> validate(
    String personaId,
    KaiReflectionValidation validation,
  ) async {
    try {
      final reflectionSnapshot = await KaiDb.instance
          .ref('${_path(personaId)}/${validation.reflectionId}')
          .get();
      final reflection = KaiStructuredReflection.fromMap(
        validation.reflectionId,
        reflectionSnapshot.value,
      );
      if (reflection == null) {
        return const KaiReflectionAdmission.refused(
            'reflection does not exist');
      }
      final events =
          await KaiLifeEventService.instance.recent(personaId, limit: 200);
      final admission = admitReflectionValidation(
        validation,
        reflection: reflection,
        outcomeEvents: events,
      );
      if (!admission.admitted) return admission;
      final ref =
          KaiDb.instance.ref('${_validationPath(personaId)}/${validation.id}');
      if ((await ref.get()).exists) {
        return const KaiReflectionAdmission.refused(
            'validation already exists');
      }
      await ref.set(validation.toMap());
      return const KaiReflectionAdmission.admitted();
    } catch (_) {
      return const KaiReflectionAdmission.refused('persistence failed');
    }
  }

  Future<List<KaiStructuredReflection>> recent(
    String personaId, {
    int limit = 50,
  }) async {
    if (limit <= 0) return const [];
    try {
      final snapshot =
          await KaiDb.instance.ref(_path(personaId)).limitToLast(limit).get();
      if (snapshot.value is! Map) return const [];
      final out = <KaiStructuredReflection>[];
      (snapshot.value as Map).forEach((key, value) {
        final reflection =
            KaiStructuredReflection.fromMap(key.toString(), value);
        if (reflection != null) out.add(reflection);
      });
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out.take(limit).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<KaiReflectionValidation>> recentValidations(
    String personaId, {
    int limit = 100,
  }) async {
    if (limit <= 0) return const [];
    try {
      final snapshot = await KaiDb.instance
          .ref(_validationPath(personaId))
          .limitToLast(limit)
          .get();
      if (snapshot.value is! Map) return const [];
      final out = <KaiReflectionValidation>[];
      (snapshot.value as Map).forEach((key, value) {
        final validation =
            KaiReflectionValidation.fromMap(key.toString(), value);
        if (validation != null) out.add(validation);
      });
      out.sort((a, b) => b.validatedAt.compareTo(a.validatedAt));
      return out.take(limit).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}

List<String> _strings(Object? value) => value is List
    ? value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false)
    : const [];
