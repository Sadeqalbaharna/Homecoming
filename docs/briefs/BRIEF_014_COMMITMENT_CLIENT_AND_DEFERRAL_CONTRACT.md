# Brief 014 — Commitment client and durable deferral contract

Owner: Claude implementation team

Reviewer: Northstar project manager

Status: ACCEPTED — TESTED 2026-08-08

Parent phase: Brief 012 durable scheduled commitment vertical slice

## PM acceptance 2026-08-08

Accepted after independent inspection and verification. Evidence:

- real client/deferral integration: **16/16 PASS**;
- combined new, Brief 013 critical, and ratified tripwire tests:
  **49/49 PASS**;
- shared regression gate: **116/116 PASS**;
- scoped analysis: **No issues found**;
- `git diff --check`: no new whitespace errors.

All 12 criteria are `PASS`. The two test-only scope exceptions are ratified:
`test/kai_desktop_goggles_policy_test.dart` now guards the permanent desktop
policy rather than badge wording, and `test/unity_presence_event_guard_test.dart`
now guards channel-derived surface authority plus return-before-model behavior
rather than the obsolete payload-surface variable name. Production behavior was
inspected before ratification; no source change was smuggled through either
exception.

The client and deferral contract is `TESTED`, not `VERIFIED LIVE`.

## Goal

The real `KaiCoreClient` can safely create, query, defer, and dispatch scheduled
commitments through Central Core, and Core can durably advance a scheduled
commitment's `nextEvaluationAt` without changing its promise or lifecycle.

## Why this is next

Brief 013 made the Core ledger safe and `TESTED`. The coordinator and desktop
must not call private server behavior or reconstruct HTTP payloads themselves.
They need one accepted client contract, and the coordinator needs a durable
deferral operation before any unattended due loop can be wired.

## Entry gate

- Brief 013 is accepted: 23/23 criteria, 28/28 critical tests, 116/116 shared
  regressions, and clean scoped analysis.
- Capture `git status --short` and preserve the dirty shared worktree.
- Reproduce these tests before editing:
  - the three Brief 013 critical suites: **28/28 PASS**;
  - the shared Brief 012 regression gate: **116/116 PASS**.
- Stop if either baseline differs.

## In scope

- Add `KaiCoreClient` operations for:
  - idempotent commitment creation with exact stored fields;
  - listing commitments, including due-only scheduler work;
  - durably advancing `nextEvaluationAt` for one scheduled commitment;
  - atomic dispatch to one exact desktop body and conversation.
- Keep the existing reusable outbound inbox and acknowledgement client methods;
  strengthen their client-level tests where needed for the commitment path.
- Add one Core endpoint:
  `PUT /v1/commitments/{commitmentId}/next-evaluation` with an exact UTC
  `nextEvaluationAt` body field.
- Add focused server/client integration tests using a temporary Core directory
  and the real HTTP client.

## Out of scope

- Coordinator timer/drain wiring, attention-engine invocation, presence wake,
  audit suppression, desktop polling, transcript persistence, `set_reminder`
  switching, Android changes, acceptance scripts, Messenger, AR, VR, or Unity.
- New commitment lifecycle states, cancellation, recurrence, snooze, UI, model
  calls, natural-language date parsing, cloud storage, or authentication.
- General Core persistence refactoring or changing Brief 013 recovery behavior.

## Invariants

- A client method never converts a non-2xx response into apparent success;
  `KaiCoreException` retains the Core status and stable error code.
- Deferral changes only `nextEvaluationAt`. It cannot alter ID, persona, text,
  due instant, wall provenance, audience, creation time, or lifecycle.
- Only a `scheduled` commitment may be deferred. Dispatched or acknowledged
  records fail closed.
- A newly advanced evaluation instant is canonical UTC, strictly after Core
  receipt time, and later than the currently persisted evaluation instant. An
  exact-value idempotent retry remains valid even if time has since passed. A
  caller cannot use deferral to make a promise eligible earlier.
- Repeating the same deferral is idempotent and durably repairs a prior failed
  write before returning success. A different later value advances once.
- Unsupported ledgers remain retained and refused.
- Dispatch remains desktop-only, due-time-gated, body-targeted, conversation-
  bound, and exact-text; the client exposes no parameter that weakens this.
- No endpoint reads host-local time or trusts a caller-supplied `now`.

## Authoritative evidence to inspect

- `docs/briefs/BRIEF_012_DURABLE_SCHEDULED_COMMITMENT_VERTICAL_SLICE.md`
- `docs/briefs/BRIEF_013_CORE_COMMITMENT_INTEGRITY_REPAIR.md`
- `lib/services/core/kai_core_server.dart`
- `lib/services/core/kai_core_client.dart`
- `lib/services/core/kai_scheduled_commitment.dart`
- `test/kai_scheduled_commitment_test.dart`
- `test/kai_scheduled_commitment_reviewer_test.dart`
- `test/kai_core_commitment_reviewer_followup_test.dart`
- `test/kai_core_recovery_regression_test.dart`
- `test/kai_core_outbound_inbox_test.dart`
- `test/kai_core_server_test.dart`

## Permitted files

- Modify only:
  - `lib/services/core/kai_core_server.dart`
  - `lib/services/core/kai_core_client.dart`
  - `test/kai_core_server_test.dart`
  - `test/kai_scheduled_commitment_test.dart`
  - `test/kai_core_outbound_inbox_test.dart`
