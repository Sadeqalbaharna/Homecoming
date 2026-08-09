import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/factory_scan_session.dart';

void main() {
  test('legacy recovery assigns new identifiers without historical claims', () {
    final session = createLegacyTablefinderRecoverySession();
    expect(session.id, legacyTablefinderScanSessionId);
    expect(session.factoryRunId, legacyTablefinderFactoryRunId);
    expect(session.scanPolicyVersion, contains('legacy-recovery'));
    expect(session.candidates.single.id, legacyTablefinderConceptId);
    expect(session.candidates.single.identity, legacyTablefinderWorkingName);
    expect(session.candidates.single.state, ScanCandidateState.yesShortlist);
    expect(session.verdictHistory.single.sessionId,
        legacyTablefinderScanSessionId);
    expect(session.verdictHistory.single.verdict, SponsorVote.yes);
    expect(session.verdictHistory.single.reconstructed, isTrue);
    expect(session.transparentTraitWeights, isEmpty);
  });

  test('only registered exact Factory run and recovery session enter Blueprint',
      () {
    final session = createLegacyTablefinderRecoverySession();
    final applied = applyRegisteredFactoryBlueprintAuthorization(
      session,
      factoryRunId: legacyTablefinderFactoryRunId,
      authorizationId: legacyTablefinderAuthorizationId,
    );
    expect(applied.accepted, isTrue);
    expect(applied.session.candidates.single.state,
        ScanCandidateState.blueprintAuthorized);
    expect(applied.session.currentAction,
        contains(legacyTablefinderAuthorizationId));

    final wrongRun = applyRegisteredFactoryBlueprintAuthorization(
      session,
      factoryRunId: 'another-factory-run',
      authorizationId: legacyTablefinderAuthorizationId,
    );
    expect(wrongRun.accepted, isFalse);
    expect(wrongRun.reason, contains('not transferable'));

    final unknown = applyRegisteredFactoryBlueprintAuthorization(
      session,
      factoryRunId: legacyTablefinderFactoryRunId,
      authorizationId: 'agent-invented-authorization',
    );
    expect(unknown.accepted, isFalse);
    expect(unknown.reason, contains('not registered'));
  });

  test('registered authorization cannot transfer to another scan session', () {
    final other = FactoryScanSession.start(
      factoryRunId: legacyTablefinderFactoryRunId,
      id: 'other-session',
      startedAtMs: 1786274402342,
      scanPolicyVersion: 'test',
    );
    final refused = applyRegisteredFactoryBlueprintAuthorization(
      other,
      factoryRunId: legacyTablefinderFactoryRunId,
      authorizationId: legacyTablefinderAuthorizationId,
    );
    expect(refused.accepted, isFalse);
    expect(refused.reason, contains('another scan session'));
  });

  test('caller cannot assert the registered run for a different-run session',
      () {
    final copied = FactoryScanSession.fromJson({
      ...createLegacyTablefinderRecoverySession().toJson(),
      'factoryRunId': 'run-002',
    });
    final refused = applyRegisteredFactoryBlueprintAuthorization(
      copied,
      factoryRunId: legacyTablefinderFactoryRunId,
      authorizationId: legacyTablefinderAuthorizationId,
    );

    expect(refused.accepted, isFalse);
    expect(refused.reason, contains('another Factory run'));
  });

  test('untrusted JSON cannot preserve Blueprint but registry can reapply it',
      () {
    final authorized = applyRegisteredFactoryBlueprintAuthorization(
      createLegacyTablefinderRecoverySession(),
      factoryRunId: legacyTablefinderFactoryRunId,
      authorizationId: legacyTablefinderAuthorizationId,
    ).session;
    final restored = FactoryScanSession.fromJson(authorized.toJson());
    expect(restored.candidates.single.state, ScanCandidateState.yesShortlist);
    final reapplied = applyRegisteredFactoryBlueprintAuthorization(
      restored,
      factoryRunId: legacyTablefinderFactoryRunId,
      authorizationId: legacyTablefinderAuthorizationId,
    );
    expect(reapplied.accepted, isTrue);
    expect(reapplied.session.candidates.single.state,
        ScanCandidateState.blueprintAuthorized);
  });
}
