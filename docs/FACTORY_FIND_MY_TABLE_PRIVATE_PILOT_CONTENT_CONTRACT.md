# Find My Table Private Pilot — Operator Content Contract v1

Status: **FROZEN PRODUCT COPY; SYNTHETIC ASSEMBLY INPUT ONLY**
Owner: Codex (product/evidence contract)
Implementation owner: governed Brief 022 implementer
Factory packet: `FSC-LEGACY-YES-001-BP-IC-v3`
Factory run: `factory-run-legacy-recovery-20260809-tablefinder-01`
Scan session: `factory-scan-legacy-recovery-20260809-tablefinder-01`
Candidate: `FSC-LEGACY-YES-001`
Content version: `find-my-table-private-pilot-content-v1`

## Authority boundary

This document is the exact source copy for the nine Markdown artifacts in the
private pilot packet. It does not authorize real data, contact, a DM offer,
venue execution, receipt access, payments, refunds, publication, or a Factory
station advance. All bracketed fields are unresolved operator inputs. In the
synthetic packet they remain visibly synthetic or `UNAVAILABLE`.

The product promise is:

> We privately match four compatible adult players and an approved DM into a
> confirmed hosted table, with schedule and fit checked before anyone commits.

It is not a guarantee of a match, attendance, game quality, safety, revenue, or
profit. The first pricing cell uses the venue's existing BHD12 minimum
food/drink bill and no matching surcharge. BHD10 DM compensation, 40% margin,
and BHD5 overhead are synthetic decision fixtures, not verified venue facts.

## `00_manifest.md`

Use this exact structure:

```markdown
# Find My Table — Private Pilot Packet v1

Proof state: SYNTHETIC / NOT LIVE
Packet: FSC-LEGACY-YES-001-BP-IC-v3
Factory run: factory-run-legacy-recovery-20260809-tablefinder-01
Scan session: factory-scan-legacy-recovery-20260809-tablefinder-01
Candidate: FSC-LEGACY-YES-001
Oracle: FMT-PILOT-V1-ORACLE-001
Content version: find-my-table-private-pilot-content-v1
Generated deterministically: [YES/NO]

## Purpose

This packet rehearses one private four-player, externally DM-run table using
synthetic records. It is not permission to contact anyone or run the table.

## Authority locks

- [ ] Real player or DM data authorized
- [ ] Private outreach authorized
- [ ] Exact DM offer authorized
- [ ] Live venue session authorized
- [ ] Receipt or revenue access authorized
- [ ] Deposit, payment, or refund authorized
- [ ] Public post or listing authorized
- [ ] Later Factory station authorized

Every box must remain unchecked in the synthetic packet.

## File integrity

[DETERMINISTIC SHA-256 TABLE FOR THE TEN PAYLOAD ARTIFACTS]

The manifest's own SHA-256 is reported outside this self-referential table in
the completion report.

## Rollback

Delete or revert only `output/find_my_table_private_pilot_v1/`. No external
cleanup is required because no live action or real data is permitted.
```

## `01_player_intake.md`

```markdown
# Private Hosted Table — Player Fit Intake

Status: SYNTHETIC TEMPLATE / DO NOT COLLECT REAL RESPONSES

This short intake helps an operator check schedule and table fit before making
an invitation. Completing it does not guarantee a match or a seat.

## Eligibility

- [ ] I am 18 or older.
- [ ] I understand this pilot covers a hosted venue table, not a home game.
- [ ] I understand an operator reviews every proposed match.

## Required fit fields

- Operator-assigned player ID: [SYNTHETIC ID]
- Available approved venue slot IDs: [SELECT ONE OR MORE]
- Game systems or categories I would play: [SELECT/LIST]
- Preferred table language(s): [SELECT/LIST]
- Experience comfort: [BEGINNER / MIXED / EXPERIENCED]
- Commitment: [ONE-SHOT / CAMPAIGN]

## Optional accessibility disclosure

Choose exactly one:

- [ ] I prefer not to disclose.
- [ ] I have no requirements to record for matching.
- [ ] I choose to disclose these operational requirements: [TEXT]

Do not enter a diagnosis or medical history. Record only what the venue or DM
must do for participation.

## Optional content-boundary disclosure

Choose exactly one:

- [ ] I prefer not to disclose.
- [ ] I have no boundaries to record for matching.
- [ ] I choose to disclose these table boundaries: [TEXT]

## Pilot understanding

- [ ] I understand the table has a BHD12 minimum food/drink bill per person.
- [ ] I understand there is no separate matching surcharge in pilot cell P0.
- [ ] I understand fit information is not shown to other players.
- [ ] I understand consent and retention terms are UNAVAILABLE until separately
      approved for live use.

Consent for real collection: UNAVAILABLE
Retention period: UNAVAILABLE
Data access owner: UNAVAILABLE
```

