# Brief 012 — Durable scheduled commitment vertical slice

Owner: Claude implementation team

Reviewer: Northstar project manager

Status: IN PROGRESS — RESUMED AFTER BRIEF 013 ACCEPTANCE

## PM resumption checkpoint 2026-08-08

Brief 013 is accepted at `TESTED`: 23/23 criteria, 28/28 critical reviewer and
recovery tests, 116/116 shared regressions, and clean scoped analysis. The Core
ledger, recovery behavior, dispatch authority, durable outbound envelope, and
retry integrity are now safe integration dependencies.

Brief 012 resumes in bounded dependency order. Brief 014 is accepted: Core
client commitment operations and the durable `nextEvaluationAt` deferral
endpoint are `TESTED`. Brief 015 is also accepted: exact-body desktop polling,
deterministic transcript persistence, watcher-race-safe visible acceptance, and
acknowledgement ordering are `TESTED` and `WIRED`. Brief 016 is accepted: the
coordinator due-commitment scheduler and lifecycle are `TESTED` and `WIRED`
under the Option C retry contract. Brief 017 now owns desktop `set_reminder`.
Attended live restart acceptance remains paused until Brief 017 is accepted.

### No-body retry contract correction 2026-08-08

Brief 016 proved that persisting a future no-body retry contradicts immediate
eligible-presence delivery: Core correctly forbids both dispatch before
`nextEvaluationAt` and regression of that instant. The accepted resolution is
to persist only engine-authored `deferUntil` instants such as quiet hours. A
no-body `storeForLater` leaves the already-due Core record unchanged; the
coordinator's positive periodic interval is the bounded retry, and eligible
desktop presence wakes that ordinary due drain immediately. Core's dispatch and
monotonic-deferral protections remain unchanged.

## PM amendment 2026-08-08

Claude correctly stopped after the explicit-audience contract made four legacy
`dueCommitment` constructions fail. The original permitted-files wording
allowed inspecting `test/kai_attention_engine_test.dart` but not modifying it,
while criterion 13 required that test to pass unchanged. Those requirements
were contradictory because a formerly valid construction is intentionally
invalid under this brief.

The reviewer reproduced exactly four failures at lines 119, 203, 290, and 381;
all fail at construction because audience is absent. Scope is therefore amended
to allow the narrow test migration below. This does not weaken an assertion or
the audience invariant.

## Goal

A reminder created from Kai's desktop workbench is owned by Central Core,
survives coordinator and desktop restarts, becomes due on Bahrain time, and is
presented once in the desktop conversation before Central Core records it as
acknowledged.

## Why this is next

Central Attention can already decide how to route a `dueCommitment`, and its
ordinary proactive queue has passed a live crash/restart test. Nothing in the
running product creates, schedules, dispatches, or acknowledges a central
commitment. The existing `set_reminder` tool is Android-only and bypasses
Central Kai entirely. This is the smallest honest vertical slice that turns
"Kai remembers what he promised" from a policy type into observable behavior.

## Entry gate

- Briefs 003, 004, 008, 009, and 010 are accepted at their documented proof
  levels.
- Read `docs/KAI_ATTENTION_RESTART_ACCEPTANCE_2026-08-08.md` and preserve its
  archived evidence.
- Capture `git status --short`; this is a dirty shared worktree. Do not revert,
  reformat, delete, or absorb unrelated changes.
- Run the existing focused attention and Core tests before changing code. Stop
  and report if they are not green.

PM baseline evidence, captured before Brief 012 implementation on 2026-08-08:

```powershell
flutter test test/kai_core_server_test.dart test/kai_attention_engine_test.dart test/kai_body_event_test.dart test/kai_headless_coordinator_test.dart test/conversation_store_service_test.dart
```

Result: **61/61 PASS**, exit code 0. Claude must reproduce or improve this
baseline; any regression is a Brief 012 failure.

## In scope

- Add a versioned scheduled-commitment ledger to Kai Core's existing durable
  state. A record must have a stable ID, exact reminder text, UTC due instant,
  Bahrain wall-clock provenance, creation time, lifecycle status, durable
  `nextEvaluationAt`, and linked outbound ID when dispatched.
- Add idempotent Core client/server operations to create a commitment, list due
  commitments, atomically dispatch one to one exact body, and observe its final
  acknowledgement.
- On Windows desktop only, make `set_reminder` create the Central Core record
  instead of calling the missing Android plugin. Keep the existing native
  Android behavior unchanged.
