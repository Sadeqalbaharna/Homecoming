# Find My Table — Venue Scale Investment Memo

Packet: `FSC-LEGACY-YES-001-BP-IC-v3`  
Factory run: `factory-run-legacy-recovery-20260809-tablefinder-01`  
Candidate: `FSC-LEGACY-YES-001`  
Station: **BLUEPRINT ONLY**  
Decision model version: `DM-COMP-v1`

## Investment answer

**INVEST in a bounded, repository-local operations MVP. Do not yet invest in a
marketplace or customer-facing app.** The venue already proves that people will
attend: Sadeq fills and DMs two four-player tables each week. The investable
problem is operational leverage—finding more suitable players and external DMs,
then matching availability and fit without making Sadeq the permanent DM.

The safest provisional external-DM structure is **BHD10 fixed per delivered
session**, paid only for an approved, completed table. It caps cost and is easy
to reconcile. This is a planning default, not a live offer or sponsor-confirmed
compensation policy. It is viable at four BHD12 seats only if the venue's
measured contribution margin is at least **31.25%** when other incremental
overhead is BHD5 per table. Actual venue margin and DM acceptance are unverified.

## What is fact, and what is modeled

Sponsor-attested facts: the venue is sponsor-owned; two hosted tables fill each
week; Sadeq DMs them; average attendance is four; each player has a BHD12 minimum
food/drink bill; the constraints are finding players, finding DMs, and matching
schedule/fit. This establishes a BHD48 minimum gross bill per full table and a
BHD96 weekly existing gross floor. It does **not** establish profit or uplift.

Decision assumptions—not actual costs—are a 25%–70% venue contribution-margin
range, BHD0–10 incremental non-DM overhead per table, and a BHD20 setup-recovery
allowance. The central comparison uses 40% margin and BHD5 overhead. Venue
credit is conservatively costed at face value; its true economic cost could be
lower, but only measured food/beverage cost can establish that.

`net incremental table contribution = seats × net-new-player fraction × BHD12 × contribution margin − incremental overhead − DM compensation`

The central case also needs at least **78.125% of a four-seat table to be
genuinely incremental**: `(BHD10 + BHD5) ÷ (BHD48 × 40%)`. One player transferred
from an existing table removes BHD4.80 of contribution, more than the modeled
BHD4.20 base upside. A moved player therefore does not count as acquisition.

## DM compensation sensitivity

At the central 40% margin and BHD5 overhead, a four-seat table has BHD14.20 of
pre-DM contribution. Break-even seats are the smallest whole seat count yielding
non-negative modeled contribution.

| Structure | Tested terms | Four-seat result | Break-even seats | Reading |
|---|---:|---:|---:|---|
| Fixed fee | BHD6 / 10 / 15 / 20 | BHD8.20 / 4.20 / -0.80 / -5.80 | 3 / 4 / 5 / 6 | Most predictable; BHD10 is the provisional ceiling-friendly default. |
| Gross revenue share | 10% / 15% / 20% / 25% | BHD9.40 / 7.00 / 4.60 / 2.20 | 2 / 2 / 3 / 3 | Aligns cost with sales, but gross-share accounting obscures food cost and may be unattractive at low percentages. |
| Venue food/credit | BHD6 / 12 / 18 / 24 face value | BHD8.20 / 2.20 / -3.80 / -9.80 | 3 / 4 / 5 / 7 | Potentially cash-light; use face value until actual COGS is measured. Never stack it on the fixed fee by default. |
| Volunteer/community host | BHD10 / 15 / 20 / 25 shadow value | BHD4.20 / -0.80 / -5.80 / -10.80 | 4 / 5 / 6 / 7 | Cash-cheap but not scalable by default; zero-value labor is excluded. |

For the modeled BHD20 setup allowance, central-case recovery requires five
additional tables at the BHD10 fixed fee, three at a 15% gross share, ten at a
BHD12 face-value credit, and five when volunteer labor is honestly valued at
BHD10. Those are sensitivities, not forecasts.

Assuming 2.5–4 total hours for preparation plus play, BHD10 implies only
BHD2.50–4.00/hour. That may be unacceptable to qualified DMs. Actual session
length, preparation burden and reservation wage remain unverified; a fee fair
to the DM can still fail venue economics.

### Fixed BHD10 sensitivity

