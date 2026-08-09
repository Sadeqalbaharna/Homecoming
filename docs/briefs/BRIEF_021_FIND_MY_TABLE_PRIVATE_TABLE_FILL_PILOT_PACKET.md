# Brief 021 — Find My Table Private Table-Fill Pilot Packet

Owner: **Unassigned until a separate execution authorization**
Reviewer: Codex (technical program manager and investment/evidence authority)
Status: **READY AS A DEFINITION; EXECUTION AND LIVE USE LOCKED**
Factory packet: `FSC-LEGACY-YES-001-BP-IC-v3`
Factory run: `factory-run-legacy-recovery-20260809-tablefinder-01`
Candidate: `FSC-LEGACY-YES-001`
Depends on: accepted synthetic operator commit `424b87e6`

## Decision

The next smallest revenue-facing Assembly box is **not another software layer**.
It is a private, manually operable packet that lets the venue assemble, approve,
deliver and reconcile one additional externally DM-run four-player table using
the existing BHD12 food/drink minimum.

This is the shortest path to testing the commercial thesis because it exposes
the unknowns—net-new player supply, DM acceptance, schedule/fit, owner rescue
time, and real venue contribution—before an operator console or marketplace is
worth building.

## Goal

Produce one versioned, copy-ready private pilot packet that an authorized venue
operator could later use to take ten net-new prospects through intake, matching,
operator approval, confirmation, one externally DM-run table, and receipt-level
attribution without inventing evidence or requiring public software.

## Entry gate

Creating the packet requires a separate scoped Assembly micro-box authorization.
Using it with real people requires later explicit approvals for:

- real player/DM data and retention;
- private outreach/contact;
- the exact external-DM offer;
- live venue execution;
- receipt/revenue access; and
- any deposit, refund, payment or public post.

The current Assembly authorization for the synthetic operator does not grant
those actions. This brief records no new sponsor verdict or station advance.

## Frozen offer

### Buyer and user

- Economic buyer/operator: the sponsor-owned venue.
- First end user: a net-new adult tabletop player who wants a reliable,
  compatible, hosted local table.
- Supply user: one separately approved external DM.

### Promise

“We privately match four compatible players and an approved DM into a confirmed
hosted table, with schedule and fit checked before anyone commits.”

### What the player buys

No separate ticket or matching fee in the first cell. The player attends the
additional hosted table and pays the venue's existing BHD12 minimum food/drink
bill. The matching service is part of the venue experience.

### Exclusions

- no public marketplace or directory;
- no guaranteed match or guaranteed game quality;
- no home games, minors or live-location sharing;
- no public ratings, direct messages or player-to-player private data;
- no automatic invitation or acceptance;
- no claim that BHD48 gross equals profit.

## Required packet artifacts

Future execution should produce one directory:
`output/find_my_table_private_pilot_v1/`.

It must contain:

1. `00_manifest.md` — packet/run/candidate/version, owner, proof state, files,
   authority status and rollback.
2. `01_player_intake.md` — minimum fields, optional disclosure flags, consent,
   retention notice and exclusions.
3. `02_dm_intake_and_approval.md` — systems, formats, availability, capacity,
   evidence, safety agreement, terms and operator approval.
4. `03_match_review_workbook.xlsx` — ten-prospect route, source/net-new status,
   hard constraints, proposal, waitlist, unmatched/duplicate reasons and
   operator decision. Formula cells must not infer missing inputs.
5. `04_private_message_templates.md` — approved private invitation,
   confirmation, decline, waitlist, replacement, reminder and cancellation
   drafts. They remain unsent.
6. `05_dm_table_brief.md` — exact slot/system/format plus aggregated minimum
   accessibility and content-boundary requirements; no player attribution.
7. `06_session_run_sheet.md` — confirmations, attendance, owner rescue time,
   DM delivery, incidents, fit feedback and support minutes.
8. `07_revenue_attribution.xlsx` — player bills, net-new classification,
   contribution margin, overhead, DM cost, fees/refunds, gross, attributable
   contribution and proof state.
9. `08_privacy_safety_incident_runbook.md` — minimization, access, retention,
   escalation, stop conditions and deletion procedure.