- Parse the tool's year/month/day/hour/minute as Bahrain wall time (UTC+03:00),
  convert once to UTC, and reject invalid or past instants. Do not infer the
  host machine timezone.
- Have the headless coordinator evaluate due commitments through the accepted
  `KaiAttentionEngine` as durable `dueCommitment` events.
- Persist the engine's `deferUntil` result as `nextEvaluationAt`. A no-body
  result leaves the already-due Core instant unchanged; the positive
  coordinator interval bounds timer retry and eligible presence wakes an
  immediate due drain. Do not emit the same decision journal record on every
  coordinator timer tick.
- Route this first slice only to a connected work-eligible desktop body. Do not
  route reminder content to Messenger, AR, or VR in this brief.
- Add an explicit trusted attention audience/route class to the event contract.
  A due commitment must declare `friend` or `work`; it may not inherit
  `proactiveFriend` accidentally. Brief 012 reminders declare `work`. Keep
  direct replies origin-bound, ordinary nudges friend-routed, and completed
  work work-routed.
- Add a reusable Core outbound inbox for a body. Wire the desktop body to poll
  its exact inbox, persist the reminder into the `in_person` transcript under a
  deterministic outbound ID, render it, and acknowledge only after that
  idempotent persistence succeeds.
- Make Core acknowledgement transition the linked commitment to acknowledged
  in the same durable Core-state write.
- Add focused tests and a model-free restart acceptance script. The script may
  use only temporary or explicitly backed-up local state and must restore the
  user's original state in `finally`.

## Out of scope

- Messenger, phone, AR, VR, Unity, cloud scheduling, push notifications,
  calendar integration, alarms, timers, recurring reminders, snooze, editing,
  cancellation UI, urgency override, natural-language date parsing, or a
  reminder-management screen.
- Feeding `KaiNoticedService` promises into this scheduler. Identity promises
  and user-requested timed reminders remain distinct until a later contract is
  approved.
- Model-generated reminder wording. The exact stored text is delivered; no LLM
  call may sit between due detection and presentation.
- Generalizing the proactive queue or changing its accepted persistence schema.
- Claiming cross-device durability or exactly-once delivery beyond the desktop
  body proven here.
- Refactoring unrelated Core state, transcript history, tools, or UI.

## Invariants

- A promise is never silently lost. A due commitment remains scheduled or
  dispatched until its exact target body acknowledges it.
- One due commitment selects at most one body. No surface fan-out is allowed.
- Messenger remains friend-only and receives no scheduled workbench reminder
  from this phase.
- Model payloads cannot grant urgency, change routing eligibility, forge an
  acknowledgement, choose an authoritative clock, or mark work complete.
- Audience is trusted typed policy, not a string read from reminder text, tool
  arguments, or event payload. A due commitment without an explicit audience
  fails construction/admission rather than defaulting to a friend surface.
- Core receipt time orders records; the due instant is stored in UTC; Bahrain
  wall time is explicit provenance rather than host-local time.
- Creating the same commitment ID with the same intent is idempotent. Reusing
  it with different text or time is a conflict.
- The desktop tool derives its stable commitment ID from persona, normalized
  exact text, and the converted UTC due instant using a deterministic SHA-256
  digest. A retry of the same tool intent therefore reaches the same Core
  record; random/time-only IDs are prohibited for this mutating operation.
- Dispatch and acknowledgement are idempotent. A coordinator retry cannot mint
  a second outbound, and a body retry cannot create a second transcript turn.
- Scheduling has its own single-drain guard. It must not borrow the ordinary
  proactive generation busy flag: due reminders contain no model call and must
  not be blocked behind Kai composing an unrelated friend message.
- Transcript persistence happens before acknowledgement. If persistence or
  rendering acceptance fails, the Core outbound remains pending.
- The deterministic transcript key contains no slash, dot, dollar, hash, or
  bracket characters forbidden by Firebase paths.
- Core state corruption behavior, backups, and unrelated state collections are
  not weakened.
- Android `set_reminder` behavior remains unchanged.
- The body ID used in the routing decision, Core outbound target, desktop inbox
  query, and acknowledgement is byte-for-byte identical. Desktop must use the
  authoritative `KaiGlobalPresenceService` body ID already visible to the
  coordinator; it must not invent an ID from hostname, PID, session, or the
  separate loopback heartbeat device ID.

## Authoritative evidence to inspect