| Contribution margin | BHD0 overhead | BHD5 overhead | BHD10 overhead |
|---:|---:|---:|---:|
| 25% | BHD2.00 | -BHD3.00 | -BHD8.00 |
| 40% | BHD9.20 | BHD4.20 | -BHD0.80 |
| 55% | BHD16.40 | BHD11.40 | BHD6.40 |
| 70% | BHD23.60 | BHD18.60 | BHD13.60 |

The recommendation is conditional: measure contribution margin and incremental
overhead first. If margin is below 31.25% in the BHD5-overhead case, do not solve
the problem by overfilling a four-player experience. Revise the DM term,
overhead, minimum spend, or experiment.

## Pricing and cost ceiling

- Customer price: the venue's existing **BHD12 minimum food/drink bill**, with
  no new ticket or matching fee in the first experiment.
- DM price: model BHD10 fixed per delivered session; sponsor confirmation and a
  real DM acceptance test remain required.
- Next-station ceiling, **only after separate exact Assembly authorization**:
  20 agent hours and BHD0 new cash for schemas, rules, synthetic fixtures,
  operator review, and attribution. `INVEST` is a product verdict, not that
  authorization, and this is not an assertion about labor already spent.
- Live test ceiling: one additional table per week for four weeks, after
  separate approval. No advertising or new software subscription is assumed.
- Revenue proof: external venue bills settled and reconciled to an additional
  table. Existing revenue, bookings, compliments, and matches do not count.

## First ten-player acquisition design

The aim is ten qualified prospects, not ten claimed buyers. After live outreach
authority, use owned and earned channels only:

1. invite up to four referrals from existing players, source recorded;
2. invite up to three suitable venue regulars or existing inbound enquirers;
3. invite up to three from a sponsor-approved local/community channel;
4. use one intake form and the same eligibility/consent language for all;
5. form at most two four-player proposals and keep remaining compatible people
   as a transparent waitlist;
6. record decline, schedule conflict, system mismatch, fit constraint and
   no-response separately.

These are allocation targets, not predicted conversions. No contact or public
post is authorized in Blueprint.

## External-DM supply design

Start with one approved external DM, not a marketplace. Capture systems,
formats, availability, capacity, experience evidence, safety agreement, terms,
and acceptance of a precise table brief. Sadeq approves the person and table.
The DM sees only minimum necessary player information. Measure sourcing time,
acceptance, preparation/support minutes, delivery, player experience, and
whether Sadeq had to co-DM or rescue the session.

## Four-week falsifiable experiment

Before launch, freeze the margin definition, compensation structure, table
attribution rule, and live authority. Then attempt one additional four-player
table per week with one approved external DM.

Pass only if, within four weeks:

- at least three additional attributable tables are delivered;
- average attendance is at least three and confirmed-player attendance is 80%+;
- an approved external DM delivers every counted additional table without Sadeq
  co-DMing or rescuing it;
- every added table has non-negative measured incremental contribution;
- operator time is measured and does not rise per table after the first two;
- no unresolved safety, privacy, or material-fit issue remains;
- settled venue receipts reconcile to the originating added tables.

Change one variable per round. If compensation fails, test one changed structure
or amount—not the identical offer. Stop if the table is contribution-negative,
the DM experience is unacceptable, or player safety/fit cannot be managed.

## Conservative / base / upside

These are four-week scenarios for **additional** full tables, not forecasts.

| Case | Margin / overhead / DM term | Added tables | Net per table | Four-week contribution |
|---|---|---:|---:|---:|
| Conservative | 25% / BHD5 / BHD10 fixed | 3 | -BHD3.00 | -BHD9.00 — fails |
| Base | 40% / BHD5 / BHD10 fixed | 4 | BHD4.20 | BHD16.80 |
| Upside | 55% / BHD5 / BHD10 fixed | 4 | BHD11.40 | BHD45.60 |

At four added full tables the gross floor is BHD192 in every case; gross is not
contribution and must never be presented as profit.

## Principal risks and controls

