# Brief 016 — Coordinator due-commitment loop

Owner: Claude implementation team

Reviewer: Northstar project manager

Status: ACCEPTED — TESTED / WIRED 2026-08-08

Parent phase: Brief 012 durable scheduled commitment vertical slice

## PM acceptance 2026-08-08

Brief 016 is accepted at `TESTED` and `WIRED`, not yet `VERIFIED LIVE`.

Option C leaves a no-body promise scheduled and due in Core, uses the positive
coordinator interval for bounded retry, and wakes the same due drain when an
eligible desktop appears. Quiet-hours `deferUntil` still persists the engine's
exact UTC instant; presence does not override it. The production lifecycle owns
initial, periodic, presence, and stop triggers, generation-invalidates stale
drains, and awaits in-flight work before stop returns.

Independent PM evidence:

- 18/18 criteria pass under the ratified Option C contract.
- 43/43 reviewer, scheduler, lifecycle, and coordinator tests pass.
- 109/109 critical dependency regressions pass.
- 116/116 shared regressions pass.
- Scoped analysis of six Brief 016 production/test files reports no issues.
- `git diff --check` passes; output contains line-ending notices only.

No live reminder was created. The next bounded seam is Brief 017: make desktop
`set_reminder` create the accepted deterministic Central Core commitment while
preserving native Android behavior.

## PM review follow-up 2026-08-08

The scheduler policy implementation passes its reported focused gate and the PM
independently reproduced 27/27 focused coordinator tests. Brief 016 is not yet
accepted because criterion 14 is `UNVERIFIED`, and inspection shows a real
shutdown race rather than missing paperwork.

`KaiHeadlessCoordinator.stop()` cancels timers and subscriptions, but an
already-started `KaiDueCommitmentScheduler.drain()` can still resume after
`commitments(dueOnly: true)` completes and dispatch or defer a commitment after
shutdown. The scheduler has no stopped/generation state, coordinator `stop()`
does not await its in-flight drain, and the production binding that owns initial
drain, periodic drain, presence wake, and teardown is not tested.

Repair only this lifecycle seam:

- Add a narrow production due-loop lifecycle used by the real coordinator.
  It owns initial drain, periodic scheduling, eligible-presence wake, and stop.
- Stop must mark the loop inactive before cancelling triggers and must await or
  invalidate in-flight work so that after `stop()` returns no stale callback can
  dispatch, defer, or journal a Core transition.
- Make stop/start generation-safe: a drain from an earlier generation cannot
  become authorized again merely because the loop was restarted.
- Test the same production lifecycle object, not copied coordinator logic or a
  source-text tripwire. Deterministically pause the Core list call, stop while it
  is awaiting, release it, and prove no dispatch/deferral occurs afterward.
- Prove initial drain, one periodic tick, eligible desktop wake, irrelevant
  presence churn, overlapping triggers, stop, and restart behavior through the
  production object.

Permitted repair files are the existing Brief 016 production/test files plus
one narrowly named lifecycle production file and its matching test. Do not
inject or redesign the entire coordinator, and do not touch desktop reminder
creation or any later seam.

## PM presence-wake review follow-up 2026-08-08

The lifecycle repair closes criteria 14, 17, and 18: the production loop owns
the four triggers, generation-invalidates suspended drains, and awaits them on
stop. Independent review found criterion 7 still fails.

After a no-body decision, Core correctly persists a future
`nextEvaluationAt`. When an eligible desktop then appears, the loop wakes but
calls `commitments(dueOnly: true)`. Core correctly returns no record before that
future instant, so the wake performs a request but cannot re-evaluate or
dispatch the promise. The existing wake test asserts only that `listCalls`
increased; it does not assert the required user-visible transition.

The immutable reviewer
`test/kai_due_commitment_presence_wake_reviewer_test.dart` proves the defect:
the ordinary no-body drain persists a bounded retry, an eligible desktop
appears before it, and the record remains `scheduled` rather than becoming
`dispatched`. Combined evidence is **39 PASS / 1 FAIL**.

Repair only the presence-specific reevaluation path using accepted Core APIs.
The timer/initial drain must continue to use `dueOnly: true`. An eligible-body
wake may explicitly list scheduled commitments, but it must consider only
promises whose original `dueAt` has arrived and must run each through the real
attention engine again. This preserves quiet hours: a quiet-hours deferral
encountered by a presence wake is deferred again, never delivered early. Do not
infer the prior deferral reason from reminder text and do not bypass the engine.

