# Brief 024 — Proactive subject and Desktop room singleton repair

Owner: Homecoming implementation
Reviewer: Codex PM/architect
Status: TESTED / BOUND LIVE; OVERNIGHT UNVERIFIED

## Goal

One semantic proactive subject can produce at most one unattended message per
silence episode, no proactive reply can be persisted after Bahrain quiet hours
begin, and only one Desktop Homecoming room can run at a time.

## Why this is next

Sponsor-observed overnight transcript evidence invalidated Brief 023's behavior
claim. The rebuilt Core is healthy, but generic check-ins still lack durable
subject identity, the final persistence boundary does not re-check quiet hours,
and two Desktop room processes were observed concurrently.

## Entry gate

- Sponsor authorized the repair on 2026-08-15.
- Entry Core PID 47400 was bound to the prior isolated Release artifact.
- Existing sponsor-owned worktree changes are preserved.

## In scope

- Stable identities for every proactive subject composed by
  `KaiProactiveService`.
- Cross-kind deduplication by semantic subject rather than generated wording.
- A final quiet-hours check after model generation and before any transcript or
  body delivery is persisted.
- A Windows single-instance mutex for the visible Desktop room, separate from
  the coordinator mutex.
- Focused and proportional regression coverage, isolated Release build, and
  exact local runtime binding.

## Out of scope

- Deleting or rewriting existing conversation history.
- Changing Kai's personality, product direction, reminder policy, Firebase
  data, credentials, deployment, publishing, spending, or unrelated UI.

## Invariants

- Bahrain quiet hours remain 22:00–08:00.
- Direct user replies and due commitments are not reclassified as ordinary
  proactive chatter.
- One silence episode can be acknowledged again only after genuine user
  activity creates a new episode identity.
- Existing Core state and unrelated work remain recoverable.

## Authoritative evidence to inspect

- `lib/services/core/kai_proactive_service.dart`
- `lib/services/attention/kai_proactive_attention_queue.dart`
- `lib/services/core/kai_headless_coordinator.dart`
- `windows/runner/main.cpp`
- focused proactive, coordinator, and Windows runner tests
- `%LOCALAPPDATA%\Homecoming\KaiCore\operations\kai-operations.jsonl`

## Procedure

1. Bind every generated proactive option to a semantic source identity.
2. Deduplicate that identity across wording and nudge kind.
3. Re-check quiet hours after generation, before persistence or body dispatch.
4. Reject a second visible Desktop room process at the native runner boundary.
5. Run focused and shared Core/coordinator regressions.
6. Build an isolated Windows Release and bind only the exact Homecoming
   processes required for acceptance.

## Pass criteria

- Paraphrases and cross-kind variants of one subject cannot stack or redeliver.
- Check-in and companionship variants from one silence episode share identity;
  genuine later user activity creates a different identity.
- A model call crossing 22:00 Bahrain cannot write or dispatch its reply.
- A second visible Desktop room exits without mounting another Flutter room.
- Focused and proportional tests and Release build pass.
- Exact rebuilt Core/watchdog/room identities are observed live.

## Required verification

- Proactive queue/topic/privacy/coordinator focused tests.
- Core/coordinator shared regressions.
- Windows Release build.
- Live process identity and bounded journal evidence.
- Full overnight behavior remains `UNVERIFIED` until the next quiet-hours
  observation window completes.

## Failure and rollback

Build to a new isolated directory. Retain the current
`build-core-stability` artifact and its process/hash evidence as rollback. Do
not clean or discard sponsor-owned changes.

## Acceptance result — 2026-08-15

- Focused proactive/queue/coordinator/native-room suite: 47/47 PASS.
- Proportional Core/conversation/commitment suite: 115/115 PASS.
- Scoped Flutter analysis: PASS, no issues.
- Isolated Windows Release build: PASS at `build-proactive-stability`.
- Accepted `Kai.exe` SHA-256:
  `58148A9B2C22E10483F0E3EADEEB12984C6ED0FFDCBE171527D185601FA92193`.
- Accepted `data/app.so` SHA-256:
  `2B2A57603E6E65072C86D59E0561BCCA141AF0EA6EE8497C32B3780A68F09206`.
- Live Core PID 5644, watchdog PID 10460, and Desktop room PID 55640 all
  execute from the accepted Release root.
- A second room launch (PID 47944) exited before mounting Flutter; one visible
  room remained.
- Durable attention primary and backup hashes were unchanged across handover.
- Post-start journal records Core healthy, attention state loaded, and
  coordinator ready with no post-start warning/error or proactive delivery.
- Full 22:00–08:00 Bahrain behavior remains `UNVERIFIED` until an overnight
  observation window completes.

## Stop and report

Report files, behavior, exact tests, build/runtime identity, process changes,
PASS/FAIL/UNVERIFIED, rollback, and the next overnight acceptance action. Do
not begin another Northstar phase.
