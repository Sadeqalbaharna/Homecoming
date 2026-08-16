# Brief 018 — Attended desktop reminder restart acceptance

Owner: Northstar project manager with Sadeq as attended operator

Reviewer: Northstar project manager

Status: BLOCKED — AWAITING ATTENDED TRAY QUIT

Parent phase: Brief 012 durable scheduled commitment vertical slice

## Goal

Prove on the real Windows Homecoming runtime that a reminder requested through
Kai's desktop workbench is stored by Central Core, survives a complete
coordinator/Core restart before it is due, reaches one exact desktop body, is
persisted and rendered exactly once, and is acknowledged only afterward.

## Why this is next

Briefs 013–017 prove every production seam deterministically, but the complete
path is only `WIRED / TESTED`. This is the highest-information remaining gate:
it can reveal stale binaries, process-ownership mistakes, Firebase/body-ID
races, restart loss, transcript failure, and duplicate presentation that unit
tests cannot establish about the running product.

## Current preflight evidence

Captured 2026-08-08 without mutating live state:

- Two `Kai.exe` processes are running from
  `build/windows/x64/runner/Release/Kai.exe`.
- Core health reports `startedAt: 2026-08-07T15:32:30.045882Z` and advertises
  only `presence`, `handoffs`, `runtime_tasks`, and `outbound_inbox`.
- `GET /v1/commitments` returns 404.
- The running `Kai.exe` was built at `2026-08-07T19:50:24Z`; the accepted
  reminder source is newer (`2026-08-08T16:49:59Z`).
- Therefore the current runtime is stale and cannot be used as evidence for
  Brief 017. A successful unit suite does not alter that fact.

Fresh-build update:

- `flutter build windows --release` completed successfully in 100.1 seconds
  without stopping the live Kai processes.
- The native `Kai.exe` launcher is unchanged because no native runner source
  changed. The authoritative rebuilt Dart payload is
  `build/windows/x64/runner/Release/data/app.so`, written
  `2026-08-08T16:59:38.6938163Z`, length 12,944,272 bytes, SHA-256
  `C69667AD9DE71FA177F333960F0D9BC23C79F16B72440781D598131F8F44857C`.
- The running process still serves the old loaded payload, as proven by its
  unchanged health capability list. No live process or Core state was touched.
- The build blocker is closed. The next action is the attended tray quit in
  procedure step 2.

## Entry gate

- Brief 017 is `ACCEPTED / TESTED / WIRED` with all 14 criteria passing.
- Build a fresh Windows Release from the accepted dirty worktree without
  deleting, reverting, staging, or committing unrelated work.
- Do not begin the attended run until `/health` advertises
  `scheduled_commitments` and `GET /v1/commitments` is supported.
- Before the first deliberate quit, record Core state-file path, length,
  modification time, and SHA-256. Keep any raw backup only under the local
  Homecoming data directory; never copy private Core state into the repository.
- Sadeq must be present for the tray-level **Quit Kai completely** action and
  for observing the visible reminder. No forced process termination is implied
  by this brief.

## In scope

- Rebuild the real Windows Release and verify its source/binary recency.
- Use the real hidden coordinator, its embedded/sidecar Core on port 8790, the
  real desktop workbench, global body registry, due loop, exact-body inbox,
  Firebase conversation store, and desktop transcript.
- Create one uniquely identifiable, harmless test reminder through ordinary
  desktop chat using Bahrain wall time at least eight minutes in the future and
  before quiet hours.
- Restart Central Kai after durable creation but before due time.
- Observe delivery, transcript restoration, acknowledgement, and duplicate
  counts from independent runtime evidence.
- Add a content-free evidence collector under `scripts/test/` only if needed;
  it may read health, commitments, and operations journals but may not create,
  dispatch, acknowledge, edit, delete, or sanitize live records.
- Save the final sanitized evidence summary under `docs/`; do not include API
  keys, auth tokens, unrelated chat, or raw Core state.

## Out of scope

