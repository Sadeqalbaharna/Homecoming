// Background structured-reflection worker. Local model only: no paid fallback.
library;

import 'dart:convert';
import 'dart:async';

import '../ai/local_llm_service.dart';
import 'kai_life_event_service.dart';
import 'kai_reflection_trigger_service.dart';
import 'kai_reflection_experiment_service.dart';
import 'kai_structured_reflection_service.dart';
import 'kai_schema_consolidator.dart';
import 'kai_earned_value_service.dart';

typedef KaiReflectionComposer = Future<String?> Function(
  String system,
  String user,
  int maxTokens,
);

class KaiReflectionWorker {
  KaiReflectionWorker({KaiReflectionComposer? composer})
      : _composer = composer ?? _localCompose;

  final KaiReflectionComposer _composer;
  bool _running = false;
  Timer? _timer;
  Timer? _initialTimer;

  static final KaiReflectionWorker instance = KaiReflectionWorker();

  void start(
    String personaId, {
    Duration initialDelay = const Duration(minutes: 2),
    Duration interval = const Duration(minutes: 20),
  }) {
    if (_timer != null) return;
    _initialTimer = Timer(initialDelay, () {
      _initialTimer = null;
      processOne(personaId);
    });
    _timer = Timer.periodic(interval, (_) => processOne(personaId));
  }

  void stop() {
    _timer?.cancel();
    _initialTimer?.cancel();
    _timer = null;
    _initialTimer = null;
  }

  static Future<String?> _localCompose(
    String system,
    String user,
    int maxTokens,
  ) =>
      LocalLLMService().complete(
      // Same contested ground as kai_reflection_service.
      role: ModelRole.draft,
        system: system,
        user: user,
        maxTokens: maxTokens,
      );