No name, phone number, email, home address, live location, payment identifier,
diagnosis, or open-ended biography belongs in this intake. Any future contact
list must be a separately authorized, access-controlled record outside the
matching operator.

## `02_dm_intake_and_approval.md`

```markdown
# Private Hosted Table — DM Review

Status: SYNTHETIC TEMPLATE / NO OFFER MADE

## Capability

- Operator-assigned DM ID: [SYNTHETIC ID]
- Approved venue slot IDs: [SELECT/LIST]
- Systems or formats supported: [SELECT/LIST]
- Table language(s): [SELECT/LIST]
- Player experience supported: [BEGINNER / MIXED / EXPERIENCED]
- Commitment supported: [ONE-SHOT / CAMPAIGN]
- Maximum player capacity: [NUMBER]
- Operational accessibility supported: [SELECT/LIST / UNDISCLOSED]
- Content boundaries accepted: [SELECT/LIST / UNDISCLOSED]

## Evidence and safety review

- Relevant hosted-table evidence reviewed: [SYNTHETIC / UNAVAILABLE]
- Venue conduct expectations acknowledged: [SYNTHETIC / UNAVAILABLE]
- Stop/escalation procedure acknowledged: [SYNTHETIC / UNAVAILABLE]
- No private player details requested: [YES/NO]

## Commercial term

- P0 fixture: BHD10 fixed for one approved, delivered session.
- Actual offer authority: LOCKED
- DM acceptance: UNAVAILABLE
- Requested alternative term: UNAVAILABLE
- Expected session duration: UNAVAILABLE
- Implied hourly rate: UNAVAILABLE

The fixture is not an offer or evidence that a qualified DM will accept.

## Operator decision

- Decision: [APPROVE / REJECT / PENDING]
- Exact slot/system/format: [VALUE]
- Reason: [REQUIRED]
- Decision time: [FIXED SYNTHETIC TIME / UNAVAILABLE]
- Operator ID: [SYNTHETIC / UNAVAILABLE]
```

DM payment details, government identity, credentials, private contact data, and
tax information are outside this packet.

## Workbook content contract

`03_match_review_workbook.xlsx` must expose two visible sheets and no hidden
columns or sheets.

`Review Queue` columns, in order:

1. prospect ID;
2. route;
3. net-new proof state;
4. slot compatibility;
5. system compatibility;
6. language compatibility;
7. experience compatibility;
8. commitment compatibility;
9. optional requirements disclosed;
10. eligibility result;
11. proposal role;
12. retained reason;
13. operator decision; and
14. proof state.

`Evidence Ledger` columns, in order:

1. sequence;
2. subject ID;
3. event type;
4. from state;
5. to state;
6. reason;
7. synthetic timestamp; and
8. authority state.

The workbook must show the oracle's 4/3/3 routes, duplicate, two hard
mismatches, selected four, ordered waitlist, approval, decline, cancellation,
and replacement. It must not include contact data or public/player projections.

## `04_private_message_templates.md`

```markdown
# Private Pilot Message Templates

Status: COPY-READY DRAFTS / ALL UNSENT

These templates require separate approval of the exact recipients, message,
slot, DM term, and outreach channel. Bracketed fields must never be inferred.

## Invitation — only after operator approval

Hi [FIRST NAME OR APPROVED HANDLE] — we are privately testing one hosted
[SYSTEM/FORMAT] table for adults on [DATE] at [TIME]. We checked the schedule
and fit preferences you chose, and we would like to offer you one of four
places. The venue's normal BHD12 minimum food/drink bill applies; there is no
separate matching fee for this pilot. Please reply [ACCEPT] or [DECLINE] by
[DEADLINE]. This is an invitation, not a guaranteed booking, until confirmed.

## Confirmation

Your place is confirmed for the hosted [SYSTEM/FORMAT] table on [DATE] at
[TIME]. Please arrive by [ARRIVAL TIME]. The normal BHD12 minimum food/drink
bill applies. If your availability changes, tell us by [CANCELLATION METHOD] so
we can offer the place to the next compatible person.

## Decline acknowledgement

Thanks for letting us know. We have recorded the decline for this table only.
We will not treat it as a rejection of future tables.

## Waitlist

This table is currently full. With your permission, we can keep you on the
ordered waitlist for this exact slot until [EXPIRY]. A place is not guaranteed.
Reply [REMOVE] at any time to leave this waitlist.

## Replacement offer

A place has opened for the hosted [SYSTEM/FORMAT] table on [DATE] at [TIME].
Because your recorded fit matches this exact table, we are offering it to you
next. Reply [ACCEPT] or [DECLINE] by [DEADLINE]. No response is not acceptance.

## Reminder

Reminder: your hosted [SYSTEM/FORMAT] table is [DATE] at [TIME]. Please arrive
by [ARRIVAL TIME]. The venue's normal BHD12 minimum food/drink bill applies.
Reply [CANCEL] if you can no longer attend.

## Venue cancellation

This table will not run on [DATE/TIME]. We are sorry for the change. No charge
or fee is created by this message. Any separately authorized payment or refund
process would be handled under its own terms; none is part of pilot cell P0.
```

