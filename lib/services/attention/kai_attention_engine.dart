/// The Central Attention decision.
///
/// One event in, one decision out. No delivery, no language, no memory, no I/O.
/// Everything mutable arrives in [KaiAttentionContext], so the same inputs
/// always produce the same decision and any decision can be replayed from its
/// audit record.
///
/// ── Why the order below is fixed ────────────────────────────────────────────
///
/// The policy is deliberately small and ordered, not a scoring function. Each
/// step can only ever narrow the outcome, and the two steps that could lose
/// something Kai owes — expiry and the budget — are placed so a durable
/// commitment passes through both untouched.
///
/// The single rule underneath all of it: **a promise is never lost quietly.**
/// Quiet hours can delay it, an empty body list can hold it, but nothing in
/// here may discard it.
library;

import '../core/kai_body_event.dart';
import 'kai_attention_event.dart';

export 'kai_attention_event.dart';

class KaiAttentionEngine {
  const KaiAttentionEngine();

  /// Core receipt time orders events. Device time is descriptive and is never
  /// consulted — a body cannot reorder the stream by lying about its clock.
  ///
  /// Ties break on `eventId` so the order is total and reproducible.
  static List<KaiAttentionEvent> orderByReceipt(
    Iterable<KaiAttentionEvent> events,
  ) {
    final ordered = events.toList()
      ..sort((a, b) {
        final byReceipt = a.receivedAt.compareTo(b.receivedAt);
        if (byReceipt != 0) return byReceipt;
        return a.eventId.compareTo(b.eventId);
      });
    return ordered;
  }

  /// The order Kai should CONSIDER things in: priority first, then arrival.
  ///
  /// Distinct from [orderByReceipt], which answers a different question — what
  /// happened first — and stays the authority for the cross-body event stream.
  /// Both exist because both are required: receipt time is how a distributed
  /// event log is ordered, priority is how a queue of pending attention is
  /// worked through.
  ///
  /// Fully deterministic: priority descending, then receipt ascending, then
  /// `eventId`. The final key makes the order total, so two events sharing a
  /// priority and a timestamp still sort the same way on every run.
  ///
  /// Priority orders; it never authorises. A 9 waits for quiet hours exactly
  /// as a 0 does.
  static List<KaiAttentionEvent> orderForAttention(
    Iterable<KaiAttentionEvent> events,
  ) {
    final ordered = events.toList()
      ..sort((a, b) {
        final byPriority = b.priority.compareTo(a.priority);
        if (byPriority != 0) return byPriority;
        final byReceipt = a.receivedAt.compareTo(b.receivedAt);
        if (byReceipt != 0) return byReceipt;
        return a.eventId.compareTo(b.eventId);
      });
    return ordered;
  }

  KaiAttentionDecision decide({
    required KaiAttentionEvent event,
    required KaiAttentionContext context,
  }) {
    // ── 1. Already handled ───────────────────────────────────────────────────
    // Idempotent by event id. A redelivered event is not a second nudge.
    if (context.processedEventIds.contains(event.eventId)) {
      return _decision(
        event,
        KaiAttentionOutcome.discardDuplicate,
        'duplicate_event_id',
      );
    }

    // ── 2. Stale ─────────────────────────────────────────────────────────────
    // Durable events skip this. A commitment that came due while nobody was
    // looking is still owed — expiry is a relevance rule for chatter, and
    // applying it to a promise is how promises get lost.
    final expiresAt = event.expiresAt;
    if (!event.isDurable &&
        expiresAt != null &&
        !context.now.isBefore(expiresAt)) {
      return _decision(
        event,
        KaiAttentionOutcome.discardExpired,
        'expired_before_delivery',
      );
    }

    // ── 3. Quiet hours ───────────────────────────────────────────────────────
    // Applies to anything proactive, including a due commitment — 3am is not
    // when to be reminded. It DEFERS rather than discards, and a commitment
    // stays durable across the wait.
    //
    // The override comes from policy. `event.payload` is untrusted body data
    // and is never read here: a body claiming its own urgency would otherwise
    // be able to write itself a pass through the one rule that protects sleep.
    final proactive = event.kind == KaiAttentionKind.proactiveNudge ||
        event.kind == KaiAttentionKind.dueCommitment;
    if (proactive &&
        context.quietHours.contains(context.now) &&
        !context.urgentOverrideAuthorized) {
      return _decision(
        event,
        KaiAttentionOutcome.deferUntil,
        'quiet_hours_active',
        notBefore: context.quietHours.endsAfter(context.now),
        remainsDurable: event.isDurable,
      );
    }

    // ── 4. Delivery budget ───────────────────────────────────────────────────
    // Pacing, not forgetting. Only ordinary proactive output is paced: a reply
    // was asked for, work was requested, and a commitment was promised.
    if (event.isPaceable && context.budgetExhausted) {
      return _decision(
        event,
        KaiAttentionOutcome.deferUntil,
        'delivery_budget_exhausted',
        notBefore: context.now.add(context.budgetRetryDelay).toUtc(),
      );
    }

    // ── 5. One body, or none ─────────────────────────────────────────────────
    // Delegated to the existing contract rather than reimplemented, so the
    // one-exact-body invariant has a single definition.
    final route = routeKaiOutput(
      kind: event.outboundKind,
      candidates: context.candidates,
      originBodyId: event.originBodyId,
    );

    if (route.storeForLater || route.bodyId == null) {
      return _decision(
        event,
        KaiAttentionOutcome.storeForLater,
        route.reason,
        // Anything owed stays owed while it waits for somewhere to land.
        remainsDurable: event.isDurable ||
            event.kind == KaiAttentionKind.directReply ||
            event.kind == KaiAttentionKind.completedWork,
      );
    }

    return _decision(
      event,
      KaiAttentionOutcome.deliverNow,
      route.reason,
      bodyId: route.bodyId,
      // Still owed even here. This engine DECIDES; it does not deliver. A
      // caller that read `deliverNow, remainsDurable: false` could drop the
      // commitment before the body ever acknowledged it, which is the exact
      // silent loss this whole policy exists to prevent. It stays owed until
      // something downstream confirms it landed.
      remainsDurable: event.isDurable,
    );
  }

  static KaiAttentionDecision _decision(
    KaiAttentionEvent event,
    KaiAttentionOutcome outcome,
    String reasonCode, {
    String? bodyId,
    DateTime? notBefore,
    bool remainsDurable = false,
  }) =>
      KaiAttentionDecision(
        outcome: outcome,
        reasonCode: reasonCode,
        eventId: event.eventId,
        correlationId: event.correlationId,
        bodyId: bodyId,
        notBefore: notBefore,
        remainsDurable: remainsDurable,
      );
}
