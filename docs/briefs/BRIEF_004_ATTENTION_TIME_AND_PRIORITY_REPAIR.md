# Brief 004 — Attention time and priority repair

Owner: Claude implementation team

Reviewer: Northstar project manager

Status: ACCEPTED — TESTED, NOT INTEGRATED

## Goal

Repair the pure-Dart attention engine so quiet hours, budget deferral, and
priority ordering are explicit, deterministic, and correct for Bahrain time as
well as UTC, while preserving every already-passing Brief 003 invariant.

## Why this is next

Brief 003 cannot be accepted because its tests prove only UTC behavior while
the implementation report directs the future caller to supply local time. The
current code converts local wall-clock fields into UTC constructors, shifting
deadlines by the timezone offset. It also hides the one-hour budget retry and
accepts unused, unbounded priority values. These are policy-contract defects,
not integration work.

## Entry gate

- Read Brief 003 and its reviewer verdict.
- Inspect only the three files added under Brief 003.
- Run `git status --short` and preserve the existing dirty worktree.
- Do not begin unless the repair remains confined to those three files.

## In scope

- Modify only:
  - `lib/services/attention/kai_attention_event.dart`
  - `lib/services/attention/kai_attention_engine.dart`
  - `test/kai_attention_engine_test.dart`
- Make quiet-hours timezone policy explicit. Use an explicit UTC offset supplied
  by trusted policy for the decision being evaluated; do not use host-local
  timezone state.
- Treat decision instants as UTC internally and return UTC `notBefore` values.
- Make the budget retry delay an explicit positive policy input supplied through
  `KaiAttentionContext`; remove the hardcoded one-hour choice.
- Enforce a documented priority range of `0..10` at value-object construction.
- Order attention evaluation by:
  1. higher explicit priority first;
  2. earlier Core `receivedAt` second;
  3. lexical `eventId` last.
- Device `occurredAt` must never affect ordering.
- Preserve existing decision outcomes, reason codes, routing delegation, and
  durability behavior.

## Out of scope

- Any Core, coordinator, routing, Unity, Firebase, Messenger, UI, transport,
  model, memory, capability, or self-improvement change.
- Integration into a running process.
- IANA timezone databases, daylight-saving lookup, geolocation, or network time.
- New attention kinds, adaptive scoring, psychological inference, or scheduler
  persistence.
- Renaming existing outcomes or changing existing routing reasons.

## Invariants

- The engine remains pure Dart with no I/O, clock reads, global state, random
  values, platform timezone lookup, or model call.
- Trusted policy supplies the effective UTC offset for the evaluated instant.
- A quiet-hours end of 07:00 Bahrain time must serialize to 04:00 UTC when the
  effective offset is UTC+03:00.
- A promise remains owed until downstream acknowledgement; `deliverNow` is a
  decision, not proof of delivery.
- One event selects zero or one exact body and never fans out.
- Existing Messenger, permission, transcript, and routing invariants remain
  unchanged.
- Equal inputs produce equal decisions.
- Invalid policy configuration fails fast; it must not silently normalize to a
  different hour or priority.

## Procedure

1. Add failing tests for all new criteria before editing implementation.
2. Add explicit timezone-offset handling to `KaiQuietHours`.
3. Replace `_nextBudgetWindow` with the caller-supplied positive retry delay.
4. Validate the priority range and implement deterministic evaluation ordering.
5. Preserve the existing 21 behavior tests, adjusting construction only where
   the new explicit policy inputs require it.
6. Format only the three allowed files.
7. Run focused tests, existing routing regression, scoped analysis, diff check,
   and status inspection.
8. Stop and report. Do not integrate.

## Pass criteria

- At Bahrain 23:30 local during a 22:00–07:00 quiet window, represented by
  `now = 2026-08-08T20:30:00Z` and UTC offset `+03:00`, the decision defers to
  exactly `2026-08-09T04:00:00Z`.
- At Bahrain 03:00 local in the same window, represented by
  `now = 2026-08-09T00:00:00Z`, deferral ends at exactly
  `2026-08-09T04:00:00Z`.
- The equivalent UTC-offset-zero cases remain correct.
- A non-one-hour budget retry policy—for example 30 minutes—produces exactly
  `now + 30 minutes`; no one-hour constant remains in implementation.
- Zero or negative budget retry duration is rejected at construction.
- Priorities `0` and `10` are accepted; `-1` and `11` are rejected.
- Higher priority sorts before lower priority even when received later.
- Equal priority sorts by Core `receivedAt`, then `eventId`.
- Changing only `occurredAt` cannot change evaluation order.
- All previous Brief 003 tests still pass semantically.
- Existing `test/kai_body_event_test.dart` passes unchanged.
- Static analysis reports no issue.
- Only the three permitted files differ from their pre-repair state.

Any missing criterion is `FAIL` or `UNVERIFIED`, not a partial pass.

## Required verification

```powershell
flutter test test/kai_attention_engine_test.dart
flutter test test/kai_body_event_test.dart
dart analyze lib/services/attention test/kai_attention_engine_test.dart
git diff --check
git status --short
```

Report exact outputs. Tests are evidence only for the pure policy; they do not
make Central Attention live.

## Failure and rollback

- Preserve failing test output and stop at the first causal policy failure.
- Do not weaken assertions or remove an existing invariant to make the suite
  pass.
- Rollback is restoring only the three Brief 003 files to their pre-repair
  content. Never reset or clean the worktree.
- If any production integration file appears necessary, stop with
  `BLOCKED_BY_INTEGRATION_BOUNDARY`.

## Stop and report

Report:

- exact changes to time, budget, and priority semantics;
- files changed;
- all commands and exact results;
- criterion-by-criterion `PASS`, `FAIL`, or `UNVERIFIED`;
- confirmation that only the three permitted files changed;
- unresolved assumptions, especially travel or daylight-saving behavior;
- rollback path;
- final verdict.

Do not integrate the engine or begin any other phase.

## Reviewer acceptance — 2026-08-08

Verdict: **PASS** after reviewer correction of three implementation deviations.

The final accepted contract uses an explicit trusted UTC offset for quiet-hours
wall-clock evaluation, returns UTC `notBefore` instants, requires a positive
caller-supplied budget retry delay, accepts only priorities `0..10`, rejects
out-of-range priorities, and orders attention by priority, Core receipt time,
then event ID.

Independent evidence:

- `flutter test test/kai_attention_engine_test.dart` — 29/29 PASS.
- `flutter test test/kai_body_event_test.dart` — 3/3 PASS.
- scoped `dart analyze` — no issues.
- Only the three authorized attention files were repaired.

Proof state: **Tested**. The engine has no production caller, durable scheduler,
budget store, processed-ID retention policy, or runtime delivery integration.
Central Attention is therefore not `Wired` or `Verified live`.
