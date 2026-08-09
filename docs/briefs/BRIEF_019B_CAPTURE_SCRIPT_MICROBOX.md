# Brief 019B — Real Pizza capture-script repair

Owner: verified Claude Opus 5 implementation relay
Reviewer: Homecoming Codex PM
Status: READY AFTER BRIEF 019A PIPELINE ACCEPTANCE

## Goal

Make one authority-gated native Windows capture command produce a fail-closed,
cryptographically bound real-Pizza evidence manifest that cannot be confused
with synthetic, stale-runtime, clipped, overlapping, or unreadable proof.

## Why this is next

`kai_pizza_update_pipeline.ps1` establishes the evidence and binding contract.
The capture tool is the next dependency because its current draft still permits
optional retry/output controls, mutating navigation by default, silent DPI
failure, and incomplete payload/freshness binding.

## Entry gate

- Brief 019A pipeline repair is handed off at a stable SHA/commit.
- `scripts/test/test_kai_pizza_update_pipeline.ps1` passes every case without
  weakening assertions.
- Codex independently accepts the pipeline path, build/runtime contract,
  synthetic refusal, and sponsor/live stops.
- The capture file's pre-change SHA-256 is recorded as
  `78CB5A6846133C569046DCF7AD86BEC6702493B88AE906C3598BCCABBAA4A934`.
- PID 27260 and live services remain untouched.

## Allowed path

Claude may edit exactly:

- `scripts/tools/kai_real_pizza_capture.ps1`

Claude must not edit the pipeline, tests, briefs, evidence, application code,
build output, or any other path.

## In scope

- Default to non-mutating `attended_bound`; UI Automation invocation requires a
  fresh, exact, unexpired authority manifest.
- Make allowed output root and failed-attempt ledger mandatory and fail closed.
- Bind PID, HWND, governed root, exact `Kai.exe`, exact `data/app.so`, build ID,
  runtime ID, run ID, and OS process creation after artifact binding.
- Establish and verify DPI-awareness before geometry calls; record effective
  context and target-window DPI.
- Compare exactly one required title/project/legend label apiece against client
  coordinates, not virtualized window coordinates.
- Compute per-label height, pixel non-uniformity, and at least 4.5:1 contrast;
  reject clipping and overlap.
- Direct native-window capture only. Canonical-hash the complete manifest and
  emit an out-of-band capture binding ID.
- Keep failure fingerprints cycle/PID/causal-strategy scoped and suppress an
  identical retry even if the caller renames the strategy.

## Out of scope

- No process restart, termination, tray interaction, UI navigation, screenshot
  execution, Firebase, credentials, network, deployment, publication, spend,
  external action, or live-service access during implementation.
- No synthetic renderer, Flutter golden, mock window, compositing, screen-wide
  capture, force-kill fallback, or optimistic proof default.
- No test changes and no weakening the frozen acceptance suite.

## Invariants

- A PNG is not proof without exact build, runtime, window, geometry, manifest,
  and out-of-band binding identities.
- `Kai.exe` equality alone is insufficient; `data/app.so` is authoritative.
- Build success is not runtime freshness, and capture success is not tracker
  phase acceptance.
- Any missing authority, root, hash, PID, time, DPI, label, or binding aborts.

## Authoritative evidence to inspect

- `docs/briefs/BRIEF_019A_REAL_PIZZA_UPDATE_PIPELINE.md`
- `docs/briefs/BRIEF_019A_OPUS5_IMPLEMENTATION_HANDOFF.md`
- `scripts/tools/kai_pizza_update_pipeline.ps1`
- `scripts/tools/kai_real_pizza_capture.ps1`
- `scripts/test/test_kai_pizza_update_pipeline.ps1`
- `docs/evidence/PIZZA_UPDATE_PIPELINE_ACCEPTANCE_2026-08-09.md`

## Procedure

1. Record the entry SHA and inspect the accepted pipeline contract.
2. Repair only the allowed capture file.
3. Parse-check it before running model-free fixtures.
4. Run the frozen pipeline acceptance suite; diagnose the first causal failure
   rather than weakening the suite.
5. Statically prove absence of process-kill, Firebase, credential, network,
   deployment, synthetic-proof, and unbounded-output paths.
6. Stop without invoking the capture command against a real process.

## Pass criteria

- The frozen acceptance suite passes all cases.
- Omitted authority, output root, ledger, build/runtime binding, payload hash,
  freshness, DPI, label, or out-of-band binding fails closed.
- Duplicate labels and identical causal retries fail.
- Synthetic/test fixtures can return only `TEST_ONLY`, never real `PASS`.
- Default invocation cannot navigate or control a GUI.
- Only the allowed file changed; PID 27260 and live services were untouched.

## Required verification

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\test\test_kai_pizza_update_pipeline.ps1
flutter test --no-pub test/kai_delivery_box_test.dart test/kai_project_portfolio_test.dart test/kai_factory_conveyor_test.dart
```

Codex reruns both independently and reviews every changed line.

## Failure and rollback

- Preserve the prior SHA and every failed fingerprint.
- Roll back only the allowed file to its recorded entry version.
- Do not retry an identical causal strategy or touch the live app to diagnose a
  fixture failure.

## Stop and report

Return tool-reported model metadata, allowed-path enforcement receipt, exact
diff/commit, tests and counts, accepted/rejected findings, risks, elapsed time,
duplicate/rework cost, rollback, and confirmation that no live action occurred.
Do not start attended desktop capture.
