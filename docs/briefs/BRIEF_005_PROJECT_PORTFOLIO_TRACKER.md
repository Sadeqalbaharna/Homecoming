# Brief 005 — Real project portfolio on Homecoming Desktop

Owner: Claude implementation team or a separate UI implementation team

Reviewer: Northstar project manager

Status: TESTED — ATTENDED DESKTOP ACCEPTANCE PENDING

## Goal

Replace the two fixed Kai-improvement project cards in Homecoming Desktop with
one live portfolio that shows Homecoming, Hoard, and every future explicitly
tracked project against its own frozen phases, current gate, evidence state, and
blockers.

The desktop must stop presenting a generic percentage as the primary truth.
Each project card must answer: what phase is active, what has been proven, what
is blocked, and what evidence closes the next gate.

## Why this is next

Homecoming currently shows `Kai Smarter Project` and `Sentience Ladder` as the
only project progress cards while the real work is Homecoming, Hoard, and other
product repositories. Both Homecoming and Hoard already have authoritative
source-of-truth documents and evidence-based roadmaps. The existing
`KaiProjectService` already provides frozen goals and evidence-backed updates,
so this is a portfolio correction rather than a new project-management system.

## Entry gate

- Brief 004 is complete, or this work runs in a genuinely separate worktree.
- Run `git status --short` and preserve all existing user-owned changes.
- Read the two governing documents:
  - `C:\code\homecoming_app\docs\NORTHSTAR_SOURCE_OF_TRUTH.md`
  - `C:\code\Hoard\docs\PROJECT_SOURCE_OF_TRUTH.md`
- Inspect the existing tracker and registry before editing:
  - `lib/services/core/kai_project_service.dart`
  - `lib/services/core/project_registry_service.dart`
  - `lib/widgets/kai_project_card.dart`
  - `lib/screens/kai_desktop_shell.dart`
  - `test/widget_test.dart`

Stop if the implementation would require changing Hoard, deleting Firebase
records, or rewriting the existing Kai Smarter/Sentience histories.

## In scope

- Add portfolio project IDs for:
  - `homecoming_northstar`
  - `hoard_northstar`
- Seed and reconcile their frozen phase definitions from the governing
  documents—not from chat summaries and not from inferred code completion.
- Homecoming phases must remain the nine governed phases 0–8:
  Baseline, Embodiment Foundation, Device Transport, Central Attention,
  Durable Continuity, Capability Fabric, Self-Improvement, Always-On
  Deployment, and Northstar Acceptance.
- Hoard phases must remain the six governed phases 0–5:
  Authorization Contract, Pilot Safety Baseline, Real Venue Close, Verified
  Savings Pilot, Repeatability, and Self-Service and Growth.
- Represent present truth honestly:
  - Homecoming: Phase 0 complete; Phase 1 active and Unity/Quest acceptance
    blocked; Brief 004 remains a separate tested-policy repair and does not
    advance the live Central Attention phase.
  - Hoard: Phase 0 active; venue-scoped Firestore enforcement and Storage
    authorization remain blockers; later phases remain unaccepted.
- Extend the project data contract minimally so a portfolio project can expose:
  - authoritative source-of-truth path;
  - repository path;
  - active phase number;
  - blocker strings;
  - whether it is visible in the desktop portfolio.
- Preserve backward-compatible reads for existing Firebase records without the
  new metadata.
- Add a live portfolio stream/list in `KaiProjectService` that includes every
  `portfolioVisible` project and sorts deterministically, with the active local
  workspace first when it can be matched safely.
- Add a compact desktop portfolio widget. Each card must visibly show:
  - project name;
  - current phase and gate;
  - phase strip or equivalent status visualization;
  - proof vocabulary (`Verified live`, `Tested`, `Wired`, `Conceptual`, or
    `UNVERIFIED`) rather than a naked completion claim;
  - blocker count and concise blocker text;
  - most recent evidence line;
  - repository/workspace state when available.
- Clicking a card may open the existing detailed `KaiProjectCard` view or a
  bounded details sheet; reuse existing layer/evidence rendering rather than
  duplicating it.
