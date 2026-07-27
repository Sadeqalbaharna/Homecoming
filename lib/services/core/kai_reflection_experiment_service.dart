// Matches a reflection's promised experiment to later lived outcomes.
library;

import 'kai_db.dart';
import 'kai_life_event_service.dart';
import 'kai_structured_reflection_service.dart';

class KaiReflectionExperimentMatch {
  final String id;
  final String reflectionId;
  final String outcomeEventId;
  final double relevance;
  final List<String> matchedSignals;
  final int queuedAt;

  const KaiReflectionExperimentMatch({
    required this.id,
    required this.reflectionId,
    required this.outcomeEventId,
    required this.relevance,
    required this.matchedSignals,
    required this.queuedAt,
  });

  Map<String, dynamic> toMap() => {
        'reflectionId': reflectionId,
        'outcomeEventId': outcomeEventId,
        'relevance': relevance,
        'matchedSignals': matchedSignals,
        'queuedAt': queuedAt,
        'status': 'pending',
      };

  static KaiReflectionExperimentMatch? fromMap(String id, Object? value) {
    if (value is! Map || value['status'] == 'completed') return null;
    final reflectionId = (value['reflectionId'] as String?)?.trim() ?? '';
    final outcomeEventId = (value['outcomeEventId'] as String?)?.trim() ?? '';
    if (reflectionId.isEmpty || outcomeEventId.isEmpty) return null;
    return KaiReflectionExperimentMatch(
      id: id,
      reflectionId: reflectionId,
      outcomeEventId: outcomeEventId,
      relevance:
          ((value['relevance'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
      matchedSignals: _termsFromList(value['matchedSignals']).toList(),
      queuedAt: (value['queuedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

KaiReflectionExperimentMatch? matchReflectionExperiment(
  KaiStructuredReflection reflection,
  KaiLifeEvent outcome,
) {
  if (outcome.occurredAt <= reflection.createdAt ||
      reflection.eventIds.contains(outcome.id)) {
    return null;
  }
  final experimentTerms = _terms(reflection.nextExperiment);
  final outcomeTerms = _terms(
    '${outcome.observation} ${outcome.choice} ${outcome.outcome} '
    '${outcome.tags.join(' ')}',
  );
  final overlap = experimentTerms.intersection(outcomeTerms);
  final tagMatches = outcome.tags
      .map((tag) => tag.toLowerCase())
      .where(experimentTerms.contains)
      .toSet();
  final signals = {...overlap, ...tagMatches};
  if (signals.length < 2 && tagMatches.isEmpty) return null;
  final denominator = experimentTerms.isEmpty ? 1 : experimentTerms.length;
  final relevance =
      (signals.length / denominator + (tagMatches.isNotEmpty ? 0.25 : 0))
          .clamp(0.0, 1.0);
  if (relevance < 0.2) return null;
  return KaiReflectionExperimentMatch(
    id: 'experiment_${reflection.id}_${outcome.id}',
    reflectionId: reflection.id,
    outcomeEventId: outcome.id,
    relevance: relevance,
    matchedSignals: signals.toList()..sort(),
    queuedAt: outcome.recordedAt,
  );
}

class KaiReflectionExperimentService {
  KaiReflectionExperimentService._();
  static final KaiReflectionExperimentService instance =
      KaiReflectionExperimentService._();

  String _path(String personaId) =>
      'kai/$personaId/reflection_experiment_queue';

  Future<int> considerOutcome(String personaId, KaiLifeEvent outcome) async {
    var queued = 0;
    final reflections = await KaiStructuredReflectionService.instance
        .recent(personaId, limit: 50);
    for (final reflection in reflections) {
      final match = matchReflectionExperiment(reflection, outcome);
      if (match == null) continue;
      try {
        final ref = KaiDb.instance.ref('${_path(personaId)}/${match.id}');
        if ((await ref.get()).exists) continue;
        await ref.set(match.toMap());
        queued++;
      } catch (_) {}
    }
    return queued;
  }

  Future<List<KaiReflectionExperimentMatch>> pending(
    String personaId, {
    int limit = 4,
  }) async {
    if (limit <= 0) return const [];
    try {
      final snapshot = await KaiDb.instance.ref(_path(personaId)).get();
      if (snapshot.value is! Map) return const [];
      final out = <KaiReflectionExperimentMatch>[];
      (snapshot.value as Map).forEach((key, value) {
        final match =
            KaiReflectionExperimentMatch.fromMap(key.toString(), value);
        if (match != null) out.add(match);
      });
      out.sort((a, b) {
        final relevance = b.relevance.compareTo(a.relevance);
        return relevance != 0 ? relevance : a.queuedAt.compareTo(b.queuedAt);
      });
      return out.take(limit).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> complete(
    String personaId,
    String matchId,
    String validationId,
  ) async {
    try {
      await KaiDb.instance.ref('${_path(personaId)}/$matchId').update({
        'status': 'completed',
        'validationId': validationId,
      });
    } catch (_) {}
  }
}

Set<String> _terms(String value) => value
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((term) => term.length >= 4 && !_stop.contains(term))
    .toSet();

Set<String> _termsFromList(Object? value) =>
    value is List ? value.map((item) => item.toString()).toSet() : const {};

const _stop = {
  'that',
  'this',
  'with',
  'from',
  'before',
  'after',
  'next',
  'when',
  'then',
  'will',
  'would',
  'could',
  'should',
  'answering',
  'event',
  'outcome'
};
