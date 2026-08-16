# Brief 011 — Kingdom joins the governed desktop portfolio

Owner: Codex implementation team  
Reviewer: Overlord Kai / Northstar project manager  
Status: TESTED — ATTENDED DESKTOP ACCEPTANCE PENDING

## Goal

Homecoming Desktop shows Kingdom beside Homecoming and Hoard using Kingdom's
own frozen roadmap, active phase, proof state, blockers, and flowchart.

## Why this is next

Kingdom is an active product repository but is invisible in the operating
portfolio. The existing generic registration API would begin it without an
approved roadmap; a governed built-in seed is required so the desktop never
invents progress from files or commits.

## Entry gate

- Inventory all three repositories and preserve their dirty worktrees.
- Read each project's authoritative source of truth.
- Create Kingdom's source of truth before encoding its frozen phases.

## In scope

- Add Kingdom's six governed phases and evidence baseline.
- Seed/reconcile a visible `kingdom_northstar` project on desktop startup.
- Correct Hoard's stale baseline/blockers to match its governing document.
- Extend focused tests for project IDs, phase order, acceptance, and honest
  Kingdom proof.
- Update Homecoming's evidence index and active portfolio record.

## Out of scope

- Editing Kingdom application behavior, Firebase state, rules, or deployments.
- Marking any Kingdom phase accepted.
- Changing Homecoming's active Northstar phase.
- Changing Hoard product code or accepting its open authorization phase.
- Broad desktop visual redesign.

## Invariants

- Each project remains governed by its own source of truth.
- No phase is accepted from code existence, commits, percentages, or builds.
- Reconciliation preserves mutable RTDB evidence and assessment state.
- Opening a project flowchart never switches the coding workspace.
- Existing Smarter and Sentience data remains intact and hidden from the
  portfolio rail.

## Authoritative evidence to inspect

- `C:\code\Kingdom\docs\PROJECT_SOURCE_OF_TRUTH.md`
- `C:\code\Hoard\docs\PROJECT_SOURCE_OF_TRUTH.md`
- `C:\code\homecoming_app\docs\NORTHSTAR_SOURCE_OF_TRUTH.md`
- `lib/services/core/kai_project_service.dart`
- `lib/screens/kai_desktop_shell.dart`
- `test/kai_project_portfolio_test.dart`
- `test/kai_project_flowchart_service_test.dart`

## Procedure

1. Encode Kingdom phases verbatim from its governing roadmap.
2. Give every phase one binary exit gate and an evidence-grounded baseline.
3. Seed Kingdom beside Homecoming and Hoard on startup.
4. Correct Hoard evidence that has drifted behind its own document.
5. Extend focused tests and run formatting, analysis, and regression checks.
6. Stop after the portfolio change and report attended UI evidence separately.

## Pass criteria

- Kingdom is a visible built-in project with repository and source paths.
- Kingdom has exactly phases 0–5 in governed order, Phase 0 active, and zero
  accepted phases.
- Kingdom's visible proof state is `Wired`, not complete or verified live.
- Kingdom blockers state the missing rules/tests and unsafe authority paths.
- Homecoming and Hoard remain present and retain their governed phase counts.
- Hoard's baseline reflects the current 130 Firestore tests, 22 Storage tests,
  deployed Firestore rules, and blocked receipt migration—not the stale
  same-org rule failure.
- Existing legacy project IDs and backward-compatible reads remain intact.
- Focused tests and analysis pass.
- An attended desktop check, if performed, confirms all three cards and that
  flowchart opening does not switch workspace.

Any missing criterion is `FAIL` or `UNVERIFIED`, not partial completion.

## Required verification

```powershell
flutter test test/kai_project_portfolio_test.dart
flutter test test/kai_project_flowchart_service_test.dart
flutter test test/widget_test.dart
dart analyze lib/services/core/kai_project_service.dart lib/screens/kai_desktop_shell.dart test/kai_project_portfolio_test.dart
git diff --check
git status --short
```

## Failure and rollback

No Firebase records are deleted or migrated. Roll back by removing the Kingdom
seed/call and restoring the prior Hoard seed metadata; preserve all RTDB records
and every user-owned dirty file.

## Stop and report

Report files changed, phase definitions, evidence changes, exact test results,
runtime evidence, unresolved risks, rollback path, and verdict. Do not begin
Kingdom ledger implementation or broader Homecoming polish.

## Reviewer checkpoint — 2026-08-08

Verdict: **AUTOMATED PASS; ATTENDED DESKTOP EVIDENCE UNVERIFIED**.

- Focused Flutter run: 26/26 tests passed across the portfolio, flowchart, and
  desktop widget regression files.
- Scoped Dart analysis completed with no errors. It reports three existing
  shell warnings and ten informational lints outside this brief.
- `git diff --check` passed for Homecoming and Kingdom; line-ending warnings on
  pre-existing dirty files do not identify whitespace errors.
- Kingdom has six frozen phases, Phase 0 active, zero accepted phases, and a
  `Wired` project proof state.
- Hoard's seed now matches its 2026-08-08 governing evidence: Firestore rules
  deployed with 130/130 tests, Storage contract at 22/22 tests, and receipt
  migration still blocking deployment.

Still `UNVERIFIED`: a reviewer has not observed the three cards, Kingdom's
flowchart, live RTDB refresh, or workspace non-mutation in the running Windows
desktop app. Do not promote this slice to `Verified live` until that attended
check is recorded.
