# Brief 009 — Durable attention failure integrity repair

Owner: Claude implementation team

Reviewer: Northstar project manager

Status: ACCEPTED — deterministic gate closed by Brief 010; live restart proof pending

## Goal

Close the four durability contradictions found during Brief 008 review so an
attention-state failure is observable, recoverable state is not destroyed, an
unsupported schema is reported honestly, and every state mutation is persisted.

## Why this is next

Brief 008's focused behavior tests pass, but acceptance is blocked by primary
code evidence. `KaiProactiveAttentionStore.save()` catches its own error, which
makes the coordinator's `attention_state_persist_failed` path unreachable. A
load from backup is followed by the normal rotation path, which can delete that
last readable backup and replace it with the corrupt primary. A syntactically
valid unsupported version is treated as a successful load. Finally,
`evaluate()` can reset the Bahrain budget day and return `null`, leaving that
mutation unpersisted. These are data-integrity failures inside the active phase.

## Entry gate

- Read `docs/briefs/BRIEF_008_DURABLE_PROACTIVE_ATTENTION.md` and its report.
- Preserve all unrelated dirty work.
- Re-run the Brief 008 focused tests before editing.
- Treat the accepted Attention Engine policy, routing rules, schema version 1,
  and Brief 008 file boundary as frozen.

## In scope

- Make each `save()` caller receive that save operation's failure while keeping
  the internal serialization tail usable for a later retry.
- Preserve the last readable backup and corrupt evidence during the first save
  after backup recovery or degraded startup. A recovered backup must not be
  deleted or replaced with the corrupt primary.
- Distinguish absent, primary-loaded, backup-recovered, corrupt/degraded, and
  unsupported-version load outcomes sufficiently for content-free journaling.
- Treat an unsupported version as degraded/unsupported, not as
  `attention_state_loaded` and not as an accepted empty version-1 queue.
- Ensure a Bahrain budget-day reset is persisted even when no attention event
  is due, without creating an unconditional disk write every 20-second timer
  tick. A narrow queue mutation-generation/revision seam is acceptable.
- Add focused regression tests for all four causal failures.

## Out of scope

- Schema version 2, migrations, encryption, cloud replication, Core schema/API,
  commitments, completed work, direct replies, new routing, UI, Messenger,
  Unity/AR, model behavior, tools, memory, or self-improvement.
- Broad refactors or changing quiet hours, budget size, retry timing, expiry,
  processed-ledger limit, or delivery policy.
- Attended crash testing; that resumes only after this repair passes review.

## Invariants

- One event selects zero or one body and never fans out.
- A failed save is visible to its caller and a later save can still succeed.
- The last readable backup is never deleted or overwritten merely because the
  primary is corrupt.
- Corrupt primary/backup bytes are retained under deterministic diagnostic
  paths until an explicit cleanup action outside this brief.
- Unsupported state is never guessed at or described as successfully loaded.
- Startup remains non-fatal for absent, corrupt, or unsupported attention state.
- Journals contain status/counts only—never seeds, replies, transcripts,
  credentials, memory, or tool authority.
- No idle timer loop writes unchanged attention state.

## Authoritative evidence to inspect

- `lib/services/attention/kai_proactive_attention_store.dart`
- `lib/services/attention/kai_proactive_attention_queue.dart`
- `lib/services/core/kai_headless_coordinator.dart`
- `test/kai_proactive_attention_store_test.dart`
- `test/kai_proactive_attention_queue_test.dart`
- `test/kai_headless_coordinator_test.dart`
- `docs/briefs/BRIEF_008_DURABLE_PROACTIVE_ATTENTION.md`

## Permitted files

- Modify only the six production/test files listed above.
- Do not edit this brief or `docs/NORTHSTAR_SOURCE_OF_TRUTH.md`; the reviewer
  owns acceptance status.
- Stop and report `BLOCKED_BY_SCOPE` before touching another file.

## Procedure

1. Capture status and pre-change focused results.
2. Add failing tests that reproduce each of the four contradictions.
3. Repair store error propagation without poisoning the serialization tail.
4. Repair recovery rotation so valid backup and corrupt evidence survive.
5. Add explicit unsupported-version load status and journal mapping.
6. Add a narrow mutation signal and persist a null-dispatch budget reset only
   when state actually changed.
7. Run the full Brief 008 focused set and scoped analyzer.
8. Stop and report; do not run the attended crash test yet.

## Pass criteria

- A forced filesystem write failure completes that `save()` future with an
  error, reaches the coordinator's content-free persistence-failure journal
  seam, and does not prevent a later valid save from succeeding.
- With corrupt primary plus readable backup, `load()` recovers the backup; the
  next save produces a readable primary while the previously readable backup
  remains readable and the corrupt primary bytes remain available separately.
- With corrupt primary plus corrupt backup, startup is degraded and non-fatal;
  the first later save does not silently delete either corrupt evidence blob.
- A valid JSON map with version 999 produces an explicit unsupported/degraded
  result, restores no queue state, and maps to a warning rather than
  `attention_state_loaded`.
- A Bahrain day rollover with pending items all blocked by `notBefore` persists
  the reset budget state even though evaluation returns no dispatch.
- Repeated idle evaluations with no state mutation do not request persistence.
- All Brief 008 snapshot, restart, budget, idempotency, corruption, privacy,
  queue, engine, routing, and coordinator tests remain green.

Any missing criterion is `FAIL` or `UNVERIFIED`, never a partial pass.

## Required verification

Run and report exact commands, test counts, warnings, and exit codes:

```powershell
flutter test test/kai_proactive_attention_store_test.dart
flutter test test/kai_proactive_attention_queue_test.dart
flutter test test/kai_attention_engine_test.dart test/kai_body_event_test.dart
flutter test test/kai_headless_coordinator_test.dart
flutter analyze lib/services/attention lib/services/core/kai_headless_coordinator.dart test/kai_proactive_attention_store_test.dart test/kai_proactive_attention_queue_test.dart
git diff --check
git status --short
```

The scoped analyzer's three known subscription-handle `unused_field` warnings
may be reported as pre-existing; no new warning or error is acceptable.

## Failure and rollback

- Never test against or delete the real `%LOCALAPPDATA%\Homecoming\KaiCore`.
- Use unique temporary directories and delete only those exact test paths.
- Preserve corrupt fixtures until their assertions have completed.
- Rollback only the Brief 009 repair delta; do not remove the otherwise-passing
  Brief 008 implementation or unrelated shared-worktree changes.

## Stop and report

Report files/behavior changed, the exact failure-propagation design, recovery
file lifecycle, load-status mapping, mutation-persistence seam, every command
and exact result, criterion-by-criterion verdict, unresolved risks, rollback,
and the precise attended test recommendation.

Do not start the attended crash test, commitments, completed-work routing,
cloud durability, device transport, Unity, or self-improvement.
