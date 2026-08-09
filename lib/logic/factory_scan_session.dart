// Deterministic Signal Scan session controller.
//
// Pure domain code: no network, credentials, database, UI, or Factory advance
// dependency. External search may only enter as an explicitly completed adapter
// result; a work packet is not evidence that a search happened.
library;

const int factoryScanSchemaVersion = 1;
const Duration factoryScanTimebox = Duration(minutes: 30);

enum ScanCandidateState {
  discovered,
  rejected,
  awaitingVote,
  yesShortlist,
  maybeIncubate,
  closeRepair,
  laterRetained,
  noArchived,
  blueprintAuthorized,
}

enum SponsorVote { none, yes, maybe, no, later }

enum CalibrationDirection { loosen, tighten }

enum ScanExecutionState { pending, completed, failed }

enum ScanEfficiency { efficient, mixed, wasteful }

enum ScanEffectiveness { high, medium, low, zero }

enum WasteKind {
  duplicateSearch,
  repeatedPacket,
  relayRejection,
  unchangedRetry,
  failedToolCall,
  timeWithoutNewEvidence,
}

String _enumName(Object value) => value.toString().split('.').last;
T _enumOr<T>(List<T> values, Object? raw, T fallback) {
  final name = raw?.toString();
  return values.firstWhere(
    (value) => _enumName(value as Object) == name,
    orElse: () => fallback,
  );
}

ScanCandidateState _safePersistedCandidateState(Object? raw) {
  final parsed =
      _enumOr(ScanCandidateState.values, raw, ScanCandidateState.discovered);
  // This slice has no trusted authorization persistence seam. Never restore a
  // privileged state from agent-writable session JSON.
  return parsed == ScanCandidateState.blueprintAuthorized
      ? ScanCandidateState.yesShortlist
      : parsed;
}