- Add one narrowly named client/deferral test under `test/` if clearer.
- Do not modify reviewer tests, recovery tests, Briefs 012–014, the Northstar
  source of truth, coordinator, desktop, tools, conversation store, or Android.
- Stop and report `BLOCKED_BY_SCOPE` before touching any other file.

## Required contract

The endpoint is:

```text
PUT /v1/commitments/{commitmentId}/next-evaluation
{ "nextEvaluationAt": "<canonical UTC ISO-8601 instant>" }
```

Canonical means the exact result of Dart
`value.toUtc().toIso8601String()`: `T` separator, fractional seconds as emitted
by Dart, and terminal `Z`; spaces, omitted fractions, and numeric offsets are
rejected. Validate in this order: parse/canonical shape; exact stored-value
idempotency; monotonic regression; then future relative to Core receipt time.

Required outcomes:

- `200`: exact value already durable, or scheduled record advanced durably;
- `400`: missing, malformed, non-UTC/non-canonical, or newly advanced but
  non-future instant;
- `404`: commitment absent;
- `409 commitment_ledger_unsupported`: unsupported ledger;
- `409 commitment_not_scheduled`: dispatched or acknowledged record;
- `409 commitment_evaluation_regression`: requested value is earlier than the
  stored value.

The server response is the complete stored commitment. Core receipt time is
authoritative. Use the existing serialized persistence path and retry-integrity
contract; do not create a second persistence mechanism.

## Procedure

1. Capture baselines and inspect current server/client conventions.
2. Write failing server tests for validation, monotonicity, lifecycle refusal,
   idempotency, persistence failure/retry, and restart durability.
3. Implement the endpoint through the accepted Core state/persistence path.
4. Add client methods and real-client integration coverage for create, list,
   due-only list, defer, dispatch, pending outbound, and acknowledgement.
5. Prove non-2xx responses surface as `KaiCoreException` with exact status and
   stable Core error code.
6. Run all required gates and stop. Do not wire the coordinator or desktop.

## Pass criteria

1. The real client creates one exact commitment and an identical retry returns
   the same record without duplication.
2. Client listing returns all records; due-only listing returns only scheduled
   work whose persisted evaluation instant is due.
3. A valid future canonical UTC deferral updates only `nextEvaluationAt` and
   survives Core restart byte-for-byte as that instant.
4. Missing, malformed, non-canonical, non-UTC, or non-future values return 400
   and leave the record unchanged.
5. An earlier value returns `409 commitment_evaluation_regression`; the exact
   current value is idempotent; a later value advances once.
6. Dispatched and acknowledged commitments return
   `409 commitment_not_scheduled` without mutation.
7. An unsupported future ledger returns `409 commitment_ledger_unsupported`
   and remains byte-preserved.
8. If the deferral write fails, the client receives a 500. An identical retry
   while storage remains broken also fails; after recovery it returns 200 and
   the requested evaluation instant survives restart.
9. Client dispatch produces exactly one existing Core envelope for the exact
   body, desktop surface, conversation, and stored text; an identical retry
   produces no duplicate.
10. Client pending-outbound and acknowledgement operations preserve target-body
    and surface checks and durably close both linked records.
11. Every non-2xx path throws `KaiCoreException` with the exact status and Core
    error code; timeouts and transport failures are not reported as success.
12. Brief 013 critical tests remain **28/28 PASS**, the shared regression gate
    remains **116/116 PASS**, scoped analysis is clean, and `git diff --check`
    reports no new whitespace errors.

Any missing criterion is `FAIL` or `UNVERIFIED`, never partial.

## Required verification

Report exact commands, counts, warnings, and exit codes:

```powershell
flutter test test/kai_core_commitment_client_test.dart
flutter test test/kai_scheduled_commitment_reviewer_test.dart test/kai_core_commitment_reviewer_followup_test.dart test/kai_core_recovery_regression_test.dart
flutter test test/kai_scheduled_commitment_test.dart test/kai_core_outbound_inbox_test.dart test/kai_core_server_test.dart
flutter test test/kai_attention_engine_test.dart test/kai_body_event_test.dart test/kai_headless_coordinator_test.dart test/conversation_store_service_test.dart test/kai_capability_broker_test.dart test/kai_surface_context_test.dart test/kai_desktop_goggles_policy_test.dart
flutter analyze lib/services/core/kai_core_server.dart lib/services/core/kai_core_client.dart test/kai_core_commitment_client_test.dart test/kai_scheduled_commitment_test.dart test/kai_core_outbound_inbox_test.dart test/kai_core_server_test.dart
git diff --check
git status --short
```

If a different focused-test filename is used, substitute it consistently and
report the reason.

## Failure and rollback

- Tests use unique system-temporary Core directories only.
- Never read or mutate the user's live `%LOCALAPPDATA%\Homecoming\KaiCore` state.
- A failed write returns failure and retains Brief 013 recovery obligations.
- Roll back only the Brief 014 delta; preserve all accepted Brief 012/013 work
  and unrelated dirty-worktree changes.

## Stop and report

Report files and behavior changed, every command and exact count, each criterion
as PASS/FAIL/UNVERIFIED, unresolved risks, rollback state, and the smallest next
Brief 012 integration seam.

Do not start coordinator, desktop, transcript, tool, Android, Unity, cloud, or
self-improvement work.