Required focused proof, through the production loop:

- no body persists a future bounded retry;
- a newly eligible desktop before that retry dispatches immediately;
- Messenger/AR/VR churn does not perform the presence-specific reevaluation;
- a commitment whose original `dueAt` is still future is not evaluated;
- a quiet-hours commitment remains deferred to the engine's exact instant;
- retries and overlapping timer/presence triggers create one outbound; and
- the immutable reviewer passes unchanged.

This paragraph clarifies criterion 1's intended relationship with criterion 7:
ordinary initial/timer drains do nothing before `nextEvaluationAt`; the sole
exception is the explicit eligible-presence wake for an already-originally-due
promise. Do not change Core server schema or the accepted deferral endpoint
unless this path is proven impossible; report `BLOCKED_BY_CONTRACT` first.

## PM contract resolution 2026-08-08 — Option C accepted

This later resolution supersedes the earlier presence-wake bullets wherever
they require persisting a future no-body retry.

Claude proved `BLOCKED_BY_CONTRACT`: once a no-body path advances
`nextEvaluationAt`, accepted Core rules correctly reject both early dispatch
(`commitment_not_yet_due`) and moving the evaluation instant backward
(`commitment_evaluation_regression`). Persisting a future no-body retry and
also dispatching immediately on presence are mutually incompatible.

The PM selects Option C. Preserve both Core security/integrity gates. For
`storeForLater` caused by no eligible body:

- do not call `deferCommitment` and do not alter Core `nextEvaluationAt`;
- leave the originally due promise scheduled and due in Core;
- use the due loop's positive periodic interval as the bounded retry;
- keep identity-based journal suppression so each timer tick does not create
  duplicate telemetry; and
- let a newly eligible desktop wake the ordinary due drain immediately.

Only `deferUntil` persists `nextEvaluationAt`; this remains mandatory for quiet
hours and any other engine-authored temporal policy. Presence never bypasses a
persisted quiet-hours instant because those records are absent from
`dueOnly:true`. Remove the speculative all-scheduled presence query if it is no
longer needed; the simplest correct path is preferred.

This is an implementation-contract correction, not a relaxation of delivery
security. It also improves restart behavior: an overdue promise with no body
remains visibly owed and can be retried immediately after restart rather than
inheriting stale absence information.

## Goal

Make the running headless coordinator turn each due Central Core commitment
into one durable, explicit-work Central Attention decision, then either dispatch
it atomically to one exact eligible desktop body or persist the exact next
evaluation time while the promise remains owed.

## Why this is next

Briefs 013–015 now prove the durable ledger, client contract, exact-body inbox,
and persistence-before-acknowledgement receiver. The missing middle is the
coordinator: no production loop currently asks Core for due commitments,
evaluates them through `KaiAttentionEngine`, or dispatches/defer them. Until
this seam exists, the tested sender and receiver never meet.

## Entry gate

- Reproduce the accepted Brief 015 focused/critical gate and the 116 shared
  regressions before editing.
- Capture `git status --short`; preserve every unrelated dirty-worktree change.
- Read Briefs 012–015 and the current attention, Core client, global presence,
  coordinator, and operations-journal contracts before designing the seam.
- If an accepted API cannot express this brief without changing Core server or
  desktop behavior, stop and report `BLOCKED_BY_CONTRACT` before expanding
  scope.

## In scope

- Add a single, non-overlapping coordinator drain for
  `client.commitments(dueOnly: true)`.
- Convert each record to one `KaiAttentionEvent` with:
  - stable event ID derived only from the commitment ID;
  - `correlationId` equal to the commitment ID;
  - `kind: KaiAttentionKind.dueCommitment`;
  - explicit trusted `audience: KaiAttentionAudience.work`;
  - durable semantics and no expiry;
  - authoritative persisted Core times, never device-local ordering.
- Build attention candidates from the current global presence snapshot using
  the exact global body IDs. Only work-eligible desktop bodies may be selected.
- Evaluate through the accepted `KaiAttentionEngine`; do not reproduce its
  policy in coordinator conditionals.
- On `deliverNow`, call the accepted atomic Core dispatch API with the exact
  selected body ID. The exact stored reminder text remains Core-owned.
- On `deferUntil`, persist the engine's exact `notBefore` through
  `deferCommitment`.
- On `storeForLater`, leave Core's already-due evaluation instant unchanged.
  The positive loop interval is the bounded retry, and a newly eligible desktop
  wakes the ordinary due drain immediately.
