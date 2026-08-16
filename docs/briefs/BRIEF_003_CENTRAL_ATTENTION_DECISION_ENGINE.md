# Brief 003 — Central attention decision engine

Owner: Claude implementation team

Reviewer: Northstar project manager

Status: ACCEPTED VIA BRIEF 004 — TESTED, NOT INTEGRATED

## Goal

Build and deterministically test a pure-Dart Central Attention decision engine
that decides whether Kai should deliver, defer, or discard an incoming event,
without performing delivery or changing any live runtime path.

The engine must make one reproducible decision from explicit inputs covering
priority, quiet hours, notification budget, commitments, deduplication, and the
eligible body-routing contract.

## Why this is safe to run in parallel

Phase 1 Unity acceptance remains open. The current worktree also contains
uncommitted embodiment and Core inbox work. This brief advances Phase 3's
backend decision seam using new pure-Dart files only. It must not modify or
integrate with Unity, Kai Core, the headless coordinator, Firebase, Messenger,
or any UI.

Passing this brief means the attention policy is `TESTED`. It does not make
Central Attention live, does not close Phase 1, and does not prove proactive
presence on a device.

## Entry gate

- Read `docs/NORTHSTAR_SOURCE_OF_TRUTH.md` and preserve its invariants.
- Read `lib/services/core/kai_body_event.dart` and
  `test/kai_body_event_test.dart` for the existing one-body routing contract.
- Run `git status --short` before editing. Preserve every existing user-owned
  modification and untracked file.
- Confirm the implementation can be contained in new attention-domain files
  plus their focused tests.

If an existing dirty file must change, stop and report the reason. Do not edit
it under this brief.

## In scope

- Add a pure-Dart attention domain under
  `lib/services/attention/`. Suggested structure:
  - `kai_attention_event.dart`
  - `kai_attention_engine.dart`
- Add focused tests in `test/kai_attention_engine_test.dart`.
- Define explicit, serializable value objects for:
  - an incoming attention event;
  - current attention context;
  - an optional commitment;
  - a deterministic attention decision.
- Support these decision outcomes:
  - `deliverNow`;
  - `deferUntil`;
  - `discardDuplicate`;
  - `discardExpired`;
  - `storeForLater` when no suitable body is available.
- Accept all changing state as input, including `now`, quiet-hours policy,
  delivery-budget usage, processed event IDs, body candidates, and commitment
  state. The engine must not read a clock or global singleton.
- Use Core `receivedAt`, not device `occurredAt`, for cross-body ordering.
- Reuse the existing `routeKaiOutput` contract where body selection is needed.
  Do not duplicate or weaken its one-exact-body behavior.
- Return machine-readable reason codes suitable for later logging and audit.

## Out of scope

- Any edits to:
  - `lib/services/core/kai_core_server.dart`
  - `lib/services/core/kai_core_client.dart`
  - `lib/services/core/kai_headless_coordinator.dart`
  - `lib/services/core/kai_body_event.dart`
  - existing Core or headless tests
  - Unity, Android, Quest, Firebase, Messenger, desktop UI, or watchdog code
- Wiring the engine into a running process.
- Sending notifications or creating Core outbound envelopes.
- Generating proactive text or making model/provider calls.
- Writing conversation history, semantic memory, or life events.
- Inferring emotion, psychological needs, or relationship state.
- Self-improvement, capability execution, transport, UI, animation, or voice.
- Refactoring nearby code or cleaning unrelated warnings.

## Invariants

- One decision may select no more than one exact body. It never fans out.
- Messenger remains friend-only and receives no technical work result unless
  the existing authoritative candidate policy explicitly permits that class;
  this brief must not expand those permissions.
- Relationship closeness never grants delivery or tool permissions.
- Quiet hours suppress ordinary proactive friendship. Only an explicitly
  authorized override supplied by policy may bypass them.
- Exhausted notification budget defers ordinary proactive output; it never
  silently drops a durable commitment.
- Duplicate event IDs are idempotently discarded.
- Expired non-commitment events are discarded with an auditable reason.
- A durable commitment with no suitable body is stored for later, not lost.
- Device timestamps are descriptive. Core receipt time is authoritative for
  ordering.
- The engine has no I/O, timers, random values, hidden mutable state, model
  calls, Firebase access, or environment-dependent behavior.
- Equal inputs produce equal decisions.
- Generated sentences are not evidence and are not part of this engine.

## Required domain behavior

Implement a small explicit policy, not a speculative general agent framework:

1. Validate the event and reject duplicate or expired non-durable events.
2. Determine whether it represents an ordinary proactive nudge, a direct
   reply, completed work, or a due commitment.
