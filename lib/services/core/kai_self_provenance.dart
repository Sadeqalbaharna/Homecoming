// Shared evidence contract for self-beliefs, revisions, and autobiography.
library;

enum SelfClaimSource {
  systemSeed,
  persistedLegacy,
  observedState,
  groundedRecord,
}

class SelfProvenance {
  final SelfClaimSource source;
  final List<String> evidenceIds;
  final double confidence;
  final int recordedAt;

  const SelfProvenance({
    required this.source,
    this.evidenceIds = const [],
    this.confidence = 0,
    this.recordedAt = 0,
  });

  bool get isGrounded => evidenceIds.isNotEmpty;
}