- Hide `kai_smarter` and `sentience_ladder` from the desktop portfolio rail.
  Preserve their Firebase data, services, tools, self-improvement dependencies,
  and prompt context unchanged.
- Provide one explicit service method for registering a future portfolio
  project from sponsor-approved frozen phases. A future project with no source
  of truth must begin `UNVERIFIED` with zero accepted phases; it must never
  inherit a fabricated percentage from repository contents.
- Replace both duplicated fixed-card lists in `kai_desktop_shell.dart`, including
  the normal project rail and the Persona-expanded rail.

## Out of scope

- Editing Hoard source code or its project source of truth.
- Automatically parsing arbitrary Markdown into progress claims.
- Automatically marking phases complete from commits, file existence, test
  counts, or an agent's report.
- Deleting or migrating the Kai Smarter/Sentience Firebase records.
- Changing project tool permissions, Firebase security rules, memory policy,
  attention integration, Unity, Messenger, transport, or self-improvement.
- Building a Jira clone, task assignment system, Gantt chart, calendar, or
  notification scheduler.
- Adding fake aggregate completion percentages.
- Visual redesign outside the desktop project rail and its details surface.

## Invariants

- The authoritative source-of-truth document governs each project's phase
  names, intent, active gate, and maturity claims.
- A phase is complete only when its exit gate is supported by evidence.
- Source paths and repository paths are metadata, never automatic proof.
- Existing live progress/evidence is preserved during reconciliation.
- The system must not overwrite a project assessment merely because seed
  constants changed.
- Frozen phase wording may be reconciled; mutable evidence and proof state may
  only change through the existing evidence-backed update path or sponsor
  authority.
- Homecoming and Hoard remain separate projects with separate roadmaps,
  blockers, and evidence.
- Existing workspace selection continues to control where Kai's coding tools
  operate. Selecting a tracker must not silently change the workspace.
- Existing Kai Smarter/Sentience data remains available to the services that
  currently depend on it.
- Empty, malformed, or unavailable Firebase data renders an honest unavailable
  state rather than invented progress.

## Authoritative files and systems

- Homecoming source of truth:
  `C:\code\homecoming_app\docs\NORTHSTAR_SOURCE_OF_TRUTH.md`
- Hoard source of truth:
  `C:\code\Hoard\docs\PROJECT_SOURCE_OF_TRUTH.md`
- Tracker storage: `/kai/{personaId}/projects/{projectId}` in Homecoming RTDB.
- Project identity registry: `/projects/{projectId}`; do not duplicate its
  responsibility for Firebase/repository identity.
- Local workspace selection: `CodeWorkspaceService`; remain read-only from the
  tracker interaction unless the user explicitly selects a workspace action.

## Procedure

1. Capture the pre-change worktree and current tracker tests.
2. Add failing model/service tests for backward compatibility, portfolio
   filtering, deterministic ordering, frozen phase reconciliation, and future
   project registration.
3. Extend `KaiProject` serialization and service APIs minimally.
4. Add Homecoming and Hoard frozen project definitions with evidence-grounded
   initial states.
5. Build the compact portfolio widget and focused widget tests.
6. Replace both fixed tracker lists in the desktop shell.
7. Confirm the old project records remain seeded and readable but are not
   mounted in the portfolio.
8. Format only changed files.
9. Run focused tests, the existing tracker regression tests, scoped analysis,
   and `git diff --check`.
10. Stop and report. Do not begin broader desktop redesign.

## Pass criteria

- Homecoming Desktop shows a Homecoming tracker with Phase 1 active and its
  Unity/Quest blocker visible.
- Homecoming Desktop shows a Hoard tracker with Phase 0 active and its
  authorization/storage blockers visible.
- The two fixed `KaiProjectService.smarterId` and
  `KaiProjectService.sentienceId` cards are absent from both desktop rail
  variants.