3. Apply quiet-hours policy.
4. Apply the notification budget.
5. Preserve durable commitments when immediate delivery is disallowed.
6. Ask the existing routing contract for zero or one body.
7. Return one decision containing:
   - outcome;
   - reason code;
   - selected body ID, if any;
   - `notBefore`, if deferred;
   - event and correlation identifiers;
   - whether the commitment remains durable.

Do not invent adaptive scoring, machine learning, or personality heuristics in
this brief. Priority must be an explicit bounded input with deterministic
tie-breaking.

## Procedure

1. Inspect the authoritative documents and existing body-routing types.
2. Write the tests first for every pass criterion below.
3. Implement the smallest pure-Dart domain model and engine that passes them.
4. Run `dart format` only on the new files.
5. Run the focused attention test.
6. Run the existing body-event routing test as the regression boundary.
7. Run static analysis against the new files if the repository tooling permits
   a scoped invocation without modifying generated files.
8. Inspect `git diff --check` and `git status --short`.
9. Stop and report. Do not integrate the engine.

## Pass criteria

- Same input evaluated twice yields structurally identical decisions.
- A duplicate event returns `discardDuplicate` and selects no body.
- An expired ordinary nudge returns `discardExpired` and selects no body.
- An ordinary proactive nudge during quiet hours returns `deferUntil` with the
  correct end-of-quiet-hours time.
- An ordinary proactive nudge with an exhausted delivery budget is deferred
  and remains available for later evaluation.
- A due durable commitment is never silently discarded because of quiet hours,
  budget exhaustion, or lack of a connected body.
- An explicitly policy-authorized urgent override can deliver during quiet
  hours; urgency text in an untrusted payload cannot grant this override.
- A direct reply remains origin-bound through the existing routing contract.
- A proactive friend event selects at most one eligible body.
- Completed work selects only a body eligible for work results or remains
  stored for later.
- When no body is eligible, the decision is `storeForLater` with no body ID.
- Cross-body ordering uses `receivedAt`; changing only an untrusted device
  timestamp does not change the order.
- Every outcome contains a stable non-empty reason code and correlation data.
- New domain files contain no imports for Flutter UI, Firebase, HTTP, file I/O,
  provider/model services, or platform APIs.
- Existing `test/kai_body_event_test.dart` continues to pass unchanged.
- No pre-existing tracked or untracked file is deleted, reverted, reformatted,
  or overwritten.

Any missing criterion is `FAIL` or `UNVERIFIED`, not a partial pass.

## Required verification

Run and report the exact outputs of:

```powershell
flutter test test/kai_attention_engine_test.dart
flutter test test/kai_body_event_test.dart
dart analyze lib/services/attention test/kai_attention_engine_test.dart
git diff --check
git status --short
```

If the installed Dart analyzer does not accept multiple scoped paths, run the
narrowest supported equivalent and report the substitution exactly.

No live-runtime claim is allowed from these tests.

## Failure and rollback

- Make no migration and no operational change.
- Keep all work confined to newly added attention files.
- If the design requires changing a dirty Core, coordinator, routing, or Unity
  file, stop with `BLOCKED_BY_INTEGRATION_BOUNDARY` and explain the smallest
  required seam.
- If an existing routing test fails, preserve the output and stop; do not weaken
  the existing invariant or its test.
- Rollback is deletion of only the new attention-domain and test files. Do not
  reset or clean the worktree.

## Stop and report

Stop after the pure engine and focused verification. Report:

- files added;
- public types and decision outcomes introduced;
- the explicit policy order implemented;
- every command run and exact result;
- a criterion-by-criterion `PASS`, `FAIL`, or `UNVERIFIED` table;
- confirmation that prohibited existing files were untouched;
- unresolved assumptions and risks;
- rollback path;
- final verdict;
- the smallest later integration seam into Central Core or the headless
  coordinator.

Do not integrate the engine, begin device transport, modify Unity, build UI,
generate proactive language, or start self-improvement work.

## Reviewer verdict — 2026-08-08

Verdict: **FAIL — focused repair required**.

Independent reruns passed all 21 focused tests, the existing three body-routing
tests, scoped static analysis, and `git diff --check`. The scope boundary was
also preserved. However, the test suite does not cover the submitted report's
most important disclosed risk, and inspection found three contract failures:

1. `KaiQuietHours.endsAfter` always constructs a UTC wall-clock value. If the
   caller supplies Bahrain local time as recommended in the report, a quiet
   window ending at 07:00 is represented as 07:00 UTC, or 10:00 Bahrain time.
2. `_nextBudgetWindow` has the same local/UTC defect and hardcodes a one-hour
   pacing decision rather than accepting it as policy input.
3. `priority` is not bounded and does not participate in deterministic
   attention ordering despite the brief requiring both.

This review failure was closed by
`BRIEF_004_ATTENTION_TIME_AND_PRIORITY_REPAIR.md`. The resulting pure decision
policy is **Tested**. Central Attention remains not integrated and not live.
