# Brief 007 — Wire proactive attention into Central Kai

Owner: Codex implementation team

Reviewer: Northstar project manager

Status: TESTED — RUNTIME DELIVERY UNVERIFIED

## Goal

Every ordinary proactive friend event received by the headless coordinator is
admitted through the tested Central Attention policy, selects at most one body,
and is retried or explicitly discarded instead of disappearing when Central Kai
is busy, quiet hours are active, the daily budget is exhausted, or no eligible
body is online.

## Why this is next

The accepted Attention Engine is tested but has no production caller. The live
coordinator still routes directly with `routeKaiOutput` and returns early when
busy or bodyless, silently losing the nudge. This is the smallest production
seam that materially advances bidirectional presence and attention without
touching the deferred Unity acceptance gate.

## Entry gate

- Briefs 003 and 004 are accepted as pure-policy `Tested` evidence.
- Preserve the existing dirty coordinator and its unrelated work.
- Existing direct-reply, Messenger, Unity/AR, memory, and tool paths remain
  unchanged.

## In scope

- A bounded in-process proactive-attention queue with explicit receipt IDs.
- Admission through `KaiAttentionEngine` using:
  - Bahrain quiet hours 01:00–08:00 at UTC+03:00;
  - six ordinary proactive deliveries per Bahrain calendar day;
  - a 45-minute budget retry;
  - two-hour relevance expiry for ordinary nudges.
- Retry after coordinator/direct-conversation contention, no eligible body, or
  a failed delivery attempt.
- One exact selected body passed into the existing delivery implementation.
- Content-free decision journaling with event/correlation ID, outcome, reason,
  chosen body, and retry instant.
- Focused deterministic queue tests and coordinator wiring regression guards.

## Out of scope

- Durable commitments, completed-work delivery, or direct-reply admission.
- Persistence of pending attention across coordinator or laptop restart.
- Cloud scheduling, notifications, UI, Unity, transport, memory, tools, or
  self-improvement.
- Changing the pure Attention Engine contract.
- Claiming Central Attention is verified live or Phase 3 complete.

## Invariants

- One event selects zero or one body; never fan out.
- Device time never orders attention.
- Payload content cannot authorize a quiet-hours override.
- Messenger remains friend-only and receives no tools or technical machinery.
- A failed or bodyless attempt remains queued until retry or explicit expiry.
- A successfully completed attempt is not delivered twice in the same
  coordinator lifetime.
- Operational logs contain no nudge seed or generated reply.

## Authoritative evidence to inspect

- `lib/services/attention/kai_attention_event.dart`
- `lib/services/attention/kai_attention_engine.dart`
- `lib/services/core/kai_headless_coordinator.dart`
- `lib/services/core/kai_proactive_service.dart`
- `lib/services/core/kai_operations_journal.dart`
- `test/kai_attention_engine_test.dart`
- `test/kai_headless_coordinator_test.dart`

## Procedure

1. Add failing deterministic queue tests.
2. Implement the bounded queue as an attention-layer adapter.
3. Replace the coordinator's direct proactive routing with queue admission.
4. Trigger reevaluation on receipt, body-presence change, and a bounded timer.
5. Preserve the selected-body delivery path and acknowledge completion only
   after the attempt finishes.
6. Add content-free decision journal records.
7. Run focused attention, routing, coordinator, and analysis checks.
8. Stop and report; do not begin commitments or durable persistence.

## Pass criteria

- A received nudge is queued even while the coordinator is processing another
  conversation.
- Bahrain quiet hours defer it to exactly 08:00 local.
- The seventh ordinary proactive delivery in a Bahrain day defers by exactly 45
  minutes.
- No eligible body returns `storeForLater` and keeps the event pending.
- A later body-presence evaluation selects exactly one body.
- A failed attempt remains pending with a bounded retry time.
- A completed attempt is removed and its event ID becomes a duplicate if
  replayed in the same coordinator lifetime.
- Two-hour-old ordinary events are explicitly expired and removed.
- The coordinator no longer calls `routeKaiOutput` directly for proactive
  friend delivery.
- Existing attention-engine, body-routing, and coordinator tests pass.

Any missing criterion is `FAIL` or `UNVERIFIED`, not partial success.

## Required verification

```powershell
flutter test test/kai_proactive_attention_queue_test.dart
flutter test test/kai_attention_engine_test.dart test/kai_body_event_test.dart
flutter test test/kai_headless_coordinator_test.dart
flutter analyze lib/services/attention lib/services/core/kai_headless_coordinator.dart test/kai_proactive_attention_queue_test.dart
git diff --check
```

Runtime delivery remains `UNVERIFIED` until an attended proactive event is
observed in a rebuilt coordinator and its journal decision is inspected.

## Verification record — 2026-08-08

- Queue policy adapter: 6/6 focused tests pass.
- Full attention/coordinator regression: 43/43 tests pass.
- Scoped analysis completes with no errors. Three existing unused-subscription
  warnings remain in `kai_headless_coordinator.dart`; the new attention adapter
  and tests report no issue.
- `git diff --check` reports no whitespace error.
- Attended coordinator delivery and journal inspection: UNVERIFIED.

## Reviewer verdict

The ordinary proactive path is **Wired** and deterministically **Tested**. It is
not `Verified live`, restart-durable, or the complete Central Attention phase.
Pending events still live only in the coordinator process and are lost if that
process or laptop dies.

## Failure and rollback

Remove the queue adapter and restore the coordinator's prior direct routing
block. Preserve all operational logs and existing Core/Firebase state. Never
delete conversation or project records.

## Stop and report

Report files, behavior, commands, exact results, runtime evidence, unresolved
restart-durability risk, rollback, verdict, and the next recommendation.

Do not start durable commitments, completed-work routing, device transport,
Unity work, or self-improvement.
