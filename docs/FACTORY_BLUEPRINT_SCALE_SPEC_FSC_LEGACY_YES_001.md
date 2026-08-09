# Find My Table — Venue Table Scaling Blueprint

Packet: `FSC-LEGACY-YES-001-BP-IC-v3`
Factory run: `factory-run-legacy-recovery-20260809-tablefinder-01`
Candidate: `FSC-LEGACY-YES-001`
Station: **BLUEPRINT ONLY**
Status: **READY FOR SPONSOR INVESTMENT VERDICT**

This v3 packet supersedes the v2 paid-seat pilot. It is grounded in the sponsor's
existing hosted-table business and does not authorize Assembly or live action.

## Answer first

**Recommendation: INVEST in a bounded internal operations MVP, not another
hosted-event pilot and not a public marketplace.**

Find My Table should help the sponsor-owned venue grow beyond two weekly tables
by acquiring and retaining a player pool, recruiting usable DM capacity, and
forming compatible four-player tables across schedules. Revenue is incremental
venue food-and-drink contribution, not an event ticket or app subscription.

## Verified operating baseline

- venue is sponsor-owned;
- two hosted tables are filled per week;
- sponsor currently DMs them;
- four players per table on average;
- BHD12 minimum food/drink bill per player;
- BHD48 minimum gross bill per average table;
- BHD96 minimum gross weekly bill across the two current tables;
- binding problems: finding players, finding DMs, and matching schedule/fit.

These facts are sponsor-attested. Existing revenue is not credited to the new
product. Profit and incremental contribution remain unverified.

## Product Northstar

Increase **incremental contribution from additional reliably filled tables**
without requiring Sadeq to DM every table or damaging player fit and experience.

The product does not pass because it stores profiles, produces matches or fills
a calendar. It passes only when a new table attributable to the system occurs,
external customers settle their venue bills, the revenue is reconciled, and
incremental contribution remains after food cost, staff labor and DM cost.

## Product users

### Venue operator

Needs a complete view of player demand, DM supply, proposed tables, confirmation
risk, unmatched reasons and revenue attribution. Retains final match and table
approval.

### Player

Needs a low-friction way to state availability, game interests, experience,
language, commitment and fit preferences, then receive a suitable table offer.

### DM

Needs to state systems, formats, availability, experience, capacity and terms,
then accept an exact table assignment with an approved player brief.

## Frozen MVP workflow

1. **Player pool:** capture minimum matching traits, acquisition source and
   consent; do not create public profiles.
2. **DM roster:** record availability, systems, formats, capacity, approval
   state and compensation terms.
3. **Session inventory:** operator creates candidate time slots with system,
   format, four-player target and venue capacity.
4. **Match proposal:** deterministic rules group compatible players and eligible
   DMs; reasons and unmatched constraints remain visible.
5. **Human approval:** venue operator approves, edits or rejects every proposed
   table before invitations.
6. **Confirmation:** track invited, accepted, declined, waitlisted, confirmed,
   attended and no-show separately.
7. **Replacement:** fill a cancellation from an ordered compatible waitlist;
   never send uncontrolled bulk invitations.
8. **Table delivery:** give the DM only the minimum approved fit/boundary brief.
9. **Attribution:** reconcile attendance and venue bill to the table; calculate
   gross and contribution separately.
10. **Learning:** preserve acquisition source, mismatch reason, DM utilization,
    schedule failure, fit feedback and changed next hypothesis.

## Matching dimensions

### Required for the first MVP

- player availability windows;
- game/system interest;
- beginner/experienced comfort;
- language;
- session commitment and campaign/one-shot preference;
- voluntary accessibility and content-boundary needs;
- DM system/format eligibility and availability;
- four-player table capacity.

### Explicitly excluded initially

- public profiles or player ratings;
- open direct messages;
- live location or home addresses;
- recommendation AI or opaque compatibility scores;
- multiple venues;
- public marketplace listings;
- app-based payment collection;
- social feed, followers or reviews;
- automated DM approval;
- minors.

