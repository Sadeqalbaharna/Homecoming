# Brief 013 — Core commitment integrity repair

Owner: Claude implementation team

Reviewer: Northstar project manager

Status: ACCEPTED — TESTED 2026-08-08

## Reviewer follow-up 2026-08-08

Claude's first repair moved the original immutable reviewer suite from 0/10 to
10/10 PASS and preserved the broader green suite. Independent source and
failure-path review then found six remaining defects. The immutable follow-up
suite `test/kai_core_commitment_reviewer_followup_test.dart` reproduced them as
**1/7 PASS, 6/7 FAIL**:

1. `test/kai_core_recovery_regression_test.dart` itself contains a literal NUL
   byte and is treated as binary. Corrupt fixtures must be generated from byte
   arrays or escaped data at runtime, not embedded in Dart source.
2. Redispatch with the same outbound/body but a changed `conversationId`
   returns 200 instead of conflict.
3. A corrupt backup is silently deleted when the primary is readable; it must
   be quarantined before normal rotation.
4. Quarantine stops at suffix 999 and overwrites/collides with existing
   evidence instead of selecting `.corrupt.1000` and beyond.
5. Non-canonical/normalised wall clocks such as a space separator, missing
   seconds, fractional seconds, and February 30 are accepted.
6. One transient write failure poisons `_writeTail`; all later saves fail even
   after the filesystem problem clears.

The seventh follow-up criterion—future ledger survival through an unrelated
Core write—already passes. This brief remains open; no Brief 012 integration is
authorized.

### Final acceptance addendum 2026-08-08

Claude's follow-up repair moved the frozen suites to 10/10 original reviewer,
7/7 follow-up reviewer, and 7/7 recovery PASS. Its completion report explicitly
disclosed that a failed save leaves the transition applied in memory but absent
from disk. Independent review classified that as a violation of the existing
"promise is never silently lost" invariant: the caller receives 500 and retries
the identical operation, but the in-memory idempotency path returns 200 without
retrying persistence. A restart can then lose creation, revert dispatch, or
reopen an acknowledged promise.

Three final reviewer cases are appended to
`test/kai_core_commitment_reviewer_followup_test.dart`. They cover identical
retry after failed persistence for creation, dispatch, and acknowledgement.
This is a critical correction to a disclosed failure mode, not a general scope
reopening. No further acceptance expansion is authorized unless new evidence
contradicts a Northstar invariant.

### PM acceptance 2026-08-08

Accepted after independent inspection and verification. The final code uses
monotonic requested/flushed snapshot sequence counters and repairs durability
only on the three identical-retry success paths. Independent results:

- original immutable reviewer: **10/10 PASS**;
- follow-up immutable reviewer: **10/10 PASS**;
- recovery regression: **8/8 PASS**;
- shared regression gate: **116/116 PASS**;
- scoped analysis: **No issues found**;
- `git diff --check`: clean, with only pre-existing line-ending advisories.

All 23 criteria are `PASS`. The Core commitment ledger is promoted to
**TESTED**, not `VERIFIED LIVE`; Brief 012 owns the remaining client,
coordinator, desktop, transcript, and restart integration evidence.

## Goal

Make the Brief 012 Core commitment ledger safe enough to wire into production:
the last readable Core state cannot be silently ignored or destroyed, and a
commitment cannot be dispatched early, captured by an unrelated outbound,
routed to a non-desktop surface, expired while still owed, or mutated through
false Bahrain provenance.

## Why this is next

Brief 012 is partial. Its accepted 116-test suite proves useful domain and Core
behavior, but independent review reproduced ten uncovered failures. The most
serious is the same crash window repaired earlier for `attention.json`: after
normal rotation leaves only `state.json.bak`, Core startup returns an empty
state without reading that readable backup. A later save can then delete the
last surviving commitments. Wiring the coordinator or desktop onto that store
would turn a known data-loss path into a live promise system.

Data integrity and dispatch authority precede integration. Brief 012 remains
open and blocked on this repair.

## Entry gate

- Preserve the entire dirty shared worktree and Claude's current Brief 012
  changes. Revert nothing.
- Read Brief 012, its partial report, and this brief.
- Reproduce both baselines before editing:
  - the PM regression command: **116/116 PASS**;
  - `flutter test test/kai_scheduled_commitment_reviewer_test.dart`:
    **0/10 PASS, 10/10 FAIL**.
- Treat the reviewer test as immutable acceptance evidence. Stop and report if
  the failure set differs before implementation.

## In scope

- Repair Core state loading and first-save recovery for:
  - primary absent plus readable backup;
  - corrupt primary plus readable backup;
  - preservation/quarantine ordering so a readable last copy is never replaced
    by corrupt bytes before a new primary is durably installed.
- Retain corrupt files as diagnostic evidence under collision-safe quarantine
  names. Do not silently delete them.
- Reject commitment dispatch before its persisted `nextEvaluationAt`.
- Return only `scheduled` due commitments from `?due=true`; `dispatched`
  commitments wait for acknowledgement and are not scheduler work.