- Add deterministic clock, policy, presence, and scheduling seams sufficient
  to test quiet hours and retries without wall-clock waiting.
- Journal state transitions and failures without reminder text or secrets, and
  suppress repeated identical decision entries on idle timer ticks.

## Out of scope

- Desktop `set_reminder`, Android tools, Messenger, AR, VR, Unity, model calls,
  generated reminder wording, notifications, TTS, recurring reminders,
  cancellation UI, cloud deployment, leader election, or live-state testing.
- Changes to the accepted Core ledger/server transition rules, desktop outbound
  receiver, conversation storage, or attention-engine policy.
- Reusing the ordinary proactive queue as the commitment ledger. Core remains
  the sole durable source of truth for scheduled commitments.

## Invariants

- A promise is never silently lost, expired, discarded, or marked complete by
  the coordinator.
- The scheduling drain has its own guard. It is not blocked by `_busy` or the
  proactive-generation busy flag; due reminders require no model call.
- Reminder text never determines audience, urgency, route, or body eligibility.
- Messenger-, AR-, and VR-only presence cannot receive this work reminder.
- The selected routing body ID and Core dispatch target body ID are byte-for-
  byte the same global presence ID later polled by desktop.
- A timer retry, presence wake, process retry, or Core retry cannot mint a
  second outbound for the same commitment.
- Quiet hours persist the engine's exact UTC `notBefore`; the coordinator does
  not reevaluate that commitment before Core says it is due again.
- No-body retries are positive, bounded policy inputs—not hard-coded accidental
  delays—and eligible presence can wake earlier.
- Network or persistence failure leaves the commitment scheduled and retryable.
- Operations telemetry contains IDs, outcomes, timing, and reason codes only;
  never reminder content, chat content, auth material, or full request URLs.

## Authoritative files

- `docs/briefs/BRIEF_012_DURABLE_SCHEDULED_COMMITMENT_VERTICAL_SLICE.md`
- `docs/briefs/BRIEF_013_CORE_COMMITMENT_INTEGRITY_REPAIR.md`
- `docs/briefs/BRIEF_014_COMMITMENT_CLIENT_AND_DEFERRAL_CONTRACT.md`
- `docs/briefs/BRIEF_015_DESKTOP_OUTBOUND_TRANSCRIPT_ACCEPTANCE.md`
- `lib/services/core/kai_headless_coordinator.dart`
- `lib/services/core/kai_core_client.dart`
- `lib/services/core/kai_global_presence_service.dart`
- `lib/services/core/kai_operations_journal.dart`
- `lib/services/attention/kai_attention_event.dart`
- `lib/services/attention/kai_attention_engine.dart`
- `lib/services/core/kai_body_event.dart`
- their focused tests under `test/`

## Permitted files

- Modify `lib/services/core/kai_headless_coordinator.dart` and
  `test/kai_headless_coordinator_test.dart`.
- Add one narrowly named production scheduler/orchestrator unit under
  `lib/services/core/` and one matching focused test if extraction is required
  to keep decisions deterministic and directly testable. The real coordinator
  must use that production unit; no copied test algorithm is acceptable.
- Modify `lib/services/core/kai_operations_journal.dart` and its test only if a
  narrow identity-based repeated-decision suppression primitive is genuinely
  required. Prefer coordinator-owned suppression.
- Modify `lib/services/core/kai_core_client.dart` and its focused test only if
  an injection seam is required; do not change accepted wire semantics.
- Do not modify Core server/ledger, attention engine/event policy, desktop,
  conversation storage, tools, Android, Unity, Briefs 012–016, or the Northstar
  source of truth. Stop with `BLOCKED_BY_SCOPE` before touching another file.

## Required decision contract

For every record returned by `commitments(dueOnly: true)`:

```text
Core due record
  -> explicit work-audience durable KaiAttentionEvent
  -> KaiAttentionEngine.decide(event, current policy + global candidates)
  -> deliverNow: dispatchCommitment(commitmentId, exact bodyId)
  -> deferUntil: deferCommitment(commitmentId, engine.notBefore)
  -> storeForLater: leave commitment scheduled and due; retry by loop/presence
```

`discardDuplicate` and `discardExpired` are contradictions for an outstanding
Core commitment in this loop. Do not mark the promise handled. Leave it owed,
journal the contradiction without text, and report how tests make the state
recoverable.

## Procedure

