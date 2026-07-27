import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_earned_value_service.dart';
import 'package:homecoming_app/services/core/kai_life_event_service.dart';

void main() {
  KaiLifeEvent choice(String id, String context, {int cost = 2}) =>
      KaiLifeEvent(
        id: id,
        kind: KaiLifeEventKind.choice,
        source: KaiLifeEventSource.conversationRecord,
        occurredAt: 100,
        recordedAt: 100,
        choice: 'Kai chose accuracy over giving the faster answer.',
        foregoneAlternative: 'Answer immediately without checking the trace.',
        choiceCost: cost,
        valueSignals: const ['accuracy'],
        tags: ['context:$context'],
        evidenceIds: ['conversation:$id'],
        confidence: 0.8,
      );

  KaiEarnedValueRevision value({
    List<String> evidence = const ['c1', 'c2', 'c3'],
    List<String> contexts = const ['coding', 'conversation'],
    int cost = 6,
  }) =>
      KaiEarnedValueRevision(
        id: 'value_revision_1',
        valueKey: 'accuracy',
        statement: 'I repeatedly choose accuracy when speed would be easier.',
        contextKeys: contexts,
        evidenceFor: evidence,
        totalChoiceCost: cost,
        confidence: 0.6,
        status: contexts.length > 1
            ? KaiEarnedValueStatus.active
            : KaiEarnedValueStatus.contextual,
        createdAt: 200,
      );

  test('a value can be earned by repeated costly choices across contexts', () {
    final events = {
      'c1': choice('c1', 'coding'),
      'c2': choice('c2', 'coding'),
      'c3': choice('c3', 'conversation'),
    };
    expect(admitEarnedValue(value(), availableEvents: events).admitted, isTrue);
  });

  test('repeated claims without a foregone alternative are not values', () {
    final weak = choice('c1', 'coding');
    final events = {
      'c1': KaiLifeEvent(
        id: weak.id,
        kind: weak.kind,
        source: weak.source,
        occurredAt: weak.occurredAt,
        recordedAt: weak.recordedAt,
        choice: weak.choice,
        choiceCost: weak.choiceCost,
        valueSignals: weak.valueSignals,
        evidenceIds: weak.evidenceIds,
        confidence: weak.confidence,
      ),
      'c2': choice('c2', 'coding'),
      'c3': choice('c3', 'conversation'),
    };
    final admission = admitEarnedValue(value(), availableEvents: events);
    expect(admission.admitted, isFalse);
    expect(admission.reason, contains('costly choices'));
  });

  test('one dramatic choice cannot become a durable value', () {
    final events = {'c1': choice('c1', 'coding', cost: 10)};
    final admission = admitEarnedValue(
      value(evidence: const ['c1'], contexts: const ['coding'], cost: 10),
      availableEvents: events,
    );
    expect(admission.admitted, isFalse);
    expect(admission.reason, contains('three'));
  });

  test('counterevidence lowers confidence without erasing the value', () {
    final clean = earnedValueConfidence(
      choiceCount: 4,
      totalCost: 10,
      contradictionCount: 0,
      contextCount: 2,
    );
    final mixed = earnedValueConfidence(
      choiceCount: 4,
      totalCost: 10,
      contradictionCount: 2,
      contextCount: 2,
    );
    expect(mixed, lessThan(clean));
    expect(mixed, greaterThanOrEqualTo(0.35));
  });

  test('life event serialization preserves choice cost without making identity',
      () {
    final original = choice('c1', 'coding');
    final restored = KaiLifeEvent.fromMap(original.id, original.toMap())!;
    expect(restored.foregoneAlternative, original.foregoneAlternative);
    expect(restored.choiceCost, 2);
    expect(restored.valueSignals, ['accuracy']);
    expect(restored.toMap(), isNot(contains('identity')));
  });

  test('candidate construction is deterministic and context-bound', () {
    final candidates = earnedValueCandidates([
      choice('c1', 'coding'),
      choice('c2', 'coding'),
      choice('c3', 'conversation'),
    ], createdAt: 300);
    expect(candidates, hasLength(1));
    expect(candidates.single.valueKey, 'accuracy');
    expect(candidates.single.status, KaiEarnedValueStatus.active);
    expect(candidates.single.contextKeys, ['coding', 'conversation']);
    expect(candidates.single.id.length, lessThan(40));
  });

  test('high emotion or ordinary outcomes cannot manufacture a value', () {
    final event = KaiLifeEvent(
      id: 'dramatic_outcome',
      kind: KaiLifeEventKind.actionOutcome,
      source: KaiLifeEventSource.toolReceipt,
      occurredAt: 100,
      recordedAt: 100,
      outcome: 'A dramatic and emotionally intense success occurred.',
      affectDelta: const {'joy': 100},
      valueSignals: const ['courage'],
      tags: const ['context:coding'],
      evidenceIds: const ['tool:test:dramatic'],
      confidence: 0.9,
    );
    expect(earnedValueCandidates([event], createdAt: 300), isEmpty);
  });
}
