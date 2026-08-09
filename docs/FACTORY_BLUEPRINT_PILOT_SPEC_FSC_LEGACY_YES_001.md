# Find My Table — Hosted One-Shot Pilot Specification

> **HISTORICAL — SUPERSEDED BY `FSC-LEGACY-YES-001-BP-IC-v3`.** Sponsor
> operating evidence proves the venue already fills two hosted tables weekly.
> Do not use this paid-seat pilot as the active product contract. See
> `FACTORY_BLUEPRINT_SCALE_SPEC_FSC_LEGACY_YES_001.md`.

Packet: `FSC-LEGACY-YES-001-BP-IC-v2`
Factory run: `factory-run-legacy-recovery-20260809-tablefinder-01`
Candidate: `FSC-LEGACY-YES-001`
Station: **BLUEPRINT ONLY**
Status: **SPECIFICATION FROZEN FOR SPONSOR INVESTMENT REVIEW**

This document freezes the smallest evidence-producing version of Find My Table.
It does not authorize Assembly, venue or host contact, outreach, publishing,
payments, account use, credentials, spending, or an event.

## Product decision

Find My Table begins as a **manually operated, adult-only hosted TTRPG one-shot
service in a consenting public Bahrain venue**, not as a general matching app.

The first buyer is an adult newcomer or lapsed player. The paid outcome is:

> A confirmed seat at a beginner-friendly, fixed-time TTRPG one-shot, with the
> host, expectations, fit and safety boundaries made clear before payment.

The service is the matching product. The software becomes eligible only after
paid sessions show which coordination step repeatedly consumes time or causes
failure.

## Buyer and non-buyer

### First buyer

- age 18 or older;
- interested in trying a TTRPG without already having a group;
- willing to attend a 2.5–3 hour public-venue session at a fixed time;
- wants beginner onboarding, clear table expectations and a confirmed seat;
- pays the displayed seat price under disclosed cancellation/refund terms.

### Explicitly not first

- minors;
- private-home groups;
- established friend groups needing only scheduling;
- campaign players seeking a long-term recurring table;
- venues buying administration software;
- GMs buying tools;
- users seeking open chat, social feeds or location tracking.

## Frozen paid offer

| Field | Blueprint specification |
|---|---|
| Working offer | Find My Table: Beginner One-Shot |
| Format | One fixed-date, 2.5–3 hour, system-identified TTRPG session |
| Location | One consenting public Bahrain venue; no venue is assumed |
| Age | 18+ only |
| Capacity | Target 5–6 paid players; never increase merely to rescue margin |
| Price cells | BHD5 first local-anchor test; BHD7 changed-price test if earned |
| Included | Host, beginner explanation, pre-session fit/boundary intake, confirmed seat, reminder, waitlist/replacement handling, issue path |
| Excluded | App, subscription, campaign, private home, transport, live location, direct messages, player ratings, public profiles, proprietary game content |
| Refund promise | Exact terms must be approved and published before collection; full refund if the organizer cancels is the minimum proposed rule |
| Success proof | External settled payment plus attendance, refund, no-show, repeat-purchase and contribution evidence |

The BHD5 and BHD7 prices are hypotheses. Neither is validated willingness to
pay. The system, adventure, host, venue, date and final refund terms remain live
dependencies requiring later approval; no named venue or game publisher is
represented as participating.

## Customer experience blueprint

### 1. Discover

The buyer sees one truthful offer containing the actual system, host identity or
approved host description, date/time, public venue, adult boundary, experience
level, content expectations, accessibility limitations, seat count, price and
refund terms. No fake scarcity or hidden recurring charge.

### 2. Fit intake

Collect only what is needed:

- first name or pseudonym and a private contact route;
- 18+ affirmation;
- prior TTRPG experience;
- language preference;
- attendance commitment;
- voluntary accessibility needs;
- voluntary content boundaries;
- agreement to the table conduct rules.

Do not collect government ID, home address, live location, medical diagnosis,
public profile, player rating or unnecessary demographic data. The actual
lawful basis, processor, access control and deletion notice must be approved
before any collection.

### 3. Confirm and pay

The live version may collect payment only through an approved sponsor-owned
route after business/legal feasibility is confirmed. A seat is not confirmed
until the payment state is explicit. The ledger must keep `reserved`, `paid`,
`refunded`, `settled` and `bank_reconciled` distinct.

### 4. Prepare

- send confirmation immediately;
- send one T-48-hour commitment check;
- replace a cancellation from one ordered waitlist;
- send the final practical reminder at T-24 hours;
- provide a concise beginner primer without copying protected rules or text;
- give the host only the minimum approved fit/boundary brief.

### 5. Run

The host opens with table expectations, safety tools, content boundaries, break
and exit options, venue rules and the escalation path. Attendance and incidents
are recorded privately. No participant is publicly scored.

### 6. Close and learn

Record attendance, issue/refund status, support and operations minutes, direct
costs, payment fees, host/venue terms and settlement. Ask whether the player
would pay for another confirmed hosted seat; only a later paid reservation or
purchase counts as repeat demand. Delete intake data on the declared schedule,
subject to a documented incident or legal retention need.