1. Reproduce entry gates and map coordinator startup, timers, shutdown, Core
   availability, and global-presence updates.
2. Write failing deterministic tests for construction, quiet hours, no body,
   exact-body dispatch, overlapping drains, presence wake, restart/idempotent
   retry, failure retention, and journal suppression.
3. Implement the smallest production scheduler unit and bind it into the real
   coordinator lifecycle.
4. Prove that its drain is independent from model/proactive busy flags and that
   disposal prevents later timer or presence callbacks.
5. Run all gates and stop. Do not start desktop reminder creation.

## Pass criteria

1. Before persisted `nextEvaluationAt`, no initial, timer, or presence drain
   produces an attention decision, deferral, or dispatch.
2. Every due record becomes a durable, expiry-free `dueCommitment` with stable
   event/correlation identity and explicit trusted `work` audience.
3. The real `KaiAttentionEngine` decides the route; the coordinator does not
   inspect reminder text or recreate attention policy.
4. During quiet hours, Core receives exactly the engine's UTC `notBefore`, no
   outbound is created, and no reevaluation occurs before that instant.
5. With no work-eligible desktop body, the commitment remains scheduled and due
   with its evaluation instant unchanged. The positive loop interval provides
   bounded retry without weakening Core's monotonic deferral contract.
6. Messenger-, AR-, VR-, expired-, malformed-, or non-work desktop candidates
   cannot be selected.
7. A newly eligible desktop presence wakes an immediate drain even before the
   bounded timer, while irrelevant presence changes do not create work.
8. With eligible desktop presence, exactly one global body ID is selected and
   passed unchanged to `dispatchCommitment`; exact text is never regenerated.
9. Overlapping timer, manual, and presence-triggered drains collapse to one.
10. The commitment drain proceeds while ordinary proactive/model work is busy.
11. Dispatch, list, or deferral failures leave the promise owed and retryable;
    later success creates no duplicate outbound.
12. Restart/retry of the same due commitment preserves stable event identity
    and relies on Core's idempotent atomic dispatch rather than local success
    claims.
13. Identical unchanged outcomes do not append one journal entry per tick;
    meaningful transition, target, reason, or retry-time changes remain visible.
14. Coordinator stop/dispose cancels timer and presence subscriptions and no
    later callback mutates Core.
15. Existing proactive attention, Messenger ownership, embodiment routing,
    Core integrity, desktop outbound acceptance, and shared tests stay green.
16. Scoped analysis adds no new diagnostic and `git diff --check` passes.
17. The real coordinator delegates initial, periodic, presence-triggered, and
    stop behavior to one directly tested production lifecycle object.
18. If stop occurs while Core's due-list request is awaiting, releasing that
    request afterward causes no dispatch, deferral, or transition journal; a
    later restart works, and no callback from the earlier generation acts.

Any missing criterion is `FAIL` or `UNVERIFIED`, never partial.

## Required verification

Report exact commands, counts, diagnostics, and exit codes:

```powershell
flutter test test/kai_due_commitment_coordinator_test.dart test/kai_headless_coordinator_test.dart
flutter test test/kai_attention_engine_test.dart test/kai_body_event_test.dart
flutter test test/kai_core_commitment_client_test.dart
flutter test test/kai_scheduled_commitment_reviewer_test.dart test/kai_core_commitment_reviewer_followup_test.dart test/kai_core_recovery_regression_test.dart
flutter test test/kai_desktop_outbound_reviewer_test.dart test/kai_desktop_outbound_acceptance_test.dart test/kai_core_outbound_poller_test.dart
flutter test test/kai_scheduled_commitment_test.dart test/kai_core_outbound_inbox_test.dart test/kai_core_server_test.dart test/kai_attention_engine_test.dart test/kai_body_event_test.dart test/kai_headless_coordinator_test.dart test/conversation_store_service_test.dart test/kai_capability_broker_test.dart test/kai_surface_context_test.dart test/kai_desktop_goggles_policy_test.dart
flutter analyze <every production and test file changed by Brief 016>
git diff --check
git status --short
```

If the new focused filename differs, substitute it consistently and explain.

## Stop and report

Report files and behavior changed; exact event, retry, wake, and journal
contracts; criterion-by-criterion PASS/FAIL/UNVERIFIED; every command and count;
scope deviations; unresolved risks; and rollback state.

Do not start desktop `set_reminder`, attended runtime acceptance, Android,
Messenger delivery, AR/VR/Unity, recurring commitments, or self-improvement.