Do not add urgency, scarcity, testimonials, partnership claims, venue marks,
game-publisher marks, guaranteed fit, guaranteed attendance, or revenue claims.

## `05_dm_table_brief.md`

```markdown
# DM Table Brief

Status: SYNTHETIC / GENERATED ONLY AFTER OPERATOR APPROVAL

- Proposal ID: [PROPOSAL ID]
- Approved slot: [SLOT ID / DATE / TIME]
- System or format: [VALUE]
- Table language: [VALUE]
- Experience level: [VALUE]
- Commitment: [ONE-SHOT / CAMPAIGN]
- Player count: 4
- Aggregated operational accessibility requirements: [LIST / NONE RECORDED]
- Aggregated content boundaries: [LIST / NONE RECORDED]
- Venue arrival and table procedure: UNAVAILABLE
- Incident contact: UNAVAILABLE

This brief intentionally omits player identities, acquisition sources,
fingerprints, individual attribution, contact details, diagnoses, and payment
information. “None recorded” is different from “players disclosed none.”
```

## `06_session_run_sheet.md`

```markdown
# Hosted Table Session Run Sheet

Status: SYNTHETIC DRY RUN / LIVE RESULTS UNAVAILABLE

## Frozen table

- Experiment ID: [ID]
- Proposal ID: [ID]
- Slot: [ID / DATE / TIME]
- System or format: [VALUE]
- Approved DM ID: [ID]
- Player IDs: [FOUR OPERATOR IDS]
- Ordered waitlist IDs: [LIST]

## Confirmation ledger

| Player ID | Invited | Accepted | Declined | Confirmed | Cancelled | Replacement reason |
|---|---|---|---|---|---|---|
| [ID] | UNAVAILABLE | UNAVAILABLE | UNAVAILABLE | UNAVAILABLE | UNAVAILABLE | UNAVAILABLE |

## Delivery evidence

- DM arrived and delivered without Sadeq co-DMing: UNAVAILABLE
- Confirmed players: UNAVAILABLE
- Attended players: UNAVAILABLE
- No-shows: UNAVAILABLE
- Attendance rate: UNAVAILABLE
- Owner rescue minutes: UNAVAILABLE
- Matching minutes: UNAVAILABLE
- Confirmation/support minutes: UNAVAILABLE
- Material fit issue: UNAVAILABLE
- Safety/privacy incident: UNAVAILABLE
- Incident reference: UNAVAILABLE

## Operator close

- Delivered proof state: UNAVAILABLE
- Notes restricted to operational facts: UNAVAILABLE
- Stop condition triggered: UNAVAILABLE
```

Do not record narrative judgments about a person's personality, health, or
protected characteristics.

## Revenue workbook content contract

`07_revenue_attribution.xlsx` must expose visible `Attribution` and
`Proof States` sheets.

`Attribution` must show four player rows with bill, explicit net-new status, and
source proof state; named inputs for contribution margin, incremental overhead,
DM cost, discounts, refunds, fees, and support labor; and formula outputs for
gross, net-new share, attributable contribution, and non-negative result.

It must include two labeled synthetic cases:

- all four seats net-new: BHD48 gross, 100% net-new, BHD4.20 contribution;
- one seat transferred: BHD48 gross, 75% net-new, -BHD0.60 contribution.

Deleting any required input must produce `UNAVAILABLE` in every dependent
result. `Proof States` must keep proposed, approved, delivered, billed, settled,
and bank-reconciled separate; live states remain `UNAVAILABLE`.

## `08_privacy_safety_incident_runbook.md`

