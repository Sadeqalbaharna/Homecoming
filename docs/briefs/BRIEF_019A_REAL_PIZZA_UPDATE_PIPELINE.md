# Brief 019A — Real Pizza update evidence pipeline

Owner: Homecoming Kai
Reviewer: supervising Kai
Status: BLOCKED — acceptance suite frozen; Claude coding model ineligible

## Goal

Make a governed Pizza tracker delta repeatable from machine-readable intake to a
bound real Windows HUD proof, while making it impossible for a synthetic or
test-rendered screenshot to satisfy real-desktop acceptance.

## Why this is next

The 2026-08-09 reconciliation reached the real HUD, but manual evidence parsing,
wrapper-level test retries, stale artifact binding, DPI/capture variants, and
synthetic screenshot detours consumed time and weakened auditability. The
accepted outcome needs a reusable fail-closed path before another tracker delta.

## Entry gate

- Tracker reconciliation commit `7da67235` exists on
  `codex/homecoming-kai-claude-partnership`.
- PID 27260 remains running and must not be restarted or controlled in this
  local-only implementation phase.
- No live service, Firebase mutation, credential, deployment, publication, or
  production action is authorized.

## In scope

- A versioned JSON tracker-delta contract with stable evidence identities.
- Fail-closed validation of Git commits, file hashes, proof states, sponsor
  ownership, and promotion requests.
- Deterministic focused-test selection and Windows build/run binding plans.
- An explicit graceful room/coordinator handover gate.
- A real-window capture manifest and validator covering PID/path/hash, build
  binding, direct-window capture, DPI, clipping, overlap, contrast/readability
  signals, cycle time, and failed-attempt fingerprints.
- Deterministic fixtures for valid intake and every material refusal.
- Documentation of manual steps removed and the remaining attended gates.

## Out of scope

- No restart, process termination, tray action, GUI navigation, screenshot
  capture, Firebase access, credential use, deployment, publication, spending,
  or external mutation during this brief.
- No synthetic renderer, Flutter golden, test widget, mock window, or composited
  image may become real-desktop evidence.
- No automatic proof promotion, phase advancement, sponsor decision, Assembly
  authorization, or product-direction change.
- Do not start Brief 020 or modify Factory, Hoard, Kingdom, or TikTok repositories.

## Invariants

- Canonical Pizza state remains under `KaiLayer`; intake is evidence, not a
  second mutable authority.
- A reported commit that cannot be resolved is `UNVERIFIED`.
- Sponsor/live/security/destructive boundaries stop immediately.
- Build success is not runtime binding; runtime binding is not visual proof;
  visual proof is not product-phase acceptance.
- Real-desktop proof requires a direct native-window capture bound to one live
  process and one exact build. A protocol success or image file alone is
  insufficient.
- Identical failed capture fingerprints are suppressed; a retry must change the
  causal strategy.

## Authoritative evidence to inspect

- `docs/NORTHSTAR_SOURCE_OF_TRUTH.md`
- `lib/services/core/kai_delivery_box.dart`
- `lib/services/core/kai_delivery_box_catalog.dart`
- `lib/services/core/kai_project_service.dart`
- `scripts/test/bind_kai_reminder_acceptance_artifact.ps1`
- `scripts/test/kai_reminder_runtime_acceptance.ps1`
- `docs/evidence/REAL_KAI_DPI_SELECTION_RETRY_2026-08-09.png`

## Procedure

1. Validate the delta schema, identity uniqueness, evidence roots, hashes, Git
   objects, requested states, authority owners, and source-of-truth references.
2. Emit a deterministic plan: focused tests, Windows build command, build
   binding output, live actions, sponsor gates, and exact stop reasons.
3. Bind a completed build to source/root/executable/payload hashes and time.
4. Before any future live handover, require a fresh authority ID and a supported
   graceful-shutdown contract for both room and coordinator. Missing support is
   a hard stop, never a force-kill fallback.
5. Bind any future HUD capture to process identity, build binding, HWND, direct
   capture method, client geometry, DPI, navigation target, file hash, semantic
   labels, and computed pixel/layout assertions.
6. Record cycle start/end, failed capture fingerprints, strategy changes, and
   removed manual steps in the evidence receipt.

## Pass criteria

- Invalid/missing Git or file identity fails before promotion planning.
- Sponsor-owned or live-bound claims cannot be auto-verified.
- Focused tests are selected deterministically from changed projects/surfaces.
- Build and runtime binding are separate and fail closed on any path/hash/time
  mismatch.
- Live handover/navigation/capture cannot run without current explicit authority.
- Synthetic/test-render captures cannot return a real-desktop PASS.
- Real capture validation rejects wrong PID/path/hash, non-direct capture,
  missing title/project/legend labels, clipping, overlap, low contrast, stale
  build binding, and repeated identical failure fingerprints.
- Focused deterministic fixtures pass.

## Required verification

- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test/test_kai_pizza_update_pipeline.ps1`
- Existing focused Pizza controller tests.
- Static inspection confirming no force-kill, Firebase, credential, deployment,
  publication, or synthetic-capture acceptance path.

## Failure and rollback

- Preserve every failed receipt and its fingerprint.
- Do not retry an identical fingerprint without a changed strategy ID.
- Roll back by reverting the scoped Brief 019A commit. The current running app
  and all external services are untouched by this implementation.

## Stop and report

Stop after local scripts, fixtures, tests, documentation, and a reversible
commit. Report exact files, tests, cycle metrics, failed fingerprints, DPI
contract, sponsor gates, manual steps removed, proof matrix, and the smallest
attended authority needed to exercise the real capture path. Do not exercise
that live path in this brief.
