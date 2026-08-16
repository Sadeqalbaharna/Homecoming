# Brief 006 — Full HTML project execution maps

Owner: Homecoming implementation team

Reviewer: Northstar project manager

Status: TESTED — ATTENDED DESKTOP ACCEPTANCE PENDING

## Goal

Clicking any Homecoming Desktop portfolio card opens a complete, readable HTML
flowchart for that project, using the same frozen phases, proof state, evidence,
active phase, and blockers as the compact card.

## In scope

- One data-driven renderer for Homecoming, Hoard, and future portfolio projects.
- A self-contained offline HTML document opened in the default desktop browser.
- Four unambiguous visual states:
  - green: completed gate;
  - amber: active/in progress;
  - red: blocker;
  - gray: future.
- Every phase's outcome, exit gate, proof rung, honest gate-evidence score, and
  recorded evidence available in the map.
- Blockers shown separately and attached to the active phase context.
- HTML escaping for all project-controlled content.
- No change to `CodeWorkspaceService.root` when a project is opened.

## Out of scope

- Editing project state from the flowchart.
- Inferring completion from files, tests, commits, or repository contents.
- An embedded Windows WebView, network hosting, CDN assets, or a second tracker.
- Changing Homecoming or Hoard phase definitions.

## Pass criteria

- Every portfolio card invokes the same HTML flowchart path.
- All governed phases render in numeric order.
- A phase is green only when `honestProgress >= 100`.
- The active incomplete phase is amber even when its capability proof is
  `Tested`.
- Blockers are red and visible outside the future phase list.
- Remaining phases are gray.
- A future registered project works without a shell code change.
- The document works offline and project text cannot inject HTML.
- Browser-open failure is visible in the desktop UI.
- Clicking the project does not change the active coding workspace.

## Verification record — 2026-08-08

- `flutter test test/kai_project_flowchart_service_test.dart test/widget_test.dart test/kai_project_portfolio_test.dart`
  — 24/24 PASS.
- Scoped `flutter analyze` — no errors; three warnings and seven infos already
  present in `kai_desktop_shell.dart` remain. No issue is reported in the new
  flowchart service or its test.
- Attended Windows click/open/render check — UNVERIFIED.

## Rollback

Restore the two shell callbacks to the prior details action and remove
`kai_project_flowchart_service.dart` plus its focused test. Project records and
source-of-truth files are untouched.

## Reviewer verdict

Automated criteria pass. This brief becomes accepted only after Sadeq clicks
Homecoming and Hoard in a rebuilt Windows desktop app and confirms both HTML
maps open with the expected colors and content.
