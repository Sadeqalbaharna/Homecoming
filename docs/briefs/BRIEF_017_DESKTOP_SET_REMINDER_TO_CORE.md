# Brief 017 — Desktop `set_reminder` creates a Central Core commitment

Owner: Claude implementation team

Reviewer: Northstar project manager

Status: ACCEPTED / TESTED / WIRED — LIVE WALKTHROUGH DEFERRED

Parent phase: Brief 012 durable scheduled commitment vertical slice

## Goal

When Kai uses `set_reminder` from the desktop goggles-on workbench, the tool
creates one deterministic, exact-text Central Core commitment using Bahrain
wall time. Android continues to invoke its existing native reminder plugin.

## Why this is next

Briefs 013–016 now prove every downstream stage: durable Core ownership,
client transitions, coordinator attention/routing, exact desktop inbox,
transcript persistence, and acknowledgement. The only missing code seam in the
vertical slice is creation from the real desktop tool path.

## Entry gate

- Brief 016 is accepted: 18/18 criteria, 43/43 focused, 109/109 critical, and
  116/116 shared tests with clean scoped analysis.
- Capture `git status --short` and preserve the dirty shared worktree.
- Reproduce the desktop tool-manifest tests, scheduled-commitment domain tests,
  Core client tests, and Brief 016 focused gate before editing.
- Inspect the final request-specific tool manifest, not only the global schema
  list; `set_reminder` must reach the actual desktop model request.

## In scope

- Offer `set_reminder` on the desktop goggles-on workbench while keeping every
  other native device action filtered there.
- Preserve the existing GPT-facing arguments: exact `message`, `year`, `month`,
  `day`, `hour`, and `minute`.
- On desktop only:
  - validate non-empty exact message and integer calendar components;
  - interpret them explicitly as Bahrain UTC+03:00 using
    `KaiScheduledCommitment.bahrainWallToUtc`;
  - reject invalid or already-past instants honestly;
  - derive the commitment ID with
    `KaiScheduledCommitment.deterministicId`;
  - generate canonical wall provenance with `wallClockLabel` and offset 180;
  - call `KaiCoreClient.createCommitment` and await its durable success; and
  - report success only from the accepted stored record.
- On Android/mobile, retain `_invokeAndroid('setReminder', args)` unchanged in
  behavior and arguments.
- Extract a narrow testable production reminder-tool unit or inject the Core
  client/platform seam into `ToolExecutorService` as needed. Tests must execute
  the production path rather than copy its conversion and ID algorithm.

## Out of scope

- Coordinator, attention, Core server/schema, desktop outbound receiver,
  conversation storage, Android plugin implementation, notification UI,
  recurring/cancel/snooze reminders, natural-language date parsing, Messenger,
  AR, VR, Unity, or attended live-state testing.
- General tool-executor cleanup or redesign.
- Changing reminder text, generating delivery wording, or inferring timezone
  from the host machine.

## Invariants

- Desktop and Android have one GPT tool name but platform-authoritative
  execution paths. Desktop never calls the missing Android plugin; Android
  never depends on loopback Core for its existing native reminder behavior.
- Exact reminder text is stored and later delivered byte-for-byte. Trimming may
  validate emptiness and normalize identity, but must not rewrite stored text.
- The same persona, exact intent, and UTC instant always reach the same ID.
- A retry after an uncertain response is idempotent; it cannot create a second
  commitment.
- Bahrain wall time is explicit provenance. Host-local timezone is irrelevant.
- Invalid, malformed, empty, or past requests create no Core record and return
  an honest failure; no success language is emitted before Core confirms.
- `set_alarm`, `set_timer`, calendar, phone, messaging, navigation, media,
  notification, and screen tools remain unavailable on desktop.
- Messenger remains goggles-off and receives neither this tool nor technical
  posture.
- Tests use temporary Core state only and never touch the user's live ledger.

## Authoritative evidence

- `docs/briefs/BRIEF_012_DURABLE_SCHEDULED_COMMITMENT_VERTICAL_SLICE.md`
- `docs/briefs/BRIEF_013_CORE_COMMITMENT_INTEGRITY_REPAIR.md`
- `docs/briefs/BRIEF_014_COMMITMENT_CLIENT_AND_DEFERRAL_CONTRACT.md`
- `docs/briefs/BRIEF_016_COORDINATOR_DUE_COMMITMENT_LOOP.md`
- `lib/services/core/tool_executor_service.dart`
- `lib/services/core/kai_scheduled_commitment.dart`
- `lib/services/core/kai_core_client.dart`
- `lib/services/core/kai_surface_context.dart`
- existing tool-manifest, route, commitment, and goggles-policy tests

