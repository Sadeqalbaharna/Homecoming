import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_motive_model.dart';

void main() {
  KaiMotive motive(
    String id,
    String aim, {
    double activation = 0.6,
    double endorsement = 0.6,
    List<String> context = const ['code'],
    List<String> sources = const ['goal:g1'],
  }) =>
      KaiMotive(
        id: id,
        kind: KaiMotiveKind.goal,
        aim: aim,
        sourceIds: sources,
        contextTerms: context,
        activation: activation,
        selfEndorsement: endorsement,
        uncertainty: 0.3,
        formedAt: 100,
        expiresAt: 1000,
      );

  test('context selects a foreground motive without deleting alternatives', () {
    final field = resolveMotiveField([
      motive('finish_work', 'finish the current code change'),
      motive('explore_idea', 'explore a new visual idea', context: ['visual']),
    ], currentContext: 'please finish this code', now: 200);
    expect(field.foreground!.id, 'finish_work');
    expect(field.background.map((item) => item.id), contains('explore_idea'));
  });

  test('competing motives remain visible as conflict', () {
    final field = resolveMotiveField([
      motive('be_accurate', 'choose accuracy before answering'),
      motive('be_fast', 'choose speed before answering'),
    ], currentContext: 'answer this code question', now: 200);
    expect(field.conflicts, hasLength(1));
  });

  test('mood cannot create an unsupported motive', () {
    final field = resolveMotiveField([],
        currentContext: 'anything', now: 200, moodBias: 100);
    expect(field.foreground, isNull);
  });

  test('motive needs a grounded source and must expire', () {
    expect(
      admissibleMotive(
          motive('ungrounded', 'explore the question', sources: const []),
          now: 200),
      isFalse,
    );
    expect(admissibleMotive(motive('expired', 'finish the work'), now: 1001),
        isFalse);
  });

  test('relationship evidence can motivate repair but grants no authority', () {
    final repair = motive(
      'repair_rupture',
      'repair a specific conversational rupture',
      sources: const ['event:rupture_1'],
    );
    expect(admissibleMotive(repair, now: 200), isTrue);
    expect(
        KaiMotiveField(
            foreground: repair, background: const [], conflicts: const []),
        const TypeMatcher<KaiMotiveField>());
  });
}