- Production Dart behavior changes, schema changes, test weakening, manual Core
  record creation, direct dispatch/ack calls, simulated bodies, Firebase
  console edits, Messenger, Android, AR, VR, Unity, recurring reminders,
  cancel/snooze, cloud hosting, or self-improvement.
- Force-killing Kai, deleting Core state, clearing transcript history, or
  manufacturing success by editing the ledger or operations journal.
- Calling a model-free fixture "desktop tool creation." The reminder must be
  requested in the visible desktop workbench and Kai must actually invoke
  `set_reminder`.

## Invariants

- The unique reminder text is stored, delivered, and restored byte-for-byte.
- Core is the sole commitment authority. The operator and evidence tooling are
  read-only observers.
- One commitment ID maps to one deterministic outbound ID and one transcript
  record ID across restart and retry.
- The coordinator may disappear; the promise may not.
- Delivery targets one work-eligible desktop body, never Messenger or another
  body, and never fans out.
- Core acknowledgement occurs only after durable transcript persistence and
  visible acceptance.
- Raw private state and unrelated conversation content never enter evidence.
- A stale runtime, missing body, missed tool call, early/late dispatch,
  duplicate bubble, missing transcript record, or missing acknowledgement is a
  failure or `UNVERIFIED`, not something to explain away.

## Authoritative evidence to inspect

- `docs/briefs/BRIEF_017_DESKTOP_SET_REMINDER_TO_CORE.md`
- `lib/services/core/kai_desktop_reminder_tool.dart`
- `lib/services/core/kai_headless_coordinator.dart`
- `lib/services/core/kai_due_commitment_loop.dart`
- `lib/services/core/kai_due_commitment_scheduler.dart`
- `lib/services/core/kai_core_server.dart`
- `lib/services/core/kai_core_client.dart`
- `lib/services/core/kai_outbound_acceptance.dart`
- `lib/services/core/conversation_store_service.dart`
- `lib/screens/kai_desktop_shell.dart`
- `windows/runner/main.cpp`
- `scripts/test/kai_reminder_runtime_acceptance.ps1`
- `scripts/test/test_kai_reminder_runtime_acceptance.ps1`
- `%LOCALAPPDATA%/Homecoming/KaiCore/state.json`
- `%LOCALAPPDATA%/Homecoming/KaiCore/operations/kai-operations.jsonl`
- live Core `/health`, `/v1/commitments`, and `/v1/presence` responses
- visible desktop transcript before and after room restart

## Attended procedure

1. Capture a run ID, UTC start instant, build hashes/timestamps, Core health,
   state metadata/hash, current commitment IDs/statuses, and current journal
   position. Do not print reminder texts from unrelated records.
2. Use the tray's **Quit Kai completely**. Within 15 seconds verify both Kai
   processes exit and port 8790 closes. If not, stop; do not force-kill.
3. Start the rebuilt `Kai.exe --coordinator-worker --background`, wait for
   `coordinator_ready`, and verify Core advertises `scheduled_commitments` and
   supports commitment listing. Open one visible desktop room and wait until
   its exact body/inbox is online.
4. Choose a Bahrain due time at least eight minutes ahead and before quiet
   hours. In desktop chat ask Kai to set one reminder containing the unique run
   marker. A plain-text promise without a successful tool receipt is `FAIL`.
5. Read Core and prove exactly one new `scheduled` commitment exists with the
   exact text, canonical Bahrain provenance, and no outbound ID. Record its ID
   and deterministic expected outbound ID without mutating it.
6. Before due time, use **Quit Kai completely** again. Verify port 8790 closes,
   then restart the rebuilt hidden coordinator and visible desktop room.
7. Prove the same commitment ID and exact fields survived and remain
   `scheduled`; no second commitment may exist for the run marker.
8. Keep the desktop room visible through due time. Observe one exact reminder
   bubble. Do not manually invoke Core dispatch or acknowledgement.
9. Prove Core reports that commitment `acknowledged`, with one outbound ID,
   one target body ID, one dispatch instant, and one acknowledgement instant.
   Prove the operations journal contains exactly one correlated
   `due_commitment_dispatched` transition.