- For this v1 work-reminder path, reject any dispatch surface other than
  `desktop`.
- Detect an existing outbound-ID collision before mutating the commitment.
  Idempotency is valid only when outbound ID, commitment ID, kind, target body,
  surface, conversation, and exact text describe the same envelope.
- Keep commitment-linked pending outbounds retrievable beyond the ordinary
  24-hour relevance expiry. Ordinary non-commitment outbounds retain their
  existing expiry behavior.
- Validate Bahrain provenance at Core admission:
  `dueWallOffsetMinutes` is required and exactly 180; the exact wall-clock value
  must convert to the supplied UTC `dueAt` using the shared pure domain helper.
- Expand same-ID/same-intent comparison to include persona, exact text, UTC due
  instant, wall clock, offset, and trusted audience.
- Remove literal NUL bytes from the Dart source. Use a textual escaped delimiter
  or an unambiguous encoded/length-prefixed digest input.
- Advertise scheduled commitments in Core health capabilities.
- Add or strengthen focused tests without weakening existing assertions.

## Out of scope

- Core client commitment APIs, coordinator due loop, `nextEvaluationAt` update
  endpoint, presence wake, duplicate-journal suppression, desktop tool wiring,
  desktop outbound polling, transcript persistence, Android behavior, or the
  restart acceptance script. Those resume under Brief 012 only after this
  repair is accepted.
- Messenger, mobile transport, AR, VR, Unity, cloud durability, recurring
  reminders, snooze/cancel/edit UI, `KaiNoticedService`, or self-improvement.
- Changing the accepted attention engine or audience contract.
- Redesigning all Core persistence or introducing a database. A narrowly
  extracted Core-state store is allowed only if required to test failure-safe
  recovery cleanly.

## Invariants

- A promise is never silently lost. Absence, corruption, unsupported schema,
  and first-run emptiness are distinct states.
- A readable backup remains untouched until a new primary has been flushed and
  installed successfully.
- Corrupt primary/backup bytes are evidence. They move to collision-safe
  quarantine; they are never mistaken for a valid empty Core.
- Unsupported future commitment ledgers remain byte-preserved and refused.
- Dispatch is a trusted transition after due-time policy, never a caller hint.
- A commitment stays `scheduled` until a valid, conflict-free atomic dispatch.
- A dispatched commitment stays owed until its exact target acknowledges it.
  Ordinary outbound expiry cannot silently strand it.
- Work-reminder content cannot be dispatched to Messenger, AR, or VR in v1.
- The exact stored reminder text is immutable and is never regenerated by a
  model.
- Existing presence, handoff, task, memory-lane, and ordinary outbound behavior
  cannot regress.
- No test or recovery path touches the user's live Core directory.

## Authoritative evidence to inspect

- `lib/services/core/kai_core_server.dart`
- `lib/services/core/kai_scheduled_commitment.dart`
- `test/kai_scheduled_commitment_reviewer_test.dart`
- `test/kai_scheduled_commitment_test.dart`
- `test/kai_core_outbound_inbox_test.dart`
- `test/kai_core_server_test.dart`
- `test/kai_core_recovery_regression_test.dart`
- `test/kai_core_commitment_reviewer_followup_test.dart`
- `docs/briefs/BRIEF_012_DURABLE_SCHEDULED_COMMITMENT_VERTICAL_SLICE.md`
- The Brief 012 partial report supplied by the reviewer.

## Permitted files

- Modify only:
  - `lib/services/core/kai_core_server.dart`
  - `lib/services/core/kai_scheduled_commitment.dart`
  - `test/kai_scheduled_commitment_test.dart`
  - `test/kai_core_outbound_inbox_test.dart`
  - `test/kai_core_server_test.dart`
  - `test/kai_core_recovery_regression_test.dart`
- Add one narrowly scoped Core-state persistence file and its test only if an
  injectable failure seam is necessary; report why before using it.
- Do not modify `test/kai_scheduled_commitment_reviewer_test.dart`, this brief,
  `test/kai_core_commitment_reviewer_followup_test.dart`, Brief 012, or the
  Northstar source of truth.
- Stop and report `BLOCKED_BY_SCOPE` before touching any other file.

## Procedure

1. Capture status and reproduce the 116-pass baseline and ten reviewer fails.
2. Repair the literal-NUL and provenance-validation defects first.
3. Repair dispatch admission, collision handling, due filtering, and durable
   commitment outbound behavior.
4. Repair Core state recovery and first-save ordering. Keep readable evidence
   until the new primary is installed.
5. Add focused regression tests for each repaired path, including ordinary
   outbound expiry remaining unchanged.
6. Run all required verification and inspect the actual filesystem artifacts
   produced by recovery tests.
7. Stop and report. Do not resume Brief 012 integration in the same turn.

## Pass criteria

1. `test/kai_scheduled_commitment_reviewer_test.dart` moves from exactly ten
   failures to **10/10 PASS unchanged**.
2. Backup-only startup restores every commitment and unrelated Core collection;
   the first successful save installs a readable primary without deleting or
   replacing the readable backup prematurely.
