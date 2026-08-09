// Tests for product_factory.dart — factory mode's safety perimeter.
//
// The critical test in this file is `no stage can reach published without
// approval`, which brute-forces every stage rather than trusting the one path
// we happened to think of. Publishing puts Sadeq's name on a product and money
// behind it; that gate is the whole reason this module is code and not a
// directive.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/product_factory.dart';

void main() {
  const full = RunEvidence(
    hasSurvivingCandidate: true,
    specComplete: true,
    artifactPath: '/out/kit.zip',
    testsPassed: true,
    buildPassed: true,
    listingPrepared: true,
    liveUrl: 'https://gum.co/x',
    views: 900,
    sales: 12,
    bankedRevenue: 49.00,
    bankSettlementReference: 'bank-settlement-001',
    observedDays: 10,
  );

  final approval = HumanApproval(
    approvedBy: 'sadeq',
    approvedAt: 1721000000,
    runId: 'r1',
  );

  group('master switch', () {
    test('factory mode off blocks every advance', () {
      const run = FactoryRun(id: 'r1', evidence: full, factoryModeOn: false);
      final r = advance(run);
      expect(r.advanced, isFalse);
      expect(r.refusal!.reason, contains('factory mode is off'));
    });
  });

  group('evidence gates', () {
    test('no surviving candidate blocks specced', () {
      const run = FactoryRun(id: 'r1', factoryModeOn: true);
      expect(advance(run).advanced, isFalse);
    });

    test('a surviving candidate advances to specced', () {
      const run = FactoryRun(
        id: 'r1',
        evidence: RunEvidence(hasSurvivingCandidate: true),
        factoryModeOn: true,
      );
      expect(advance(run).run!.stage, FactoryStage.specced);
    });

    test('a failing build blocks listingReady — "it\'s done" is not evidence',
        () {
      const run = FactoryRun(
        id: 'r1',
        stage: FactoryStage.verified,
        evidence: RunEvidence(
          artifactPath: '/a',
          testsPassed: true,
          buildPassed: false,
        ),
        factoryModeOn: true,
      );
      final r = advance(run);
      expect(r.advanced, isFalse);
      expect(r.refusal!.reason, contains('quality gates'));
    });

    test('a blank artifact path blocks verified', () {
      const run = FactoryRun(
        id: 'r1',
        stage: FactoryStage.building,
        evidence: RunEvidence(specComplete: true, artifactPath: '   '),
        factoryModeOn: true,
      );
      expect(advance(run).advanced, isFalse);
    });
  });

  group('the human perimeter', () {
    const ready = FactoryRun(
      id: 'r1',
      stage: FactoryStage.awaitingApproval,
      evidence: full,
      factoryModeOn: true,
    );

    test('publishing is refused without approval, even on perfect evidence',
        () {
      final r = advance(ready);
      expect(r.advanced, isFalse);
      expect(r.refusal!.reason, contains('approval'));
    });

    test('publishing proceeds with a valid approval', () {
      expect(advance(ready, approval: approval).run!.stage,
          FactoryStage.published);
    });

    test('an approval issued for another run is rejected — no replay', () {
      final other = HumanApproval(
        approvedBy: 'sadeq',
        approvedAt: 1721000000,
        runId: 'a-different-run',
      );
      final r = advance(ready, approval: other);
      expect(r.advanced, isFalse);
      expect(r.refusal!.reason, contains('not transferable'));
    });

    test('malformed approvals are rejected', () {
      final blankApprover =
          HumanApproval(approvedBy: '  ', approvedAt: 1721000000, runId: 'r1');
      final noTime =
          HumanApproval(approvedBy: 'sadeq', approvedAt: 0, runId: 'r1');
      expect(advance(ready, approval: blankApprover).advanced, isFalse);
      expect(advance(ready, approval: noTime).advanced, isFalse);
    });

    test('an approval cannot bypass an ordinary evidence gate', () {
      const unscouted = FactoryRun(id: 'r1', factoryModeOn: true);
      expect(advance(unscouted, approval: approval).advanced, isFalse);
    });

    test('NO stage can reach published without approval', () {
      for (final stage in FactoryStage.values) {
        final run = FactoryRun(
          id: 'r1',
          stage: stage,
          evidence: full,
          factoryModeOn: true,
        );
        final r = advance(run);
        expect(
          r.run?.stage == FactoryStage.published,
          isFalse,
          reason: 'stage ${stage.name} reached published without approval',
        );
      }
    });
  });

  group('the learning gate', () {
    test('two days of data is noise, not learning', () {
      const run = FactoryRun(
        id: 'r1',
        stage: FactoryStage.measuring,
        evidence: RunEvidence(
          liveUrl: 'https://x',
          views: 900,
          sales: 12,
          observedDays: 2,
        ),
        factoryModeOn: true,
      );
      expect(advance(run).advanced, isFalse);
    });

    test('a run with no numbers taught nothing', () {
      const run = FactoryRun(
        id: 'r1',
        stage: FactoryStage.measuring,
        evidence: RunEvidence(liveUrl: 'https://x', observedDays: 10),
        factoryModeOn: true,
      );
      expect(advance(run).advanced, isFalse);
    });

    test('a storefront sale is not success until money reaches the bank', () {
      const run = FactoryRun(
        id: 'r1',
        stage: FactoryStage.measuring,
        evidence: RunEvidence(
          liveUrl: 'https://x',
          views: 900,
          sales: 12,
          observedDays: 10,
        ),
        factoryModeOn: true,
      );

      final result = advance(run);

      expect(result.advanced, isFalse);
      expect(result.refusal!.reason, contains('bank account'));
    });

    test('banked money needs a reconciliation reference', () {
      const run = FactoryRun(
        id: 'r1',
        stage: FactoryStage.measuring,
        evidence: RunEvidence(
          liveUrl: 'https://x',
          views: 900,
          sales: 12,
          observedDays: 10,
          bankedRevenue: 49.00,
        ),
        factoryModeOn: true,
      );

      final result = advance(run);

      expect(result.advanced, isFalse);
      expect(result.refusal!.reason, contains('reconciliation reference'));
    });

    test('full data advances to learned', () {
      const run = FactoryRun(
        id: 'r1',
        stage: FactoryStage.measuring,
        evidence: full,
        factoryModeOn: true,
      );
      expect(advance(run).run!.stage, FactoryStage.learned);
    });
  });

  group('lifecycle', () {
    test('stopped run is saved state and cannot advance until resumed', () {
      const run = FactoryRun(
        id: 'r1',
        evidence: RunEvidence(hasSurvivingCandidate: true),
        factoryModeOn: true,
        stoppedAt: 1721000000,
        stoppedReason: 'factory mode toggled off',
      );

      final r = advance(run);

      expect(run.isStopped, isTrue);
      expect(r.advanced, isFalse);
      expect(r.refusal!.reason, contains('run is stopped'));
    });

    test('copyWith can resume stopped state without losing evidence', () {
      const run = FactoryRun(
        id: 'r1',
        evidence: RunEvidence(hasSurvivingCandidate: true),
        factoryModeOn: false,
        stoppedAt: 1721000000,
        stoppedReason: 'app restarted',
      );

      final resumed = run.copyWith(
        factoryModeOn: true,
        stoppedAt: null,
        stoppedReason: null,
      );

      expect(resumed.isStopped, isFalse);
      expect(resumed.evidence.hasSurvivingCandidate, isTrue);
      expect(advance(resumed).run!.stage, FactoryStage.specced);
    });

    test('learned is terminal', () {
      const run = FactoryRun(
        id: 'r1',
        stage: FactoryStage.learned,
        evidence: full,
        factoryModeOn: true,
      );
      expect(advance(run).advanced, isFalse);
    });

    test('restart clears evidence rather than faking forward motion', () {
      const run = FactoryRun(
        id: 'r1',
        stage: FactoryStage.verified,
        evidence: full,
        factoryModeOn: true,
      );
      final back = restart(run);
      expect(back.stage, FactoryStage.scouting);
      expect(back.evidence.artifactPath, isNull);
    });
  });
}