## Manual operating roles

| Role | Responsibility | Gate |
|---|---|---|
| Sponsor | Accept investment verdict, identity/public copy, accounts, credentials, spend, payment route, venue/host/outreach and release | Explicit each time |
| Factory operator | Prepare evidence, offer, scripts, forms, ledger design, calculations and decision packet | Repository-local Blueprint work |
| Host | Run the session, respect boundaries, report attendance/incidents | Identity, terms and suitability must be approved before offer |
| Venue | Permit the exact use, date, capacity and commercial arrangement | Written/recorded permission before naming or publishing |
| Payment provider | Process and settle external customer money | Account, KYC, terms and payment authority remain sponsor-controlled |

No role is currently filled merely because it is described here.

## Unit-economics contract

The current model uses:

- 3% payment-cost assumption;
- 5% refund reserve;
- two operations hours valued at BHD5/hour;
- BHD30 fixed-host sensitivity, plus a 70% revenue-share sensitivity;
- no venue cost because venue terms are unknown, not because venue cost is zero.

At six BHD5 seats with a BHD30 host, modeled contribution is **-BHD12.40**.
At six BHD7 seats it is **-BHD1.36**. The maximum break-even host compensation
at six seats is BHD17.60 at BHD5 or BHD28.64 at BHD7 before any venue cost.

Therefore:

1. the first box is a capped mechanism test expected to lose money;
2. venue and host economics must be measured before claiming viability;
3. a large table cannot be used to manufacture margin at the expense of the
   beginner experience;
4. payment count alone is not a pass; later scale requires non-negative measured
   contribution after labor, refunds, host, venue and payment costs.

## First-ten-buyer acquisition design

This is a future execution design, not permission to contact anyone.

1. Prepare one exact evidence page for one real date, host, permitted venue and
   price.
2. Sponsor approves one message, sender identity and bounded audience.
3. Offer first to a genuine owned network; friendship, compliments and free
   attendance do not count as demand.
4. With moderator or venue permission, make one transparent post in at most two
   relevant Bahrain communities; no scraping, bulk messages or duplicate posts.
5. Attribute every paid seat to one source.
6. Open a second date only after the first date earns it or a materially changed
   hypothesis is recorded.

## Instrumentation ledger

The manual pilot must preserve:

- offer version, price, date and seat cap;
- source and number of qualified offer views where observable;
- checkout starts where exposed by the provider;
- reserved, paid, refunded, attended and no-show counts;
- gross, payment fee, refund, host, venue and other direct costs;
- net processor receipt and later bank settlement reference;
- operations and support minutes;
- waitlist fills and cancellation timing;
- safety/accessibility issues and resolution state;
- later paid reservation/purchase count;
- changed hypothesis before any retry.

Provider tokens, credits or impressions are recorded only when exposed. They are
never estimated.

## Pass, revise and kill gates

### Mechanism pass after at most two separately authorized dates

Require all of the following:

- at least eight external paid seats total;
- at least six payments remain settled after refunds;
- at least one date has five paid seats at the tested price;
- at least two actual later paid reservations or purchases;
- refund rate no more than 15%;
- no-show rate no more than 20%;
- operations no more than 60 minutes per session after the first;
- no unresolved safety issue;
- measured host terms are non-negative at six seats before scale.

This passes the mechanism only. It does not prove repeatable profitability or
authorize software.

### Revise once

Revise one variable only when evidence identifies a causal failure: buyer,
message, price, date/time, format, host terms or venue terms. Preserve the failed
offer and reason. An unchanged retry is prohibited.

### Kill or park

Kill or park when two materially distinct offers each fail to produce four paid
seats, full-capacity economics remain negative, acceptable host/venue terms
cannot fit the cap, safety/legal/payment obligations exceed the cap, or no
changed hypothesis remains.

## Software eligibility gate

No app starts merely because the service operates. Software becomes a Blueprint
candidate only after:

1. at least four paid hosted sessions;
2. repeat paid behavior exists;
3. a specific coordination step repeatedly exceeds 60 minutes per session or
   causes a recorded failure;
4. the proposed feature removes that measured bottleneck;
5. the software cost is lower than the expected saved operations burden within
   a declared evidence window.

The first eligible features are intake, seat confirmation, ordered waitlist,
replacement and host operations. Chat, social feeds, recommendation AI, public
ratings, multi-venue marketplaces and global discovery remain excluded until
separately evidenced.

## Investment box

Recommended Blueprint verdict remains **REVISE**. If Sadeq later chooses
`INVEST`, the maximum first mechanism box is:

- 12 agent hours;
- 20 sponsor review/approval minutes;
- BHD50 cash;
- one adult beginner one-shot;
- one consenting public venue;
- one approved host;
- no app;
- every live action separately authorized.

The next decision is the Shark verdict on packet
`FSC-LEGACY-YES-001-BP-IC-v2`: `INVEST`, `REVISE`, `KILL` or `PARK`. Feedback
does not itself authorize Assembly or any live action.
