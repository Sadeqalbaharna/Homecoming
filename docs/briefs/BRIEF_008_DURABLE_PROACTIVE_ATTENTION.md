# Brief 008 — Proactive attention survives coordinator restart

Owner: Claude implementation team

Reviewer: Northstar project manager

Status: ACCEPTED — deterministic gate closed by Briefs 009 and 010; live restart proof pending

## Goal

An ordinary proactive attention event that is queued, deferred, or awaiting an
eligible body survives a headless-coordinator restart and resumes from the same
policy state without duplicate delivery.

## Why this is next

Brief 007 production-wired the tested Attention Engine, but its queue,
processed-ID ledger, daily budget, and retry times exist only in memory. A
coordinator crash currently erases everything Kai was waiting to say and resets
his pacing. Restart durability is the first causal gap between wired attention
and continuous presence.

## Entry gate

- Read:
  - `docs/NORTHSTAR_SOURCE_OF_TRUTH.md`
  - `docs/briefs/BRIEF_007_PROACTIVE_ATTENTION_ADMISSION.md`
- Run the Brief 007 focused tests before editing; preserve their output.
- Run `git status --short`. The worktree is intentionally dirty. Preserve all
  unrelated user/Codex work and do not reformat broad files.
- Treat Brief 007's queue behavior and policy constants as frozen unless a
  failing acceptance test proves a contradiction.

## In scope

- Persist proactive-attention state in a dedicated versioned file:
  `%LOCALAPPDATA%\Homecoming\KaiCore\attention.json`.
- Persist only what is required to resume:
  - pending event metadata and the pending nudge seed/kind;
  - `notBefore` retry/defer instant;
  - bounded processed event IDs;
  - Bahrain budget-day stamp and delivery count;
  - event-ID sequence/collision state if the chosen ID design requires it.
- Add explicit snapshot/restore APIs to `KaiProactiveAttentionQueue`; parsing
  malformed individual records must skip/quarantine them rather than crash the
  coordinator.
- Add an asynchronous `KaiProactiveAttentionStore` (or equivalently narrow
  name) with serialized writes, temp-file replacement, and one backup file,
  following the proven atomic pattern in `KaiCoreServer._persist()`.
- Hydrate the queue before the coordinator subscribes to new proactive events.
- Persist after every state-changing operation: enqueue, defer, discard,
  complete, failure retry, budget reset, and processed-ID change. A harmless
  extra write after a read-only evaluation is acceptable; a missed mutation is
  not.
- On startup, evaluate restored items normally. Expiry, quiet hours, budget,
  and body routing remain decisions of `KaiAttentionEngine`, not the store.
- Journal content-free lifecycle events for load success, recovery from backup,
  corrupt/unsupported state, and persistence failure. Never put the nudge seed
  in the operations journal.

## Out of scope

- Modifying `KaiCoreServer` state schema or HTTP API.
- Firebase/cloud replication, multi-host election, laptop-loss survival, or
  encryption/key-management work.
- Durable commitments, completed-work delivery, direct-reply admission, or new
  attention kinds.
- UI, notifications, Messenger behavior, Unity/AR, transport, memory, model,
  tools, capabilities, or self-improvement.
- Changing quiet hours, daily budget, retry delays, relevance expiry, routing,
  or the pure Attention Engine.
- Claiming Phase 3, always-on deployment, or cross-device durability complete.

## Invariants

- One event selects zero or one body and never fans out.
- A restored event retains its original Core receipt time; restart time must not
  reorder it or refresh its expiry.
- Device `occurredAt` remains descriptive only.
- A completed/processed event is not delivered again after restart.
- Budget usage and Bahrain calendar-day identity survive restart; restart never
  grants six fresh nudges.
- The state file may contain the pending internal seed because resumption
  requires it. It must contain no generated reply, raw user transcript, memory
  payload, API key, credential, or tool authority.
- Operational logs remain content-free.
- Corrupt state never deletes the last readable backup and never prevents
  Central Kai from starting.
- Writes are serialized and recoverable; overlapping timer/presence callbacks
  cannot leave partial JSON.

## Authoritative evidence to inspect

- `lib/services/attention/kai_proactive_attention_queue.dart`
- `lib/services/attention/kai_attention_event.dart`
- `lib/services/attention/kai_attention_engine.dart`
- `lib/services/core/kai_headless_coordinator.dart`
- `lib/services/core/kai_core_server.dart` (`_loadState` and `_persist` only as
  a reference; do not edit it)