## Permitted files

- Modify `lib/services/core/tool_executor_service.dart` and its directly
  relevant existing tests.
- Add one narrowly named desktop reminder production unit under
  `lib/services/core/` and matching focused tests if extraction is needed.
- Modify `lib/services/core/kai_core_client.dart` only for a narrow injection
  seam that does not change accepted wire behavior; report why.
- Do not modify Core server/ledger, scheduler/loop/coordinator, attention,
  desktop shell, Android host/plugin code, conversation storage, Briefs
  012–017, or the Northstar source of truth.
- Stop with `BLOCKED_BY_SCOPE` before touching another file.

### PM-ratified scope amendments

- `lib/services/core/tool_policy_service.dart` is ratified for the single
  `set_reminder` change from `androidOnly: true` to `false`. That flag is an
  enforced desktop gate, so leaving it true would expose the tool and then
  reject its real desktop implementation. No other policy entry may change.
- For the exact-text repair only, `lib/services/core/kai_core_server.dart` and
  directly relevant commitment tests are permitted. Do not change the global
  `_requiredString` behavior: identifiers, persona, provenance, and unrelated
  Core fields must retain their accepted canonicalization.
- `ToolCapability.phone` on `set_reminder` is currently descriptive rather
  than an authorization gate. Its naming is cleanup debt, not permission to
  broaden this brief into a capability-model redesign.

## Required platform contract

```text
set_reminder(message, Bahrain wall components)
  desktop goggles-on
    -> deterministic Core commitment
    -> await durable Core response
  Android/mobile
    -> existing setReminder MethodChannel call
  Messenger/AR/VR/goggles-off
    -> tool absent from request manifest
```

The branch comes from trusted platform/surface authority, never model
arguments. A caller cannot claim `platform: android` or `surface: desktop`.

## Procedure

1. Reproduce entry gates and trace schema → route filtering → request manifest
   → `execute` → platform branch.
2. Write failing tests against the production path for desktop manifest,
   conversion/provenance, deterministic retry, exact text, Core failure,
   invalid/past input, and mobile target selection.
3. Implement the smallest platform split and Core-backed desktop creation.
4. Prove unrelated desktop-native tool filtering and goggles/surface policy did
   not loosen.
5. Run all gates and stop. Do not perform a live reminder walkthrough.

## Pass criteria

1. The final desktop goggles-on request manifest contains `set_reminder`.
2. The final Messenger, AR, VR, and goggles-off manifests do not gain it.
3. Other Android-only tools remain absent from desktop.
4. A valid Bahrain wall time produces the exact expected UTC instant, canonical
   wall label, offset 180, persona `truekai`, exact text, and deterministic ID
   in one temporary Core record.
5. Repeating the same call returns the same record and leaves one commitment.
6. Different text or due instant produces a different deterministic ID.
7. Empty message, non-integer/missing fields, impossible date, invalid hour or
   minute, and past instant create no record and return honest failure.
8. Core unavailable, timeout, rejection, or persistence failure cannot produce
   a success receipt or local success claim; retry remains safe.
9. Desktop execution makes no MethodChannel call.
10. Android target selection retains the exact existing `setReminder` method
    and unmodified argument map; no Core call is attempted.
11. Tool policy, trace receipts, and outcome classification continue to observe
    the real result through `ToolExecutorService.execute`.
12. Existing Android-only filtering, goggles, route, tool-awareness, scheduled
    commitment, Core client, Brief 016, and shared tests remain green.
13. Scoped analysis introduces no diagnostics and `git diff --check` passes.
14. Commitment admission validates `text.trim().isNotEmpty` but stores and
    returns the original string unchanged, including leading/trailing
    whitespace, line breaks, and Unicode; the 2000-character limit applies to
    that exact stored string. Whitespace-only text is still rejected, and
    unrelated Core string fields retain their existing normalization.

Any missing criterion is `FAIL` or `UNVERIFIED`, never partial.

## Required verification

Report exact commands, counts, diagnostics, and exit codes:

