import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_delivery_box.dart';
import 'package:homecoming_app/services/core/kai_project_service.dart';
import 'package:homecoming_app/widgets/kai_project_portfolio.dart';

KaiDeliveryBox _box({
  String id = 'box',
  KaiDeliveryBoxOwner owner = KaiDeliveryBoxOwner.agent,
  KaiDeliveryRisk risk = KaiDeliveryRisk.localSafe,
  KaiDeliveryBoxState state = KaiDeliveryBoxState.ready,
  List<String> dependencies = const [],
  List<KaiDeliveryAttempt> attempts = const [],
  String? workRequestId,
}) =>
    KaiDeliveryBox(
      projectId: 'p',
      phase: 1,
      boxId: id,
      outcome: 'Produce bounded evidence',
      dependencies: dependencies,
      owner: owner,
      risk: risk,
      requiredEvidence: const ['tests', 'review'],
      state: state,
      attempts: attempts,
      sourceOfTruthRef: 'docs/source.md',
      workRequestId: workRequestId,
    );

void main() {
  group('frozen catalog', () {
    test('every governed phase has bounded boxes with stable identity', () {
      final projects = <String, List<KaiLayer>>{
        KaiProjectService.homecomingId:
            KaiProjectService.homecomingPhasesForTest,
        KaiProjectService.hoardId: KaiProjectService.hoardPhasesForTest,
        KaiProjectService.kingdomId: KaiProjectService.kingdomPhasesForTest,
        KaiProjectService.factoryId: KaiProjectService.factoryPhasesForTest,
      };
      expect(
        projects.map((key, layers) => MapEntry(
              key,
              layers.fold<int>(
                  0, (total, layer) => total + layer.deliveryBoxes.length),
            )),
        {
          KaiProjectService.homecomingId: 29,
          KaiProjectService.hoardId: 19,
          KaiProjectService.kingdomId: 18,
          KaiProjectService.factoryId: 23,
        },
      );
      for (final entry in projects.entries) {
        for (final layer in entry.value) {
          expect(layer.deliveryBoxes.length, greaterThanOrEqualTo(2));
          expect(
            layer.deliveryBoxes.map((box) => box.identity).toSet().length,
            layer.deliveryBoxes.length,
          );
          for (final box in layer.deliveryBoxes) {
            expect(box.projectId, entry.key);
            expect(box.phase, layer.n);
            expect(box.outcome, isNotEmpty);
            expect(box.requiredEvidence, isNotEmpty);
            expect(box.sourceOfTruthRef, isNotEmpty);
          }
        }
      }
    });

    test('Hoard and Kingdom remain honest about current evidence', () {
      final hoard = KaiProjectService.hoardPhasesForTest;
      expect(
        hoard[0]
            .deliveryBoxes
            .every((box) => box.state == KaiDeliveryBoxState.verified),
        isTrue,
      );
      expect(hoard[1].deliveryBoxes.first.state, KaiDeliveryBoxState.verified);
      expect(
          hoard[1].deliveryBoxes[1].state, KaiDeliveryBoxState.awaitingSponsor);

      final kingdom = KaiProjectService.kingdomPhasesForTest;
      expect(
        kingdom
            .expand((layer) => layer.deliveryBoxes)
            .where((box) => box.state == KaiDeliveryBoxState.verified),
        isEmpty,
      );
      expect(kingdom.first.deliveryBoxes.first.requiredEvidence.single,
          contains('UNVERIFIED'));
    });

    test('Factory is scan-only and sponsor-locks Blueprint', () {
      final factory = KaiProjectService.factoryPhasesForTest;
      expect(factory[0].deliveryBoxes[0].state, KaiDeliveryBoxState.verified);
      expect(factory[0].deliveryBoxes[1].state,
          KaiDeliveryBoxState.awaitingSponsor);
      expect(factory[0].deliveryBoxes[2].owner, KaiDeliveryBoxOwner.sponsor);
      expect(factory[6].deliveryBoxes.last.risk, KaiDeliveryRisk.liveExternal);
      expect(factory[8].deliveryBoxes.first.owner, KaiDeliveryBoxOwner.sponsor);
      expect(factory[8].deliveryBoxes.last.outcome.toLowerCase(),
          contains('banked revenue'));
    });
  });

  group('parsing and migration', () {
    test('legacy layer defaults to no invented boxes', () {
      final layer = KaiLayer.fromMap({
        'n': 1,
        'title': 'Legacy',
        'intent': 'Preserve it',
      });
      expect(layer.deliveryBoxes, isEmpty);
    });

    test('box and attempt round-trip every authority field', () {
      final original = _box(
        state: KaiDeliveryBoxState.repairing,
        attempts: const [
          KaiDeliveryAttempt(
            fingerprint: 'repair-a',
            causalBlocker: 'compiler',
            outcome: 'failed',
            recordedAt: 10,
            evidenceRefs: ['log'],
          ),
        ],
        workRequestId: 'request-1',
      );
      final back = KaiDeliveryBox.fromMap(original.toMap());
      expect(back.identity, original.identity);
      expect(back.state, KaiDeliveryBoxState.repairing);
      expect(back.attempts.single.fingerprint, 'repair-a');
      expect(back.workRequestId, 'request-1');
      expect(back.owner, KaiDeliveryBoxOwner.agent);
      expect(back.risk, KaiDeliveryRisk.localSafe);
    });
  });

  group('deterministic eligibility and dispatch', () {
    test('selects one active-phase local agent box after verified dependencies',
        () {
      final dependency = _box(
        id: 'a',
        state: KaiDeliveryBoxState.verified,
      );
      final eligible = _box(
        id: 'b',
        dependencies: [dependency.identity],
      );
      final sponsor = _box(
        id: 'c',
        owner: KaiDeliveryBoxOwner.sponsor,
        risk: KaiDeliveryRisk.productDecision,
      );
      expect(
        KaiDeliveryController.selectNext(
          projectId: 'p',
          activePhase: 1,
          boxes: [sponsor, eligible, dependency],
        )?.identity,
        eligible.identity,
      );
      expect(
        KaiDeliveryController.selectNext(
          projectId: 'p',
          activePhase: 2,
          boxes: [eligible],
        ),
        isNull,
      );
    });

    test('refuses duplicate active work request and non-local risk', () {
      final leased = _box(id: 'a', workRequestId: 'request-a');
      final risky = _box(id: 'b', risk: KaiDeliveryRisk.liveExternal);
      expect(
        KaiDeliveryController.selectNext(
          projectId: 'p',
          activePhase: 1,
          boxes: [leased, risky],
          activeWorkRequestIds: {'request-a'},
        ),
        isNull,
      );
    });

    test('dispatch is idempotent and honestly remains READY FOR AGENT',
        () async {
      final requestIds = <String>{};
      final result = await KaiDeliveryController.dispatchNext(
        projectId: 'p',
        activePhase: 1,
        boxes: [_box()],
        attemptFingerprint: 'aaaaaaaaaaaaaaaa',
        ensureRequest: (packet) async => !requestIds.add(packet.requestId),
      );
      expect(result, isNotNull);
      expect(result!.reused, isFalse);
      expect(result.box.state, KaiDeliveryBoxState.ready);
      expect(result.box.workRequestId, result.packet.requestId);
      expect(result.packet.text, startsWith('READY FOR AGENT'));
      expect(result.packet.text, contains('Required evidence:'));

      final same = KaiDeliveryController.packetFor(
        _box(),
        attemptFingerprint: 'aaaaaaaaaaaaaaaa',
      );
      expect(same.requestId, result.packet.requestId);
      expect(!requestIds.add(same.requestId), isTrue);
    });
  });

  group('repair, escalation, and proof integrity', () {
    test('safe failures repair, suppress identical attempts, then escalate',
        () {
      var box = _box();
      box = KaiDeliveryController.recordFailure(
        box,
        fingerprint: 'aaaaaaaaaaaaaaaa',
        causalBlocker: 'compiler',
        evidenceRefs: const ['a.log'],
        recordedAt: 1,
      );
      expect(box.state, KaiDeliveryBoxState.repairing);
      expect(
        () => KaiDeliveryController.recordFailure(
          box,
          fingerprint: 'aaaaaaaaaaaaaaaa',
          causalBlocker: 'compiler',
          evidenceRefs: const [],
          recordedAt: 2,
        ),
        throwsStateError,
      );
      box = KaiDeliveryController.recordFailure(
        box,
        fingerprint: 'bbbbbbbbbbbbbbbb',
        causalBlocker: 'compiler',
        evidenceRefs: const ['b.log'],
        recordedAt: 3,
      );
      box = KaiDeliveryController.recordFailure(
        box,
        fingerprint: 'cccccccccccccccc',
        causalBlocker: 'compiler',
        evidenceRefs: const ['c.log'],
        recordedAt: 4,
      );
      expect(box.state, KaiDeliveryBoxState.blocked);
      expect(box.attempts.length, 3);
      expect(box.escalationReason, contains('three distinct'));
    });

    test('true sponsor boundary stops immediately', () {
      final box = KaiDeliveryController.recordFailure(
        _box(
          owner: KaiDeliveryBoxOwner.sponsor,
          risk: KaiDeliveryRisk.productDecision,
        ),
        fingerprint: 'aaaaaaaaaaaaaaaa',
        causalBlocker: 'Sadeq must choose',
        evidenceRefs: const [],
        recordedAt: 1,
      );
      expect(box.state, KaiDeliveryBoxState.awaitingSponsor);
      expect(box.attempts, isEmpty);
    });

    test('agent completion cannot promote itself without evidence review', () {
      final box = _box();
      expect(
        () => KaiDeliveryController.verify(
          box,
          independentlyReviewed: true,
          reviewedBy: 'northstar_pm',
          evidenceRefs: const ['tests => test.log', 'review => review.md'],
          verifiedAt: 1,
        ),
        throwsStateError,
      );
      final review = KaiDeliveryController.submitEvidence(
        box,
        evidenceRefs: const ['tests => test.log', 'review => review.md'],
      );
      expect(review.state, KaiDeliveryBoxState.evidenceReview);
      expect(
        () => KaiDeliveryController.verify(
          review,
          independentlyReviewed: false,
          reviewedBy: 'northstar_pm',
          evidenceRefs: const ['tests => test.log', 'review => review.md'],
          verifiedAt: 1,
        ),
        throwsStateError,
      );
      expect(
        KaiDeliveryController.verify(
          review,
          independentlyReviewed: true,
          reviewedBy: 'northstar_pm',
          evidenceRefs: const ['tests => test.log', 'review => review.md'],
          verifiedAt: 1,
        ).state,
        KaiDeliveryBoxState.verified,
      );

      final sponsorReview = KaiDeliveryController.submitEvidence(
        _box(owner: KaiDeliveryBoxOwner.sponsor),
        evidenceRefs: const ['tests => test.log', 'review => review.md'],
      );
      expect(
        () => KaiDeliveryController.verify(
          sponsorReview,
          independentlyReviewed: true,
          reviewedBy: 'northstar_pm',
          evidenceRefs: const ['tests => test.log', 'review => review.md'],
          verifiedAt: 1,
        ),
        throwsStateError,
      );
    });

    test('closed requests without proof enter the bounded attempt ledger', () {
      var box = _box();
      for (final fingerprint in [
        '1111111111111111',
        '2222222222222222',
        '3333333333333333',
      ]) {
        box = KaiDeliveryController.reconcileWorkRequest(
          box,
          status: 'done',
          attemptFingerprint: fingerprint,
          evidenceRefs: const [],
          recordedAt: box.attempts.length + 1,
        );
      }
      expect(box.attempts.length, 3);
      expect(box.state, KaiDeliveryBoxState.blocked);
      expect(
          box.attempts.every(
              (attempt) => attempt.causalBlocker == 'closed_without_evidence'),
          isTrue);

      final cancelled = KaiDeliveryController.reconcileWorkRequest(
        _box(),
        status: 'cancelled',
        attemptFingerprint: '4444444444444444',
        evidenceRefs: const [],
        recordedAt: 1,
      );
      expect(cancelled.state, KaiDeliveryBoxState.repairing);
      expect(
        cancelled.attempts.single.causalBlocker,
        'cancelled_before_review',
      );
    });

    test('verified proof survives serialization and bare proof is rejected',
        () {
      final review = KaiDeliveryController.submitEvidence(
        _box(),
        evidenceRefs: const ['tests => test.log', 'review => review.md'],
      );
      final verified = KaiDeliveryController.verify(
        review,
        independentlyReviewed: true,
        reviewedBy: 'northstar_pm',
        evidenceRefs: const ['tests => test.log', 'review => review.md'],
        verifiedAt: 42,
      );
      final restored = KaiDeliveryBox.fromMap(verified.toMap());
      expect(restored.hasCompleteVerification, isTrue);
      expect(restored.verifiedBy, 'northstar_pm');
      expect(restored.verifiedAt, 42);
      expect(restored.evidenceRefs, hasLength(2));

      expect(
        _box(state: KaiDeliveryBoxState.verified).hasCompleteVerification,
        isFalse,
      );
    });
  });

  test('Pizza summary exposes compact counts and authority language', () {
    final boxes = [
      _box(id: 'done', state: KaiDeliveryBoxState.verified),
      _box(id: 'work', state: KaiDeliveryBoxState.active),
      _box(
        id: 'choice',
        owner: KaiDeliveryBoxOwner.sponsor,
        risk: KaiDeliveryRisk.productDecision,
        state: KaiDeliveryBoxState.awaitingSponsor,
      ),
      _box(id: 'stuck', state: KaiDeliveryBoxState.blocked),
    ];
    final summary = summarizeDeliveryBoxes(boxes);
    expect(summary.total, 4);
    expect(summary.verified, 1);
    expect(summary.active, 1);
    expect(summary.awaitingSponsor, 1);
    expect(summary.blocked, 1);
    expect(summary.kaiNext, 'Produce bounded evidence');
    expect(summary.sponsorNext, 'Produce bounded evidence');
  });
}
