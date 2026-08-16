# Brief 015 — Desktop outbound transcript acceptance

Owner: Claude implementation team

Reviewer: Northstar project manager

Status: ACCEPTED — TESTED 2026-08-08

Parent phase: Brief 012 durable scheduled commitment vertical slice

## PM acceptance 2026-08-08

Brief 015 is accepted at `TESTED` and `WIRED`, not yet `VERIFIED LIVE`.

The repaired production path uses one shared `KaiOutboundAcceptance` unit from
the desktop shell. It awaits deterministic transcript persistence, re-checks
record identity after that await so a realtime watcher cannot double-render,
and permits acknowledgement only after the exact record is visibly accepted.
`ConversationStoreService` now tracks session idempotency by outbound
`recordId`, after durable write success, so two distinct IDs with identical
text and timestamp remain distinct while a retry of one ID remains one line.

Independent PM evidence:

- 14/14 brief criteria pass.
- 70/70 combined reviewer, acceptance, poller, client, Core-integrity, and
  recovery tests pass.
- 116/116 shared regressions pass.
- `git diff --check` passes; its output contains line-ending notices only.
- Scoped analysis introduces no new diagnostic. The command still exits 1
  because `kai_desktop_shell.dart` has nine pre-existing notices: three
  warnings and six info lints outside this repair's changed behavior.

The next bounded seam is Brief 016: the coordinator due-commitment loop. Live
desktop reminder delivery remains unverified until that seam and the later
desktop creation seam are accepted and exercised together.

## PM review follow-up 2026-08-08

Claude's first implementation reports all required suites green, but independent
code review found two contradictions that the copied acceptance harness cannot
detect:

1. `_acceptCoreOutbound` computes `alreadyVisible` before awaiting the durable
   transcript write. The realtime history watcher can render that `recordId`
   during the await; the callback then resumes and adds a second bubble using
   the stale boolean. The test helper copies the same algorithm, so it proves
   the copy agrees with production rather than forcing the watcher interleaving.
2. `saveAssistantOutbound` deduplicates `_sessionBuffer` with
   `line.formatted`. Two distinct outbound IDs with identical text and timestamp
   therefore collapse to one session line, contradicting identity-based
   semantics. The immutable reviewer test
   `test/kai_desktop_outbound_reviewer_test.dart` reproduces this as a failure.

The repair is narrow. Extract one testable production acceptance unit used by
the shell (do not maintain a second test-only copy), re-check identity after the
await before rendering, and make session-buffer idempotency track `recordId`
rather than formatted content. Force the watcher-during-write interleaving in a
deterministic test. No other Brief 012 work is authorized.

## Goal

The live desktop body polls only its own Central Core outbound inbox, durably
persists each exact reminder once into the `in_person` transcript, renders it
once, and acknowledges Core only after persistence and visible acceptance
succeed.

## Why this is next

Briefs 013 and 014 made the ledger and client safe. Before an unattended
coordinator is allowed to create delivery work, the receiving body must prove
it cannot lose, duplicate, cross-route, or prematurely acknowledge that work.
This is the smallest user-visible seam through the full durable outbound path.

## Entry gate

- Brief 014 is accepted: 12/12 criteria, 16/16 new integration tests, 116/116
  shared regressions, and clean scoped analysis.
- Capture `git status --short` and preserve all shared dirty-worktree changes.
- Reproduce the Brief 014 client suite and 116-test shared gate before editing.
- The two ratified tripwire files are now part of the baseline. Do not rewrite
  them again unless their protected behavior is contradicted.

## In scope

- Add a reusable single-drain Core outbound inbox poller for one exact
  `(surface, bodyId)` pair. It calls the existing client methods and
  acknowledges only after an asynchronous acceptance callback returns true.
- Add an acknowledgement-safe deterministic assistant-only persistence API to
  `ConversationStoreService` for Core outbound records.
- Preserve the deterministic transcript key produced by
  `KaiScheduledCommitment.transcriptKey(outboundId)` as the Firebase child key.
- Carry that record identity through restored/watched conversation lines and
  desktop chat messages so the same outbound cannot render twice while two
  distinct reminders with identical text remain distinct.
- Wire the desktop shell after both the Core sidecar and authoritative
  `KaiGlobalPresenceService.bodyId` are available. Poll exactly
  `surface: desktop` plus that byte-for-byte body ID.
- For each accepted outbound: persist exact text, render/confirm the exact
  record in the visible `in_person` transcript, then acknowledge using the same
  body ID and desktop surface.
- Add focused deterministic tests. A narrow injected transcript-write seam is
  allowed solely to test success/failure without touching live Firebase.

## Out of scope