- `lib/services/core/kai_operations_journal.dart`
- `test/kai_proactive_attention_queue_test.dart`
- `test/kai_headless_coordinator_test.dart`
- `test/kai_core_server_test.dart` for the existing restart-test pattern

## Permitted files

- Modify:
  - `lib/services/attention/kai_proactive_attention_queue.dart`
  - `lib/services/core/kai_headless_coordinator.dart`
  - `test/kai_proactive_attention_queue_test.dart`
  - `test/kai_headless_coordinator_test.dart`
- Add:
  - one attention persistence service under `lib/services/attention/`
  - one focused persistence test under `test/`

Stop and report `BLOCKED_BY_SCOPE` before editing any other production file.
Do not edit this brief or the Northstar source of truth; the reviewer owns their
status.

## Procedure

1. Capture pre-change status and run the Brief 007 focused tests.
2. Add failing tests for snapshot round-trip, process-restart recovery,
   processed-ID idempotency, budget continuity, defer/retry continuity,
   corruption fallback, and serialized writes.
3. Add versioned queue snapshot/restore without adding I/O to the pure Attention
   Engine.
4. Implement the narrow atomic store with injectable directory/clock seams for
   deterministic tests.
5. Hydrate before proactive subscription; persist every queue mutation.
6. Add content-free load/save/recovery journal records.
7. Run focused and shared-infrastructure regressions.
8. Stop and report. Do not start commitments or cloud replication.

## Pass criteria

- Snapshot → restore preserves every pending event ID, correlation ID, original
  receipt/occurrence/expiry instants, nudge seed/kind, and `notBefore` instant.
- After six completed deliveries, restart preserves the exhausted Bahrain-day
  budget and the seventh event still defers by the remaining policy.
- A completed event ID replayed after restart is `discardDuplicate` and selects
  no body.
- A bodyless stored event survives restart and later selects at most one newly
  eligible body.
- A failed event's retry instant survives restart and cannot run early.
- An event that expires while the coordinator is down is explicitly expired on
  first eligible evaluation, not delivered and not silently lost.
- Primary corruption loads the last valid backup. Primary plus backup
  corruption starts with an honest empty queue, records a warning, and does not
  overwrite the corrupt evidence before startup reports it.
- Two overlapping save requests produce valid JSON representing the later
  snapshot; no partial/truncated file is observable after completion.
- Startup hydration completes before new nudge subscription and before the
  attention timer can drain.
- No state or journal output contains generated replies, raw user transcript,
  credentials, or tool permissions.
- All Brief 007, Attention Engine, routing, coordinator, and new persistence
  tests pass unchanged except for narrowly required construction seams.

Any missing required criterion is `FAIL` or `UNVERIFIED`, not partial success.

## Required verification

Run and report exact results:

```powershell
flutter test test/kai_proactive_attention_store_test.dart
flutter test test/kai_proactive_attention_queue_test.dart
flutter test test/kai_attention_engine_test.dart test/kai_body_event_test.dart
flutter test test/kai_headless_coordinator_test.dart
flutter analyze lib/services/attention lib/services/core/kai_headless_coordinator.dart test/kai_proactive_attention_store_test.dart test/kai_proactive_attention_queue_test.dart
git diff --check
git status --short
```

Also run one model-free restart harness in a temporary directory: enqueue a
bodyless event, persist it, dispose the first store/queue, construct a fresh
store/queue, restore, add one eligible candidate, and prove one `deliverNow`
decision with the original event/correlation ID. This is integration evidence,
not live model delivery.

## Failure and rollback

- Never delete existing `%LOCALAPPDATA%\Homecoming\KaiCore` state.
- Tests use only unique temporary directories and clean only those exact paths.
- If the new file is unreadable, retain it and its backup for diagnosis; start
  safely with an empty queue and journal the degraded state.
- Rollback restores the Brief 007 in-memory queue wiring and removes only the
  new attention store/snapshot integration. Core, Firebase, conversations, and
  project data remain untouched.

## Stop and report

Report:

- files and behavior changed;
- exact schema/version and fields persisted;
- startup hydration order;
- atomic-write and corruption-recovery behavior;
- every command/test and exact result;
- model-free restart-harness evidence;
- criterion-by-criterion `PASS`, `FAIL`, or `UNVERIFIED`;
- unresolved risks, especially local-file privacy and laptop-loss durability;
- rollback path;
- final verdict and exact next recommendation.

Do not start commitments, completed-work routing, Firebase replication,
multi-host deployment, device transport, Unity work, or self-improvement.