- `lib/services/core/kai_core_server.dart`
- `lib/services/core/kai_core_client.dart`
- `lib/services/core/kai_headless_coordinator.dart`
- `lib/services/core/kai_global_presence_service.dart`
- `lib/services/core/kai_body_event.dart`
- `lib/services/core/tool_executor_service.dart`
- `lib/services/core/conversation_store_service.dart`
- `lib/screens/kai_desktop_shell.dart`
- `lib/services/attention/kai_attention_event.dart`
- `lib/services/attention/kai_attention_engine.dart`
- `test/kai_core_server_test.dart`
- `test/kai_attention_engine_test.dart`
- `test/kai_headless_coordinator_test.dart`
- `test/conversation_store_service_test.dart`
- `docs/NORTHSTAR_SOURCE_OF_TRUTH.md`

## Permitted files

- Modify only the authoritative production files listed above when the change
  is necessary for this vertical slice.
- Modify `test/kai_attention_engine_test.dart` only to:
  - let its `_event` helper accept and forward an explicit audience;
  - add `audience: KaiAttentionAudience.friend` to the four pre-existing generic
    commitment constructions at the PM-reproduced failure sites; and
  - add focused contract coverage proving missing due-commitment audience is
    rejected, work commitments select only work-eligible bodies, friend
    commitments retain friend routing, and origin-bound direct replies reject
    any supplied audience.
  Do not remove, rename, skip, loosen, or rewrite any pre-existing assertion.
- Add narrowly named commitment/outbound-inbox domain files under
  `lib/services/core/` if separation makes the contract clearer.
- Add narrowly named tests under `test/` and one acceptance script under
  `scripts/test/`.
- Do not edit this brief or `docs/NORTHSTAR_SOURCE_OF_TRUTH.md`.
- Stop and report `BLOCKED_BY_SCOPE` before touching any other existing file.

## Required contract

Use this lifecycle, or report a concrete contradiction before substituting it:

```text
scheduled -> dispatched -> acknowledged
```

- `scheduled`: durable Core record; not yet assigned to a body.
- `dispatched`: one deterministic outbound exists for one exact eligible body;
  the commitment is still owed.
- `acknowledged`: the target body durably persisted/accepted the transcript
  turn and acknowledged the outbound; the commitment is complete.

Do not introduce a terminal `failed`, `expired`, or `delivered` state in this
brief. A transient failure remains owed and retryable. If a future product
policy needs abandonment, it requires a separate explicit decision.

The attention event contract must also encode audience explicitly:

```text
proactiveNudge -> friend
completedWork  -> work
directReply    -> origin-bound (audience prohibited)
dueCommitment  -> explicit friend | work (required)
```

Brief 012 constructs only `dueCommitment -> work`. A missing or incompatible
audience is a validation failure, not a friend-routing default. A direct reply
with any audience is also invalid: its authoritative origin is the only route.

## Procedure

1. Capture baseline status and run the pre-change suite.
2. Write failing pure/Core tests for record validation, Bahrain conversion,
   idempotent creation, conflict, due ordering, atomic dispatch, target-scoped
   acknowledgement, restart restore, and transcript idempotency.
3. Add the Core commitment contract and client API. Keep all state transitions
   inside Core's serialized durable mutation path. Store the collection with
   an explicit supported commitment-ledger version; a pre-Brief-012 Core state
   with no ledger migrates to an empty version-1 ledger without changing any
   existing presence, handoff, outbound, or task record. An unsupported future
   ledger version is retained and rejected, never interpreted as empty.
4. Add the coordinator due loop. Construct `KaiAttentionEvent` with a stable
   event ID derived from the commitment ID, `kind: dueCommitment`, no expiry,
   durable semantics, and an explicit trusted `work` audience. Extend the
   attention contract so this maps to the existing work-eligible routing path;
   never inspect reminder text to decide the audience. Persist quiet-hour
   deferrals, leave no-body promises due for bounded loop retry, wake the drain
   on eligible presence changes, and suppress repeated identical audit entries.
5. Add the reusable outbound inbox and desktop acceptance callback. Persist by
   deterministic outbound key before acknowledging.
6. Switch desktop `set_reminder` to Central Core while preserving native
   Android behavior and tool filtering for other Android-only actions.
7. Run focused and shared-infrastructure regression tests, analysis, formatting
   checks, and the model-free restart script.
8. Stop and report. Do not perform the attended real-state acceptance or begin
   another Northstar phase.

## Pass criteria

1. A valid future Bahrain wall time created through the desktop reminder path
   produces one supported Core commitment with the exact text and correct UTC
   instant.
2. Invalid calendar values, past instants, empty/oversized text, missing IDs,
   and unsupported fields fail closed without creating a record.