10. `09_pilot_decision_card.md` — PASS/REVISE/KILL/PARK evidence summary and
    exact next gate.
11. `10_launch_checklist.md` — every live/account/contact/payment authority
    separately unchecked by default.

Editable sources are authoritative. PDF previews may be added for review, but
no polished PDF can replace the calculation workbooks or evidence ledger.

## Operator workflow

### Assembly dry run

1. Load ten synthetic prospects using the 4/3/3 acquisition allocation.
2. Record each source and explicit net-new status; “unknown” is not net-new.
3. Load at least one synthetic approved DM and one four-seat venue slot.
4. Apply the deterministic hard constraints from the accepted operator.
5. Preserve every mismatch, duplicate, shortfall and waitlist decision.
6. Present one exact proposal to the synthetic operator-review step.
7. Generate private invitation drafts only after recorded operator approval.
8. Exercise acceptance, decline, cancellation and ordered replacement once.
9. Produce the minimum-data DM brief and session run sheet.
10. Reconcile the central economics fixture and a cannibalized-seat failure.
11. Complete the pilot decision card with all live results marked unavailable.

### Later live workflow—separately gated

1. Freeze real-data policy, channels, DM term and experiment ID before contact.
2. Qualify the first ten prospects through the same private intake.
3. Sadeq approves the DM, exact table, invitation text and recipients.
4. Send only authorized private invitations; record every outcome separately.
5. Confirm four players, an ordered waitlist and the external DM.
6. Deliver one table with no Sadeq co-DM/rescue.
7. Record attendance, actual bills, costs, DM compensation, support time and
   incidents.
8. Reconcile settled venue receipts to that exact additional table.
9. Classify the experiment against the predeclared gate before changing terms.

No live step is authorized by this document.

## Pricing and compensation experiment

Run a sequential single-variable experiment; do not split a tiny audience into
an underpowered simultaneous A/B test.

### Cell P0 — recommended first cell

- Player price: existing BHD12 minimum food/drink bill.
- Matching/event surcharge: BHD0.
- DM compensation hypothesis: BHD10 fixed, payable only for an approved,
  delivered session.
- Table size: exactly four players.
- Other modeled overhead: record actual; BHD5 is only the central fixture.
- Contribution margin: record actual; 40% is only the central fixture.

Rationale: customer price and venue behavior remain familiar while the test
isolates the external-DM and matching economics. At the central fixture, P0
requires 31.25% contribution margin and four of four seats to be net-new because
three of four is only 75%, below the 78.125% continuous threshold.

### P0 failure response

- If a qualified DM will not accept BHD10, do not repeat the identical offer.
  Record requested compensation and implied hourly rate. Sponsor confirmation
  is required before one changed term.
- The safest modeled alternative is **one** BHD12 venue credit at face value,
  not stacked with cash. It may be economically cheaper than face value only
  after actual food/drink COGS is known.
- Do not test BHD15 fixed under the central case: it models at -BHD0.80 per full
  four-seat table before support time.
- Do not add a customer surcharge until evidence shows the venue cannot support
  acceptable DM terms at the existing BHD12 minimum.
- A future booking deposit must be credited against the BHD12 bill and requires
  separate payment/refund authority; it is not part of this box.

## First-ten-buyer route

These are prospect allocation targets, not forecasts or permission to contact.
Every person counted toward incremental revenue must be new to the added-table
cohort, not moved from an existing hosted table.

| Route | Target | Qualification | Main risk |
|---|---:|---|---|
| Existing-player referrals | 4 | referred adult who is not currently occupying an existing hosted-table seat | social-circle duplication or cannibalization |
| Venue inbound/regulars | 3 | adult who has expressed tabletop interest but is not an existing hosted-table attendee | classifying an existing customer as new |
| One sponsor-approved community channel | 3 | local adult, suitable schedule/format, privately consents to intake | channel permission and weak fit |

For each prospect record: route, first contact authority, intake completion,
net-new proof state, availability, system, language, experience comfort,
commitment, optional disclosure state, match result, invitation decision,
confirmation, attendance and settled bill. “Interested,” a like, a compliment,
or a form view is not a buyer.

The first ten may yield zero, one or two table proposals. Only one table may be
delivered in the first live micro-test; additional compatible people remain on
an explicitly consented waitlist rather than becoming filler.

