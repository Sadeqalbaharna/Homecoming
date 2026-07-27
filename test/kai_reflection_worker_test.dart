import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_reflection_worker.dart';
import 'package:homecoming_app/services/core/kai_structured_reflection_service.dart';

void main() {
  const json = '''
{
  "expectation":"I expected my explanation to survive inspection.",
  "observedOutcome":"The supplied test event disproved that explanation.",
  "intention":"I was trying to close the issue accurately and quickly.",
  "emotionalInfluence":"Wanting closure may have narrowed my attention.",
  "hypotheses":[
    {"claim":"Premature closure narrowed the investigation.","evidenceFor":["event_1"],"evidenceAgainst":[],"confidence":0.65},
    {"claim":"The initial evidence was genuinely misleading.","evidenceFor":["event_1"],"evidenceAgainst":["event_1"],"confidence":0.35}
  ],
  "uncertainties":["Whether time pressure affected the choice."],
  "provisionalLesson":"Test a competing cause before offering a confident explanation.",
  "nextExperiment":"On the next failure, inspect one disconfirming trace before answering."
}''';

  test('local worker output parses into admissible structured reflection', () {
    final reflection = parseWorkerReflection(
      json,
      reflectionId: 'reflection_1',
      eventIds: const ['event_1'],
      createdAt: 100,
    );
    expect(reflection, isNotNull);
    final admission = admitStructuredReflection(
      reflection!,
      availableEventIds: {'event_1'},
    );
    expect(admission.admitted, isTrue);
  });

  test('markdown-fenced JSON is tolerated without relaxing admission', () {
    final reflection = parseWorkerReflection(
      '```json\n$json\n```',
      reflectionId: 'reflection_2',
      eventIds: const ['event_1'],
      createdAt: 100,
    );
    expect(reflection, isNotNull);
    expect(reflection!.hypotheses, hasLength(2));
  });

  test('prose and malformed output fail closed', () {
    expect(
      parseWorkerReflection(
        'I think I learned something profound.',
        reflectionId: 'reflection_3',
        eventIds: const ['event_1'],
        createdAt: 100,
      ),
      isNull,
    );
  });

  test('parser cannot make unavailable citations admissible', () {
    final reflection = parseWorkerReflection(
      json,
      reflectionId: 'reflection_4',
      eventIds: const ['event_1'],
      createdAt: 100,
    );
    final admission = admitStructuredReflection(
      reflection!,
      availableEventIds: const {},
    );
    expect(admission.admitted, isFalse);
  });

  test('experiment validation parses only explicit resolutions', () {
    final validation = parseWorkerValidation(
      '{"resolution":"revised","finding":"The event supports the behavior but only in coding contexts."}',
      validationId: 'validation_1',
      reflectionId: 'reflection_1',
      outcomeEventId: 'event_2',
      validatedAt: 300,
    );
    expect(validation, isNotNull);
    expect(validation!.resolution, KaiReflectionResolution.revised);

    expect(
      parseWorkerValidation(
        '{"resolution":"probably","finding":"maybe"}',
        validationId: 'validation_2',
        reflectionId: 'reflection_1',
        outcomeEventId: 'event_2',
        validatedAt: 300,
      ),
      isNull,
    );
  });
}
