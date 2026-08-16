# Brief 010 — Backup-only attention recovery repair

Owner: Claude implementation team

Reviewer: Northstar project manager

Status: ACCEPTED — 70 focused tests and scoped analysis passed; live restart proof pending

## Goal

Make the first save after backup-only attention recovery preserve the last
readable copy, and make backup-only corruption retain its diagnostic evidence.

## Why this is next

Brief 009 repaired the common corrupt-primary recovery path, but acceptance
review reproduced two remaining data-loss cases. A crash after rotating
`attention.json` to `.bak` and before installing the temp file legitimately
leaves only a readable backup. The next save currently deletes that last copy.
When only a corrupt backup exists, the next save deletes it rather than
quarantining it. Both contradict the durability invariant and block Brief
008/009 acceptance.

## Entry gate

- Read Briefs 008 and 009 plus their reports.
- Run `test/kai_proactive_attention_recovery_edge_test.dart` unchanged and
  preserve its two failing results as the pre-change reproduction.
- Preserve the dirty worktree and all unrelated changes.

## In scope

- Repair the store's first-save recovery lifecycle for:
  - primary absent plus readable backup;
  - primary absent plus corrupt backup;
  - a pre-existing quarantine destination from an earlier incident.
- Keep the save future's failure propagation and healthy serialization tail.
- Add a collision-safe, deterministic quarantine strategy that never silently
  overwrites or deletes earlier corrupt evidence.
- Add the pre-existing-quarantine regression to the reviewer-created edge test.

## Out of scope

- Queue, coordinator, Attention Engine, routing, schema, policy, UI, Firebase,
  Core API, encryption, cloud durability, commitments, Unity, or attended tests.
- Cleanup or retention policy for quarantine files.
- Broad persistence refactors.

## Invariants

- A recovered readable backup remains readable until a new primary has been
  installed successfully; the first resumed save must not delete it.
- A backup known to be corrupt is moved to a diagnostic quarantine path, never
  deleted as ordinary rotation.
- Existing quarantine evidence is preserved; a later incident receives a
  collision-safe path and does not make saving permanently fail.
- `load()` remains read-only and non-fatal.
- Normal primary-plus-backup rotation behavior remains unchanged.
- Save failures remain observable to the caller and later saves remain usable.

## Authoritative evidence to inspect

- `lib/services/attention/kai_proactive_attention_store.dart`
- `test/kai_proactive_attention_recovery_edge_test.dart`
- `test/kai_proactive_attention_store_test.dart`
- `docs/briefs/BRIEF_009_DURABLE_ATTENTION_REPAIR.md`

## Permitted files

- Modify only:
  - `lib/services/attention/kai_proactive_attention_store.dart`
  - `test/kai_proactive_attention_recovery_edge_test.dart`
- Stop and report `BLOCKED_BY_SCOPE` before touching any other file.
- Do not edit this brief or the Northstar source of truth.

## Procedure

1. Capture status and reproduce the two failing edge tests unchanged.
2. Add one failing test for a pre-existing quarantine destination.
3. Repair recovery-state tracking and first-save ordering.
4. Run the edge test, the entire Brief 008/009 focused suite, analyzer, and
   diff checks.
5. Stop and report. Do not start the attended crash test.

## Pass criteria

- Primary absent plus readable backup loads as `recoveredFromBackup`; after the
  next successful save, the new primary and the previous backup both parse as
  supported JSON.
- If that save fails before primary installation, the readable backup remains
  untouched and a later retry can succeed.
- Primary absent plus corrupt backup loads as `corrupt`; the next save creates
  a readable primary and retains the exact corrupt bytes under quarantine.
- A pre-existing quarantine file remains byte-for-byte intact; a new corrupt
  file receives a distinct deterministic quarantine path and the save succeeds.
- The two reviewer-created tests move from FAIL to PASS without weakening their
  assertions.
- All 66 previously passing Brief 008/009 focused tests remain green.

Any missing criterion is `FAIL` or `UNVERIFIED`, never a partial pass.

## Required verification

Report exact commands, counts, warnings, and exit codes:

```powershell
flutter test test/kai_proactive_attention_recovery_edge_test.dart
flutter test test/kai_proactive_attention_store_test.dart
flutter test test/kai_proactive_attention_queue_test.dart
flutter test test/kai_attention_engine_test.dart test/kai_body_event_test.dart
flutter test test/kai_headless_coordinator_test.dart
flutter analyze lib/services/attention/kai_proactive_attention_store.dart test/kai_proactive_attention_recovery_edge_test.dart test/kai_proactive_attention_store_test.dart
git diff --check
git status --short
```

No new analyzer warning or error is acceptable.

## Failure and rollback

- Tests use unique temporary directories only.
- Never read, modify, or delete the real
  `%LOCALAPPDATA%\Homecoming\KaiCore\attention.json*` files.
- Roll back only the Brief 010 delta; retain the failing reviewer tests as
  evidence if the repair cannot pass.

## Stop and report

Report the recovery-state model, exact write ordering, collision strategy,
files changed, every command and exact result, criterion-by-criterion verdict,
unresolved risks, rollback, and the attended restart recommendation.

Do not start the attended crash test, commitments, cloud durability, device
transport, Unity, or self-improvement.
