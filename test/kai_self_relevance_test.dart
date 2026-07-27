import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_autobiography_service.dart';
import 'package:homecoming_app/services/core/kai_noticed_service.dart';
import 'package:homecoming_app/services/core/kai_router_service.dart';
import 'package:homecoming_app/services/core/kai_self_nuance_service.dart';
import 'package:homecoming_app/services/core/kai_self_provenance.dart';
import 'package:homecoming_app/services/core/kai_self_relevance.dart';

void main() {
  Noticed commitment(String id, String text) => Noticed(
        id: id,
        text: text,
        notedAt: DateTime.now().millisecondsSinceEpoch,
        kind: NoticedKind.promise,
        authoredByKai: true,
        authorReceiptId: 'tool:make_commitment:$id',
      );

  test('topic overlap beats mere recency for a coding turn', () {
    final selected = KaiSelfRelevance.commitments(
      candidates: [
        commitment('new', 'Remember to buy flowers'),
        commitment('code', 'Run the compiler benchmark after the refactor'),
      ],
      message: 'Let us finish the compiler refactor and benchmark it',
      route: KaiRoute.coding,
      mood: const {'valence': 50},
      limit: 1,
    );
    expect(selected.single.id, 'code');
  });

  test('emotional route favors corrective emotional autobiography', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    AutobiographicalEpisode episode(
      String id,
      AutobiographicalEpisodeKind kind,
    ) =>
        AutobiographicalEpisode(
          id: id,
          kind: kind,
          choice: 'I chose a response that could be checked',
          outcome: 'The result was recorded for later reflection',
          meaning: 'A grounded consequence',
          provenance: SelfProvenance(
            source: SelfClaimSource.groundedRecord,
            evidenceIds: ['trace:$id'],
            confidence: 0.8,
            recordedAt: now,
          ),
          occurredAt: now,
        );
    final selected = KaiSelfRelevance.episodes(
      candidates: [
        episode('action', AutobiographicalEpisodeKind.completedAction),
        episode('correction', AutobiographicalEpisodeKind.correctedBelief),
      ],
      message: 'I am having a hard day',
      route: KaiRoute.emotional,
      mood: const {'valence': 25},
      limit: 1,
    );
    expect(selected.single.id, 'correction');
  });

  test('unreceipted commitments can never enter selection', () {
    final selected = KaiSelfRelevance.commitments(
      candidates: const [
        Noticed(
          id: 'forged',
          text: 'I promise anything',
          notedAt: 1,
          kind: NoticedKind.promise,
          authoredByKai: false,
        ),
      ],
      message: 'promise',
      route: KaiRoute.fastChat,
      mood: const {},
      limit: 2,
    );
    expect(selected, isEmpty);
  });

  test('nuance is hidden until repeated evidence matures it', () {
    final young = KaiSelfNuance.fromMap('intuition_up', {
      'description': 'I increasingly connect patterns',
      'observations': 2,
      'lastObservedAt': 10,
    });
    final mature = KaiSelfNuance.fromMap('intuition_up', {
      'description': 'I increasingly connect patterns',
      'observations': 3,
      'lastObservedAt': 20,
    });
    expect(young!.isMature, isFalse);
    expect(mature!.isMature, isTrue);
  });

  test('balanced opposing tendencies become context-dependent nuance', () {
    final now = DateTime(2026, 7, 27);
    final active = KaiSelfNuanceService.activeNuances([
      KaiSelfNuance(
        key: 'intuition_up',
        description: 'patterns',
        observations: 4,
        lastObservedAt: now.millisecondsSinceEpoch,
      ),
      KaiSelfNuance(
        key: 'intuition_down',
        description: 'particulars',
        observations: 3,
        lastObservedAt: now.millisecondsSinceEpoch,
      ),
    ], now: now);
    expect(active.single.key, 'intuition_contextual');
    expect(active.single.description, contains('depending'));
  });

  test('stale nuance leaves active self without deleting its record', () {
    final now = DateTime(2026, 7, 27);
    final active = KaiSelfNuanceService.activeNuances([
      KaiSelfNuance(
        key: 'feeling_up',
        description: 'human impact',
        observations: 9,
        lastObservedAt:
            now.subtract(const Duration(days: 181)).millisecondsSinceEpoch,
      ),
    ], now: now);
    expect(active, isEmpty);
  });
}
