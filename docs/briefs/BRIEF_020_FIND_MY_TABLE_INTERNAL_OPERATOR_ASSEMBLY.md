# Brief 020 — Find My Table Internal Operator Assembly

Owner: **Codex under explicit sponsor coding-fallback authorization**
Reviewer: Codex (technical program manager and independent acceptance)  
Status: **ACCEPTED — REPOSITORY-LOCAL SYNTHETIC ASSEMBLY ONLY**
Factory packet: `FSC-LEGACY-YES-001-BP-IC-v3`  
Factory run: `factory-run-legacy-recovery-20260809-tablefinder-01`  
Candidate: `FSC-LEGACY-YES-001`

## Goal

Create one repository-local internal operator that, from synthetic player, DM,
and venue-slot data, deterministically proposes explainable four-player tables,
preserves unmatched reasons, requires human approval, and produces a draft
incremental-contribution record without contacting anyone or touching live data.

## Why this is next

The venue already fills two four-player tables weekly. The critical-path risk is
not demand-from-zero; it is whether additional tables can be formed around
availability and fit, delivered by external DMs, and attributed without making
Sadeq the permanent operational bottleneck. A public marketplace would add
network, privacy, moderation, and acquisition risk before this internal process
is proven.

## Entry gate

Implementation must not start until both conditions are recorded:

1. Sadeq issues separate exact **Assembly authorization** naming packet
   `FSC-LEGACY-YES-001-BP-IC-v3`, run
   `factory-run-legacy-recovery-20260809-tablefinder-01`, and candidate
   `FSC-LEGACY-YES-001`.
2. The Claude relay/tool reports an exact model identifier proving **Opus 5 or
   higher**. A plan name, UI label, self-description, or missing identifier does
   not qualify. Until then, Claude is `MODEL UNVERIFIED / INELIGIBLE` for code.

An `INVEST` recommendation, earlier YES, Blueprint authorization, or this brief
does not satisfy either condition. If Sadeq explicitly authorizes Codex as the
coding fallback, record that exception before implementation.

## Frozen commercial contract

- Buyer and operator: sponsor-owned venue.
- Player payment: existing BHD12 minimum food/drink bill; no new ticket.
- Table target: four players.
- Provisional external-DM comparison: BHD10 fixed per approved, delivered
  session; sponsor confirmation and DM acceptance remain pending.
- Central decision assumptions: 40% venue contribution margin, BHD5 other
  incremental overhead, 78.125% minimum net-new-seat share. These are test
  fixtures, not claims about actual venue performance.
- Product proof: additional externally DM-run tables with non-negative measured
  contribution and settled, reconciled venue receipts. A match proposal is not
  revenue.

## In scope

- Focused domain models for synthetic player preferences, DM capabilities,
  venue slots, table proposals, confirmations, attendance and attribution.
- Stable opaque IDs and schema-versioned local serialization.
- Deterministic matching across:
  - availability overlap;
  - game/system interest;
  - beginner/experienced comfort;
  - language;
  - one-shot/campaign commitment;
  - voluntary accessibility and content-boundary constraints;
  - DM system, format, availability, capacity and approval state.
- Exact include/exclude reasons for every proposal and unmatched person.
- Operator review queue: propose → approve/edit/reject. No invitation state may
  be reached without an explicit operator decision.
- Confirmation states: invited, accepted, declined, waitlisted, confirmed,
  attended and no-show remain distinct.
- Ordered compatible waitlist replacement with a recorded reason.
- A draft attribution calculator that separates gross, contribution, DM cost,
  overhead and net-new-seat share. Unknown inputs remain unavailable.
- Synthetic fixtures and focused deterministic tests.
- Integration adapter specification only for `KaiFactoryService` and the Brief
  019 portfolio watch; no shared controller changes.

## Out of scope

- Real player, DM, receipt, venue-account or payment data.
- Account access, credentials, outreach, invitations, email, messaging, calls,
  publishing, spending, payment collection or venue execution.
- Public profiles, ratings, direct messages, social feeds or reviews.
- AI compatibility scoring, opaque ranking or automatic player rejection.
- Multiple venues, public marketplace discovery or external APIs.
- Minors, home addresses, live location, health diagnoses or mandatory
  disclosure of accessibility/safety details.
- Assembly of a customer-facing app, QA Gate, Packaging, Approval, Dispatch,
  Telemetry or Money in Bank.
- Changes to KaiLayer, the shared four-project delivery-box controller, Pizza UI,
  Hoard, Kingdom or the nine Factory stations.

## Invariants

- YES, Blueprint, Assembly and public/live authorities remain separate and exact
  run/session/candidate bound. No data field or local test can mint authority.
