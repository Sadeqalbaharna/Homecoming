# Brief 019A — Opus 5 implementation handoff

Dispatch status: **BLOCKED — relay model/security proof required**

## Entry proof required before dispatch

The callable relay must provide transport/tool metadata proving the actual
dispatched model is Opus 5 or higher, plus explicit sponsor authorization for a
write-enabled relay. A subscription plan, prompt label, direct-session model,
self-description, or UI name is insufficient. Record the exact model identifier
and metadata provenance in the completion receipt before sharing code.

## Ownership and isolation

- Claude Opus 5+ owns implementation in an isolated worktree/branch.
- Claude may edit only:
  - `scripts/tools/kai_pizza_update_pipeline.ps1`
  - `scripts/tools/kai_real_pizza_capture.ps1`
- Codex owns and must not duplicate implementation:
  - `scripts/test/test_kai_pizza_update_pipeline.ps1`
  - Briefs, source of truth, evidence adjudication, integration, Windows/live
    verification, and acceptance.
- Preserve the current draft hashes and sponsor-owned dirty tree. Return a
  commit or bounded diff; never edit the live `C:\code\homecoming_app` root.

## Outcome

Make the frozen Brief 019A acceptance suite pass without weakening any proof,
authority, privacy, or real-desktop gate.

## First repair packet

1. Make native Git failures deterministic data: capture stdout, stderr, and exit
   code without leaking a native error record through the strict parent harness.
2. Repair exact linked-worktree source binding; do not bypass commit or source
   fingerprint validation.
3. Bind both `Kai.exe` and `data/app.so` in build, runtime, and capture paths.
4. Require OS process creation after artifact binding and stable run/runtime IDs.
5. Canonical-hash the capture manifest and require an out-of-band expected
   capture binding ID.
6. Default navigation to non-mutating `attended_bound`. UI Automation invocation
   requires a fresh exact authority manifest.
7. Make allowed output root and failed-attempt ledger mandatory. Keep attempts
   cycle/PID scoped; suppress identical causal strategies even if a caller
   renames them.
8. Fail if DPI-awareness context cannot be established and record the effective
   context. Compare UIA geometry to the captured client area at target DPI.
9. Require exactly one of every title/project/legend label. Compute per-label
   height, non-uniformity, and at least 4.5:1 contrast from the captured pixels;
   reject clipping and pairwise overlap. Remove global yellow-pixel heuristics.
10. Keep synthetic/test-render fixtures `TEST_ONLY`; they can test validation
    but can never return real-desktop `PASS`.

## Non-goals and hard stops

- Do not restart, terminate, navigate, click, capture, or otherwise control PID
  27260 during implementation.
- No Firebase, credentials, network listener, deployment, publication, spend,
  external mutation, process kill, product direction, tracker-state promotion,
  Brief 020, or other repository edits.
- Do not weaken the suite to obtain green tests.

## Acceptance commands

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\test\test_kai_pizza_update_pipeline.ps1
flutter test --no-pub test/kai_delivery_box_test.dart test/kai_project_portfolio_test.dart test/kai_factory_conveyor_test.dart
```

Codex will also inspect for force-kill commands, synthetic-proof acceptance,
unbounded paths, optional authority/ledger inputs, model/network/credential
ingestion, and accidental live actions.

## Required Claude completion receipt

- relay/tool-reported model identifier and provenance;
- isolated branch/worktree and commit;
- exact files changed;
- exact commands and full pass counts;
- accepted/rejected design findings;
- unresolved risks and assumptions;
- elapsed implementation time;
- duplicate/rework performed;
- rollback command;
- explicit statement that no live process, GUI, Firebase, credential, network,
  deployment, publication, or external action occurred.

Stop after the scoped commit and report to Codex. Codex independently reviews,
runs acceptance, and either accepts or issues one focused repair packet.