```powershell
flutter test test/kai_desktop_set_reminder_test.dart
flutter test test/kai_desktop_reminder_exact_text_reviewer_test.dart test/kai_desktop_set_reminder_test.dart
flutter test test/tools_for_route_test.dart test/kai_desktop_goggles_policy_test.dart test/kai_capability_broker_test.dart test/kai_surface_context_test.dart
flutter test test/kai_scheduled_commitment_test.dart test/kai_core_commitment_client_test.dart
flutter test test/kai_due_commitment_presence_wake_reviewer_test.dart test/kai_due_commitment_loop_test.dart test/kai_due_commitment_coordinator_test.dart test/kai_headless_coordinator_test.dart
flutter test test/kai_scheduled_commitment_test.dart test/kai_core_outbound_inbox_test.dart test/kai_core_server_test.dart test/kai_attention_engine_test.dart test/kai_body_event_test.dart test/kai_headless_coordinator_test.dart test/conversation_store_service_test.dart test/kai_capability_broker_test.dart test/kai_surface_context_test.dart test/kai_desktop_goggles_policy_test.dart
flutter analyze <every production and test file changed by Brief 017>
git diff --check
git status --short
```

If focused filenames differ, substitute consistently and explain why.

## Failure and rollback

- Use only temporary Core directories and injected clients/channels.
- A failed desktop creation leaves no local shadow reminder or success receipt.
- Roll back only Brief 017 files; preserve accepted Briefs 012–016 and every
  unrelated dirty-worktree edit.

## Stop and report

Report files/behavior changed, exact platform branch, stored record fields,
criterion-by-criterion verdicts, commands/counts, scope deviations, unresolved
risks, and rollback state.

Do not start attended live reminder acceptance, recurring reminders, Android
redesign, Messenger delivery, AR/VR/Unity, or self-improvement work.

## PM review of the first Brief 017 report — repair required

The platform split, desktop manifest, deterministic Bahrain conversion,
idempotent Core creation, Android preservation, and regression evidence are
provisionally accepted. The reported implementation is not accepted as a
whole because criterion 4 and the exact-text invariant are false at the Core
boundary.

Independent production-path evidence:

- Claude's focused Brief 017 suite: 13 passing.
- Immutable PM exact-text reviewer plus that suite: 13 passing, 1 failing,
  exit code 1.
- Expected stored text:
  `"  Ring Ahmed\nabout the gas line — 2× before 9:00  "`.
- Actual stored text loses both outer spaces because commitment admission uses
  the globally trimming `_requiredString` helper.

Required repair:

1. Preserve the current platform/tool implementation; do not redesign it.
2. At commitment admission only, require a string, use `trim()` solely to
   reject empty/whitespace-only input, enforce the length limit against the
   original value, and store the original value byte-for-byte.
3. Do not loosen or change global string validation for any other Core field.
4. Strengthen the existing Brief 017 test so it expects outer whitespace to
   survive instead of documenting Core trimming as acceptable.
5. Make
   `test/kai_desktop_reminder_exact_text_reviewer_test.dart` pass unchanged,
   then rerun the Brief 013 Core integrity gates, Brief 017 gates, shared
   regressions, scoped analysis, and `git diff --check`.

Brief 017 remains open until all 14 criteria pass. Do not begin the attended
end-to-end reminder walkthrough before PM acceptance.

## PM review of the exact-text repair — behavior accepted, lint repair required

Independent PM verification accepts the behavioral repair:

- immutable exact-text reviewer plus Brief 017 suite: 16/16 passing;
- Brief 013 integrity reviewers plus the shared regression set: 144/144
  passing; and
- `git diff --check`: passing, with line-ending notices only.

Criterion 13 remains `FAIL`. Scoped analysis exits 1 with six diagnostics.
Five are pre-existing in `tool_executor_service.dart`; one is introduced by
the new production file:

```text
lib/services/core/kai_desktop_reminder_tool.dart:155:7
curly_braces_in_flow_control_structures
```

Required final repair: add braces around the `if (value is num)` branch in
`KaiDesktopReminderTool._integer`. Do not alter conversion behavior, suppress
the lint, reformat unrelated code, or begin another feature. Rerun scoped
analysis and report its output in baseline-versus-delta terms. Brief 017 is
accepted only when the changed files introduce zero diagnostics and all prior
behavioral gates remain green.

## Final PM acceptance

The braces-only repair changed no behavior and closes criterion 13.

- Immutable reviewer plus Brief 017 focused suite: **16/16 PASS**, exit 0.
- Six-file scoped analysis: reduced from six diagnostics to the five
  pre-existing diagnostics in `tool_executor_service.dart`; no Brief 017
  diagnostic remains.
- Changed production file analysis:
  `kai_desktop_reminder_tool.dart` reports **No issues found**, exit 0.
- `git diff --check` for the repair and governing documents: PASS, exit 0.
- Previously independently reproduced Core-integrity/shared gate: **144/144
  PASS**.

All 14 criteria are `PASS`. Brief 017 is **ACCEPTED / TESTED / WIRED**. This
does not claim `VERIFIED LIVE`: the attended restart and exactly-once desktop
reminder walkthrough is the next separate gate and was not started here.
