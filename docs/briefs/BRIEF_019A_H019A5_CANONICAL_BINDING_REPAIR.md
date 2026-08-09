# Brief 019A H019A-5 — Canonical capture-binding repair

Owner: verified Claude Opus 5 implementation relay
Reviewer: Codex / Homecoming Kai
Status: BLOCKED — provider session limit until 21:30 Bahrain

## Goal

Make frozen acceptance case 7 compute the single canonical capture binding so
Brief 019A reaches exactly 10/14 and only Brief 019B cases 10-13 remain failing.

## Entry gate

- H019A-4 independent result is 9 PASS / 5 FAIL.
- Case 7 computed binding is
  `886fee001cbdeb9a9553ca8f9e306bf2fa963d1a33c034526a0d862434144e72`.
- Declared and frozen expected binding is
  `4638daf62b324338006e11badfe1296416f083799130cf8165e46233861c341a`.
- PID 27260 and live services remain locked.

## In scope

- Modify only `scripts/tools/kai_pizza_update_pipeline.ps1`.
- Inspect the frozen test's exact `Get-CaptureBinding` field serialization and
  canonical label order.
- Make the validator compute that one canonical form exactly.

## Out of scope

- Do not modify the frozen test oracle.
- Do not add alternate serializations or tolerant fallback hashes.
- Do not modify `scripts/tools/kai_real_pizza_capture.ps1` or cases 10-13.
- No process control, GUI, Firebase, credentials, build, deployment,
  screenshot, or live-service action.

## Pass criteria

- Case 7 passes.
- Overall frozen-suite result is exactly 10 PASS / 4 FAIL.
- Only cases 10-13 fail.
- No file outside the one allowed path changes.

## Required verification

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\test\test_kai_pizza_update_pipeline.ps1
```

## Failure and rollback

On a different fingerprint, preserve the receipt and stop without widening
scope. The pre-H019A-5 SHA-256 is
`922AA2669CC3728430C04A777015F746E0BACC748E850E2FADB38C32A1D08D61`.

## Stop and report

Return model metadata, session, exact diff and SHA-256, frozen-suite output,
risks, and rollback. Do not start Brief 019B.