3. Corrupt-primary plus readable-backup startup restores from backup; the first
   save produces a readable primary, retains the readable backup, and preserves
   the exact corrupt bytes under a collision-safe quarantine path.
4. Dispatch before `nextEvaluationAt` returns conflict, creates no outbound,
   and leaves the commitment scheduled.
5. `?due=true` returns only scheduled records whose `nextEvaluationAt` is due;
   dispatched and acknowledged records are absent.
6. A v1 work commitment cannot dispatch to Messenger, AR, VR, mobile, or an
   arbitrary surface.
7. An unrelated pre-existing outbound ID returns conflict and leaves both the
   prior outbound and commitment unchanged.
8. Idempotent redispatch succeeds only for an identical envelope, including
   surface and conversation identity.
9. An unacknowledged commitment outbound remains pending and retrievable after
   48 hours; an ordinary outbound still expires under the existing policy.
10. Missing/wrong Bahrain offset and wall-clock/UTC mismatch fail admission
    without writing. Same ID with changed persona, wall provenance, offset,
    text, due instant, or audience conflicts.
11. `kai_scheduled_commitment.dart` contains zero literal NUL bytes and remains
    a normal text source; deterministic IDs remain stable across equivalent
    retries and differ across distinct intents.
12. Unsupported future commitment ledgers remain retained/refused through
    recovery and unrelated Core writes.
13. Core health advertises the scheduled-commitment capability.
14. All 116 independently verified pre-repair regression tests remain green.
15. Scoped analysis and `git diff --check` are clean; no unrelated file changes
    are introduced.
16. `test/kai_core_commitment_reviewer_followup_test.dart` moves from exactly
    **1/7 PASS, 6/7 FAIL** to **7/7 PASS unchanged**.
17. Every Dart source added or modified by Brief 013 contains zero literal NUL
    bytes. Binary corruption fixtures are constructed at runtime.
18. Idempotent redispatch compares conversation identity as well as outbound,
    target body, surface, kind, commitment, and exact text.
19. A readable primary plus corrupt backup quarantines the exact corrupt backup
    bytes before installing the old primary as the new readable backup.
20. Quarantine suffix selection is unbounded and collision-safe; no artificial
    cap or fallback to an existing destination is allowed.
21. Bahrain wall provenance accepts only the exact canonical
    `yyyy-MM-ddTHH:mm:ss` form produced by `wallClockLabel`, and rejects
    constructor-normalised invalid calendar dates.
22. Persistence separates each caller-visible save result from a healthy
    internal serialization tail. A failed write remains observable, preserves
    recovery obligations and evidence, and a later save can succeed after the
    transient fault clears.
23. When commitment creation, commitment dispatch, or linked outbound
    acknowledgement returns 500 because persistence failed, an identical retry
    must durably persist the already-applied in-memory transition before
    returning success. After restart, creation remains present, dispatch retains
    both the ledger transition and exact outbound envelope, and acknowledgement
    remains closed in both records.

Any missing criterion is `FAIL` or `UNVERIFIED`, never a partial pass.

## Required verification

Report commands, exact counts, warnings, and exit codes:

```powershell
flutter test test/kai_scheduled_commitment_reviewer_test.dart
flutter test test/kai_core_commitment_reviewer_followup_test.dart
flutter test test/kai_core_recovery_regression_test.dart
flutter test test/kai_scheduled_commitment_test.dart
flutter test test/kai_core_outbound_inbox_test.dart
flutter test test/kai_core_server_test.dart
flutter test test/kai_attention_engine_test.dart test/kai_body_event_test.dart
flutter test test/kai_headless_coordinator_test.dart
flutter test test/conversation_store_service_test.dart
flutter test test/kai_capability_broker_test.dart test/kai_surface_context_test.dart
flutter test test/kai_desktop_goggles_policy_test.dart
flutter analyze lib/services/core/kai_core_server.dart lib/services/core/kai_scheduled_commitment.dart test/kai_scheduled_commitment_reviewer_test.dart test/kai_scheduled_commitment_test.dart test/kai_core_outbound_inbox_test.dart test/kai_core_server_test.dart
git diff --check
git status --short
```

## Failure and rollback

- All tests use unique system-temporary directories.
- Never read, mutate, migrate, or delete the user's real
  `%LOCALAPPDATA%\Homecoming\KaiCore\state.json*` files.
- A failed recovery retains primary, backup, temp, and quarantine evidence.
- Roll back only the Brief 013 delta. Preserve Claude's pre-repair Brief 012
  files and all reviewer tests.

## Stop and report

Report:

- exact recovery-state model and write ordering;
- quarantine naming and collision behavior;
- dispatch/provenance/expiry rules;
- files changed;
- every command and exact result;
- criterion-by-criterion PASS, FAIL, or UNVERIFIED;
- unresolved risks and rollback state;
- verdict and the exact recommendation for resuming Brief 012.

Do not start the coordinator loop, Core client API, tool switch, desktop inbox,
transcript persistence, acceptance script, cloud/device transport, Unity, or
self-improvement.