## Assembly acceptance gate

The packet passes Assembly only when every item below is directly evidenced:

- all eleven required files exist in one versioned directory and the manifest
  hashes every artifact;
- the player and DM intake artifacts collect only fields in the accepted domain
  schema and distinguish undisclosed from none;
- a ten-prospect synthetic fixture preserves the 4/3/3 route and explicit
  net-new status;
- four compatible players plus one approved DM produce one operator-reviewed
  four-seat proposal, with surplus prospects waitlisted;
- at least one hard mismatch, duplicate, decline, cancellation and ordered
  replacement are retained with reasons;
- no invitation draft is produced before operator approval;
- public/player output excludes identity fingerprints, acquisition source,
  accessibility needs and content boundaries;
- the DM brief contains only aggregated operational requirements after approval;
- the revenue workbook reproduces BHD48 gross and BHD4.20 modeled contribution
  for four BHD12 net-new seats at 40% margin/BHD5 overhead/BHD10 DM cost;
- changing one seat to transferred produces 75% net-new share and -BHD0.60,
  failing the central case;
- deleting any margin, overhead, DM-cost, bill or net-new input produces
  `UNAVAILABLE`, never an estimate or zero;
- proposed, approved, delivered, billed, settled and bank-reconciled remain
  separate; all live proof stays unavailable in the dry run;
- private-message templates contain no fake urgency, guarantee, testimonial,
  partnership or public-venue mark;
- the incident runbook stops the pilot for unresolved safety/privacy/material
  fit issues;
- the launch checklist visibly leaves real data, contact, payment, public and
  live-venue authorities locked;
- every page/sheet is visually inspected for legibility, clipping, formula
  errors and hidden sensitive columns;
- rollback is deletion/reversion of the single versioned packet directory; no
  external cleanup is necessary.

Any missing criterion is FAIL or UNVERIFIED, not a partial pass.

## Evidence required before a live pilot request

Completion of the packet alone does not justify contact. A later live-pilot
request is decision-ready only when it includes:

1. the accepted packet and synthetic dry-run evidence;
2. the venue's actual contribution-margin definition and data source;
3. actual per-table incremental overhead fields to capture;
4. Sadeq's selected DM compensation term and maximum exposure;
5. one named, permission-compatible private acquisition route;
6. the exact real-data fields, consent text, access owner and retention period;
7. the exact outreach recipients/message and venue slot;
8. stop rules, incident owner and rollback;
9. explicit confirmation that no existing-table seat will be reclassified as
   net-new; and
10. separate exact approvals for data, contact, DM offer, venue execution and
    receipt reconciliation.

## Evidence required to proceed after one live table

One delivered table is an information gate, not proof of scale. Proceed to the
four-week/three-table Blueprint experiment only if the first live table shows:

- four of four seats are verified net-new under the central P0 economics, or a
  recalculated threshold based on frozen actual margin/overhead;
- the approved external DM accepts the declared term and delivers without Sadeq
  co-DMing or rescuing;
- confirmed-player attendance is at least 80%;
- actual bills settle and reconcile to the exact added table;
- measured incremental contribution is non-negative after food/drink cost,
  incremental labor, DM compensation, matching/support time, discounts and
  refunds;
- no unresolved safety, privacy or material-fit issue;
- acquisition, matching, confirmation and operator minutes are recorded;
- failed routes and mismatches change the next declared hypothesis.

If any economic, substitution, settlement or safety condition fails, the next
decision is REVISE or KILL—not “build more software.”

## Non-goals

- no implementation of the packet in this PM box;
- no operator-console, app, database or `KaiFactoryService` change;
- no real intake, outreach, DM offer, invitation or venue booking;
- no deposit, charge, refund, payment credential or receipt access;
- no public post, listing, advertising, partnership claim or venue mark;
- no QA Gate, Packaging, Dispatch, Telemetry or later-station advance.

## Stop and report

Stop after this definition. If the micro-box is later authorized and assembled,
report artifact paths/hashes, formula and visual QA, synthetic fixture outcomes,
PASS/FAIL/UNVERIFIED by criterion, labor/model provenance, rollback and the
smallest remaining live gate. Do not contact anyone or run the pilot.
