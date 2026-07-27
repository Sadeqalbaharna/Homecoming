import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_life_event_service.dart';
import 'package:homecoming_app/services/core/kai_relationship_model.dart';

void main() {
  KaiLifeEvent moment(
    String id,
    Map<String, int> delta, {
    Map<String, int> mood = const {},
    int at = 100,
  }) =>
      KaiLifeEvent(
        id: id,
        kind: KaiLifeEventKind.relationshipMoment,
        source: KaiLifeEventSource.conversationRecord,
        occurredAt: at,
        recordedAt: at,
        observation: 'An observable relationship exchange occurred.',
        relationshipDelta: delta,
        affectDelta: mood,
        evidenceIds: ['conversation:$id'],
        confidence: 0.8,
      );

  test('relationship dimensions evolve independently', () {
    final model = deriveRelationshipModel([
      moment('m1', const {'familiarity': 2, 'emotionalSafety': 1}),
      moment('m2', const {'epistemicTrust': 2}, at: 101),
    ]);
    expect(model.familiarity, greaterThan(0.05));
    expect(model.epistemicTrust, greaterThan(0.1));
    expect(model.reciprocity, 0.05);
  });

  test('strong emotion alone does not create relationship evidence', () {
    final event = KaiLifeEvent(
      id: 'mood_only',
      kind: KaiLifeEventKind.actionOutcome,
      source: KaiLifeEventSource.conversationRecord,
      occurredAt: 100,
      recordedAt: 100,
      outcome: 'The exchange felt unusually intense and memorable.',
      affectDelta: const {'joy': 100, 'attachment': 100},
      evidenceIds: const ['conversation:mood_only'],
      confidence: 0.8,
    );
    final model = deriveRelationshipModel([event]);
    expect(model, const TypeMatcher<KaiRelationshipModel>());
    expect(model.familiarity, 0.05);
    expect(model.evidenceEventIds, isEmpty);
  });

  test('rupture weighs more quickly than warmth and repair does not erase it',
      () {
    final warm = moment('warm', const {'epistemicTrust': 3});
    final rupture = moment('rupture', const {'epistemicTrust': -3}, at: 101);
    final repaired = moment(
      'repair',
      const {'repairConfidence': 3, 'epistemicTrust': 1},
      at: 102,
    );
    final afterWarm = deriveRelationshipModel([warm]);
    final afterRupture = deriveRelationshipModel([warm, rupture]);
    final afterRepair = deriveRelationshipModel([warm, rupture, repaired]);
    expect(afterRupture.epistemicTrust, lessThan(afterWarm.epistemicTrust));
    expect(afterRepair.epistemicTrust, lessThan(afterWarm.epistemicTrust));
    expect(afterRepair.repairConfidence, greaterThan(0.05));
  });

  test('closeness serialization contains no permission or authority', () {
    final model = deriveRelationshipModel([
      for (var i = 0; i < 20; i++)
        moment(
            'm$i',
            const {
              'familiarity': 5,
              'epistemicTrust': 5,
              'emotionalSafety': 5,
              'reciprocity': 5,
            },
            at: 100 + i),
    ]);
    expect(model.familiarity, 1);
    expect(model.toMap(), isNot(contains('permission')));
    expect(model.toMap(), isNot(contains('authority')));
  });

  test('unbounded or mood-key relationship deltas are refused', () {
    expect(
      admitKaiLifeEvent(moment('bad1', const {'attachment': 4})).admitted,
      isFalse,
    );
    expect(
      admitKaiLifeEvent(moment('bad2', const {'familiarity': 99})).admitted,
      isFalse,
    );
  });
}