- Coordinator due loop, attention-engine evaluation, quiet-hour decisions,
  presence-triggered scheduling wake, `set_reminder` tool switching, Android,
  Messenger, AR, VR, Unity, model calls, generated wording, TTS, notification
  UI, cloud scheduling, or live-state acceptance.
- General conversation-history redesign or migration of existing pushed turns.
- A fallback that acknowledges when Firebase/transcript persistence is
  unavailable. Pending Core work is the fallback.
- Polling by hostname, PID, loopback heartbeat device ID, or surface alone.

## Invariants

- Persistence precedes rendering acceptance; rendering acceptance precedes
  Core acknowledgement.
- Any persistence exception, unavailable Firebase, unmounted window, render
  rejection, wrong body, wrong surface, or acknowledgement failure leaves the
  Core outbound pending and retryable.
- Firebase uses a deterministic child key, never `push()`, for Core outbound
  transcript records. Rewriting that child is idempotent.
- The exact stored Core text is persisted and rendered. No model call or text
  transformation sits in this path.
- Identity, not text equality, suppresses duplicates. Two different outbound
  IDs with identical text must produce two records and two visible turns.
- The Core `targetBodyId`, inbox query body ID, acknowledgement body ID, and
  `KaiGlobalPresenceService.bodyId` are byte-for-byte identical.
- A poll cycle and timer cannot overlap; records are handled deterministically
  and never in parallel for the same body.
- Existing ordinary conversation saves, Messenger separation, history restore,
  echo suppression, desktop chat, and handoff polling cannot regress.
- No test reads, writes, or acknowledges the user's live Core/Firebase records.

## Authoritative evidence to inspect

- `docs/briefs/BRIEF_012_DURABLE_SCHEDULED_COMMITMENT_VERTICAL_SLICE.md`
- `docs/briefs/BRIEF_014_COMMITMENT_CLIENT_AND_DEFERRAL_CONTRACT.md`
- `lib/services/core/kai_core_client.dart`
- `lib/services/core/kai_global_presence_service.dart`
- `lib/services/core/kai_scheduled_commitment.dart`
- `lib/services/core/conversation_store_service.dart`
- `lib/screens/kai_desktop_shell.dart`
- `lib/services/core/kai_transcript_echo_guard.dart`
- `test/kai_core_commitment_client_test.dart`
- `test/kai_core_outbound_inbox_test.dart`
- `test/conversation_store_service_test.dart`
- `test/kai_transcript_echo_guard_test.dart`
- `test/widget_test.dart`

## Permitted files

- Modify only:
  - `lib/services/core/kai_core_client.dart`
  - `lib/services/core/conversation_store_service.dart`
  - `lib/screens/kai_desktop_shell.dart`
  - `test/conversation_store_service_test.dart`
  - `test/widget_test.dart`
- Add narrowly named outbound-inbox and desktop-acceptance tests under `test/`.
- Modify `lib/services/core/kai_transcript_echo_guard.dart` and its existing test
  only if record identity cannot be integrated without it; report why.
- Add one narrowly named production acceptance helper under
  `lib/services/core/` only if needed to make the shell's real ordering logic
  directly testable. The shell must call that helper; a test-only reproduction
  of private widget logic is not acceptance evidence.
- Do not modify Core server/ledger, coordinator, attention engine, tools,
  global-presence authority, Android, reviewer/recovery tests, Briefs 012–015,
  Northstar source of truth, or either ratified tripwire.
- Stop and report `BLOCKED_BY_SCOPE` before touching any other file.

## Required persistence contract

Add a narrowly named API equivalent to:

```dart
Future<ConversationLine> saveAssistantOutbound({
  required String personaId,
  required String surfaceId,
  required String outboundId,
  required String exactText,
  required int timestampMillis,
})
```

The persisted child key is
`KaiScheduledCommitment.transcriptKey(outboundId)`. The record is assistant-only
and contains enough explicit identity/surface metadata for restore/watch to
return the same `recordId`. It must await the real durable database write and
throw when the database is unavailable or rejects the write. Session-buffer
mutation must not make a failed database write appear durable.

The exact signature may vary to fit the code, but all semantics above are
mandatory. Do not change ordinary `saveTurn` behavior in this brief.

## Required inbox contract

The reusable poller owns:

```text
pendingOutbound(desktop, exactBodyId)
  -> await onOutbound(record)
  -> if accepted: acknowledgeOutbound(id, exactBodyId, desktop)
  -> otherwise: leave pending
```

It has one drain guard, per-ID processing protection, bounded polling, explicit
`start`, testable `poll`, and `stop`. Exceptions are contained while Core keeps
the record pending. The callback never receives a record for another body.

## Procedure

