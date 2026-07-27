import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_life_event_service.dart';
import 'package:homecoming_app/services/core/kai_reflection_trigger_service.dart';

void main() {
  KaiLifeEvent event(
    KaiLifeEventKind kind, {
    List<String> tags = const [],
    List<String> linked = const [],
    Map<String, int> affect = const {},
  }) =>
      KaiLifeEvent(
        id: 'event_123',
        kind: kind,
        source: KaiLifeEventSource.conversationRecord,
        occurredAt: 100,
        recordedAt: 101,
        observation: 'A concrete interaction occurred and was recorded.',
        outcome: 'The observed result is available for comparison.',
        tags: tags,
        linkedEventIds: linked,
        affectDelta: affect,
        evidenceIds: const ['conversation:100'],
        confidence: 0.8,
      );

  test('correction queues high-priority reflection', () {
    final candidate =
        reflectionCandidateFor(event(KaiLifeEventKind.correction));
    expect(candidate, isNotNull);
    expect(candidate!.kind, KaiReflectionTriggerKind.correction);
    expect(candidate.priority, greaterThanOrEqualTo(0.9));
  });

  test('ordinary action does not cause constant self-analysis', () {
    expect(
        reflectionCandidateFor(event(KaiLifeEventKind.actionOutcome)), isNull);
  });

  test('expectation is reflected on only after linked outcome arrives', () {
    final candidate = reflectionCandidateFor(event(
      KaiLifeEventKind.actionOutcome,
      linked: const ['expectation_1'],
    ));
    expect(candidate!.kind, KaiReflectionTriggerKind.expectationViolation);
    expect(candidate.eventIds, contains('expectation_1'));
  });

  test('rupture and repair remain psychologically distinct', () {
    final rupture = reflectionCandidateFor(event(
      KaiLifeEventKind.relationshipMoment,
      tags: const ['rupture'],
    ));
    final repair = reflectionCandidateFor(event(
      KaiLifeEventKind.relationshipMoment,
      tags: const ['repair'],
    ));
    expect(rupture!.kind, KaiReflectionTriggerKind.relationshipRupture);
    expect(repair!.kind, KaiReflectionTriggerKind.relationshipRepair);
    expect(rupture.priority, greaterThan(repair.priority));
  });

  test('strong affect raises relevance but cannot create a trigger', () {
    final ordinary = reflectionCandidateFor(event(
      KaiLifeEventKind.choice,
      affect: const {'valence': -20},
    ));
    expect(ordinary, isNull);

    final correction = reflectionCandidateFor(event(
      KaiLifeEventKind.correction,
      affect: const {'confidence': -15},
    ));
    expect(correction!.priority, closeTo(0.96, 0.001));
  });
}