3. The same ID plus same intent returns the existing record; the same ID plus
   different intent returns a conflict.
   The desktop tool's deterministic digest produces that same ID across an
   execution retry.
4. Restarting Core and the coordinator before due time restores the commitment
   as scheduled with the same ID, text, due instant, and creation time.
5. Before the due instant no attention decision or outbound is produced.
6. Once due, the coordinator evaluates the record as a durable
   `dueCommitment`; quiet hours defer it and do not mutate it into a terminal
   state. The exact engine `notBefore` value is persisted and no reevaluation
   occurs before it.
   Contract tests also prove that a missing due audience and any direct-reply
   audience fail construction rather than being silently ignored.
7. With no eligible desktop body, it remains scheduled. Messenger-only,
   AR-only, or VR-only presence cannot receive it. Timer retries are bounded,
   while a newly eligible desktop presence triggers an immediate reevaluation.
8. With one or more bodies online, exactly one work-eligible desktop body is
   selected and one deterministic outbound is atomically linked. A retry or
   restart produces no second outbound.
   The chosen body ID is the same ID the desktop inbox polls and acknowledges.
9. Desktop persists the exact reminder once under the deterministic outbound
   key, presents it in the `in_person` transcript, and only then acknowledges.
10. A crash/retry after transcript persistence but before acknowledgement
    rewrites the same record rather than adding another visible turn, then
    safely acknowledges.
11. A wrong body or wrong surface cannot acknowledge the outbound or the linked
    commitment.
12. After valid acknowledgement, both outbound and commitment are terminal and
    another coordinator evaluation produces no work.
13. Existing Android `set_reminder`, proactive attention, Core handoff/outbound,
    conversation history, desktop goggles-on, and Messenger isolation
    behavioral assertions pass. The only permitted migration inside an existing
    test is the four explicit `audience: KaiAttentionAudience.friend`
    construction arguments described above; every prior assertion and expected
    outcome remains unchanged.
14. The acceptance script proves pre-due restart, due-without-body retention,
    one-body dispatch, desktop acknowledgement, and post-ack restart without a
    second transcript record. It uses a temporary Core directory and an
    injectable/fake transcript sink; it does not write the user's Firebase
    transcript. Any later attended real-transcript run is a separate gate.
15. Operations logs contain IDs, lifecycle state, route reason, body/surface,
    and timing but never reminder text. An unchanged deferred/no-body decision
    does not create one duplicate record per timer tick.

Any missing criterion is `FAIL` or `UNVERIFIED`, never a partial pass.

## Required verification

Report exact commands, counts, warnings, and exit codes. At minimum:

```powershell
flutter test test/kai_scheduled_commitment_test.dart
flutter test test/kai_core_outbound_inbox_test.dart
flutter test test/kai_core_server_test.dart
flutter test test/kai_attention_engine_test.dart test/kai_body_event_test.dart
flutter test test/kai_headless_coordinator_test.dart
flutter test test/conversation_store_service_test.dart
flutter test test/kai_desktop_goggles_policy_test.dart
flutter test test/kai_capability_broker_test.dart test/kai_surface_context_test.dart
flutter analyze <every production and test file changed by Brief 012>
powershell -ExecutionPolicy Bypass -File scripts/test/kai_commitment_restart_acceptance.ps1
git diff --check
git status --short
```

If an exact pre-existing test filename differs, identify the equivalent test;
do not silently omit the policy regression.

## Failure and rollback

- Tests and scripted acceptance use unique temporary Core directories or an
  explicit backup directory. Never point failure-path tests at the user's live
  Core state.
- The acceptance script must restore the exact original state and processes in
  `finally`, including on assertion failure or interruption.
- Preserve corrupt or conflicting records as evidence; do not auto-delete them.
- If the new Core schema cannot load the existing state without loss, stop and
  report `MIGRATION_BLOCKED`; do not start empty.
- Roll back only the Brief 012 delta. Existing attention state, conversation
  history, and Android reminders must remain recoverable.

## Stop and report

Report:

- files and behavior changed;
- the exact Core schema and lifecycle transitions;
- Bahrain conversion rule;
- how atomic dispatch and transcript idempotency work;
- commands/tests/scripts and exact results;
- criterion-by-criterion PASS, FAIL, or UNVERIFIED;
- runtime evidence, with paths to retained artifacts;
- unresolved risks and rollback state;
- the smallest attended acceptance step after review.

Do not start phone/cloud transport, Messenger delivery, AR/VR/Unity, recurring
commitments, `KaiNoticedService` integration, or self-improvement work.