## Revenue model

Players continue paying the venue's normal minimum food/drink bill. Find My
Table does not add a ticket in the first MVP.

For an attributable table:

`gross venue bill = sum(actual player food/drink bills)`

`incremental contribution = gross venue bill - food/beverage cost - incremental staff labor - DM compensation - matching/support cost - discounts/refunds`

The BHD12 minimum produces a BHD48 gross floor at four players. It is not a
margin target. External DM compensation cannot be chosen safely until actual
venue contribution and expected DM work are recorded.

## First evidence window

### Baseline instrumentation

For four operating weeks, record the existing two-table process without changing
customer treatment:

- player acquisition source;
- inquiry-to-confirmation funnel;
- days and messages required to fill each seat;
- unmatched players and exact constraint;
- cancellations and no-shows;
- sponsor DM and coordination minutes;
- actual players, gross bill, food/beverage cost and contribution per table;
- repeat attendance;
- requested dates/systems that could not be served.

Historical records may shorten this window only when their definitions match.
Account/customer-data access remains sponsor-controlled.

### Scale hypothesis

After baseline and separate live approvals, test whether the system can support
one additional four-player table per week using an approved external DM. The
gross floor is BHD48 per added full table. The experiment passes only on
incremental contribution and acceptable experience, not gross sales alone.

## MVP pass gate

Within a declared four-week scale window, require:

- at least three additional delivered tables attributable to the workflow;
- average attendance of at least three players per additional table;
- at least one approved external DM delivers a table without Sadeq co-DMing;
- at least 80% of confirmed players attend;
- no unresolved safety or material fit issue;
- unmatched and rejected proposals retain explicit reasons;
- operator coordination time is measured and does not increase per delivered
  table after the first two;
- each added table has non-negative measured incremental contribution after
  food cost, staff labor, DM compensation and matching/support time;
- venue receipts settle and are reconciled to the originating tables.

Thresholds are Blueprint hypotheses. Baseline evidence may revise them before a
live scale test, but the revision must be recorded before results are known.

## Kill and stop-loss rules

- Do not scale when an added full table is contribution-negative under acceptable
  DM terms.
- Stop automated matching after any unsafe or materially misleading match until
  the cause and rule change are recorded.
- Do not retry the same acquisition or DM-supply hypothesis after a failed
  evidence window.
- Stop at one venue until the internal operation produces repeatable incremental
  contribution.
- Do not build public marketplace/network features to compensate for a weak
  local player or DM pool.
- Do not count existing two-table revenue as product-generated uplift.

## Local Assembly box after INVEST

An `INVEST` verdict would authorize only a repository-local prototype and
operating packet:

- player and DM intake schemas;
- match-proposal rules with visible reasons;
- operator review queue;
- session/confirmation/waitlist state model;
- privacy and retention fields;
- venue-revenue attribution ledger;
- deterministic tests and sample fixtures using synthetic data;
- operator runbook and measurement definitions.

It would not authorize customer-data import, account access, player/DM contact,
public release, payment handling, spending or use in the live venue. Each remains
a later exact gate.

## Open variables that must remain visible

- average actual spend above the BHD12 minimum;
- food/beverage and labor contribution margin;
- current acquisition channels and funnel losses;
- fill lead time, unmatched-player volume, cancellations and no-shows;
- acceptable external-DM compensation and approval criteria;
- sponsor coordination/DM time;
- venue capacity by time slot;
- player consent, privacy and retention workflow;
- which mismatch dimension causes the most lost tables.

## Exact decision

Sadeq chooses `INVEST`, `REVISE`, `KILL` or `PARK` for
`FSC-LEGACY-YES-001-BP-IC-v3`.

Recommended verdict: **INVEST in the local internal-operations MVP only**. No
live or public authority is implied.
