import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/attention/kai_attention_engine.dart';
import 'package:homecoming_app/services/attention/kai_proactive_attention_queue.dart';
import 'package:homecoming_app/services/core/kai_body_event.dart';
import 'package:homecoming_app/services/core/kai_proactive_service.dart';

void main() {
  const nudge = KaiNudge('(proactive) be around');
  final body = KaiBodyRouteCandidate(
    bodyId: 'messenger-phone',
    surface: 'messenger',
    lastUserActivityAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    allowsFriendConversation: true,
  );

  test('Bahrain quiet hours defer exactly to 08:00 local', () {
    final queue = KaiProactiveAttentionQueue();
    final now = DateTime.utc(2026, 8, 8, 20, 58); // 23:58 Bahrain.
    queue.enqueue(nudge, receivedAt: now);

    final dispatch = queue.evaluate(now: now, candidates: [body])!;

    expect(dispatch.decision.outcome, KaiAttentionOutcome.deferUntil);
    expect(dispatch.decision.reasonCode, 'quiet_hours_active');
    expect(dispatch.decision.notBefore, DateTime.utc(2026, 8, 9, 5));
    expect(queue.pending, hasLength(1));
  });

  test('third delivery defers by the explicit daily policy', () {
    final queue = KaiProactiveAttentionQueue();
    final start = DateTime.utc(2026, 8, 8, 9); // Noon Bahrain.
    for (var i = 0; i < 2; i++) {
      final pending = queue.enqueue(
        nudge,
        receivedAt: start.add(Duration(minutes: i)),
      );
      final dispatch = queue.evaluate(
        now: start.add(Duration(minutes: i)),
        candidates: [body],
      )!;
      expect(dispatch.decision.outcome, KaiAttentionOutcome.deliverNow);
      queue.complete(pending.event.eventId,
          now: start.add(Duration(minutes: i)));
    }
    final thirdAt = start.add(const Duration(minutes: 10));
    queue.enqueue(nudge, receivedAt: thirdAt);

    final third = queue.evaluate(now: thirdAt, candidates: [body])!;

    expect(third.decision.outcome, KaiAttentionOutcome.deferUntil);
    expect(third.decision.reasonCode, 'delivery_budget_exhausted');
    expect(third.decision.notBefore, thirdAt.add(const Duration(minutes: 45)));
  });

  test('bodyless event stays pending then selects exactly one later body', () {
    final queue = KaiProactiveAttentionQueue();
    final now = DateTime.utc(2026, 8, 8, 9);
    queue.enqueue(nudge, receivedAt: now);

    final parked = queue.evaluate(now: now, candidates: const [])!;
    expect(parked.decision.outcome, KaiAttentionOutcome.storeForLater);
    expect(queue.pending, hasLength(1));
    expect(queue.pending.single.notBefore, now.add(const Duration(minutes: 1)));

    expect(
      queue.evaluate(
        now: now.add(const Duration(seconds: 20)),
        candidates: [body],
      ),
      isNull,
      reason: 'presence churn must not reconsider the same thought immediately',
    );

    final delivered = queue.evaluate(
      now: now.add(const Duration(minutes: 1)),
      candidates: [
        body,
        KaiBodyRouteCandidate(
          bodyId: 'desktop-main',
          surface: 'desktop',
          lastUserActivityAt:
              DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
          allowsFriendConversation: true,
        ),
      ],
    )!;
    expect(delivered.decision.outcome, KaiAttentionOutcome.deliverNow);
    expect(delivered.decision.bodyId, isNotNull);
  });

  test('failed attempt remains queued with bounded retry', () {
    final queue = KaiProactiveAttentionQueue();
    final now = DateTime.utc(2026, 8, 8, 9);
    final pending = queue.enqueue(nudge, receivedAt: now);
    expect(
      queue.evaluate(now: now, candidates: [body])!.decision.outcome,
      KaiAttentionOutcome.deliverNow,
    );

    queue.fail(pending.event.eventId, now: now);

    expect(queue.pending, hasLength(1));
    expect(
      queue.evaluate(
        now: now.add(const Duration(seconds: 59)),
        candidates: [body],
      ),
      isNull,
    );
    expect(
      queue
          .evaluate(
            now: now.add(const Duration(minutes: 1)),
            candidates: [body],
          )!
          .decision
          .outcome,
      KaiAttentionOutcome.deliverNow,
    );
  });

  test('completed event is removed and replay is discarded as duplicate', () {
    final queue = KaiProactiveAttentionQueue();
    final now = DateTime.utc(2026, 8, 8, 9);
    final pending = queue.enqueue(nudge, receivedAt: now, eventId: 'same-id');
    queue.evaluate(now: now, candidates: [body]);
    queue.complete(pending.event.eventId, now: now);
    expect(queue.pending, isEmpty);

    queue.enqueue(nudge,
        receivedAt: now.add(const Duration(seconds: 1)), eventId: 'same-id');
    final replay = queue.evaluate(
      now: now.add(const Duration(seconds: 1)),
      candidates: [body],
    )!;
    expect(replay.decision.outcome, KaiAttentionOutcome.discardDuplicate);
    expect(queue.pending, isEmpty);
  });

  test('two-hour-old ordinary nudge is explicitly expired', () {
    final queue = KaiProactiveAttentionQueue();
    final received = DateTime.utc(2026, 8, 8, 9);
    queue.enqueue(nudge, receivedAt: received);

    final result = queue.evaluate(
      now: received.add(const Duration(hours: 2)),
      candidates: [body],
    )!;

    expect(result.decision.outcome, KaiAttentionOutcome.discardExpired);
    expect(result.decision.reasonCode, 'expired_before_delivery');
    expect(queue.pending, isEmpty);
  });
}