1. Reproduce entry gates and inspect existing restore/watch/echo behavior.
2. Write failing pure/injected tests for deterministic persistence identity,
   duplicate retry, identical-text distinct IDs, unavailable/write failure,
   and no session-buffer lie.
3. Implement the awaited deterministic assistant-outbound persistence API and
   record identity through parse/watch/restore.
4. Write and implement the reusable exact-body outbound poller with ordering,
   drain, failure, retry, and acknowledgement tests.
5. Wire desktop startup only when both Core and the authoritative global body ID
   exist. Wire disposal and reconnection without creating two pollers.
6. Prove persistence -> render acceptance -> acknowledgement ordering, including
   crash-like retries at each boundary and history-watcher echo races.
7. Run all required verification and stop. Do not start scheduling or tools.

## Pass criteria

1. The desktop poller queries only `desktop` plus the authoritative global body
   ID; no alternative ID is constructed.
2. One pending outbound is persisted under its deterministic transcript key,
   rendered once with exact text, then acknowledged by the exact target body.
3. Persistence failure or unavailable Firebase produces no acknowledgement and
   no durable/session-buffer claim; a later retry can succeed.
4. A render rejection/unmounted desktop produces no acknowledgement. If the
   deterministic record was already persisted, retry rewrites the same child
   and later renders/acknowledges without a second record.
5. An acknowledgement failure leaves the outbound pending; retry does not add a
   second database record or visible bubble before acknowledgement succeeds.
6. A restart after persistence but before acknowledgement restores the record
   identity, recognizes it as already visible, and acknowledges without adding
   another visible turn.
7. Two different outbound IDs carrying identical text remain two deterministic
   records and two visible turns.
8. Wrong-body and wrong-surface records never reach the callback and cannot be
   acknowledged by this desktop.
9. Overlapping timer/manual polls execute one drain; one body never processes
   the same outbound concurrently.
10. Ordinary `saveTurn`, history restore/watch, Messenger separation, echo
    suppression, handoff inbox, and existing desktop conversation behavior stay
    green.
11. The new path makes zero model/tool calls and never alters reminder text.
12. Brief 014 client tests, Brief 013 critical tests, the 116 shared regressions,
    focused desktop/conversation tests, scoped analysis, and `git diff --check`
    all pass without weakening tests.
13. A history-watcher callback that makes the same `recordId` visible while the
    durable write is awaiting causes no second render. This is proven against
    the production acceptance unit used by the shell, not a copied test helper.
14. Two different outbound IDs with identical text and timestamp remain two
    session-buffer lines; retrying the same outbound ID remains one line. The
    immutable reviewer test passes unchanged.

Any missing criterion is `FAIL` or `UNVERIFIED`, never partial.

## Required verification

Report commands, exact counts, warnings, and exit codes:

```powershell
flutter test test/kai_desktop_outbound_acceptance_test.dart test/kai_core_outbound_poller_test.dart
flutter test test/kai_core_commitment_client_test.dart
flutter test test/kai_scheduled_commitment_reviewer_test.dart test/kai_core_commitment_reviewer_followup_test.dart test/kai_core_recovery_regression_test.dart
flutter test test/conversation_store_service_test.dart test/kai_transcript_echo_guard_test.dart test/widget_test.dart
flutter test test/kai_scheduled_commitment_test.dart test/kai_core_outbound_inbox_test.dart test/kai_core_server_test.dart test/kai_attention_engine_test.dart test/kai_body_event_test.dart test/kai_headless_coordinator_test.dart test/kai_capability_broker_test.dart test/kai_surface_context_test.dart test/kai_desktop_goggles_policy_test.dart
flutter analyze lib/services/core/kai_core_client.dart lib/services/core/conversation_store_service.dart lib/screens/kai_desktop_shell.dart test/kai_desktop_outbound_acceptance_test.dart test/kai_core_outbound_poller_test.dart test/conversation_store_service_test.dart test/widget_test.dart
git diff --check
git status --short
```

If focused filenames differ, substitute them consistently and explain why.

## Failure and rollback

- Use injected fakes and temporary Core directories only. Never touch live
  Firebase conversations or the user's live Core state.
- Core outbounds remain pending on every failure before acknowledgement.
- Roll back only the Brief 015 delta; preserve accepted Brief 012–014 work,
  ratified tripwires, and unrelated dirty-worktree changes.

## Stop and report

Report files and behavior changed, exact test counts/exit codes, each criterion
as PASS/FAIL/UNVERIFIED, scope deviations, unresolved risks, rollback state, and
the smallest next Brief 012 seam.

Do not start coordinator scheduling, desktop `set_reminder`, Android, Unity,
cloud/device transport, or self-improvement work.