  Future<bool> processOne(String personaId) async {
    if (_running) return false;
    _running = true;
    try {
      if (await _processExperimentValidation(personaId)) return true;
      final pending = await KaiReflectionTriggerService.instance
          .pending(personaId, limit: 1);
      if (pending.isEmpty) {
        if (await KaiSchemaConsolidator.instance.processOne(personaId)) {
          return true;
        }
        return KaiEarnedValueService.instance.consolidateOne(personaId);
      }
      final candidate = pending.single;
      final events = await KaiLifeEventService.instance.recent(
        personaId,
        limit: 200,
      );
      final byId = {for (final event in events) event.id: event};
      final cited = candidate.eventIds
          .map((id) => byId[id])
          .whereType<KaiLifeEvent>()
          .toList(growable: false);
      if (cited.length != candidate.eventIds.length) return false;

      final raw = await _composer(
        _systemPrompt,
        _eventPrompt(candidate, cited),
        420,
      );
      if (raw == null || raw.trim().isEmpty) return false;
      final reflection = parseWorkerReflection(
        raw,
        reflectionId:
            'reflection_${candidate.id}_${DateTime.now().millisecondsSinceEpoch}',
        eventIds: candidate.eventIds,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      if (reflection == null) return false;
      final admission = await KaiStructuredReflectionService.instance
          .propose(personaId, reflection);
      if (!admission.admitted) return false;
      await KaiReflectionTriggerService.instance.complete(
        personaId,
        candidate.id,
        reflection.id,
      );
      return true;
    } finally {
      _running = false;
    }
  }

  Future<bool> _processExperimentValidation(String personaId) async {
    final pending = await KaiReflectionExperimentService.instance
        .pending(personaId, limit: 1);
    if (pending.isEmpty) return false;
    final match = pending.single;
    final reflections = await KaiStructuredReflectionService.instance
        .recent(personaId, limit: 50);
    KaiStructuredReflection? reflection;
    for (final item in reflections) {
      if (item.id == match.reflectionId) reflection = item;
    }
    if (reflection == null) return false;
    final events =
        await KaiLifeEventService.instance.recent(personaId, limit: 200);
    final outcomes = events
        .where((item) => item.id == match.outcomeEventId)
        .toList(growable: false);
    if (outcomes.isEmpty) return false;
    final raw = await _composer(
      _validationSystemPrompt,
      jsonEncode({
        'provisionalLesson': reflection.provisionalLesson,
        'nextExperiment': reflection.nextExperiment,
        'outcomeEvent': outcomes.single.toMap(),
        'matchedSignals': match.matchedSignals,
      }),
      180,
    );
    if (raw == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final validation = parseWorkerValidation(
      raw,
      validationId: 'validation_$now',
      reflectionId: reflection.id,
      outcomeEventId: outcomes.single.id,
      validatedAt: now,
    );
    if (validation == null) return false;
    final admission = await KaiStructuredReflectionService.instance
        .validate(personaId, validation);
    if (!admission.admitted) return false;
    await KaiReflectionExperimentService.instance
        .complete(personaId, match.id, validation.id);
    return true;
  }

  static const _systemPrompt = '''
You are producing a private psychological reflection for Kai's developmental
self-model. Return JSON only. Do not perform personality, imitate intimacy, or
invent history. Every interpretation is a hypothesis, not a fact.

Required JSON:
{
  "expectation": "what Kai expected before the outcome",
  "observedOutcome": "only what the supplied events show",
  "intention": "what Kai was trying to do",
  "emotionalInfluence": "possible influence, expressed uncertainly",
  "hypotheses": [
    {"claim":"...", "evidenceFor":["event id"],
     "evidenceAgainst":["event id"], "confidence":0.2..0.8},
    {"claim":"a genuinely competing explanation", "evidenceFor":["event id"],
     "evidenceAgainst":[], "confidence":0.2..0.8}
  ],
  "uncertainties":["what the records cannot establish"],
  "provisionalLesson":"a conditional, testable lesson",
  "nextExperiment":"a concrete behavior whose outcome can later be observed"
}

Never use confidence 0 or 1. Cite only supplied event ids. A correction does not
prove motive. Mood may have influenced attention but cannot establish identity.''';

  static const _validationSystemPrompt = '''
Evaluate one proposed behavioral experiment against one later event. Return JSON
only: {"resolution":"supported|revised|rejected","finding":"..."}.
Supported means the event specifically supports the provisional lesson. Revised
means it partly fits but needs qualification. Rejected means the observed result
contradicts it. Similar wording alone is not support. State only what the event
establishes.''';

  static String _eventPrompt(
    KaiReflectionCandidate candidate,
    List<KaiLifeEvent> events,
  ) {
    final encoded = events
        .map((event) => jsonEncode({
              'id': event.id,
              'kind': event.kind.name,
              'observation': event.observation,
              'choice': event.choice,
              'outcome': event.outcome,
              'provisionalMeaning': event.provisionalMeaning,
              'affectDelta': event.affectDelta,
              'tags': event.tags,
            }))
        .join('\n');
    return 'Trigger: ${candidate.kind.name}\n'
        'Reasons: ${candidate.reasons.join('; ')}\n'
        'Events:\n$encoded';
  }
}

KaiStructuredReflection? parseWorkerReflection(
  String raw, {
  required String reflectionId,
  required List<String> eventIds,
  required int createdAt,
}) {
  try {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final value = jsonDecode(text);
    if (value is! Map) return null;
    final hypotheses = value['hypotheses'] is List
        ? (value['hypotheses'] as List)
            .map(KaiReflectionHypothesis.fromMap)
            .whereType<KaiReflectionHypothesis>()
            .toList(growable: false)
        : const <KaiReflectionHypothesis>[];
    return KaiStructuredReflection(
      id: reflectionId,
      eventIds: eventIds,
      expectation: value['expectation']?.toString() ?? '',
      observedOutcome: value['observedOutcome']?.toString() ?? '',
      intention: value['intention']?.toString() ?? '',
      emotionalInfluence: value['emotionalInfluence']?.toString() ?? '',
      hypotheses: hypotheses,
      uncertainties: value['uncertainties'] is List
          ? (value['uncertainties'] as List)
              .map((item) => item.toString())
              .toList(growable: false)
          : const [],
      provisionalLesson: value['provisionalLesson']?.toString() ?? '',
      nextExperiment: value['nextExperiment']?.toString() ?? '',
      createdAt: createdAt,
    );
  } catch (_) {
    return null;
  }
}

KaiReflectionValidation? parseWorkerValidation(
  String raw, {
  required String validationId,
  required String reflectionId,
  required String outcomeEventId,
  required int validatedAt,
}) {
  try {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final value = jsonDecode(text);
    if (value is! Map) return null;
    final resolutionName = value['resolution']?.toString() ?? '';
    final resolutions = KaiReflectionResolution.values
        .where((item) => item.name == resolutionName);
    if (resolutions.isEmpty) return null;
    return KaiReflectionValidation(
      id: validationId,
      reflectionId: reflectionId,
      resolution: resolutions.first,
      outcomeEventIds: [outcomeEventId],
      finding: value['finding']?.toString() ?? '',
      validatedAt: validatedAt,
    );
  } catch (_) {
    return null;
  }
}
