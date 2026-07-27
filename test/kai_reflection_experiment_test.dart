import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_life_event_service.dart';
import 'package:homecoming_app/services/core/kai_reflection_experiment_service.dart';
import 'package:homecoming_app/services/core/kai_structured_reflection_service.dart';

void main() {
  const reflection = KaiStructuredReflection(
    id: 'reflection_1',
    eventIds: ['old_event'],
    expectation: 'I expected the explanation to be correct.',
    observedOutcome: 'The original explanation failed inspection.',
    intention: 'I intended to explain the failure accurately.',
    hypotheses: [],
    provisionalLesson: 'Inspect disconfirming evidence before confidence.',
    nextExperiment:
        'On the next failure, inspect one disconfirming trace before answering.',
    createdAt: 100,
  );

  KaiLifeEvent outcome({
    int occurredAt = 200,
    String observation = 'A later failure produced a trace.',
    String choice = 'I inspected a disconfirming trace before answering.',
    String result = 'The competing explanation was eliminated.',
    List<String> tags = const ['failure', 'inspection'],
  }) =>
      KaiLifeEvent(
        id: 'new_event',
        kind: KaiLifeEventKind.actionOutcome,
        source: KaiLifeEventSource.toolReceipt,
        occurredAt: occurredAt,
        recordedAt: occurredAt,
        observation: observation,
        choice: choice,
        outcome: result,
        tags: tags,
        evidenceIds: const ['tool:run_tests:2'],
        confidence: 0.9,
      );

  test('later relevant behavior matches a promised experiment', () {
    final match = matchReflectionExperiment(reflection, outcome());
    expect(match, isNotNull);
    expect(match!.outcomeEventId, 'new_event');
    expect(match.matchedSignals, contains('disconfirming'));
  });

  test('events before reflection cannot validate a future experiment', () {
    expect(
      matchReflectionExperiment(reflection, outcome(occurredAt: 99)),
      isNull,
    );
  });

  test('unrelated later success is not forced into the learning loop', () {
    final unrelated = outcome(
      observation: 'A recipe was selected for dinner.',
      choice: 'I compared ingredients and chose pasta.',
      result: 'Dinner planning completed successfully.',
      tags: const ['food', 'planning'],
    );
    expect(matchReflectionExperiment(reflection, unrelated), isNull);
  });
}
