import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_self_context.dart';
import 'package:homecoming_app/services/core/kai_self_service.dart';
import 'package:homecoming_app/services/core/kai_autobiography_service.dart';
import 'package:homecoming_app/services/core/kai_self_nuance_service.dart';

void main() {
  KaiSelf legacy({String purpose = '', String dream = ''}) => KaiSelf(
        bornAt: 1,
        awakenings: 412,
        identity: KaiSelfService.defaultIdentity,
        values: KaiSelfService.defaultValues,
        currentFocus: 'shipping the context compiler',
        lastAwake: 2,
        purpose: purpose,
        dream: dream,
      );

  test('legacy projection distinguishes seeds from mutable legacy wording', () {
    final seeded = KaiSelfContext.fromLegacySelf(legacy());
    expect(seeded.identity.provenance.source, SelfClaimSource.systemSeed);
    expect(seeded.purpose.provenance.source, SelfClaimSource.systemSeed);
    expect(seeded.dream.provenance.source, SelfClaimSource.systemSeed);

    final changed = KaiSelfContext.fromLegacySelf(
      legacy(purpose: 'A revised purpose', dream: 'A revised dream'),
    );
    expect(changed.purpose.provenance.source, SelfClaimSource.persistedLegacy);
    expect(changed.dream.provenance.confidence, 0.5);
    expect(changed.dream.provenance.isGrounded, isFalse);
  });

  test('non-default identity text is not promoted to a foundational seed', () {
    final self = legacy();
    final changed = KaiSelf(
      bornAt: self.bornAt,
      awakenings: self.awakenings,
      identity: 'I am whatever the last writer said I am.',
      values: const ['an unreviewed persisted value'],
      currentFocus: self.currentFocus,
      lastAwake: self.lastAwake,
    );

    final context = KaiSelfContext.fromLegacySelf(changed);
    expect(
      context.identity.provenance.source,
      SelfClaimSource.persistedLegacy,
    );
    expect(
      context.values.single.provenance.source,
      SelfClaimSource.persistedLegacy,
    );
  });

  test('renderer does not turn instrumentation into first-person psychology',
      () {
    final rendered = KaiSelfContextRenderer.render(
      KaiSelfContext.fromLegacySelf(legacy()),
    );

    expect(rendered, isNot(contains('412')));
    expect(rendered, isNot(contains('woken')));
    expect(rendered, contains('Current focus (temporary state)'));
  });

  test('renderer marks ungated legacy identity evolution honestly', () {
    final rendered = KaiSelfContextRenderer.render(
      KaiSelfContext.fromLegacySelf(
        legacy(purpose: 'Choose difficult honesty.'),
      ),
    );

    expect(rendered, contains('persisted legacy wording'));
    expect(rendered, contains('Choose difficult honesty.'));
  });

  test('renderer enforces its token approximation budget', () {
    const maxTokens = 80;
    final rendered = KaiSelfContextRenderer.render(
      KaiSelfContext.fromLegacySelf(legacy()),
      maxTokens: maxTokens,
    );

    expect(rendered.length, lessThanOrEqualTo(maxTokens * 4));
    expect(rendered, isNotEmpty);
  });

  test('compiler emits an inspectable budget and provenance receipt', () {
    final compiled = KaiSelfContextRenderer.compile(
      KaiSelfContext.fromLegacySelf(
        legacy(purpose: 'Choose difficult honesty.'),
      ),
      maxTokens: 80,
    );

    expect(compiled.receipt.budgetTokens, 80);
    expect(compiled.receipt.estimatedTokens, lessThanOrEqualTo(80));
    expect(compiled.receipt.renderedChars, compiled.text.length);
    expect(
      compiled.receipt.claimSources['purpose'],
      SelfClaimSource.persistedLegacy.name,
    );
    expect(compiled.receipt.toJson()['truncated'], isTrue);
  });

  test('renderer exposes only explicitly supplied autobiographical episodes',
      () {
    final context = KaiSelfContext.fromLegacySelf(legacy()).withEpisodes([
      const AutobiographicalEpisode(
        id: 'e1',
        kind: AutobiographicalEpisodeKind.commitment,
        choice: 'I chose to keep the benchmark open.',
        outcome: 'A commitment receipt was stored.',
        meaning: 'I carry unfinished work across turns.',
        provenance: SelfProvenance(
          source: SelfClaimSource.groundedRecord,
          evidenceIds: ['tool:make_commitment:123'],
          confidence: 0.7,
          recordedAt: 123,
        ),
        occurredAt: 123,
      ),
    ]);
    final rendered = KaiSelfContextRenderer.render(context, maxTokens: 600);
    expect(rendered, contains('Relevant autobiography (receipt-backed)'));
    expect(rendered, contains('I chose to keep the benchmark open.'));
  });

  test('fast-route identity projection has a measured legacy prompt delta', () {
    final self = legacy(
      purpose: 'Choose difficult honesty and preserve demonstrated continuity.',
      dream:
          'Become present across devices without pretending the gaps vanished.',
    );
    final oldBlock = KaiSelfService.selfSummary(self);
    final compiled = KaiSelfContextRenderer.compile(
      KaiSelfContext.fromLegacySelf(self),
      maxTokens: 220,
    );

    expect(compiled.text.length, lessThan(oldBlock.length));
    expect(compiled.receipt.estimatedTokens, lessThanOrEqualTo(220));
    expect(compiled.receipt.renderedChars, compiled.text.length);
    expect(
      (oldBlock.length - compiled.text.length) / oldBlock.length,
      greaterThan(0.25),
    );
  });

  test('compact projection carries consequences through readable handles', () {
    final context =
        KaiSelfContext.fromLegacySelf(legacy()).withCommitments(const [
      SelfContinuityItem(
        id: 'commitment-123456789',
        kind: 'promise',
        text: 'Revisit the benchmark after the compiler lands',
      ),
    ]).withEpisodes([
      const AutobiographicalEpisode(
        id: 'episode-987654321',
        kind: AutobiographicalEpisodeKind.completedAction,
        choice: 'kept the benchmark open',
        outcome: 'the follow-up survived the session',
        meaning: 'continuity is enacted, not narrated',
        provenance: SelfProvenance(
          source: SelfClaimSource.groundedRecord,
          evidenceIds: ['tool:job_done:1'],
          confidence: 0.8,
          recordedAt: 1,
        ),
        occurredAt: 1,
      ),
    ]);

    final compiled = KaiSelfContextRenderer.compileCompact(
      context,
      maxTokens: 120,
    );

    expect(compiled.text, contains('Carry [C:'));
    expect(compiled.text, contains('Earned [E:'));
    expect(compiled.text, contains('Boundary:'));
    expect(compiled.text, isNot(contains(context.identity.value)));
    expect(compiled.receipt.format, 'compact-v1');
    expect(compiled.receipt.estimatedTokens, lessThanOrEqualTo(120));
  });

  test('compact fast projection beats rich projection without losing values',
      () {
    final context = KaiSelfContext.fromLegacySelf(legacy());
    final rich = KaiSelfContextRenderer.compile(context, maxTokens: 220);
    final compact =
        KaiSelfContextRenderer.compileCompact(context, maxTokens: 120);

    expect(compact.text, contains('Core:'));
    expect(compact.text.length, lessThan(rich.text.length));
    expect(compact.receipt.estimatedTokens, lessThanOrEqualTo(120));
  });

  test('mature nuance fits compact context without rewriting identity', () {
    final context = KaiSelfContext.fromLegacySelf(legacy()).withNuances(const [
      KaiSelfNuance(
        key: 'intuition_up',
        description: 'I increasingly connect patterns and implications',
        observations: 4,
        lastObservedAt: 10,
      ),
    ]);
    final compiled =
        KaiSelfContextRenderer.compileCompact(context, maxTokens: 120);
    expect(compiled.text, contains('Nuance [N:'));
    expect(compiled.text, contains('x4'));
    expect(compiled.text, isNot(contains(context.identity.value)));
    expect(compiled.receipt.estimatedTokens, lessThanOrEqualTo(120));
  });
}
