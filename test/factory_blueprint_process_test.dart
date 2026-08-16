import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/factory_blueprint_process.dart';

void main() {
  FactoryBlueprintProcess packet({
    List<FactoryAuthorityReference> authorities = const [],
  }) =>
      FactoryBlueprintProcess(
        packetId: 'bp-1',
        factoryRunId: 'run-1',
        scanSessionId: 'scan-1',
        candidateId: 'candidate-1',
        conceptFingerprint: 'table-matching-v1',
        authorityReferences: authorities,
        searchLog: const [
          BlueprintSearchLogEntry(
            attemptId: 'a1',
            hypothesis: 'players need compatible tables',
            query: 'table matching',
            sourceRefs: ['s1'],
            outcome: BlueprintSearchOutcome.evidenceAdded,
            fingerprint: 'attempt-fp',
            recordedAtMs: 1100,
          ),
          BlueprintSearchLogEntry(
            attemptId: 'a2',
            hypothesis: 'players need compatible tables',
            query: 'table matching',
            sourceRefs: const [],
            outcome: BlueprintSearchOutcome.duplicateSuppressed,
            fingerprint: 'attempt-fp',
            recordedAtMs: 1200,
          ),
        ],
        strictness: 1,
        calibration: const [
          BlueprintCalibrationChange(
            previousStrictness: 0,
            nextStrictness: 1,
            changedFilter: 'require settled-payment path',
            evidenceReason: 'too many weak candidates',
          ),
        ],
        scenarios: const [
          BlueprintScenario(
            scenarioId: 'base',
            label: 'Base',
            assumptions: {'margin': .4, 'dmFee': 10},
            outputs: {'netPerTable': 4.2},
            unverifiedInputs: ['margin'],
          ),
        ],
        firstTenRoutes: const [
          FirstTenBuyerRoute(
            routeId: 'existing-referrals',
            channel: 'existing player referrals',
            allocationTarget: 4,
            messageHypothesis: 'better-fit table',
            proofEvent: 'settled venue bill',
            killCondition: 'no qualified acceptance',
          ),
          FirstTenBuyerRoute(
            routeId: 'venue-inbound',
            channel: 'venue inbound',
            allocationTarget: 3,
            messageHypothesis: 'reliable hosted table',
            proofEvent: 'settled venue bill',
            killCondition: 'cannibalizes existing tables',
          ),
          FirstTenBuyerRoute(
            routeId: 'approved-community',
            channel: 'approved community',
            allocationTarget: 3,
            messageHypothesis: 'compatible local table',
            proofEvent: 'settled venue bill',
            killCondition: 'no net-new attendance',
          ),
        ],
        risks: const [
          BlueprintRiskChallenge(
            riskId: 'thin-margin',
            claimUnderChallenge: 'external DM is affordable',
            disconfirmingEvidence: 'negative contribution',
            mitigation: 'measure before offer',
            stopRule: 'stop negative table',
          ),
        ],
        evidence: const [
          BlueprintEvidenceEntry(
            evidenceId: 'e1',
            sourceRef: 'direct sponsor statement',
            claimSupported: 'two weekly tables',
            proofState: 'sponsor-attested',
            accessedAtMs: 1000,
            contradiction: 'profit remains unverified',
          ),
        ],
        cycle: const BlueprintCycleMetrics(
          startedAtMs: 1000,
          completedAtMs: 5000,
          rework: [
            BlueprintReworkEvent(
              eventId: 'r1',
              causalFailure: 'ticket model contradicted venue economics',
              changedStrategy: 'venue contribution model',
              recordedAtMs: 3000,
            ),
          ],
        ),
      );

  test('retains full search and calibration evidence', () {
    final process = packet();
    expect(process.searchLog, hasLength(2));
    expect(
      process.searchLog.last.outcome,
      BlueprintSearchOutcome.duplicateSuppressed,
    );
    expect(process.calibration.single.previousStrictness, 0);
    expect(process.calibration.single.nextStrictness, 1);
  });

  test('fingerprint dedupe does not erase sponsor concept', () {
    final process = packet();
    expect(process.hasDuplicateConcept(['other', 'table-matching-v1']), isTrue);
    expect(process.candidateId, 'candidate-1');
  });

  test('recorded duplicate is visible in the decision presentation', () {
    final process = FactoryBlueprintProcess(
      packetId: 'bp-1',
      factoryRunId: 'run-1',
      scanSessionId: 'scan-1',
      candidateId: 'candidate-1',
      conceptFingerprint: 'fp',
      duplicateOfCandidateId: 'candidate-older',
      authorityReferences: const [],
      cycle: const BlueprintCycleMetrics(startedAtMs: 0),
    );
    expect(
      process.buildPresentation().first.bullets,
      contains('Duplicate status: related to candidate-older'),
    );
  });

  test('YES and Blueprint never leak Assembly or public authority', () {
    final process = packet(authorities: const [
      FactoryAuthorityReference(
        kind: FactoryAuthorityKind.yesShortlist,
        factoryRunId: 'run-1',
        scanSessionId: 'scan-1',
        candidateId: 'candidate-1',
        evidenceId: 'vote-1',
      ),
      FactoryAuthorityReference(
        kind: FactoryAuthorityKind.blueprint,
        factoryRunId: 'run-1',
        scanSessionId: 'scan-1',
        candidateId: 'candidate-1',
        evidenceId: 'bp-auth-1',
      ),
    ]);

    expect(process.isBlueprintAuthorized, isTrue);
    expect(process.isAssemblyAuthorized, isFalse);
    expect(process.isPublicActionAuthorized, isFalse);
  });

  test('cross-run authority reference is refused', () {
    final process = packet(authorities: const [
      FactoryAuthorityReference(
        kind: FactoryAuthorityKind.assembly,
        factoryRunId: 'old-run',
        scanSessionId: 'scan-1',
        candidateId: 'candidate-1',
        evidenceId: 'assembly-1',
      ),
    ]);
    expect(process.isAssemblyAuthorized, isFalse);
  });

  test('scenario, first-ten route, risk, cycle and presentation are auditable',
      () {
    final process = packet();
    expect(process.scenarios.single.outputs['netPerTable'], 4.2);
    expect(
        process.firstTenRoutes
            .fold<int>(0, (sum, route) => sum + route.allocationTarget),
        10);
    expect(process.risks.single.stopRule, 'stop negative table');
    expect(process.cycle.cycleTimeMs, 4000);
    expect(process.cycle.reworkCount, 1);
    expect(process.validationIssues, isEmpty);

    final presentation = process.buildPresentation();
    expect(presentation, hasLength(4));
    expect(presentation.first.bullets, contains('Assembly authority: locked'));
    expect(presentation[1].bullets, contains('2 retained search attempts'));
  });

  test('validation catches unchanged retry and broken strictness chain', () {
    final invalid = FactoryBlueprintProcess(
      packetId: 'bp-1',
      factoryRunId: 'run-1',
      scanSessionId: 'scan-1',
      candidateId: 'candidate-1',
      conceptFingerprint: 'fp',
      authorityReferences: const [],
      strictness: 5,
      calibration: const [
        BlueprintCalibrationChange(
          previousStrictness: 0,
          nextStrictness: 1,
          changedFilter: 'one filter',
          evidenceReason: 'weak results',
        ),
      ],
      searchLog: const [
        BlueprintSearchLogEntry(
          attemptId: 'a1',
          hypothesis: 'h',
          query: 'q',
          sourceRefs: [],
          outcome: BlueprintSearchOutcome.failed,
          fingerprint: 'same',
          recordedAtMs: 1,
        ),
        BlueprintSearchLogEntry(
          attemptId: 'a2',
          hypothesis: 'h',
          query: 'q',
          sourceRefs: [],
          outcome: BlueprintSearchOutcome.failed,
          fingerprint: 'same',
          recordedAtMs: 2,
        ),
      ],
      cycle: const BlueprintCycleMetrics(startedAtMs: 0),
    );

    expect(invalid.validationIssues, hasLength(2));
  });

  test('sponsor verdict is packet-bound and grants no later authority', () {
    final process = FactoryBlueprintProcess(
      packetId: 'bp-1',
      factoryRunId: 'run-1',
      scanSessionId: 'scan-1',
      candidateId: 'candidate-1',
      conceptFingerprint: 'fp',
      authorityReferences: const [],
      sponsorVerdicts: const [
        BlueprintSponsorVerdict(
          verdict: BlueprintInvestmentVerdict.invest,
          packetId: 'bp-1',
          candidateId: 'candidate-1',
          evidenceId: 'verdict-1',
          sponsorReason: 'bounded test',
          recordedAtMs: 10,
        ),
      ],
      cycle: const BlueprintCycleMetrics(startedAtMs: 0),
    );

    expect(process.validationIssues, isEmpty);
    expect(process.isAssemblyAuthorized, isFalse);
    expect(process.isPublicActionAuthorized, isFalse);
    expect(
      process.buildPresentation().first.bullets,
      contains('Sponsor verdict: invest'),
    );
  });

  test('durable round trip retains evidence, scenarios and cycle metrics', () {
    final original = packet();
    final restored = FactoryBlueprintProcess.fromJson(original.toJson());

    expect(restored.packetId, original.packetId);
    expect(restored.searchLog.length, 2);
    expect(restored.searchLog.last.outcome,
        BlueprintSearchOutcome.duplicateSuppressed);
    expect(restored.scenarios.single.outputs['netPerTable'], 4.2);
    expect(restored.firstTenRoutes, hasLength(3));
    expect(restored.evidence.single.contradiction, isNotEmpty);
    expect(restored.cycle.cycleTimeMs, 4000);
    expect(restored.validationIssues, isEmpty);
  });
}