- The operator—not the matcher—makes every final table decision.
- Matching is deterministic and explainable; identical inputs produce identical
  proposals and reasons.
- Sensitive fit/accessibility/boundary inputs are optional, minimized and never
  exposed in player-to-player output.
- Failed, rejected, duplicate and unmatched records remain evidence.
- Gross, contribution, settled revenue and banked revenue never collapse into
  one status.
- Existing-table customers do not count as net-new merely because they are moved
  into an additional-table record.
- No production side effect is reachable from this slice.

## Authoritative evidence to inspect

- `docs/FACTORY_PROJECT_SOURCE_OF_TRUTH.md`
- `docs/FACTORY_BLUEPRINT_FSC_LEGACY_YES_001.md`
- `docs/FACTORY_BLUEPRINT_SCALE_SPEC_FSC_LEGACY_YES_001.md`
- `docs/FACTORY_BLUEPRINT_SCALE_INVESTMENT_MEMO_FSC_LEGACY_YES_001.md`
- `docs/analysis/fsc_legacy_yes_001_dm_compensation_sensitivity.py`
- `lib/logic/factory_scan_session.dart`
- `lib/logic/factory_blueprint_authorization_registry.dart`
- `lib/logic/factory_blueprint_process.dart`
- `lib/services/core/factory_scan_session_repository.dart`
- `lib/services/core/kai_factory_service.dart` (inspect only unless a separately
  reviewed adapter change is unavoidable)
- `test/factory_scan_session_test.dart`
- `test/factory_legacy_blueprint_recovery_test.dart`
- `test/factory_blueprint_process_test.dart`
- `test/factory_blueprint_packet_consistency_test.dart`

## Proposed bounded file ownership

Prefer new focused files:

- `lib/logic/find_my_table_operator.dart`
- `lib/services/core/find_my_table_operator_repository.dart`
- `test/find_my_table_operator_test.dart`
- `test/find_my_table_operator_repository_test.dart`
- `docs/FACTORY_FIND_MY_TABLE_OPERATOR_INTEGRATION_DELTA.md`

Do not edit the shared portfolio/Pizza controller. If repository inspection
shows a different existing seam is authoritative, stop and propose the smallest
file-list change before editing it.

## Procedure

1. Record entry-gate evidence and exact implementer model metadata.
2. Inspect the authoritative files and dirty worktree; preserve all unrelated
   changes.
3. Freeze schema version 1 and synthetic fixtures before matcher behavior.
4. Implement pure deterministic eligibility and grouping functions.
5. Implement explicit unmatched and rejection reasons.
6. Add operator review and confirmation state transitions with illegal-transition
   refusal.
7. Add waitlist replacement and minimum-data DM brief projection.
8. Add draft attribution math with unavailable—not estimated—unknowns and
   net-new/cannibalized seat distinction.
9. Add schema-versioned repository persistence using the safest existing local
   seam; no network or credentials.
10. Write the read-only integration delta for `KaiFactoryService`, Factory HUD,
    and Brief 019 portfolio watch.
11. Run focused tests, existing Factory authority regressions, formatter and
    analyzer on owned files.
12. Commit only brief-owned files on `codex/factory-operator-automation` or an
    isolated child branch. Stop before live data or UI wiring.

## Acceptance suite

Every required criterion must be PASS; missing evidence is UNVERIFIED.

### Matching and dedupe

- Four mutually compatible synthetic players plus one approved, compatible DM
  and slot produce one stable proposal with visible reasons.
- Any hard availability, system, language, commitment, accessibility or content
  boundary conflict prevents that composition and records the exact reason.
- An unapproved or unavailable DM cannot be assigned.
- Reordering identical input collections does not change proposal identity or
  membership.
- Repeated player, DM, slot or proposal fingerprints are suppressed without
  erasing the retained duplicate record.
- Fewer than four eligible players produces no table and an explicit shortfall.
- More than four produces one four-player proposal and an ordered compatible
  waitlist; it does not silently enlarge the table.

### Human control and lifecycle

- A proposal cannot become invited or confirmed before operator approval.
- Rejection preserves operator reason and cannot be relabeled as progress.
- Illegal confirmation transitions are refused deterministically.
- A cancellation selects only the next compatible waitlisted player and records
  the replacement reason.
- No code path sends messages, invokes tools, reads credentials or calls a
  network service.

### Privacy and explanations

- Player-to-player projections exclude private accessibility/content-boundary
  values and source identifiers.
- DM brief includes only the minimum approved operational constraints.
- Serialization contains no required real name, phone, email, home address,
  live location or payment identifier.
