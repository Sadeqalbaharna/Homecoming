# Brief 022 — Find My Table Synthetic Pilot Packet Assembly

Owner: Claude only if Relay v2 reports an exact model identifier proving Opus 5+
Reviewer: Codex
Status: READY; IMPLEMENTER MODEL GATE PENDING
Factory run: `factory-run-legacy-recovery-20260809-tablefinder-01`
Candidate: `FSC-LEGACY-YES-001`
Assembly authority: standing repository-local safe-work authority

## Goal

Generate one deterministic, copy-ready private pilot packet from synthetic data
so an operator can review the complete table-fill workflow before any real data,
contact, payment, publication, or venue execution is authorized.

## Why this is next

Brief 020 proved the pure synthetic operator. Brief 021 froze the commercial
pilot. This box turns those accepted decisions into inspectable forms,
workbooks, messages, controls, and evidence without crossing the live-use gate.

## Entry gate

- Repository-local synthetic assembly is authorized by the supervising sponsor.
- Before code dispatch, Relay v2 must allowlist this worktree and report an exact
  model identifier proving Opus 5 or higher. Missing or ambiguous metadata is
  `MODEL UNVERIFIED / INELIGIBLE`.
- Preserve the dirty worktree and commit only the paths below.

## Exact allowed paths

Claude may create or edit only:

- `scripts/tools/generate_find_my_table_private_pilot_packet.dart`
- `test/find_my_table_private_pilot_packet_test.dart`
- `output/find_my_table_private_pilot_v1/00_manifest.md`
- `output/find_my_table_private_pilot_v1/01_player_intake.md`
- `output/find_my_table_private_pilot_v1/02_dm_intake_and_approval.md`
- `output/find_my_table_private_pilot_v1/03_match_review_workbook.xlsx`
- `output/find_my_table_private_pilot_v1/04_private_message_templates.md`
- `output/find_my_table_private_pilot_v1/05_dm_table_brief.md`
- `output/find_my_table_private_pilot_v1/06_session_run_sheet.md`
- `output/find_my_table_private_pilot_v1/07_revenue_attribution.xlsx`
- `output/find_my_table_private_pilot_v1/08_privacy_safety_incident_runbook.md`
- `output/find_my_table_private_pilot_v1/09_pilot_decision_card.md`
- `output/find_my_table_private_pilot_v1/10_launch_checklist.md`

`docs/briefs/BRIEF_022_FIND_MY_TABLE_SYNTHETIC_PILOT_PACKET_ASSEMBLY.md`
is reviewer-owned and must not be edited. No dependency or shared-service edit
is allowed; use the existing `archive` package for deterministic OOXML.

## Invariants and frozen inputs

- Reuse `lib/logic/find_my_table_operator.dart`; do not create a second matcher.
- Packet IDs and version are stable and all content is explicitly synthetic.
- Ten prospects use routes 4 referrals / 3 venue inbound / 3 approved-community.
- P0 is BHD12 minimum per player, BHD0 surcharge, BHD10 fixed DM cost, four seats.
- Central fixture is 40% contribution margin and BHD5 overhead: four net-new
  seats yield BHD48 gross and BHD4.20 contribution; one transferred seat yields
  75% net-new share and -BHD0.60.
- Unknown live inputs and all live proof states render `UNAVAILABLE`, never zero
  or estimated.
- Proposed, approved, delivered, billed, settled, and bank-reconciled remain
  distinct. Synthetic data cannot claim settlement or bank proof.
- Invitation templates may exist, but a recipient-specific invitation draft may
  be generated only after a recorded synthetic operator approval.
- No real identity, contact, location, diagnosis, payment, credential, network,
  message-send, public action, or mutable external state.
- Every live/data/contact/payment/public/venue lock is visibly false/unchecked.

## Procedure

1. Inspect Briefs 020–021 and the accepted operator/tests before editing.
2. Implement one deterministic generator with a temporary-output option used by
   tests and a default exact output directory used for the committed packet.
3. Generate the ten-prospect fixture, retaining a hard mismatch, duplicate,
   decline, cancellation, ordered replacement, waitlist, and rejection reason.
4. Create two valid minimal `.xlsx` OOXML workbooks with stable ZIP metadata,
   visible formulas/labels, no macros, links, hidden sheets, or external data.
5. Generate the other nine Markdown artifacts and hash the ten payload artifacts
   in `00_manifest.md`; report the manifest's own SHA-256 separately.
6. Run generation twice and prove byte-for-byte equality.
7. Run focused tests, existing operator tests, format, analyze owned Dart files,
   inspect the generated diff, and commit only allowed paths.

## Deterministic acceptance tests

- Exactly the eleven required artifacts exist; no extras are generated.
- Two clean generations have identical relative paths and SHA-256 hashes.
- Manifest binds run, candidate, packet version, synthetic proof state, authority
  locks, generator version, and correct hashes for all ten payload artifacts.
- Both workbooks decode as ZIP/OOXML and contain required sheets/cells/formulas;
  formulas reproduce BHD48, BHD4.20, 75%, and -BHD0.60.
- Missing bill, margin, overhead, DM cost, or net-new classification produces
  `UNAVAILABLE` and no numeric derived result.
- Fixture records exactly 4/3/3 sources and retains mismatch, duplicate,
  decline, cancellation, replacement, waitlist, and reasons.
- Recipient-specific invitation generation is refused before approval and
  succeeds only after exact synthetic proposal approval.
- Player-facing output excludes fingerprints, acquisition source, accessibility
  details, content boundaries, and DM/private operator fields.
- DM brief includes only aggregated approved operational constraints.
- Launch checklist leaves real data, outreach, DM offer, receipt access, live
  venue, payment/refund, public post, and later-station gates locked.
- Static scan finds no URL invocation, credential access, message-send, live
  repository adapter, or claim of actual buyers/revenue/settlement.
- `dart test test/find_my_table_private_pilot_packet_test.dart`
  and both accepted Brief 020 operator test files pass.
- `dart format --output=none --set-exit-if-changed` and `dart analyze` pass for
  the two owned Dart files.

Any missing criterion is FAIL or UNVERIFIED, never a partial pass.

## Failure, rollback, and stop

Preserve the first causal failure and change strategy before retry. Do not edit
outside allowed paths to make the test pass. Rollback is the single scoped
commit plus deletion of the versioned output directory; no external cleanup.

Stop after local generation, deterministic tests, inspection, and scoped commit.
Report relay model metadata, authored paths/commit, exact commands/results,
artifact SHA-256 values, PASS/FAIL/UNVERIFIED by criterion, remaining risks, and
rollback. Do not use real data, contact anyone, offer DM compensation, book a
table, access receipts, publish, charge, spend, or advance beyond Assembly.