```markdown
# Privacy and Safety Runbook

Status: SYNTHETIC TEMPLATE / LIVE OWNERS UNAVAILABLE

## Minimize

- Use opaque operator IDs in the matcher and packet.
- Keep any separately authorized contact list outside the matching record.
- Collect only schedule, system, language, experience, commitment, and optional
  operational accessibility/content-boundary inputs.
- Never collect a diagnosis, home address, live location, payment credential,
  government ID, or open-ended personality profile in this pilot.

## Access and retention

- Data access owner: UNAVAILABLE
- Approved operators: UNAVAILABLE
- Retention period: UNAVAILABLE
- Deletion deadline: UNAVAILABLE
- Consent text/version: UNAVAILABLE

No real collection may begin while any item above is unavailable.

## Immediate stop conditions

Stop matching/contact/session preparation if any of these occurs:

- disclosure reaches an unauthorized person;
- consent, access owner, or retention rule is missing;
- a participant is a minor or age is unresolved;
- a material accessibility or content-boundary requirement cannot be met;
- harassment, threat, discrimination, coercion, or unsafe conduct is reported;
- the DM or exact table lacks operator approval;
- contact, venue, payment, receipt, or public authority is absent;
- someone is pressured to disclose optional information;
- a live result would otherwise be estimated or invented.

## Incident procedure

1. Stop the affected workflow; do not send another message.
2. Preserve the minimum evidence needed to explain what happened.
3. Restrict access and prevent further disclosure.
4. Notify the named incident owner through an approved private channel.
5. Record facts, affected record IDs, time, scope, action, and unresolved risk.
6. Delete or correct data only under the approved retention/deletion process.
7. Resume only after the incident owner records a safe, scoped decision.

Incident owner: UNAVAILABLE
Approved notification channel: UNAVAILABLE
Resume authority: UNAVAILABLE
```

## `09_pilot_decision_card.md`

```markdown
# Private Pilot Decision Card

Status: SYNTHETIC DRY RUN

Decision: [PASS / REVISE / KILL / PARK / UNAVAILABLE]

## Commercial proof

- Four of four seats verified net-new: UNAVAILABLE
- External DM accepted declared term: UNAVAILABLE
- External DM delivered without Sadeq rescue: UNAVAILABLE
- Attendance at least 80%: UNAVAILABLE
- Bills settled and tied to exact added table: UNAVAILABLE
- Incremental contribution after all measured costs: UNAVAILABLE
- Bank reconciliation: UNAVAILABLE

## Operational proof

- Acquisition route counts: SYNTHETIC 4/3/3
- Duplicate/mismatch evidence retained: SYNTHETIC PASS
- Operator approval before invitation: SYNTHETIC PASS
- Matching minutes: UNAVAILABLE
- Confirmation/support minutes: UNAVAILABLE
- Owner rescue minutes: UNAVAILABLE
- Unresolved safety/privacy/material-fit issue: UNAVAILABLE

## Decision rule

PASS requires every declared live commercial, operational, safety, and
settlement criterion to pass. Missing evidence is UNVERIFIED. A proposal,
compliment, form completion, attendance intention, gross bill, or synthetic
result is not settled external profit.

## Exact next gate

[ONE SCOPED ACTION, OWNER, AUTHORITY, EVIDENCE, AND STOP POINT]

This decision does not authorize another Factory station.
```

## `10_launch_checklist.md`

```markdown
# Private Pilot Launch Checklist

Status: NOT LAUNCHABLE / ALL LIVE GATES LOCKED

## Synthetic packet acceptance

- [ ] All eleven artifacts exist and hashes verify
- [ ] Two generations are byte-identical
- [ ] Match and revenue workbooks pass formula/structure checks
- [ ] Every page and sheet is visually inspected
- [ ] Synthetic operator regressions pass

## Real-data gate

- [ ] Exact fields approved
- [ ] Consent text/version approved
- [ ] Access owner approved
- [ ] Retention and deletion period approved

## Contact gate

- [ ] Exact recipients approved
- [ ] Exact private channel approved
- [ ] Exact message/version approved
- [ ] Contact stop rule approved

## DM gate

- [ ] Exact DM approved
- [ ] Exact compensation term approved
- [ ] Maximum exposure approved
- [ ] Delivery and cancellation terms approved

## Venue and safety gate

- [ ] Exact slot/table approved
- [ ] Incident owner and channel approved
- [ ] Accessibility/boundary capability confirmed
- [ ] No existing-table seat will be reclassified as net-new

## Money and evidence gate

- [ ] Receipt access approved
- [ ] Margin definition and source frozen
- [ ] Incremental costs and support time capture frozen
- [ ] Any payment/deposit/refund authority approved separately

## Public gate

- [ ] Public copy or listing approved
- [ ] Public channel/account approved
- [ ] Marks and affiliation claims approved

## Final status

LAUNCH AUTHORIZED: NO
LIVE DATA AUTHORIZED: NO
CONTACT AUTHORIZED: NO
PAYMENT AUTHORIZED: NO
PUBLICATION AUTHORIZED: NO
LATER FACTORY STATION AUTHORIZED: NO
```

## Content acceptance

The generated Markdown passes only if it preserves this meaning exactly, keeps
all synthetic/live proof distinctions, contains no invented venue detail or
actual person, and leaves all live gates locked. Formatting changes may improve
legibility but may not weaken consent, privacy, economics, evidence, or
authority language.
