# Brief 019 — Pizza delivery-box automation

Owner: Codex implementation team with Claude challenge review

Reviewer: Northstar project manager

Status: ACCEPTED / TESTED — LIVE UI UNVERIFIED

## Goal

Turn the four-project Pizza from a macro progress display into an
evidence-driven delivery controller: every governed phase exposes bounded boxes,
one deterministic selector identifies the next safe agent-owned box, and only a
real sponsor or live-operation boundary may say `awaiting_sponsor`.

## Why this is next

The four Northstars and macro phase names are frozen, but one broad checklist
item per phase cannot safely drive autonomous delivery or distinguish repairable
work from decisions only Sadeq can make.

## Entry gate

- Brief 018 local readiness repair is committed at `330d834`; no attended
  restart is part of this brief.
- `docs/NORTHSTAR_SOURCE_OF_TRUTH.md` governs Homecoming.
- Hoard's 2026-08-09 source of truth reports Phase 0 accepted and Phase 1B
  active, with reset repair `5821f73` tested and the attended staging drill open.
- Kingdom's expected `C:\code\Kingdom\docs\PROJECT_SOURCE_OF_TRUTH.md` is absent.
  Its six frozen Homecoming tracker phases remain usable, but repository-derived
  box evidence is `UNVERIFIED`.
- Factory remains scan-only. Blueprint and public Dispatch require explicit,
  run-bound sponsor authority; Money in Bank remains the terminal fact.

## In scope

- Add one canonical delivery-box model beneath `KaiLayer` with stable identity,
  dependencies, owner, authority/risk class, evidence requirements, lifecycle,
  attempt history, blocker, source reference, lease/work-request correlation.
- Freeze bounded boxes for all 9 Homecoming, 6 Hoard, 6 Kingdom, and 9 Factory
  macro phases without changing their names or Northstars.
- Reconcile durable evidence, select at most one eligible box per project, and
  create/reuse a deterministic self-contained `READY FOR AGENT` work request.
- Retain failed attempts, suppress identical failed strategies, enter repair for
  safe failures, and block only after one causal blocker survives three
  materially distinct safe repairs. True sponsor/live boundaries stop at once.
- Make Factory box state a projection of the same `FactoryRun` evidence that
  drives the conveyor; never maintain a contradictory success ledger.
- Show per-phase total/verified/active/awaiting-sponsor/blocked counts, bounded
  box details, `Kai is doing next`, and `Only you can decide` in the existing
  drawer without redesigning the HUD or overlapping Pizza labels.
- Add deterministic model, migration, eligibility, dispatch, repair, escalation,
  sponsor-boundary, proof-integrity, Factory projection, and widget tests.

## Out of scope

- Changing any Northstar or macro phase name.
- Direct Codex/Claude execution; queued packets are not execution.
- Credentials, live services, Firebase mutation during acceptance, deployment,
  publishing, purchase, sale, restore, destructive action, Unity/Quest, or GUI.
- Starting Factory Blueprint, public Dispatch, or editing Hoard/Kingdom repos.

## Invariants

- Sadeq owns product meaning, candidate votes, money/risk choices, run-bound
  publication consent, and acceptance requiring his observation.
- Sponsor boxes cannot be auto-completed or converted into transferable consent.
- Only boxes in the active governed phase with verified dependencies, agent
  ownership, local-safe authority, and no active duplicate lease/request qualify.
- Code existence and agent claims never promote proof. Verification requires the
  declared evidence and independent review.
- A failed attempt and its evidence are retained. The exact failed strategy is
  never dispatched twice.

## Authoritative evidence to inspect

- `lib/services/core/kai_project_service.dart`
- `lib/services/core/kai_work_request_service.dart`
- `lib/services/core/kai_factory_service.dart`
- `lib/logic/product_factory.dart`
- `lib/widgets/kai_project_portfolio.dart`
- `lib/widgets/kai_factory_conveyor.dart`
- `docs/NORTHSTAR_SOURCE_OF_TRUTH.md`
- `docs/FACTORY_PROJECT_SOURCE_OF_TRUTH.md`
- `C:\code\Hoard\docs\PROJECT_SOURCE_OF_TRUTH.md` (read-only)
- `docs/briefs/BRIEF_011_KINGDOM_PORTFOLIO.md`

## Pass criteria

1. Every macro phase in all four slices has at least two frozen delivery boxes.
2. The lifecycle includes queued, ready, active, repairing, evidence_review,
   verified, awaiting_sponsor, blocked, and deferred.
3. Selection is deterministic and never crosses phase, dependency, ownership,
   risk, lease, or duplicate-request boundaries.
4. Dispatch uses a deterministic durable ID and produces one self-contained
   `READY FOR AGENT` packet; it does not claim an agent ran.
5. Safe failure enters repair; identical failure is suppressed; three distinct
   attempts against one blocker escalate; sponsor/live boundaries stop at once.
6. Proof promotion requires evidence and review, never code or agent assertion.
7. Hoard reflects the exact accepted Phase 0 / tested Phase 1B delta; Kingdom
   repository claims remain `UNVERIFIED`.
8. Factory is scan-only and shares `FactoryRun` evidence with the conveyor/Pizza;
   Blueprint, approval/public Dispatch, and bank settlement gates cannot drift.
9. The existing Pizza drawer exposes counts and plain-language agent/sponsor
   areas without label overlap or whole-HUD redesign.
10. Focused and proportionate regression tests pass; source of truth and evidence
    index match the implementation.

## Failure and rollback

- Stop on the first causal proof-integrity or authority leak.
- Preserve existing project/work-request records and sponsor-owned dirty files.
- Do not migrate or write live Firebase during verification; test pure models and
  fixture parsing locally.
- Roll back the scoped milestone commit; Brief 018 remains independently
  recoverable at `330d834`.

## Stop and report

Report files, architecture, exact box counts per project/phase, tests, Claude
verdict, PASS/FAIL/UNVERIFIED matrix, risks, rollback, and exact next action.
Stop after the local commit. No live action.

## Reviewer checkpoint — 2026-08-09

Claude session `32011ace-4de7-4d54-959c-2170bf719a93` initially rejected the
implementation on two causal proof-integrity defects: verification provenance
was discarded after checking, and `done`-without-evidence / cancelled requests
could repair forever without entering the attempt ledger. Both findings were
independently reproduced and repaired.

Verified boxes now persist requirement-bound evidence, reviewer identity, and
review time. Stored bare `verified` values demote to `evidence_review`. All
closed-without-proof outcomes use the same durable failure ledger; identical
strategy digests are refused and one stable blocker escalates after three
distinct 16–64 character lowercase-hex strategy digests. Sponsor boxes still
cannot pass the agent verification API.

Final automated evidence: 68/68 focused tests pass. Scoped Dart analysis reports
no errors; four pre-existing desktop-shell unused-code warnings and existing
style infos remain. Visible Windows layout, Firebase migration, and real agent
claim/execution remain `UNVERIFIED` and were not attempted.
