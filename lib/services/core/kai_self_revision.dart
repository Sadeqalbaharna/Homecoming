// Pure admission rules for durable changes to Kai's self-description.
library;

import 'kai_self_context.dart';

enum SelfRevisionField { dream, purpose }

class SelfRevisionProposal {
  final SelfRevisionField field;
  final String proposedValue;
  final String rationale;
  final String evidenceSummary;
  final SelfProvenance provenance;
  final int proposedAt;

  const SelfRevisionProposal({
    required this.field,
    required this.proposedValue,
    required this.rationale,
    required this.evidenceSummary,
    required this.provenance,
    required this.proposedAt,
  });
}

enum SelfRevisionDecision { admitted, refused }

class SelfRevisionAdmission {
  final SelfRevisionDecision decision;
  final String reason;

  const SelfRevisionAdmission._(this.decision, this.reason);

  const SelfRevisionAdmission.admitted()
      : this._(SelfRevisionDecision.admitted, 'admitted');

  const SelfRevisionAdmission.refused(String reason)
      : this._(SelfRevisionDecision.refused, reason);

  bool get isAdmitted => decision == SelfRevisionDecision.admitted;
}

SelfRevisionAdmission admitSelfRevision({
  required SelfRevisionProposal proposal,
  required String currentValue,
}) {
  final next = proposal.proposedValue.trim();
  if (next.isEmpty) {
    return const SelfRevisionAdmission.refused('proposed value is empty');
  }
  if (next == currentValue.trim()) {
    return const SelfRevisionAdmission.refused('proposed value is unchanged');
  }
  if (proposal.proposedAt <= 0) {
    return const SelfRevisionAdmission.refused('proposal has no timestamp');
  }
  if (proposal.rationale.trim().length < 20) {
    return const SelfRevisionAdmission.refused(
      'rationale is too thin to support durable self-change',
    );
  }
  if (proposal.evidenceSummary.trim().length < 12) {
    return const SelfRevisionAdmission.refused(
      'no concrete triggering experience was supplied',
    );
  }
  if (!proposal.provenance.isGrounded) {
    return const SelfRevisionAdmission.refused(
      'proposal has no trusted tool-call receipt',
    );
  }
  if (proposal.provenance.source != SelfClaimSource.groundedRecord) {
    return const SelfRevisionAdmission.refused(
      'proposal provenance is not an authoritative record',
    );
  }
  return const SelfRevisionAdmission.admitted();
}
