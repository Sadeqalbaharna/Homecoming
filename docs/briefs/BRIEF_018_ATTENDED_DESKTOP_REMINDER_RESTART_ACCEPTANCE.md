# Brief 018 — Attended desktop reminder restart acceptance

Owner: Northstar project manager with Sadeq as attended operator

Reviewer: Northstar project manager

Status: READY FOR CLEAN-TRAY RE-ENTRY — IDENTITY REPAIR TESTED / LIVE UNVERIFIED

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

The 2026-08-09 attended attempt stopped before process or GUI action because
the live payload hash `97A08CB0...` did not match the then-accepted
`C69667AD...` payload and the live executable came from `C:\code\homecoming_app`
rather than this governed worktree. It also proved that `/health.startedAt` is
persisted Core-state metadata (`??=`), not an OS process-start instant. The old
freshness inference was invalid and has been removed.

The repaired local gate now has one immutable artifact manifest at
`docs/evidence/BRIEF_018_ACCEPTED_ARTIFACT.json`:

- governed root:
  `C:\Users\sadeq\.codex\worktrees\3740\homecoming_app`;
- source commit: `9a5c6ffc951a2213d9b5cf5d7a28df16518aa2b6`, plus an exact compiled-source
  fingerprint for the captured dirty tree;
- credential profile: `empty-local-build-stub-v1`;
- `Kai.exe` SHA-256:
  `B906B94D56E9B151DE1DC1CC23ADF3B257C1DA39A9D3AE2624A47B74B4192896`;
- `app.so` SHA-256:
  `E74B61177D81C9F09244BF9A87557AD7061AFF61C064CCAC75A34C871B8A82A8`;
- binding ID:
  `0B1D8B4FB435B4DE4DE6BEA12465A7E0104862F4F24F174F494463EA04EA874A`.

The Release was built in this worktree without embedded credentials. Artifact
verification passes locally. The live `C:\code` runtime remains untouched and
is not acceptance evidence.

## Entry gate

- Brief 017 is `ACCEPTED / TESTED / WIRED` with all 14 criteria passing.
- Verify the immutable accepted-artifact manifest before any process action.
- After the clean tray quit, launch only the manifest's exact `Kai.exe`.
- Before opening a desktop room, the runtime verifier must bind port 8790 to
  that executable and payload, prove one matching watchdog, and prove the OS
  process creation time is later than the manifest binding time.
- `/health.startedAt` may be recorded only as persisted-state metadata and must
  never be used as process freshness evidence.
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
- `scripts/test/bind_kai_reminder_acceptance_artifact.ps1`
- `scripts/test/test_kai_reminder_runtime_acceptance.ps1`
- `docs/evidence/BRIEF_018_ACCEPTED_ARTIFACT.json`
- `%LOCALAPPDATA%/Homecoming/KaiCore/state.json`
- `%LOCALAPPDATA%/Homecoming/KaiCore/operations/kai-operations.jsonl`
- live Core `/health`, `/v1/commitments`, and `/v1/presence` responses
- visible desktop transcript before and after room restart

## Attended procedure

1. Run `-Mode Artifact` against the committed manifest. Capture its binding ID,
   UTC start instant, state metadata/hash, current commitment IDs/statuses, and
   current journal position. Preflight must capture a non-empty journal anchor
   hash/length that remains a byte prefix of one retained generation at
   delivery. Do not print reminder texts from unrelated records. Any
   manifest/path/hash mismatch stops before process or GUI action.
2. Use the tray's **Quit Kai completely**. Within 15 seconds verify every
   `Kai.exe` exits and port 8790 closes. If any governed or ungoverned Kai
   process remains, stop; do not force-kill.
3. Start the manifest's exact `Kai.exe --coordinator-worker --background`.
   Before opening any GUI, run `-Mode Preflight` and prove stable port ownership,
   exact governed root and hashes, one `--watchdog --watch-pid=<corePid>` child,
   and OS process creation after artifact binding. Record the returned runtime
   identity ID. Then verify `scheduled_commitments`, commitment listing, and
   `coordinator_ready`; only then open one visible desktop room.
4. Choose a Bahrain due time at least eight minutes ahead and before quiet
   hours. Use an opaque run marker. Record the exact composed reminder text and
   its UTF-8 SHA-256 before reading Core; never derive the expected hash from a
   Core response. In desktop chat ask Kai to set it. A plain-text promise
   without a successful tool receipt is `FAIL`.
5. Read Core and prove exactly one new `scheduled` commitment exists with the
   exact text, canonical Bahrain provenance, and no outbound ID. Record its ID
   and deterministic expected outbound ID without mutating it.
6. Preserve the first `Created` evidence file and its promise fingerprint.
   Before due time, use **Quit Kai completely** again. Verify port 8790 closes,
   restart the exact bound coordinator, and run `-Mode Survived` before opening
   the GUI. The new runtime identity must differ from the pre-restart identity.
7. Prove the same commitment ID and exact fields survived and remain
   `scheduled`; no second commitment may exist for the run marker.
8. Before due time capture `/v1/presence`, including the IDs and count of
   work-eligible desktop bodies. Keep the room visible through due time and
   observe one exact reminder bubble. Do not manually invoke Core dispatch or
   acknowledgement.
9. Prove Core reports that commitment `acknowledged`, with one outbound ID,
   one target body ID, one dispatch instant, and one acknowledgement instant.
   Prove the operations journal contains exactly one correlated
   `due_commitment_dispatched` transition.
10. Close and reopen only the visible desktop room. Confirm transcript restore
    shows the reminder exactly once and Core stays acknowledged with no new
    dispatch. Capture a screenshot or attended observation plus the sanitized
    machine evidence.
11. Use distinct immutable evidence files for Artifact, Preflight, Created,
    Survived, and Delivered. The first verdict for each mode is authoritative;
    do not rerun a failed mode to obtain green evidence. Stop and report.

## Pass criteria

1. The port-owning coordinator and its one watchdog execute the exact governed
   artifact, its payload hashes match the immutable binding, OS creation is
   later than binding, and health advertises `scheduled_commitments`.
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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test/kai_reminder_runtime_acceptance.ps1 -Mode Artifact -AcceptedArtifactPath docs/evidence/BRIEF_018_ACCEPTED_ARTIFACT.json -ExpectedBindingId 0b1d8b4fb435b4de4de6bea12465a7e0104862f4f24f174f494463ea04ea874a
```

After launching the accepted artifact, run `Preflight`, then `Created`,
`Survived`, and `Delivered` with the same manifest. Pin Created to the Preflight
runtime identity. Pin Survived to its newly returned identity and provide the
previous identity so an unchanged process fails. Pin Delivered to the Survived
identity. Copy each expected identity only from the preceding mode's immutable
evidence file; never re-derive it from the runtime being checked. Also provide
the Preflight journal anchor to Delivered so retention loss fails closed, the
exact commitment ID, independently sourced UTF-8 text hash, initial promise
fingerprint, opaque marker, acceptance-window UTC, and one distinct sanitized
evidence path per mode.

Verifier self-test evidence: **28/28 PASS**. Identity cases cover ignored stale
persisted `startedAt`, missing artifact binding, wrong root, wrong payload,
PID/port-owner change, process older than binding, missing watchdog relation,
ungoverned extra Kai processes, out-of-band manifest pinning, payload/source
ordering, cross-run evidence, and unchanged restart identity. The original
creation, survival, exact-text, duplicate, timing, lifecycle, dispatch,
journal-anchor retention and journal-privacy cases continue to pass. The live
runtime was not restarted.

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
