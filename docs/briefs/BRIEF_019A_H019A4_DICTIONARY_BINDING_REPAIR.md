# Brief 019A H019A-4 — Dictionary-safe capture binding repair

Owner: verified Claude Opus 5 implementation relay
Reviewer: Codex / Homecoming Kai
Status: READY

## Goal

Make frozen acceptance case 7 return its deterministic PASS receipt so Brief
019A reaches exactly 10/14, with only Brief 019B capture cases 10-13 failing.

## Entry gate

- H019A-3 independent result is 9 PASS / 5 FAIL.
- First causal failure is the one-argument `.Contains($Name)` call at
  `scripts/tools/kai_pizza_update_pipeline.ps1:138`.
- PID 27260 and live services remain locked.

## In scope

- Modify only `scripts/tools/kai_pizza_update_pipeline.ps1`.
- Normalize key lookup across the actual dictionary/ordered-dictionary shapes
  used by the frozen capture fixture.
- Preserve the one canonical capture-binding serialization expected by
  `Get-CaptureBinding` in the frozen test.
- Return deterministic receipts rather than unhandled exceptions.

## Out of scope

- Do not modify the frozen acceptance suite.
- Do not modify `scripts/tools/kai_real_pizza_capture.ps1`.
- Do not repair or weaken cases 10-13; they belong to Brief 019B.
- No process control, GUI action, Firebase, credential, network, deployment,
  build, screenshot, or live-service action.

## Invariants

- Test-only capture evidence still requires its out-of-band pin.
- Unknown/missing keys fail closed.
- No additional serialization guess or broad dual-form tolerance is allowed.
- Sponsor, live, privacy, output-root, and synthetic-proof gates remain intact.

## Required verification

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\test\test_kai_pizza_update_pipeline.ps1
```

## Pass criteria

- Case 7 passes with a deterministic receipt.
- Overall result is exactly 10 PASS / 4 FAIL.
- The only failures are cases 10-13.
- No file outside the one allowed path changes.

## Failure and rollback

On any different failure fingerprint, stop and report it without widening
scope. Preserve the H019A-3 file as the rollback input; do not commit.

## Stop and report

Return the tool-reported model identifier, session, exact file SHA-256, diff,
test output, risks, and rollback. Do not start Brief 019B.
