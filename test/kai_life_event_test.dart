import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_life_event_service.dart';
import 'package:homecoming_app/services/core/kai_autobiography_service.dart';
import 'package:homecoming_app/services/core/kai_self_provenance.dart';

void main() {
  KaiLifeEvent event({
    String id = 'event_001',
    KaiLifeEventKind kind = KaiLifeEventKind.actionOutcome,
    String observation = 'The verification command completed.',
    String choice = 'Kai chose to run the focused test first.',
    String outcome = 'All focused tests passed with an exit code of zero.',
    List<String> evidence = const ['tool:run_tests:001'],
  }) =>
      KaiLifeEvent(
        id: id,
        kind: kind,
        source: KaiLifeEventSource.toolReceipt,
        occurredAt: 100,
        recordedAt: 101,
        observation: observation,
        choice: choice,
        outcome: outcome,
        provisionalMeaning: 'Verification before confidence may be useful.',
        affectDelta: const {'confidence': 4},
        tags: const ['coding', 'verification'],
        evidenceIds: evidence,
        confidence: 0.9,
      );

  test('grounded event is admitted and round-trips without losing layers', () {
    final original = event();
    expect(admitKaiLifeEvent(original).admitted, isTrue);
    final restored = KaiLifeEvent.fromMap(original.id, original.toMap());
    expect(restored, isNotNull);
    expect(restored!.observation, original.observation);
    expect(restored.choice, original.choice);
    expect(restored.outcome, original.outcome);
    expect(restored.provisionalMeaning, original.provisionalMeaning);
    expect(restored.affectDelta['confidence'], 4);
    expect(restored.evidenceIds, ['tool:run_tests:001']);
  });

  test('generated prose without evidence cannot become lived history', () {
    final admission = admitKaiLifeEvent(event(evidence: const []));
    expect(admission.admitted, isFalse);
    expect(admission.reason, contains('evidence'));
  });

  test('expectation cannot be backfilled with an already-known outcome', () {
    final admission = admitKaiLifeEvent(event(
      kind: KaiLifeEventKind.expectation,
      outcome: 'The result was already known before this forecast.',
    ));
    expect(admission.admitted, isFalse);
    expect(admission.reason, contains('future outcome'));
  });

  test('malformed identifiers cannot select arbitrary persistence paths', () {
    final admission = admitKaiLifeEvent(event(id: '../self/identity'));
    expect(admission.admitted, isFalse);
    expect(admission.reason, contains('event id'));
  });

  test('interpretation remains explicitly provisional after persistence', () {
    final restored = KaiLifeEvent.fromMap('event_002', event().toMap());
    expect(restored!.provisionalMeaning, startsWith('Verification'));
    expect(restored.toMap(), isNot(contains('identity')));
  });

  test('autobiography adapter preserves evidence and separates meaning', () {
    const episode = AutobiographicalEpisode(
      id: '',
      kind: AutobiographicalEpisodeKind.correctedBelief,
      choice: 'I chose to inspect the failing trace again.',
      outcome: 'The trace disproved my original explanation.',
      meaning: 'Correction can sharpen confidence when it is inspectable.',
      provenance: SelfProvenance(
        source: SelfClaimSource.groundedRecord,
        evidenceIds: ['trace:correction_1'],
        confidence: 0.85,
        recordedAt: 200,
      ),
      occurredAt: 199,
    );
    final adapted = lifeEventFromLegacyAutobiography(
      legacyKind: episode.kind.name,
      storageId: 'legacy_001',
      choice: episode.choice,
      outcome: episode.outcome,
      meaning: episode.meaning,
      evidenceIds: episode.provenance.evidenceIds,
      confidence: episode.provenance.confidence,
      occurredAt: episode.occurredAt,
      recordedAt: episode.provenance.recordedAt,
    );
    expect(adapted.kind, KaiLifeEventKind.correction);
    expect(adapted.observation, episode.outcome);
    expect(adapted.provisionalMeaning, episode.meaning);
    expect(adapted.evidenceIds, episode.provenance.evidenceIds);
    expect(admitKaiLifeEvent(adapted).admitted, isTrue);
  });
}