- Existing Kai Smarter/Sentience records and service callers remain intact.
- Homecoming has exactly the nine governed phases in the governed order.
- Hoard has exactly the six governed phases in the governed order.
- Phase 0 is the only accepted Homecoming phase; Hoard has no accepted phase
  unless newer direct evidence in its governing document says otherwise.
- Tested-but-not-integrated attention work does not visually mark Central
  Attention live or complete.
- Blockers appear as blockers, not as ordinary pending tasks or hidden tooltip
  text.
- Every visible maturity label maps to the existing proof vocabulary; no
  unsupported `done`, `online`, or aggregate-percent claim appears.
- A third sponsor-approved portfolio project appears automatically through the
  portfolio stream without another shell code change.
- A project lacking approved frozen phases appears `UNVERIFIED` and 0 accepted,
  with no inferred completion.
- Legacy Firebase project records without new metadata still deserialize.
- Updating a project's evidence in RTDB updates the visible card without app
  restart.
- Clicking a tracker never changes `CodeWorkspaceService.root` implicitly.
- The existing propaganda-card guards continue to pass.
- No Hoard file and no unrelated dirty Homecoming file changes.

Any missing criterion is `FAIL` or `UNVERIFIED`, not a partial pass.

## Required verification

At minimum, run and report:

```powershell
flutter test test/kai_project_portfolio_test.dart
flutter test test/kai_smarter_dashboard_test.dart
flutter test test/widget_test.dart
dart analyze lib/services/core/kai_project_service.dart lib/widgets/kai_project_portfolio.dart lib/screens/kai_desktop_shell.dart test/kai_project_portfolio_test.dart
git diff --check
git status --short
```

Also perform one attended Windows desktop check:

1. Launch Homecoming Desktop.
2. Confirm Homecoming and Hoard are visible.
3. Confirm their active phases and blockers match their governing documents.
4. Update one non-acceptance evidence line through the approved tracker path and
   confirm the card refreshes live.
5. Confirm selecting/opening either tracker does not switch the coding
   workspace.

Automated tests cannot promote the attended UI check to `Verified live`.

## Failure and rollback

- Preserve the existing Firebase records; make no destructive migration.
- Additive fields must have backward-compatible defaults.
- If reconciliation would overwrite live evidence or proof state, stop before
  writing and report the causal conflict.
- If the new widget fails, rollback by restoring the old shell mounting only;
  do not delete project data.
- Never use `git reset`, clean the worktree, or rewrite Hoard files.

## Stop and report

Report:

- files changed;
- data-contract additions and backward-compatible defaults;
- exact Homecoming and Hoard frozen phase definitions;
- evidence used for every initial maturity/blocker claim;
- tests/commands and exact results;
- attended desktop evidence or `UNVERIFIED` if not performed;
- criterion-by-criterion `PASS`, `FAIL`, `UNVERIFIED`, or sponsor-approved
  `DEFERRED`;
- confirmation that legacy tracker data was preserved;
- rollback path;
- final verdict and exact next recommendation.

Do not begin project-task management, attention integration, Unity work, Hoard
feature work, or broader desktop polish.

## Reviewer checkpoint — 2026-08-08

Verdict: **AUTOMATED PASS; PHASE NOT YET ACCEPTED**.

Independent reruns:

- `flutter test test/kai_project_portfolio_test.dart` — 13/13 PASS.
- `flutter test test/kai_smarter_dashboard_test.dart` — 11/11 PASS.
- `flutter test test/widget_test.dart` — 6/6 PASS.
- Scoped analysis completed with no error; three pre-existing shell warnings
  and ten informational lints remain.
- The Windows debug executable exists and was launched for attended review.

The implementation is therefore **Tested**. It is not `Verified live` because
the reviewer could not observe the rendered Windows surface through the
available OS-control bridge. The following remain `UNVERIFIED`:

- Homecoming and Hoard cards render with the governed phases and blockers;
- an RTDB evidence update refreshes the visible card without restart; and
- opening a tracker leaves the selected coding workspace unchanged in the
  running desktop app.

Do not mark Brief 005 accepted until those three attended observations are
recorded.
