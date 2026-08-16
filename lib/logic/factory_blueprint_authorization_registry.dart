part of 'factory_scan_session.dart';

const String legacyTablefinderFactoryRunId =
    'factory-run-legacy-recovery-20260809-tablefinder-01';
const String legacyTablefinderScanSessionId =
    'factory-scan-legacy-recovery-20260809-tablefinder-01';
const String legacyTablefinderConceptId = 'FSC-LEGACY-YES-001';
const String legacyTablefinderAuthorizationId =
    'BPA-20260809-FSC-LEGACY-YES-001';
const String legacyTablefinderWorkingName = 'Find My Table — Bahrain';

/// Added only after the supervising sponsor record explicitly named this
/// concept and requested Blueprint. Runtime agents cannot add another entry to
/// this compiled registry.
const Map<String, SponsorBlueprintAuthorization>
    registeredFactoryBlueprintAuthorizations = {
  legacyTablefinderAuthorizationId: SponsorBlueprintAuthorization(
    authorizationId: legacyTablefinderAuthorizationId,
    factoryRunId: legacyTablefinderFactoryRunId,
    sessionId: legacyTablefinderScanSessionId,
    candidateId: legacyTablefinderConceptId,
    approvedBy: 'sadeq',
    approvedAtMs: 1786274402372,
    sponsorEvidence:
        'Supervising Factory record: Sadeq originated the TTRPG/board-game group-matching concept, previously voted YES, and explicitly requested moving this exact concept to Blueprint.',
  ),
};

/// Creates a current recovery session without claiming that these identifiers
/// or timestamps existed in the lost historical run.
FactoryScanSession createLegacyTablefinderRecoverySession() {
  var session = FactoryScanSession.start(
    factoryRunId: legacyTablefinderFactoryRunId,
    id: legacyTablefinderScanSessionId,
    startedAtMs: 1786274402342,
    scanPolicyVersion: 'signal-scan-v1-legacy-recovery',
  );
  const evidence = [
    ScanEvidenceReference(
      id: 'LY-E-001',
      source: 'Bahrain Tourism',
      reference: 'https://www.bahrain.com/en/the-tavern-eatery-and-hobbie',
      observedFact:
          'The Tavern is a public Bahrain venue offering board and card games.',
    ),
    ScanEvidenceReference(
      id: 'LY-E-002',
      source: 'Manama Boardgames Meetup',
      reference: 'https://www.meetup.com/meetup-group-amjsbtqo/',
      observedFact: 'The group lists 81 members and no upcoming events.',
    ),
    ScanEvidenceReference(
      id: 'LY-E-003',
      source: 'Bahrain community discussion',
      reference:
          'https://www.reddit.com/r/Bahrain/comments/1vdc6bo/board_games/',
      observedFact:
          'A recent local post asks where to meet new board-game players.',
    ),
    ScanEvidenceReference(
      id: 'LY-E-004',
      source: 'Competitor evidence',
      reference: 'https://groupfinder.eu/welcome',
      observedFact:
          'A free global tabletop group finder reports active profiles and group posts.',
    ),
  ];
  const packet = ScanWorkPacket(
    id: 'legacy-recovery-attempt-001',
    hypothesis:
        'Bahrain tabletop players need reliable public-venue group formation.',
    query: 'Recovered sponsor concept plus credential-free evidence refresh',
    filters: [
      ScanFilter('geography', 'Bahrain'),
      ScanFilter('venue', 'public tabletop venue'),
    ],
    requestedSources: [
      'local venues',
      'local community',
      'direct competitors',
    ],
  );
  const result = ScanAttemptResult(
    attemptId: 'legacy-recovery-attempt-001',
    executionState: ScanExecutionState.completed,
    completedAtMs: 1786274402352,
    resultCount: 1,
    evidence: evidence,
    candidates: [
      ScanCandidateObservation(
        id: legacyTablefinderConceptId,
        identity: legacyTablefinderWorkingName,
        fingerprint:
            'bahrain|tabletop-lfg|public-venue-tables|schedule-fit|open-seats',
        reviewWorthy: true,
        strong: true,
        evidenceReferenceIds: [
          'LY-E-001',
          'LY-E-002',
          'LY-E-003',
          'LY-E-004',
        ],
        oneSentenceIdea:
            'Match Bahrain TTRPG and board-game players into scheduled tables at known public venues.',
        intendedConsumer:
            'Adults seeking compatible local players, game masters, and reliable sessions.',
        painOrDesire:
            'Finding enough compatible people at the same time and a safe public place is fragmented across chats and social pages.',
        audienceRationale:
            'A visible niche community and real venues exist, while current event cadence and group formation remain inconsistent.',
        simplestProduct:
            'A mobile web table board with game, language, experience, venue, schedule, open-seat, join-request, and waitlist fields.',
        moneyPath:
            'A venue table-filling subscription or disclosed confirmed-seat fee that settles and reconciles to the bank.',
        strongestRejection:
            'Small-market cold start plus free global and group-chat substitutes may prevent match density and payment.',
        proofState:
            'MEDIUM — externally evidenced; commercial validation UNVERIFIED',
        traits: [
          'local-community',
          'public-venue',
          'schedule-matching',
          'two-sided-network',
          'consumer-social',
        ],
      ),
    ],
  );
  final recorded = session.recordCompletedAttempt(packet, result);
  if (!recorded.accepted) {
    throw StateError('legacy recovery attempt refused: ${recorded.reason}');
  }
  session = recorded.session;
  final voted = session.recordSponsorVote(
    legacyTablefinderConceptId,
    SponsorVote.yes,
    recordedAtMs: 1786274402362,
    sponsorReason:
        'Recovered from supervising conversation: sponsor-originated concept and explicit prior YES.',
    reconstructed: true,
  );
  if (!voted.accepted) {
    throw StateError('legacy recovery YES refused: ${voted.reason}');
  }
  return voted.session;
}

/// The only Blueprint transition reachable from persisted data in this scan
/// domain. It accepts only a source-registered packet and revalidates Factory
/// run, session, candidate, sponsor evidence, and the prior exact-session YES.
ScanMutation applyRegisteredFactoryBlueprintAuthorization(
  FactoryScanSession session, {
  required String factoryRunId,
  required String authorizationId,
}) {
  final authorization =
      registeredFactoryBlueprintAuthorizations[authorizationId];
  if (authorization == null) {
    return ScanMutation(
        session, false, 'Blueprint authorization is not registered');
  }
  final check = session.checkBlueprintAuthorization(
    authorization,
    factoryRunId: factoryRunId,
  );
  if (!check.accepted) return ScanMutation(session, false, check.reason);
  final index = session.candidates
      .indexWhere((candidate) => candidate.id == authorization.candidateId);
  final updated = [...session.candidates];
  updated[index] =
      updated[index].copyWith(state: ScanCandidateState.blueprintAuthorized);
  return ScanMutation(
    session._copyWith(
      candidates: updated,
      currentAction:
          'Entered Blueprint for ${authorization.candidateId} under ${authorization.authorizationId}.',
      nextSafeAction:
          'Resolve the first Blueprint question: who pays first and what is the smallest sellable offer?',
    ),
    true,
    'registered exact-run Blueprint authorization applied',
  );
}
