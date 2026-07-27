import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_structured_reflection_service.dart';
import 'package:homecoming_app/services/core/kai_life_event_service.dart';

void main() {
  KaiStructuredReflection reflection({
    List<KaiReflectionHypothesis>? hypotheses,
    List<String> eventIds = const ['autobiography_1'],
  }) =>
      KaiStructuredReflection(
        id: 'reflection_1',
        eventIds: eventIds,
        expectation: 'I expected the first explanation to survive inspection.',
        observedOutcome: 'The test disproved the first explanation.',
        intention: 'I wanted to close the bug accurately and quickly.',
        emotionalInfluence: 'Wanting closure may have raised my confidence.',
        hypotheses: hypotheses ??
            const [
              KaiReflectionHypothesis(
                claim: 'Curiosity was overridden by premature closure.',
                evidenceFor: ['autobiography_1'],
                confidence: 0.65,
              ),
              KaiReflectionHypothesis(
                claim:
                    'The available trace genuinely supported the first view.',
                evidenceFor: ['autobiography_1'],
                evidenceAgainst: ['autobiography_1'],
                confidence: 0.35,
              ),
            ],
        uncertainties: const ['Whether time pressure changed the decision.'],
        provisionalLesson:
            'Inspect the failing edge before explaining its cause.',
        nextExperiment:
            'On the next failure, test one competing cause before answering.',
        createdAt: 1000,
      );

  test('reflection requires events, alternatives, and a future experiment', () {
    final admission = admitStructuredReflection(
      reflection(),
      availableEventIds: {'autobiography_1'},
    );
    expect(admission.admitted, isTrue);
  });

  test('eloquent reflection cannot cite an experience that does not exist', () {
    final admission = admitStructuredReflection(
      reflection(),
      availableEventIds: const {},
    );
    expect(admission.admitted, isFalse);
    expect(admission.reason, contains('missing event'));
  });

  test('one favored story is introspective certainty, not reflection', () {
    final admission = admitStructuredReflection(
      reflection(hypotheses: const [
        KaiReflectionHypothesis(
          claim: 'I already know exactly why I did it.',
          evidenceFor: ['autobiography_1'],
          confidence: 0.9,
        ),
      ]),
      availableEventIds: {'autobiography_1'},
    );
    expect(admission.admitted, isFalse);
    expect(admission.reason, contains('competing hypotheses'));
  });

  test('certainty of zero or one is refused as false introspective precision',
      () {
    final admission = admitStructuredReflection(
      reflection(hypotheses: const [
        KaiReflectionHypothesis(
          claim: 'Premature closure explains the behavior.',
          evidenceFor: ['autobiography_1'],
          confidence: 1,
        ),
        KaiReflectionHypothesis(
          claim: 'The evidence available at the time was misleading.',
          evidenceFor: ['autobiography_1'],
          confidence: 0.4,
        ),
      ]),
      availableEventIds: {'autobiography_1'},
    );
    expect(admission.admitted, isFalse);
    expect(admission.reason, contains('not grounded'));
  });

  test('reflection round-trip preserves uncertainty and counterevidence', () {
    final original = reflection();
    final restored =
        KaiStructuredReflection.fromMap(original.id, original.toMap());
    expect(restored, isNotNull);
    expect(restored!.uncertainties, original.uncertainties);
    expect(restored.hypotheses[1].evidenceAgainst, ['autobiography_1']);
    expect(restored.nextExperiment, original.nextExperiment);
  });

  test('an event from before reflection cannot validate its experiment', () {
    final original = reflection();
    final validation = KaiReflectionValidation(
      id: 'validation_1',
      reflectionId: original.id,
      resolution: KaiReflectionResolution.supported,
      outcomeEventIds: const ['old_event'],
      finding: 'The earlier event appears to support the lesson.',
      validatedAt: 1100,
    );
    final admission = admitReflectionValidation(
      validation,
      reflection: original,
      outcomeEvents: const [
        KaiLifeEvent(
          id: 'old_event',
          kind: KaiLifeEventKind.actionOutcome,
          source: KaiLifeEventSource.toolReceipt,
          occurredAt: 900,
          recordedAt: 900,
          outcome: 'The event occurred before reflection was created.',
          evidenceIds: ['tool:test:old'],
          confidence: 0.8,
        ),
      ],
    );
    expect(admission.admitted, isFalse);
    expect(admission.reason, contains('after reflection'));
  });
}
