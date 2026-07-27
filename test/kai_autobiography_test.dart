import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_autobiography_service.dart';
import 'package:homecoming_app/services/core/kai_self_context.dart';

void main() {
  AutobiographicalEpisode episode({
    List<String> evidence = const ['tool:make_commitment:123'],
    String choice = 'I chose to carry the context benchmark forward.',
    String outcome = 'The commitment was admitted and persisted.',
  }) =>
      AutobiographicalEpisode(
        id: 'e1',
        kind: AutobiographicalEpisodeKind.commitment,
        choice: choice,
        outcome: outcome,
        meaning: 'Continuity requires carrying choices into later turns.',
        provenance: SelfProvenance(
          source: SelfClaimSource.groundedRecord,
          evidenceIds: evidence,
          confidence: 0.7,
          recordedAt: 123,
        ),
        occurredAt: 123,
      );

  test('admits a receipt-backed choice and outcome', () {
    expect(isAdmissibleEpisode(episode()), isTrue);
  });

  test('refuses persuasive autobiography without evidence', () {
    expect(isAdmissibleEpisode(episode(evidence: const [])), isFalse);
  });

  test('refuses arbitrary evidence identifiers', () {
    expect(
      isAdmissibleEpisode(episode(evidence: const ['memory:I-said-so'])),
      isFalse,
    );
  });

  test('round trip preserves provenance and meaning', () {
    final original = episode();
    final restored =
        AutobiographicalEpisode.fromMap('restored', original.toMap());
    expect(restored, isNotNull);
    expect(restored!.choice, original.choice);
    expect(restored.meaning, original.meaning);
    expect(restored.isGrounded, isTrue);
    expect(restored.provenance.evidenceIds, original.provenance.evidenceIds);
  });
}
