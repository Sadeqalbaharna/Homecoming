import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_self_context.dart';
import 'package:homecoming_app/services/core/kai_self_revision.dart';

void main() {
  SelfRevisionProposal proposal({
    String value = 'To become more honest through demonstrated continuity.',
    String rationale =
        'A repeated outcome changed how I understand this durable aim.',
    String evidence =
        'Three completed turns produced the same observed result.',
    List<String> evidenceIds = const ['tool:refine_purpose:123'],
    SelfClaimSource source = SelfClaimSource.groundedRecord,
  }) =>
      SelfRevisionProposal(
        field: SelfRevisionField.purpose,
        proposedValue: value,
        rationale: rationale,
        evidenceSummary: evidence,
        provenance: SelfProvenance(
          source: source,
          evidenceIds: evidenceIds,
          confidence: 0.6,
          recordedAt: 123,
        ),
        proposedAt: 123,
      );

  test('admits a changed, explained, receipted revision', () {
    final result = admitSelfRevision(
      proposal: proposal(),
      currentValue: 'My prior purpose.',
    );
    expect(result.isAdmitted, isTrue);
  });

  test('refuses unchanged wording', () {
    const same = 'My prior purpose.';
    final result = admitSelfRevision(
      proposal: proposal(value: same),
      currentValue: same,
    );
    expect(result.isAdmitted, isFalse);
    expect(result.reason, contains('unchanged'));
  });

  test('refuses thin rationale and evidence', () {
    final result = admitSelfRevision(
      proposal: proposal(rationale: 'felt right', evidence: 'a vibe'),
      currentValue: 'My prior purpose.',
    );
    expect(result.isAdmitted, isFalse);
  });

  test('refuses an unreceipted or non-authoritative revision', () {
    final noReceipt = admitSelfRevision(
      proposal: proposal(evidenceIds: const []),
      currentValue: 'My prior purpose.',
    );
    expect(noReceipt.isAdmitted, isFalse);
    expect(noReceipt.reason, contains('receipt'));

    final legacy = admitSelfRevision(
      proposal: proposal(source: SelfClaimSource.persistedLegacy),
      currentValue: 'My prior purpose.',
    );
    expect(legacy.isAdmitted, isFalse);
    expect(legacy.reason, contains('authoritative'));
  });
}