- Unknown or withheld optional fields do not become inferred facts.

### Economics and evidence

- Four BHD12 seats produce BHD48 gross in the synthetic fixture.
- At 40% margin, BHD5 overhead and BHD10 DM cost, four wholly net-new seats
  produce BHD4.20 modeled contribution.
- One transferred seat at the central case removes BHD4.80 of attributable
  contribution and causes the BHD4.20 base case to fail.
- Missing margin, overhead, DM cost or source classification yields
  `unavailable`; the operator never estimates it silently.
- Proposed, approved, delivered, billed, settled and bank-reconciled remain
  separate states. Synthetic data cannot satisfy a live-money gate.

### Authority and durability

- YES and Blueprint references do not authorize Assembly, invitations, public
  action, payments or later stations.
- Cross-run/session/candidate authority is refused.
- Untrusted serialized data cannot mint any authority.
- Schema-version 1 round-trip retains proposals, rejects, duplicates, state
  history, economics inputs and reasons.
- Unknown future schema versions fail closed without data destruction.

### Integration regression

- Existing `factory_scan_session_test.dart`,
  `factory_legacy_blueprint_recovery_test.dart`,
  `factory_blueprint_process_test.dart`,
  `factory_blueprint_packet_consistency_test.dart`,
  `product_factory_test.dart`, and `kai_factory_conveyor_test.dart` pass.
- `git diff` contains no changes to KaiLayer, shared Pizza/portfolio controller,
  Hoard, Kingdom or live tool policy.

## Integration delta for KaiFactoryService and Brief 019

The operator owns a separate versioned local packet. `KaiFactoryService` may
later read a projection containing counts and proof states only: eligible
players, eligible DMs, proposals awaiting operator review, confirmed tables,
unmatched reasons, measured coordination minutes, net-new-seat share, and
attribution status. It must not copy or mutate operator truth.

Brief 019 may display that same immutable projection in the Factory delivery
box. It must not implement matching, approvals, lifecycle transitions,
economics, or authority. No general Pizza UI redesign is required.

## Failure and rollback

- Preserve the first causal failure and the exact fixture that exposes it.
- Change the implementation hypothesis before retrying; suppress identical
  retries.
- After three materially different safe repairs fail on the same cause, report
  `BLOCKED` with evidence.
- Rollback is the single scoped implementation commit; local synthetic fixtures
  contain no customer data and require no external cleanup.
- Never weaken privacy, explainability, authority or live-action gates to pass.

## Stop and report

Stop when the repository-local synthetic operator passes or when a genuine gate
is reached. Report:

- relay-reported Claude model identifier and eligibility verdict;
- Claude-authored files and commit/diff;
- files and behavior changed;
- exact commands/tests and results;
- criterion-by-criterion PASS/FAIL/UNVERIFIED matrix;
- Codex independent review verdict and accepted/rejected findings;
- runtime evidence and what remains synthetic;
- elapsed handoff/implementation/review time and duplicate work;
- unresolved assumptions, rollback and exact next gate.

Do not begin live data import, player/DM contact, UI integration, QA Gate,
Packaging, publishing, payments, spending or venue execution.

## Assembly acceptance record

Entry gate resolved by the sponsor's direct `I authorize` reply to the exact
preceding request naming this packet, run and candidate and explicitly
authorizing Codex as coding fallback. The Claude relay still exposed no model
identifier, so Claude remained `MODEL UNVERIFIED / INELIGIBLE`; Claude authored
no implementation files.

Assembly authorization ID:
`FAA-20260809-FSC-LEGACY-YES-001-ASSEMBLY-01`.

| Acceptance area | Verdict | Evidence |
|---|---|---|
| Matching, hard constraints, stable identity and dedupe | PASS | focused deterministic tests |
| Human approval, lifecycle, rejection and waitlist replacement | PASS | focused deterministic tests |
| Privacy projections and minimum-data DM brief | PASS | focused deterministic tests |
| Explicit economics, unavailable inputs and cannibalization | PASS | focused deterministic tests |
| Authority stripping, exact reapplication and future-schema refusal | PASS | domain and repository tests |
| Persistence revision and failure behavior | PASS | repository tests |
| No shared controller or live-tool integration | PASS | scoped diff inspection |
| Owned-file analyzer | PASS | `No issues found` |
| Factory regression suite | PASS | 88 tests |
| Real customers, DMs, receipts, settlement or venue execution | UNVERIFIED | deliberately outside Assembly authority |

Proof state: **TESTED**. The operator is not wired to a runtime UI, not using
real customer data, and not verified live. QA Gate has not begun.
