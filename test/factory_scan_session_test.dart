import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/factory_scan_session.dart';

void main() {
  FactoryScanSession fresh([String id = 'scan-1']) => FactoryScanSession.start(
      factoryRunId: 'factory-run-1',
      id: id,
      startedAtMs: 1000,
      scanPolicyVersion: 'v1');

  ScanCalibrationChange loosen() => const ScanCalibrationChange(
        direction: CalibrationDirection.loosen,
        filterName: 'format',
        fromValue: 'spreadsheet',
        toValue: 'digital asset',
        reason: 'zero credible hits',
      );
  ScanCalibrationChange tighten() => const ScanCalibrationChange(
        direction: CalibrationDirection.tighten,
        filterName: 'buyer proof',
        fromValue: 'complaint',
        toValue: 'paid review',
        reason: 'over-broad batch',
      );
  ScanWorkPacket packet(String id, {String hypothesis = 'boring inventory'}) =>
      ScanWorkPacket(
        id: id,
        hypothesis: hypothesis,
        query: '$hypothesis paid complaints',
        filters: const [ScanFilter('channel', 'marketplace')],
        requestedSources: const ['structured reviews'],
      );
  ScanCandidateObservation hit(String id, {bool strong = false, String? fp}) =>
      ScanCandidateObservation(
        id: id,
        identity: 'Candidate $id',
        fingerprint: fp ?? 'fp-$id',
        reviewWorthy: true,
        strong: strong,
        evidenceReferenceIds: ['e-$id'],
      );
  ScanAttemptResult result(String id,
          {List<ScanCandidateObservation> candidates = const [],
          List<ScanEvidenceReference> evidence = const [],
          ScanCalibrationChange? change,
          ScanExecutionState state = ScanExecutionState.completed,
          String? failure,
          ProviderUsage usage = const ProviderUsage(),
          List<WasteKind> waste = const []}) =>
      ScanAttemptResult(
        attemptId: id,
        executionState: state,
        completedAtMs: 2000,
        resultCount: candidates.length,
        candidates: candidates,
        evidence: evidence,
        calibrationChange: change,
        causalFailure: failure,
        usage: usage,
        wasteSignals: waste,
      );

  FactoryScanSession recordHits(FactoryScanSession session, String id,
      List<ScanCandidateObservation> candidates,
      {String hypothesis = 'boring inventory'}) {
    final evidence = candidates
        .map((candidate) => ScanEvidenceReference(
              id: 'e-${candidate.id}',
              source: 'marketplace',
              reference: 'https://example.invalid/${candidate.id}',
            ))
        .toList();
    final mutation = session.recordCompletedAttempt(
      packet(id, hypothesis: hypothesis),
      result(id,
          candidates: candidates,
          evidence: evidence,
          change: candidates.length > 4 ? tighten() : null),
    );
    expect(mutation.accepted, isTrue, reason: mutation.reason);
    return mutation.session;
  }

  test('retains the full search ledger and source references', () {
    final session = recordHits(fresh(), 'a1', [hit('c1'), hit('c2')]);
    expect(session.attempts, hasLength(1));
    expect(session.attempts.single.query, contains('paid complaints'));
    expect(session.attempts.single.filters.single.name, 'channel');
    expect(session.attempts.single.requestedSources, ['structured reviews']);
    expect(session.evidence, hasLength(2));
    expect(session.attempts.single.candidateIds, ['c1', 'c2']);
  });

  test('deduplicates candidate fingerprints without another challenge', () {
    var session = recordHits(fresh(), 'a1', [hit('c1', fp: 'same')]);
    session = recordHits(session, 'a2', [hit('c2', fp: 'same')],
        hypothesis: 'adjacent stock sheets');
    expect(session.candidates.last.state, ScanCandidateState.rejected);
    expect(session.candidates.last.rejectionReasons,
        contains('duplicate fingerprint'));
    expect(
        session.attempts.last.wasteSignals, contains(WasteKind.repeatedPacket));
  });

  test('zero hits requires exactly one recorded loosen change', () {
    final refused = fresh().recordCompletedAttempt(packet('a1'), result('a1'));
    expect(refused.accepted, isFalse);
    final accepted = fresh().recordCompletedAttempt(
      packet('a1'),
      result('a1', change: loosen()),
    );
    expect(accepted.accepted, isTrue);
    expect(accepted.session.calibrationChanges.single.direction,
        CalibrationDirection.loosen);
  });

  test('more than four review candidates requires one tighten change', () {
    final hits = List.generate(5, (index) => hit('c$index'));
    expect(
        fresh()
            .recordCompletedAttempt(
                packet('a1'), result('a1', candidates: hits))
            .accepted,
        isFalse);
    final accepted = recordHits(fresh(), 'a1', hits);
    expect(accepted.calibrationChanges.single.direction,
        CalibrationDirection.tighten);
  });

  test(
      'three equal causal failures stop hypothesis and require territory switch',
      () {
    var session = fresh();
    for (var i = 1; i <= 3; i++) {
      final distinctPacket = ScanWorkPacket(
        id: 'a$i',
        hypothesis: 'boring inventory',
        query: 'boring inventory source territory $i',
        filters: [ScanFilter('source-depth', '$i')],
      );
      final mutation = session.recordCompletedAttempt(
        distinctPacket,
        result('a$i',
            state: ScanExecutionState.failed,
            failure: 'relay rejected',
            waste: const [WasteKind.relayRejection]),
      );
      expect(mutation.accepted, isTrue);
      session = mutation.session;
    }
    expect(session.territorySwitchRequired, isTrue);
    final blocked = session.recordCompletedAttempt(
      packet('a4'),
      result('a4', state: ScanExecutionState.failed, failure: 'relay rejected'),
    );
    expect(blocked.accepted, isFalse);
    expect(blocked.reason, contains('switch territory'));
  });

  test('three strong unreviewed candidates halt additional scanning', () {
    final session = recordHits(fresh(), 'a1', [
      hit('c1', strong: true),
      hit('c2', strong: true),
      hit('c3', strong: true),
    ]);
    expect(session.reviewBackpressure, isTrue);
    final blocked = session.recordCompletedAttempt(
      packet('a2', hypothesis: 'other territory'),
      result('a2', change: loosen()),
    );
    expect(blocked.accepted, isFalse);
    expect(blocked.reason, contains('sponsor review'));
  });

  test('identical attempt is suppressed and retained as a waste proxy only',
      () {
    var session = recordHits(fresh(), 'a1', [hit('c1')]);
    final duplicatePacket = ScanWorkPacket(
      id: 'a2',
      hypothesis: packet('a1').hypothesis,
      query: packet('a1').query,
      filters: packet('a1').filters,
      requestedSources: packet('a1').requestedSources,
    );
    final suppressed = session.recordCompletedAttempt(
        duplicatePacket, result('a2', candidates: [hit('c2')]));
    expect(suppressed.accepted, isFalse);
    expect(suppressed.session.attempts, hasLength(1));
    expect(suppressed.session.audit.wasteCounts[WasteKind.duplicateSearch], 1);
  });

  test('YES is shortlist only and never advances itself to Blueprint', () {
    var session = recordHits(fresh(), 'a1', [hit('c1')]);
    final vote =
        session.recordSponsorVote('c1', SponsorVote.yes, recordedAtMs: 4000);
    expect(vote.accepted, isTrue);
    session = vote.session;
    expect(session.candidates.single.state, ScanCandidateState.yesShortlist);
    expect(vote.reason, contains('Blueprint remains locked'));
  });

  test(
      'Blueprint check binds exact candidate, run, and prior YES without advancing',
      () {
    var session = recordHits(fresh(), 'a1', [hit('c1')]);
    session = session
        .recordSponsorVote('c1', SponsorVote.yes, recordedAtMs: 4000)
        .session;
    final accepted = session.checkBlueprintAuthorization(
        const SponsorBlueprintAuthorization(
            authorizationId: 'test-auth',
            factoryRunId: 'factory-run-1',
            sessionId: 'scan-1',
            candidateId: 'c1',
            approvedBy: 'sadeq',
            approvedAtMs: 5000,
            sponsorEvidence: 'test sponsor evidence'),
        factoryRunId: 'factory-run-1');
    expect(accepted.accepted, isTrue);
    expect(session.candidates.single.state, ScanCandidateState.yesShortlist);
    expect(accepted.reason, contains('trusted sponsor verification'));
  });

  test('cross-run Blueprint approval is refused', () {
    var session = recordHits(fresh('new-run'), 'a1', [hit('c1')]);
    session = session
        .recordSponsorVote('c1', SponsorVote.yes, recordedAtMs: 4000)
        .session;
    final refused = session.checkBlueprintAuthorization(
        const SponsorBlueprintAuthorization(
            authorizationId: 'test-auth',
            factoryRunId: 'factory-run-1',
            sessionId: 'old-run',
            candidateId: 'c1',
            approvedBy: 'sadeq',
            approvedAtMs: 5000,
            sponsorEvidence: 'test sponsor evidence'),
        factoryRunId: 'factory-run-1');
    expect(refused.accepted, isFalse);
    expect(refused.reason, contains('not transferable'));
  });

  test('stopped territory remains locked after a successful other territory',
      () {
    var session = fresh();
    for (var i = 1; i <= 3; i++) {
      final p = ScanWorkPacket(
          id: 'f$i', hypothesis: 'dead territory', query: 'distinct $i');
      session = session
          .recordCompletedAttempt(
              p,
              result('f$i',
                  state: ScanExecutionState.failed, failure: 'same cause'))
          .session;
    }
    session =
        recordHits(session, 'good', [hit('good')], hypothesis: 'new territory');
    final blocked = session.recordCompletedAttempt(
        const ScanWorkPacket(
            id: 'again', hypothesis: 'dead territory', query: 'new query'),
        result('again',
            state: ScanExecutionState.failed, failure: 'same cause'));
    expect(blocked.accepted, isFalse);
    expect(blocked.reason, contains('switch territory'));
  });

  test('one verdict does not clear backpressure while three strong remain', () {
    var session = recordHits(fresh(), 'a1', [
      hit('c1', strong: true),
      hit('c2', strong: true),
      hit('c3', strong: true),
      hit('c4', strong: true),
    ]);
    session = session
        .recordSponsorVote('c1', SponsorVote.no, recordedAtMs: 5000)
        .session;
    expect(session.reviewBackpressure, isTrue);
  });

  test('review-worthy candidate cannot cite missing evidence', () {
    final mutation = fresh().recordCompletedAttempt(
        packet('a1'), result('a1', candidates: [hit('c1')]));
    expect(mutation.accepted, isFalse);
    expect(mutation.reason, contains('unresolved evidence'));
  });

  test('token usage is unavailable unless provider exposes exact usage', () {
    var session = recordHits(fresh(), 'a1', [hit('c1')]);
    expect(session.audit.exactTokens, isNull);
    expect(session.hudAt(2000), contains('Token usage: unavailable'));
    session = recordHits(session, 'a2', [hit('c2')],
        hypothesis: 'adjacent territory');
    expect(session.audit.exactTokens, isNull);
  });

  test('concrete duplicate and unchanged retry signals classify waste', () {
    var session = recordHits(fresh(), 'a1', [hit('c1')]);
    final duplicatePacket = ScanWorkPacket(
        id: 'a2',
        hypothesis: packet('a1').hypothesis,
        query: packet('a1').query,
        filters: packet('a1').filters,
        requestedSources: packet('a1').requestedSources);
    session =
        session.recordCompletedAttempt(duplicatePacket, result('a2')).session;
    expect(session.audit.efficiency, ScanEfficiency.wasteful);
    expect(session.changedHypothesisRequired, isTrue);
  });

  test('HUD is plain language with required counts and actions', () {
    final session = recordHits(fresh(), 'a1', [hit('c1'), hit('c2')]);
    final hud = session.hudAt(1000);
    for (final text in [
      'minute(s) remaining',
      'Attempts: 1',
      'Credible candidates: 2',
      'Awaiting votes: 2',
      'Duplicates:',
      'Rejections:',
      'Failed rounds:',
      'Efficiency:',
      'Effectiveness: HIGH',
      'Wasted-token warning:',
      'Current action:',
      'Exact next safe action:'
    ]) {
      expect(hud, contains(text));
    }
  });

  test('30-minute timebox expires deterministically', () {
    final session = fresh();
    expect(session.deadlineAtMs - session.startedAtMs,
        factoryScanTimebox.inMilliseconds);
    expect(session.isCompleteAt(session.deadlineAtMs - 1), isFalse);
    expect(session.isCompleteAt(session.deadlineAtMs), isTrue);
    expect(
        session.hudAt(session.deadlineAtMs), contains('Signal Scan complete'));
  });

  test('serialization round trip and legacy migration retain safe truth', () {
    final session = recordHits(fresh(), 'a1', [hit('c1'), hit('c2')]);
    final restored = FactoryScanSession.fromJson(session.toJson());
    expect(restored.id, session.id);
    expect(restored.attempts.single.fingerprint,
        session.attempts.single.fingerprint);
    expect(restored.candidates, hasLength(2));
    expect(restored.audit.effectiveness, ScanEffectiveness.high);

    final migrated = FactoryScanSession.fromJson({
      'id': 'legacy',
      'startedAtMs': 10,
    });
    expect(migrated.schemaVersion, factoryScanSchemaVersion);
    expect(migrated.deadlineAtMs, 10 + factoryScanTimebox.inMilliseconds);
    expect(migrated.attempts, isEmpty);
    expect(() => FactoryScanSession.fromJson({'schemaVersion': 99}),
        throwsFormatException);

    final forged = FactoryScanSession.fromJson({
      'id': 'forged',
      'startedAtMs': 1,
      'candidates': [
        {
          'id': 'c1',
          'identity': 'forged',
          'fingerprint': 'forged',
          'state': 'blueprintAuthorized',
        }
      ],
    });
    expect(forged.candidates.single.state, ScanCandidateState.yesShortlist);
  });

  test('MAYBE and LATER remain distinct and verdict traits are transparent',
      () {
    const base = ScanCandidateObservation(
        id: 'c1',
        identity: 'Pocket ritual',
        fingerprint: 'ritual',
        reviewWorthy: true,
        traits: ['offline', 'giftable']);
    var session = recordHits(fresh(), 'a1', [base]);
    session = session
        .recordSponsorVote('c1', SponsorVote.later,
            recordedAtMs: 6000, sponsorReason: 'seasonal')
        .session;
    expect(session.candidates.single.state, ScanCandidateState.laterRetained);
    expect(session.verdictHistory.single.sponsorReason, 'seasonal');
    expect(session.transparentTraitWeights['offline'], 0);

    const second = ScanCandidateObservation(
        id: 'c2',
        identity: 'Other ritual',
        fingerprint: 'ritual-2',
        reviewWorthy: true,
        traits: ['offline']);
    session = recordHits(session, 'a2', [second], hypothesis: 'other rituals');
    session = session
        .recordSponsorVote('c2', SponsorVote.maybe, recordedAtMs: 7000)
        .session;
    expect(session.candidates.last.state, ScanCandidateState.maybeIncubate);
    expect(session.transparentTraitWeights['offline'], 1);
  });
}