10. Close and reopen only the visible desktop room. Confirm transcript restore
    shows the reminder exactly once and Core stays acknowledged with no new
    dispatch. Capture a screenshot or attended observation plus the sanitized
    machine evidence.
11. Stop and report. Do not start another feature.

## Pass criteria

1. Rebuilt runtime health advertises `scheduled_commitments`; the endpoint is
   not the stale preflight process.
2. The visible desktop request causes a real successful `set_reminder` tool
   execution, not narration or a manually inserted Core record.
3. Exactly one new commitment stores the unique text byte-for-byte with
   persona `truekai`, canonical Bahrain wall provenance, offset 180, and the
   expected UTC due instant.
4. The commitment is durable before Kai reports success.
5. A complete coordinator/Core shutdown and restart before due preserves the
   same commitment ID, text, provenance, status, and evaluation instant.
6. No second commitment or outbound is created by retry/restart.
7. Nothing dispatches before the authoritative due/evaluation instant.
8. Delivery selects exactly one currently eligible desktop body and never a
   friend-only/Messenger body.
9. The visible reminder is byte-for-byte exact and appears once during live
   delivery.
10. Transcript persistence contains one deterministic record for the outbound,
    and reopening the room restores exactly one bubble.
11. Core reaches `acknowledged` only after persistence and visible acceptance;
    the record is no longer due and no pending envelope remains for that body.
12. Journal evidence contains one correlated dispatch and no failure,
    duplicate dispatch, sensitive material, or reminder text.
13. Existing commitments, transcripts, and unrelated dirty-worktree files are
    unchanged except for ordinary live runtime activity.
14. Evidence records exact commands, times, IDs, body, status transitions,
    counts, screenshots/observations, and any latency without exposing private
    content or credentials.

Any missing criterion is `FAIL` or `UNVERIFIED`, never partial.

## Required verification

The acceptance collector is read-only. It exposes fixture paths only for its
own tests; the attended run must leave them empty and query live Core.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test/test_kai_reminder_runtime_acceptance.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test/kai_reminder_runtime_acceptance.ps1 -Mode Preflight
```

After creation, restart, and delivery, rerun the collector respectively with
`-Mode Created`, `-Mode Survived`, and `-Mode Delivered`, providing the exact
commitment ID, UTF-8 text SHA-256, initial promise fingerprint, run marker,
acceptance-window UTC instant, and a sanitized evidence output path.

Verifier self-test evidence: **9/9 PASS** for rebuilt preflight, stale runtime,
creation, survival, fingerprint drift, text drift, completed delivery,
duplicate dispatch, and journal marker leakage. The live preflight currently
returns `UNVERIFIED` with Core start time
`2026-08-07T15:32:30.045882Z`, exactly because the old process remains loaded.

Blocked checkpoint: the same stale Core and three `Kai.exe` processes remain
after three consecutive continuation turns. All safe preparation is complete.
The PM will not substitute Task Manager, forced termination, direct ledger
mutation, or a synthetic run for Sadeq's attended tray-level **Quit Kai
completely**. Resume this brief when Sadeq reports that action complete.

## Failure and rollback

- Stop at the first causal failure and preserve the ledger/journal evidence.
- Do not delete a failed test commitment; an explicit later cleanup decision
  must preserve the incident record first.
- If the rebuilt coordinator cannot start, relaunch the last known executable
  only after recording the failure. Never replace or delete Core state.
- If Firebase/transcript persistence fails, leave Core pending; do not
  acknowledge manually.
- If the tray quit does not stop cleanly, stop and request a separate recovery
  decision rather than escalating to forced termination.

## Stop and report

Report runtime build/hash, process lifecycle, Core capability/start times,
commitment and outbound IDs, exact status transitions, selected body, dispatch
and acknowledgement counts/times, visible and restored bubble counts,
credential scan, state preservation, criterion-by-criterion verdicts,
unresolved risks, and rollback state.

Do not start recurring reminders, notification polish, Messenger reminder
delivery, AR/VR/Unity, cloud migration, or self-improvement work.