| Risk | Early evidence | Control / stop rule |
|---|---|---|
| DM terms unattractive | no qualified DM accepts | revise one term once; do not call volunteer labor scalable |
| Venue margin too thin | measured full-table contribution negative | stop; never count gross as success |
| Sadeq stays bottleneck | rescue/co-DM time remains high | fail leverage thesis even when tables fill |
| Schedule/fit weakness | repeated unmatched reason or churn | change one matching hypothesis; preserve rejects |
| Safety/privacy harm | over-sharing or unresolved incident | stop matching; minimize data; require operator review |
| False attribution | receipts cannot tie to added tables | mark revenue proof unverified |
| Cannibalization | existing tables lose players | require ≥78.125% net-new seats in the central case; measure source and net additions |
| Automation outruns trust | opaque score or automatic invitation | deterministic reasons and human approval only |

## 30 / 60 / 90-day roadmap

- **0–30 days after INVEST and separate Assembly authorization:** build the
  repository-local model with synthetic data, instrument current operations,
  define consent/retention, and confirm margin and DM compensation. No live use
  is implied.
- **31–60 days after separate live approval:** run the one-table-per-week window,
  preserve every proposal/outcome, and reconcile contribution.
- **61–90 days:** only after a pass, repeat with a second DM or slot while holding
  other variables stable. Do not open a public marketplace.

## Investment-committee narrative and speaker notes

1. **Proof already exists:** “We fill two four-player tables weekly; this is not
   a demand-from-zero pitch.”
2. **Constraint:** “Growth is capped by player/DM discovery and schedule/fit,
   while the owner is still the DM.”
3. **Wedge:** “Build an internal operator, not another social network.”
4. **Money:** “A full table is BHD48 gross minimum; contribution depends on real
   food, labor, overhead, and DM cost.”
5. **DM economics:** “BHD10 fixed is safest provisionally, but needs at least
   31.25% margin at BHD5 overhead.”
6. **Experiment:** “One additional weekly table, four weeks, one external DM,
   deterministic matching, human approval.”
7. **Proof gate:** “Three delivered additions, 80% attendance, non-negative
   contribution, ≥78.125% net-new seats in the central case, settled receipts,
   and no owner rescue.”
8. **Stop-loss:** “No marketplace, ads, or feature expansion if the unit fails.”
9. **Ask:** “Approve only the 20-hour/BHD0 local MVP. Live action stays locked.”

## Decision and smallest remaining gate

Recommended verdict: **INVEST** in the proposed local internal-operations MVP
under the 20-hour/BHD0 cap, contingent on separate exact Assembly authority.
Sponsor confirmation of the live DM structure remains pending;
the provisional recommendation is “BHD10 fixed per approved, delivered session,
not stacked with venue credit.” No Assembly, outreach, customer-data use,
account access, payment, spending, publishing, or live venue action is authorized.

At presentation close, capture `INVEST / REVISE / KILL / PARK`, confidence 0–10,
strongest reason, first belief increase/drop, weakest element, customer change,
and proof needed. Feedback does not authorize the next station.

## Claude challenge adjudication

Persistent Claude session `dbfce24c-0faf-460a-9f1f-a7e6c7b422f5` independently
challenged the compact economics/process packet. Codex reproduced each adopted
calculation locally.

- **ACCEPTED:** missing cannibalization sensitivity. Added net-new-player
  fraction and the 78.125% central threshold.
- **REJECTED AS WORDED, CONTROL RETAINED:** “three-player attendance and
  non-negative contribution are mutually unsatisfiable.” They are independent
  gates, so a three-player table may correctly fail on contribution. The packet
  now makes margin-dependent contribution decisive rather than treating three
  attendees as a pass.
- **ACCEPTED:** INVEST language could blur Assembly. The memo now requires a
  separate exact Assembly authorization before executable build work.
- **ACCEPTED:** one external-DM delivery under-tested owner substitution. Every
  counted additional table must now be external-DM delivered without rescue.
- **ACCEPTED:** DM attractiveness lacked an hourly view. Added a 2.5–4-hour
  sensitivity; actual prep/play time and reservation wage remain UNVERIFIED.
- **ACCEPTED:** zero-value volunteer labor distorted optimization. Removed it.
- **ACCEPTED:** dedupe, retry suppression, calibration continuity and sponsor
  investment verdict needed enforceable reusable-process representation. Added
  explicit types, validations and tests.
- **ACCEPTED:** first-ten routes needed net-new-buyer semantics and alignment.
  All route allocations now default to requiring net-new buyers.
- **UNVERIFIED:** whether BHD10 attracts a qualified external DM; whether the
  venue's measured contribution margin clears 31.25%; actual cannibalization;
  and actual preparation/play hours.