String canonicalFingerprint(Iterable<String> parts) => parts
    .map((part) => part.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '))
    .where((part) => part.isNotEmpty)
    .join('|');

class ScanFilter {
  final String name;
  final String value;
  const ScanFilter(this.name, this.value);

  Map<String, Object?> toJson() => {'name': name, 'value': value};
  factory ScanFilter.fromJson(Map<Object?, Object?> json) => ScanFilter(
        json['name']?.toString() ?? '',
        json['value']?.toString() ?? '',
      );
}

class ScanEvidenceReference {
  final String id;
  final String source;
  final String reference;
  final String? observedFact;

  const ScanEvidenceReference({
    required this.id,
    required this.source,
    required this.reference,
    this.observedFact,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'source': source,
        'reference': reference,
        if (observedFact != null) 'observedFact': observedFact,
      };

  factory ScanEvidenceReference.fromJson(Map<Object?, Object?> json) =>
      ScanEvidenceReference(
        id: json['id']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        reference: json['reference']?.toString() ?? '',
        observedFact: json['observedFact']?.toString(),
      );
}

class ProviderUsage {
  /// Null means the provider did not expose exact usage. Never estimated.
  final int? exactTokens;
  final double? exactCredits;

  const ProviderUsage({this.exactTokens, this.exactCredits});
  bool get available => exactTokens != null || exactCredits != null;

  Map<String, Object?> toJson() => {
        'exactTokens': exactTokens,
        'exactCredits': exactCredits,
      };
  factory ProviderUsage.fromJson(Map<Object?, Object?> json) => ProviderUsage(
        exactTokens: (json['exactTokens'] as num?)?.toInt(),
        exactCredits: (json['exactCredits'] as num?)?.toDouble(),
      );
}

class ScanCalibrationChange {
  final CalibrationDirection direction;
  final String filterName;
  final String fromValue;
  final String toValue;
  final String reason;

  const ScanCalibrationChange({
    required this.direction,
    required this.filterName,
    required this.fromValue,
    required this.toValue,
    required this.reason,
  });

  bool get materiallyChangesFilter =>
      filterName.trim().isNotEmpty &&
      fromValue.trim().isNotEmpty &&
      toValue.trim().isNotEmpty &&
      fromValue.trim() != toValue.trim();

  Map<String, Object?> toJson() => {
        'direction': _enumName(direction),
        'filterName': filterName,
        'fromValue': fromValue,
        'toValue': toValue,
        'reason': reason,
      };

  factory ScanCalibrationChange.fromJson(Map<Object?, Object?> json) =>
      ScanCalibrationChange(
        direction: _enumOr(
          CalibrationDirection.values,
          json['direction'],
          CalibrationDirection.loosen,
        ),
        filterName: json['filterName']?.toString() ?? '',
        fromValue: json['fromValue']?.toString() ?? '',
        toValue: json['toValue']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
      );
}

class ScanCandidate {
  final String id;
  final String identity;
  final String fingerprint;
  final ScanCandidateState state;
  final List<String> evidenceReferenceIds;
  final List<String> rejectionReasons;
  final SponsorVote sponsorVote;
  final bool strong;
  final String oneSentenceIdea;
  final String intendedConsumer;
  final String painOrDesire;
  final String audienceRationale;
  final String simplestProduct;
  final String moneyPath;
  final String strongestRejection;
  final String proofState;
  final String originatingAttemptId;
  final String originatingHypothesis;
  final List<String> traits;

  const ScanCandidate({
    required this.id,
    required this.identity,
    required this.fingerprint,
    this.state = ScanCandidateState.discovered,
    this.evidenceReferenceIds = const [],
    this.rejectionReasons = const [],
    this.sponsorVote = SponsorVote.none,
    this.strong = false,
    this.oneSentenceIdea = '',
    this.intendedConsumer = '',
    this.painOrDesire = '',
    this.audienceRationale = '',
    this.simplestProduct = '',
    this.moneyPath = '',
    this.strongestRejection = '',
    this.proofState = 'UNVERIFIED',
    this.originatingAttemptId = '',
    this.originatingHypothesis = '',
    this.traits = const [],
  });

  ScanCandidate copyWith({
    ScanCandidateState? state,
    List<String>? evidenceReferenceIds,
    List<String>? rejectionReasons,
    SponsorVote? sponsorVote,
  }) =>
      ScanCandidate(
        id: id,
        identity: identity,
        fingerprint: fingerprint,
        state: state ?? this.state,
        evidenceReferenceIds: evidenceReferenceIds ?? this.evidenceReferenceIds,
        rejectionReasons: rejectionReasons ?? this.rejectionReasons,
        sponsorVote: sponsorVote ?? this.sponsorVote,
        strong: strong,
        oneSentenceIdea: oneSentenceIdea,
        intendedConsumer: intendedConsumer,
        painOrDesire: painOrDesire,
        audienceRationale: audienceRationale,
        simplestProduct: simplestProduct,
        moneyPath: moneyPath,
        strongestRejection: strongestRejection,
        proofState: proofState,
        originatingAttemptId: originatingAttemptId,
        originatingHypothesis: originatingHypothesis,
        traits: traits,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'identity': identity,
        'fingerprint': fingerprint,
        'state': _enumName(state),
        'evidenceReferenceIds': evidenceReferenceIds,
        'rejectionReasons': rejectionReasons,
        'sponsorVote': _enumName(sponsorVote),
        'strong': strong,
        'oneSentenceIdea': oneSentenceIdea,
        'intendedConsumer': intendedConsumer,
        'painOrDesire': painOrDesire,
        'audienceRationale': audienceRationale,
        'simplestProduct': simplestProduct,
        'moneyPath': moneyPath,
        'strongestRejection': strongestRejection,
        'proofState': proofState,
        'originatingAttemptId': originatingAttemptId,
        'originatingHypothesis': originatingHypothesis,
        'traits': traits,
      };

  factory ScanCandidate.fromJson(Map<Object?, Object?> json) => ScanCandidate(
        id: json['id']?.toString() ?? '',
        identity: json['identity']?.toString() ?? '',
        fingerprint: json['fingerprint']?.toString() ?? '',
        state: _safePersistedCandidateState(json['state']),
        evidenceReferenceIds:
            (json['evidenceReferenceIds'] as List? ?? const [])
                .map((value) => value.toString())
                .toList(growable: false),
        rejectionReasons: (json['rejectionReasons'] as List? ?? const [])
            .map((value) => value.toString())
            .toList(growable: false),
        sponsorVote: _enumOr(
          SponsorVote.values,
          json['sponsorVote'],
          SponsorVote.none,
        ),
        strong: json['strong'] == true,
        oneSentenceIdea: json['oneSentenceIdea']?.toString() ?? '',
        intendedConsumer: json['intendedConsumer']?.toString() ?? '',
        painOrDesire: json['painOrDesire']?.toString() ?? '',
        audienceRationale: json['audienceRationale']?.toString() ?? '',
        simplestProduct: json['simplestProduct']?.toString() ?? '',
        moneyPath: json['moneyPath']?.toString() ?? '',
        strongestRejection: json['strongestRejection']?.toString() ?? '',
        proofState: json['proofState']?.toString() ?? 'UNVERIFIED',
        originatingAttemptId: json['originatingAttemptId']?.toString() ?? '',
        originatingHypothesis: json['originatingHypothesis']?.toString() ?? '',
        traits: (json['traits'] as List? ?? const [])
            .map((value) => value.toString())
            .toList(growable: false),
      );
}

class ScanCandidateObservation {
  final String id;
  final String identity;
  final String fingerprint;
  final bool reviewWorthy;
  final bool strong;
  final List<String> evidenceReferenceIds;
  final List<String> rejectionReasons;
  final String oneSentenceIdea;
  final String intendedConsumer;
  final String painOrDesire;
  final String audienceRationale;
  final String simplestProduct;
  final String moneyPath;
  final String strongestRejection;
  final String proofState;
  final List<String> traits;

  const ScanCandidateObservation({
    required this.id,
    required this.identity,
    required this.fingerprint,
    this.reviewWorthy = false,
    this.strong = false,
    this.evidenceReferenceIds = const [],
    this.rejectionReasons = const [],
    this.oneSentenceIdea = '',
    this.intendedConsumer = '',
    this.painOrDesire = '',
    this.audienceRationale = '',
    this.simplestProduct = '',
    this.moneyPath = '',
    this.strongestRejection = '',
    this.proofState = 'UNVERIFIED',
    this.traits = const [],
  });
}

class SponsorVerdictRecord {
  final String sessionId;
  final String candidateId;
  final SponsorVote verdict;
  final List<String> traits;
  final List<String> evidenceReferenceIds;
  final String? sponsorReason;
  final int recordedAtMs;

  const SponsorVerdictRecord({
    required this.sessionId,
    required this.candidateId,
    required this.verdict,
    required this.traits,
    required this.evidenceReferenceIds,
    required this.recordedAtMs,
    this.sponsorReason,
  });

  Map<String, Object?> toJson() => {
        'sessionId': sessionId,
        'candidateId': candidateId,
        'verdict': _enumName(verdict),
        'traits': traits,
        'evidenceReferenceIds': evidenceReferenceIds,
        'sponsorReason': sponsorReason,
        'recordedAtMs': recordedAtMs,
      };

  factory SponsorVerdictRecord.fromJson(Map<Object?, Object?> json) =>
      SponsorVerdictRecord(
        sessionId: json['sessionId']?.toString() ?? '',
        candidateId: json['candidateId']?.toString() ?? '',
        verdict: _enumOr(SponsorVote.values, json['verdict'], SponsorVote.none),
        traits: (json['traits'] as List? ?? const [])
            .map((value) => value.toString())
            .toList(growable: false),
        evidenceReferenceIds:
            (json['evidenceReferenceIds'] as List? ?? const [])
                .map((value) => value.toString())
                .toList(growable: false),
        sponsorReason: json['sponsorReason']?.toString(),
        recordedAtMs: (json['recordedAtMs'] as num?)?.toInt() ?? 0,
      );
}

class ScanWorkPacket {
  final String id;
  final String hypothesis;
  final String query;
  final List<ScanFilter> filters;
  final List<String> requestedSources;

  const ScanWorkPacket({
    required this.id,
    required this.hypothesis,
    required this.query,
    this.filters = const [],
    this.requestedSources = const [],
  });

  String get fingerprint => canonicalFingerprint([
        hypothesis,
        query,
        ...filters.map((filter) => '${filter.name}=${filter.value}'),
        ...requestedSources,
      ]);
}

/// Adapter boundary only. No production implementation is supplied in this
/// block, so live external execution remains UNVERIFIED.
abstract class FactoryScanSearchAdapter {
  Future<ScanAttemptResult> execute(ScanWorkPacket packet);
}

class ScanAttemptResult {
  final String attemptId;
  final ScanExecutionState executionState;
  final int resultCount;
  final List<ScanEvidenceReference> evidence;
  final List<ScanCandidateObservation> candidates;
  final String? causalFailure;
  final ProviderUsage usage;
  final List<WasteKind> wasteSignals;
  final ScanCalibrationChange? calibrationChange;
  final int completedAtMs;

  const ScanAttemptResult({
    required this.attemptId,
    required this.executionState,
    required this.completedAtMs,
    this.resultCount = 0,
    this.evidence = const [],
    this.candidates = const [],
    this.causalFailure,
    this.usage = const ProviderUsage(),
    this.wasteSignals = const [],
    this.calibrationChange,
  });
}

class ScanAttempt {
  final String id;
  final String fingerprint;
  final String hypothesis;
  final String query;
  final List<ScanFilter> filters;
  final List<String> requestedSources;
  final ScanExecutionState executionState;
  final int resultCount;
  final List<String> evidenceReferenceIds;
  final List<String> candidateIds;
  final String? causalFailure;
  final ProviderUsage usage;
  final List<WasteKind> wasteSignals;
  final int completedAtMs;

  const ScanAttempt({
    required this.id,
    required this.fingerprint,
    required this.hypothesis,
    required this.query,
    required this.filters,
    required this.requestedSources,
    required this.executionState,
    required this.resultCount,
    required this.evidenceReferenceIds,
    required this.candidateIds,
    required this.usage,
    required this.wasteSignals,
    required this.completedAtMs,
    this.causalFailure,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'fingerprint': fingerprint,
        'hypothesis': hypothesis,
        'query': query,
        'filters': filters.map((value) => value.toJson()).toList(),
        'requestedSources': requestedSources,
        'executionState': _enumName(executionState),
        'resultCount': resultCount,
        'evidenceReferenceIds': evidenceReferenceIds,
        'candidateIds': candidateIds,
        'causalFailure': causalFailure,
        'usage': usage.toJson(),
        'wasteSignals': wasteSignals.map(_enumName).toList(),
        'completedAtMs': completedAtMs,
      };

  factory ScanAttempt.fromJson(Map<Object?, Object?> json) => ScanAttempt(
        id: json['id']?.toString() ?? '',
        fingerprint: json['fingerprint']?.toString() ?? '',
        hypothesis: json['hypothesis']?.toString() ?? '',
        query: json['query']?.toString() ?? '',
        filters: (json['filters'] as List? ?? const [])
            .whereType<Map>()
            .map((value) => ScanFilter.fromJson(value))
            .toList(growable: false),
        requestedSources: (json['requestedSources'] as List? ?? const [])
            .map((value) => value.toString())
            .toList(growable: false),
        executionState: _enumOr(
          ScanExecutionState.values,
          json['executionState'],
          ScanExecutionState.failed,
        ),
        resultCount: (json['resultCount'] as num?)?.toInt() ?? 0,
        evidenceReferenceIds:
            (json['evidenceReferenceIds'] as List? ?? const [])
                .map((value) => value.toString())
                .toList(growable: false),
        candidateIds: (json['candidateIds'] as List? ?? const [])
            .map((value) => value.toString())
            .toList(growable: false),
        causalFailure: json['causalFailure']?.toString(),
        usage: json['usage'] is Map
            ? ProviderUsage.fromJson(json['usage'] as Map)
            : const ProviderUsage(),
        wasteSignals: (json['wasteSignals'] as List? ?? const [])
            .map((value) => _enumOr(
                  WasteKind.values,
                  value,
                  WasteKind.failedToolCall,
                ))
            .toList(growable: false),
        completedAtMs: (json['completedAtMs'] as num?)?.toInt() ?? 0,
      );
}

class FailedScanRound {
  final String hypothesis;
  final String causalFailure;
  final String attemptFingerprint;
  const FailedScanRound({
    required this.hypothesis,
    required this.causalFailure,
    required this.attemptFingerprint,
  });

  Map<String, Object?> toJson() => {
        'hypothesis': hypothesis,
        'causalFailure': causalFailure,
        'attemptFingerprint': attemptFingerprint,
      };
  factory FailedScanRound.fromJson(Map<Object?, Object?> json) =>
      FailedScanRound(
        hypothesis: json['hypothesis']?.toString() ?? '',
        causalFailure: json['causalFailure']?.toString() ?? '',
        attemptFingerprint: json['attemptFingerprint']?.toString() ?? '',
      );
}

/// Deliberately data-only. The controller can validate this capability but
/// cannot mint it; a sponsor-owned UI/storage seam must construct it.
class SponsorBlueprintAuthorization {
  final String sessionId;
  final String candidateId;
  final String approvedBy;
  final int approvedAtMs;
  const SponsorBlueprintAuthorization({
    required this.sessionId,
    required this.candidateId,
    required this.approvedBy,
    required this.approvedAtMs,
  });
}

class BlueprintAuthorizationCheck {
  final bool accepted;
  final String reason;
  const BlueprintAuthorizationCheck(this.accepted, this.reason);
}

class ScanAudit {
  final ScanEfficiency efficiency;
  final ScanEffectiveness effectiveness;
  final List<String> efficiencyReasons;
  final List<String> effectivenessReasons;
  final Map<WasteKind, int> wasteCounts;
  final int? exactTokens;
  final double? exactCredits;

  const ScanAudit({
    required this.efficiency,
    required this.effectiveness,
    required this.efficiencyReasons,
    required this.effectivenessReasons,
    required this.wasteCounts,
    this.exactTokens,
    this.exactCredits,
  });

  Map<String, Object?> toJson() => {
        'efficiency': _enumName(efficiency),
        'effectiveness': _enumName(effectiveness),
        'efficiencyReasons': efficiencyReasons,
        'effectivenessReasons': effectivenessReasons,
        'wasteCounts':
            wasteCounts.map((key, value) => MapEntry(_enumName(key), value)),
        'exactTokens': exactTokens,
        'exactCredits': exactCredits,
      };
}

class ScanMutation {
  final FactoryScanSession session;
  final bool accepted;
  final String reason;
  const ScanMutation(this.session, this.accepted, this.reason);
}

class FactoryScanSession {
  final int schemaVersion;
  final String id;
  final int startedAtMs;
  final int deadlineAtMs;
  final String scanPolicyVersion;
  final List<ScanAttempt> attempts;
  final List<ScanEvidenceReference> evidence;
  final List<ScanCandidate> candidates;
  final List<ScanCalibrationChange> calibrationChanges;
  final List<FailedScanRound> failedRounds;
  final List<WasteKind> suppressedWasteSignals;
  final List<SponsorVerdictRecord> verdictHistory;
  final String currentAction;
  final String nextSafeAction;
  final bool territorySwitchRequired;
  final bool reviewBackpressure;
  final bool changedHypothesisRequired;
  final List<String> lockedTerritoryKeys;

  const FactoryScanSession({
    this.schemaVersion = factoryScanSchemaVersion,
    required this.id,
    required this.startedAtMs,
    required this.deadlineAtMs,
    required this.scanPolicyVersion,
    this.attempts = const [],
    this.evidence = const [],
    this.candidates = const [],
    this.calibrationChanges = const [],
    this.failedRounds = const [],
    this.suppressedWasteSignals = const [],
    this.verdictHistory = const [],
    this.currentAction = 'Prepare the first materially distinct search packet.',
    this.nextSafeAction = 'Submit a governed search work packet.',
    this.territorySwitchRequired = false,
    this.reviewBackpressure = false,
    this.changedHypothesisRequired = false,
    this.lockedTerritoryKeys = const [],
  });

  factory FactoryScanSession.start({
    required String id,
    required int startedAtMs,
    required String scanPolicyVersion,
  }) {
    if (id.trim().isEmpty) throw ArgumentError('session id must be stable');
    if (scanPolicyVersion.trim().isEmpty) {
      throw ArgumentError('scan policy version is required');
    }
    return FactoryScanSession(
      id: id.trim(),
      startedAtMs: startedAtMs,
      deadlineAtMs: startedAtMs + factoryScanTimebox.inMilliseconds,
      scanPolicyVersion: scanPolicyVersion.trim(),
    );
  }

  bool isCompleteAt(int nowMs) => nowMs >= deadlineAtMs;
  int remainingMsAt(int nowMs) =>
      nowMs >= deadlineAtMs ? 0 : deadlineAtMs - nowMs;

  int get awaitingVotes => candidates
      .where((candidate) => candidate.state == ScanCandidateState.awaitingVote)
      .length;
  int get credibleCandidates => candidates
      .where((candidate) => const {
            ScanCandidateState.awaitingVote,
            ScanCandidateState.yesShortlist,
            ScanCandidateState.maybeIncubate,
            ScanCandidateState.closeRepair,
            ScanCandidateState.laterRetained,
            ScanCandidateState.blueprintAuthorized,
          }.contains(candidate.state))
      .length;
  int get duplicateRejections => candidates
      .where((candidate) =>
          candidate.rejectionReasons.contains('duplicate fingerprint'))
      .length;
  int get rejections => candidates
      .where((candidate) =>
          candidate.state == ScanCandidateState.rejected ||
          candidate.state == ScanCandidateState.noArchived)
      .length;

  ScanMutation recordCompletedAttempt(
    ScanWorkPacket packet,
    ScanAttemptResult result,
  ) {
    if (result.executionState == ScanExecutionState.pending) {
      return ScanMutation(
          this, false, 'pending work is not completed search evidence');
    }
    if (result.attemptId != packet.id) {
      return ScanMutation(
          this, false, 'adapter result does not name this packet');
    }
    if (attempts.any((attempt) => attempt.fingerprint == packet.fingerprint)) {
      return ScanMutation(
        _copyWith(
          suppressedWasteSignals: [
            ...suppressedWasteSignals,
            WasteKind.duplicateSearch,
            WasteKind.repeatedPacket,
          ],
          currentAction: 'Suppressed an identical search packet.',
          nextSafeAction:
              'Change the hypothesis and submit a materially distinct packet.',
          changedHypothesisRequired: true,
        ),
        false,
        'identical attempt suppressed',
      );
    }
    if (reviewBackpressure) {
      return ScanMutation(
          this, false, 'three strong candidates await sponsor review');
    }
    if (lockedTerritoryKeys
        .contains(canonicalFingerprint([packet.hypothesis]))) {
      return ScanMutation(
          this, false, 'this failed hypothesis is stopped; switch territory');
    }
    final incomingFailure = result.causalFailure?.trim().isNotEmpty == true
        ? result.causalFailure!.trim()
        : result.executionState == ScanExecutionState.failed
            ? 'tool failure'
            : null;
    final projectedSameFailureCount = incomingFailure == null
        ? 0
        : failedRounds
                .where((failure) =>
                    canonicalFingerprint(
                        [failure.hypothesis, failure.causalFailure]) ==
                    canonicalFingerprint([packet.hypothesis, incomingFailure]))
                .length +
            1;
    // Permit only the materially distinct third confirmation needed to close a
    // repeatedly failing territory. It is recorded, then the territory locks.
    if (changedHypothesisRequired &&
        projectedSameFailureCount < 3 &&
        attempts.isNotEmpty &&
        canonicalFingerprint([packet.hypothesis]) ==
            canonicalFingerprint([attempts.last.hypothesis])) {
      return ScanMutation(
        _copyWith(suppressedWasteSignals: [
          ...suppressedWasteSignals,
          WasteKind.unchangedRetry,
        ]),
        false,
        'wasteful round requires a changed hypothesis',
      );
    }

    final reviewCount =
        result.candidates.where((value) => value.reviewWorthy).length;
    final calibration = result.calibrationChange;
    if (result.executionState == ScanExecutionState.completed &&
        reviewCount == 0) {
      if (calibration == null ||
          calibration.direction != CalibrationDirection.loosen ||
          !calibration.materiallyChangesFilter) {
        return ScanMutation(this, false,
            'zero credible hits must loosen exactly one recorded filter');
      }
    }
    if (result.executionState == ScanExecutionState.completed &&
        reviewCount > 4) {
      if (calibration == null ||
          calibration.direction != CalibrationDirection.tighten ||
          !calibration.materiallyChangesFilter) {
        return ScanMutation(this, false,
            'over-broad result must tighten exactly one recorded filter');
      }
    }

    final knownFingerprints =
        candidates.map((value) => value.fingerprint).toSet();
    final knownCandidateIds = candidates.map((value) => value.id).toSet();
    final availableEvidenceIds = <String>{
      ...evidence.map((value) => value.id),
      ...result.evidence.map((value) => value.id),
    };
    final nextCandidates = [...candidates];
    final observedIds = <String>[];
    final attemptWaste = [...result.wasteSignals];
    for (final observed in result.candidates) {
      if (!knownCandidateIds.add(observed.id)) {
        return ScanMutation(
            this, false, 'candidate id ${observed.id} is not unique');
      }
      final unresolved = observed.evidenceReferenceIds
          .where((id) => !availableEvidenceIds.contains(id))
          .toList(growable: false);
      if ((observed.reviewWorthy || observed.strong) && unresolved.isNotEmpty) {
        return ScanMutation(this, false,
            'candidate ${observed.id} has unresolved evidence references: ${unresolved.join(', ')}');
      }
      observedIds.add(observed.id);
      final duplicate = knownFingerprints.contains(observed.fingerprint);
      if (duplicate) {
        nextCandidates.add(ScanCandidate(
          id: observed.id,
          identity: observed.identity,
          fingerprint: observed.fingerprint,
          state: ScanCandidateState.rejected,
          evidenceReferenceIds: observed.evidenceReferenceIds,
          rejectionReasons: const ['duplicate fingerprint'],
          originatingAttemptId: packet.id,
          originatingHypothesis: packet.hypothesis,
        ));
        attemptWaste.add(WasteKind.repeatedPacket);
      } else {
        knownFingerprints.add(observed.fingerprint);
        nextCandidates.add(ScanCandidate(
          id: observed.id,
          identity: observed.identity,
          fingerprint: observed.fingerprint,
          state: observed.reviewWorthy
              ? ScanCandidateState.awaitingVote
              : observed.rejectionReasons.isNotEmpty
                  ? ScanCandidateState.rejected
                  : ScanCandidateState.discovered,
          evidenceReferenceIds: observed.evidenceReferenceIds,
          rejectionReasons: observed.rejectionReasons,
          strong: observed.strong,
          oneSentenceIdea: observed.oneSentenceIdea,
          intendedConsumer: observed.intendedConsumer,
          painOrDesire: observed.painOrDesire,
          audienceRationale: observed.audienceRationale,
          simplestProduct: observed.simplestProduct,
          moneyPath: observed.moneyPath,
          strongestRejection: observed.strongestRejection,
          proofState: observed.proofState,
          originatingAttemptId: packet.id,
          originatingHypothesis: packet.hypothesis,
          traits: observed.traits,
        ));
      }
    }

    final evidenceIds =
        result.evidence.map((value) => value.id).toList(growable: false);
    if (evidenceIds.isEmpty &&
        result.executionState == ScanExecutionState.completed) {
      attemptWaste.add(WasteKind.timeWithoutNewEvidence);
    }
    if (result.executionState == ScanExecutionState.failed) {
      attemptWaste.add(WasteKind.failedToolCall);
    }
    final uniqueWaste = attemptWaste.toSet().toList(growable: false);
    final attempt = ScanAttempt(
      id: packet.id,
      fingerprint: packet.fingerprint,
      hypothesis: packet.hypothesis,
      query: packet.query,
      filters: List.unmodifiable(packet.filters),
      requestedSources: List.unmodifiable(packet.requestedSources),
      executionState: result.executionState,
      resultCount: result.resultCount,
      evidenceReferenceIds: evidenceIds,
      candidateIds: observedIds,
      causalFailure: result.causalFailure,
      usage: result.usage,
      wasteSignals: uniqueWaste,
      completedAtMs: result.completedAtMs,
    );

    final nextFailures = [...failedRounds];
    if (result.executionState == ScanExecutionState.failed ||
        (result.causalFailure?.trim().isNotEmpty ?? false)) {
      nextFailures.add(FailedScanRound(
        hypothesis: packet.hypothesis,
        causalFailure: result.causalFailure?.trim().isNotEmpty == true
            ? result.causalFailure!.trim()
            : 'tool failure',
        attemptFingerprint: packet.fingerprint,
      ));
    }
    final sameFailureCount = projectedSameFailureCount;
    final switchTerritory = sameFailureCount >= 3;
    final nextLockedTerritories = <String>{...lockedTerritoryKeys};
    if (switchTerritory) {
      nextLockedTerritories.add(canonicalFingerprint([packet.hypothesis]));
    }
    final strongUnreviewed = nextCandidates
        .where((candidate) =>
            candidate.state == ScanCandidateState.awaitingVote &&
            candidate.strong)
        .length;
    final backpressure = strongUnreviewed >= 3;
    final tentative = _copyWith(
      attempts: [...attempts, attempt],
      evidence: [...evidence, ...result.evidence],
      candidates: nextCandidates,
      calibrationChanges: calibration == null
          ? calibrationChanges
          : [...calibrationChanges, calibration],
      failedRounds: nextFailures,
      territorySwitchRequired: switchTerritory,
      reviewBackpressure: backpressure,
      lockedTerritoryKeys: nextLockedTerritories.toList(growable: false),
    );
    final audit = tentative.audit;
    return ScanMutation(
      tentative._copyWith(
        changedHypothesisRequired: audit.efficiency == ScanEfficiency.wasteful,
        currentAction: switchTerritory
            ? 'Stopped the repeated failing hypothesis.'
            : backpressure
                ? 'Paused scanning for sponsor review.'
                : 'Recorded completed attempt ${packet.id}.',
        nextSafeAction: switchTerritory
            ? 'Switch territory and submit a materially distinct hypothesis.'
            : backpressure
                ? 'Sponsor reviews the three strong candidates.'
                : audit.efficiency == ScanEfficiency.wasteful
                    ? 'Change the hypothesis before another search packet.'
                    : 'Prepare the next materially distinct governed packet.',
      ),
      true,
      'attempt recorded',
    );
  }

  ScanMutation recordSponsorVote(
    String candidateId,
    SponsorVote vote, {
    required int recordedAtMs,
    String? sponsorReason,
  }) {
    if (vote == SponsorVote.none) {
      return ScanMutation(this, false, 'a sponsor vote must be explicit');
    }
    final index =
        candidates.indexWhere((candidate) => candidate.id == candidateId);
    if (index < 0) return ScanMutation(this, false, 'candidate not found');
    if (candidates[index].state == ScanCandidateState.rejected ||
        candidates[index].state == ScanCandidateState.blueprintAuthorized) {
      return ScanMutation(
          this, false, 'candidate state cannot receive a sponsor verdict');
    }
    final state = switch (vote) {
      SponsorVote.yes => ScanCandidateState.yesShortlist,
      SponsorVote.maybe => ScanCandidateState.maybeIncubate,
      SponsorVote.no => ScanCandidateState.noArchived,
      SponsorVote.later => ScanCandidateState.laterRetained,
      SponsorVote.none => candidates[index].state,
    };
    final updated = [...candidates];
    updated[index] = updated[index].copyWith(state: state, sponsorVote: vote);
    final remainingStrong = updated
        .where((candidate) =>
            candidate.state == ScanCandidateState.awaitingVote &&
            candidate.strong)
        .length;
    return ScanMutation(
      _copyWith(
        candidates: updated,
        verdictHistory: [
          ...verdictHistory,
          SponsorVerdictRecord(
            sessionId: id,
            candidateId: candidateId,
            verdict: vote,
            traits: candidates[index].traits,
            evidenceReferenceIds: candidates[index].evidenceReferenceIds,
            sponsorReason: sponsorReason?.trim().isEmpty == true
                ? null
                : sponsorReason?.trim(),
            recordedAtMs: recordedAtMs,
          ),
        ],
        reviewBackpressure: remainingStrong >= 3,
        currentAction: 'Recorded sponsor vote for $candidateId.',
        nextSafeAction: vote == SponsorVote.yes
            ? 'Keep the candidate shortlisted; await separate run-bound Blueprint authorization.'
            : vote == SponsorVote.later
                ? 'Retain without active refinement until the sponsor explicitly revisits it.'
                : 'Continue only with the sponsor-directed candidate disposition.',
      ),
      true,
      vote == SponsorVote.yes
          ? 'YES shortlisted only; Blueprint remains locked'
          : 'sponsor vote recorded',
    );
  }

  /// Transparent trait signal for a later scan. Positive means sponsor YES,
  /// MAYBE, or LATER retained the trait; negative means NO rejected it. This is
  /// an exposed ranking input, not opaque personal learning.
  Map<String, int> get transparentTraitWeights {
    final weights = <String, int>{};
    for (final verdict in verdictHistory) {
      final delta = switch (verdict.verdict) {
        SponsorVote.yes => 2,
        SponsorVote.maybe => 1,
        SponsorVote.later => 0,
        SponsorVote.no => -2,
        SponsorVote.none => 0,
      };
      for (final trait in verdict.traits) {
        weights[trait] = (weights[trait] ?? 0) + delta;
      }
    }
    return weights;
  }

  /// Structural validation only. This block has no trusted sponsor adapter and
  /// therefore deliberately has no method that mutates a candidate into
  /// Blueprint from agent-constructible data.
  BlueprintAuthorizationCheck checkBlueprintAuthorization(
      SponsorBlueprintAuthorization authorization) {
    if (authorization.sessionId != id) {
      return const BlueprintAuthorizationCheck(false,
          'authorization belongs to another scan session and is not transferable');
    }
    if (authorization.approvedBy.trim().isEmpty ||
        authorization.approvedAtMs <= 0) {
      return const BlueprintAuthorizationCheck(
          false, 'authorization is malformed');
    }
    final index = candidates
        .indexWhere((candidate) => candidate.id == authorization.candidateId);
    if (index < 0) {
      return const BlueprintAuthorizationCheck(
          false, 'authorization candidate is not in this session');
    }
    if (candidates[index].state != ScanCandidateState.yesShortlist) {
      return const BlueprintAuthorizationCheck(
          false, 'candidate must first be an explicit YES shortlist');
    }
    final yesRecord = verdictHistory.any((record) =>
        record.sessionId == id &&
        record.candidateId == authorization.candidateId &&
        record.verdict == SponsorVote.yes &&
        record.recordedAtMs <= authorization.approvedAtMs);
    if (!yesRecord) {
      return const BlueprintAuthorizationCheck(false,
          'authorization is not bound to a prior exact-session YES verdict');
    }
    return const BlueprintAuthorizationCheck(true,
        'exact run-bound authorization record is structurally valid; trusted sponsor verification remains required');
  }

  ScanAudit get audit {
    final counts = <WasteKind, int>{};
    for (final signal in suppressedWasteSignals) {
      counts[signal] = (counts[signal] ?? 0) + 1;
    }
    for (final attempt in attempts) {
      for (final signal in attempt.wasteSignals) {
        counts[signal] = (counts[signal] ?? 0) + 1;
      }
    }
    final severe = (counts[WasteKind.unchangedRetry] ?? 0) +
        (counts[WasteKind.duplicateSearch] ?? 0);
    final totalWaste = counts.values.fold<int>(0, (sum, value) => sum + value);
    final efficiency = severe > 0 || totalWaste >= 3
        ? ScanEfficiency.wasteful
        : totalWaste > 0
            ? ScanEfficiency.mixed
            : ScanEfficiency.efficient;
    final efficiencyReasons = <String>[
      if (totalWaste == 0) 'No concrete waste proxy was recorded.',
      for (final entry in counts.entries)
        '${_enumName(entry.key)}: ${entry.value}',
    ];
    final credible = credibleCandidates;
    final effectiveness = credible >= 2 && credible <= 4
        ? ScanEffectiveness.high
        : credible > 0
            ? ScanEffectiveness.medium
            : evidence.isNotEmpty
                ? ScanEffectiveness.low
                : ScanEffectiveness.zero;
    final effectivenessReasons = <String>[
      '$credible credible candidate(s); target is 2-4.',
      '${evidence.length} retained evidence reference(s).',
      '${failedRounds.length} failed round(s) remain evidence, not progress.',
    ];
    int? tokens;
    double? credits;
    for (final attempt in attempts) {
      if (attempt.usage.exactTokens != null) {
        tokens = (tokens ?? 0) + attempt.usage.exactTokens!;
      }
      if (attempt.usage.exactCredits != null) {
        credits = (credits ?? 0) + attempt.usage.exactCredits!;
      }
    }
    return ScanAudit(
      efficiency: efficiency,
      effectiveness: effectiveness,
      efficiencyReasons: efficiencyReasons,
      effectivenessReasons: effectivenessReasons,
      wasteCounts: counts,
      exactTokens: tokens,
      exactCredits: credits,
    );
  }

  String hudAt(int nowMs) {
    final report = audit;
    final complete = isCompleteAt(nowMs);
    final minutes =
        (remainingMsAt(nowMs) / Duration.millisecondsPerMinute).ceil();
    final wasteReason = report.wasteCounts.isEmpty
        ? 'none'
        : report.efficiencyReasons.skip(1).join(', ');
    return 'Signal Scan ${complete ? 'complete' : '$minutes minute(s) remaining'}. '
        'Attempts: ${attempts.length}. Credible candidates: $credibleCandidates. '
        'Awaiting votes: $awaitingVotes. Duplicates: $duplicateRejections. '
        'Rejections: $rejections. Failed rounds: ${failedRounds.length}. '
        'Efficiency: ${_enumName(report.efficiency).toUpperCase()}. '
        'Effectiveness: ${_enumName(report.effectiveness).toUpperCase()}. '
        'Wasted-token warning: ${report.efficiency == ScanEfficiency.wasteful ? 'YES' : 'NO'} ($wasteReason). '
        'Token usage: ${report.exactTokens?.toString() ?? 'unavailable'}. '
        'Current action: $currentAction Exact next safe action: $nextSafeAction';
  }

  FactoryScanSession _copyWith({
    List<ScanAttempt>? attempts,
    List<ScanEvidenceReference>? evidence,
    List<ScanCandidate>? candidates,
    List<ScanCalibrationChange>? calibrationChanges,
    List<FailedScanRound>? failedRounds,
    List<WasteKind>? suppressedWasteSignals,
    List<SponsorVerdictRecord>? verdictHistory,
    String? currentAction,
    String? nextSafeAction,
    bool? territorySwitchRequired,
    bool? reviewBackpressure,
    bool? changedHypothesisRequired,
    List<String>? lockedTerritoryKeys,
  }) =>
      FactoryScanSession(
        schemaVersion: schemaVersion,
        id: id,
        startedAtMs: startedAtMs,
        deadlineAtMs: deadlineAtMs,
        scanPolicyVersion: scanPolicyVersion,
        attempts: attempts ?? this.attempts,
        evidence: evidence ?? this.evidence,
        candidates: candidates ?? this.candidates,
        calibrationChanges: calibrationChanges ?? this.calibrationChanges,
        failedRounds: failedRounds ?? this.failedRounds,
        suppressedWasteSignals:
            suppressedWasteSignals ?? this.suppressedWasteSignals,
        verdictHistory: verdictHistory ?? this.verdictHistory,
        currentAction: currentAction ?? this.currentAction,
        nextSafeAction: nextSafeAction ?? this.nextSafeAction,
        territorySwitchRequired:
            territorySwitchRequired ?? this.territorySwitchRequired,
        reviewBackpressure: reviewBackpressure ?? this.reviewBackpressure,
        changedHypothesisRequired:
            changedHypothesisRequired ?? this.changedHypothesisRequired,
        lockedTerritoryKeys: lockedTerritoryKeys ?? this.lockedTerritoryKeys,
      );

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'startedAtMs': startedAtMs,
        'deadlineAtMs': deadlineAtMs,
        'scanPolicyVersion': scanPolicyVersion,
        'attempts': attempts.map((value) => value.toJson()).toList(),
        'evidence': evidence.map((value) => value.toJson()).toList(),
        'candidates': candidates.map((value) => value.toJson()).toList(),
        'calibrationChanges':
            calibrationChanges.map((value) => value.toJson()).toList(),
        'failedRounds': failedRounds.map((value) => value.toJson()).toList(),
        'suppressedWasteSignals':
            suppressedWasteSignals.map(_enumName).toList(),
        'verdictHistory':
            verdictHistory.map((value) => value.toJson()).toList(),
        'transparentTraitWeights': transparentTraitWeights,
        'currentAction': currentAction,
        'nextSafeAction': nextSafeAction,
        'territorySwitchRequired': territorySwitchRequired,
        'reviewBackpressure': reviewBackpressure,
        'changedHypothesisRequired': changedHypothesisRequired,
        'lockedTerritoryKeys': lockedTerritoryKeys,
        'audit': audit.toJson(),
      };

  /// Missing collections and schema 0 are migrated to safe empty defaults.
  /// Future schemas fail closed instead of being misread.
  factory FactoryScanSession.fromJson(Map<Object?, Object?> json) {
    final schema = (json['schemaVersion'] as num?)?.toInt() ?? 0;
    if (schema > factoryScanSchemaVersion) {
      throw FormatException('unsupported FactoryScanSession schema $schema');
    }
    final started = (json['startedAtMs'] as num?)?.toInt() ?? 0;
    return FactoryScanSession(
      schemaVersion: factoryScanSchemaVersion,
      id: json['id']?.toString() ?? '',
      startedAtMs: started,
      deadlineAtMs: (json['deadlineAtMs'] as num?)?.toInt() ??
          started + factoryScanTimebox.inMilliseconds,
      scanPolicyVersion:
          json['scanPolicyVersion']?.toString() ?? 'legacy-unversioned',
      attempts: (json['attempts'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => ScanAttempt.fromJson(value))
          .toList(growable: false),
      evidence: (json['evidence'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => ScanEvidenceReference.fromJson(value))
          .toList(growable: false),
      candidates: (json['candidates'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => ScanCandidate.fromJson(value))
          .toList(growable: false),
      calibrationChanges: (json['calibrationChanges'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => ScanCalibrationChange.fromJson(value))
          .toList(growable: false),
      failedRounds: (json['failedRounds'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => FailedScanRound.fromJson(value))
          .toList(growable: false),
      suppressedWasteSignals:
          (json['suppressedWasteSignals'] as List? ?? const [])
              .map((value) => _enumOr(
                    WasteKind.values,
                    value,
                    WasteKind.failedToolCall,
                  ))
              .toList(growable: false),
      verdictHistory: (json['verdictHistory'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => SponsorVerdictRecord.fromJson(value))
          .toList(growable: false),
      currentAction:
          json['currentAction']?.toString() ?? 'Loaded legacy scan session.',
      nextSafeAction: json['nextSafeAction']?.toString() ??
          'Review migrated session before continuing.',
      territorySwitchRequired: json['territorySwitchRequired'] == true,
      reviewBackpressure: json['reviewBackpressure'] == true,
      changedHypothesisRequired: json['changedHypothesisRequired'] == true,
      lockedTerritoryKeys: (json['lockedTerritoryKeys'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }
}
