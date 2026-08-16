# Product Factory — project source of truth

## Authority

This document governs the Factory project slice shown by Homecoming. Factory is
one commercial line serving multiple product runs/lanes. The Pizza wheel shows
the furthest evidence-backed line capability reached by any individual product
lane; it does not collapse product identities or transfer one product's
authority to another. Operational runs and typed product-lane evidence remain
authoritative for their own facts. The UI cannot manufacture progress,
approval, sales, or revenue.

The sponsor owns product meaning, release approval, bank access, and acceptance
of the final commercial outcome.

## Northstar

**Actual money into the bank account.**

The Northstar is reached only when a genuine external customer payment has:

1. purchased the approved product;
2. settled as a positive amount into Sadeq's bank account; and
3. been reconciled to the originating order through a recorded bank or payment
   processor settlement reference.

A listing, page view, checkout, sale notification, processor balance, test
payment, self-payment, pending payout, or unreconciled deposit does **not** meet
the Northstar.

## Non-negotiable invariants

- Every phase advances from recorded evidence, never UI state or agent claims.
- Publishing requires run-bound human approval that Kai cannot mint.
- Starting Factory Mode does not grant publishing or money authority.
- A product run does not inherit evidence or approval from another product.
- Line-level maturity is the maximum typed, evidence-backed stage reached by a
  product lane; descriptive prose alone cannot advance it.
- Revenue is zero for Northstar purposes until it settles in the bank.
- The final gate requires a positive amount and a reconciliation reference.
- Failed and rejected attempts remain useful history; they are not progress.

## Pre-build commercial value gate

`factory-pre-build-commercial-value-v1` sits at Blueprint and applies before
Assembly. Its origin is recorded rather than theorised: Practice Ladder passed
every technical check and the sponsor rejected it on buyer value and quality.
The gate exists so that verdict arrives before substantial build work, not
after it.

Six required checks: a one-sentence paid transformation naming the exact buyer
and why payment is rational; a depth benchmark against at least three real
current products with live external evidence; a finished buyer-facing sample;
an adversarial buyer-value review; sponsor review of that exact sample hash;
and a thin-wrapper kill.

**Technical tests cannot pass this value gate.** A green suite proves the thing
works, never that anyone would pay for it, and the run that created this gate
is the proof of that distinction. Agents may prepare evidence and may not infer
sponsor approval. Passing authorizes neither Assembly nor publishing.

Verdicts are PASS, REVISE, KILL or UNVERIFIED. UNVERIFIED is not a soft pass.

## Advancement gates

| # | Station | Outcome | Exit gate |
|---|---|---|---|
| 0 | Signal Scan | Choose a painful problem and reachable external buyer | Specific buyer, painful job, demand signal, and rejected alternatives recorded |
| 1 | Blueprint | Freeze the smallest sellable offer and economic model | Scope, cuts, price, channel, fulfilment, refund terms, and margin explicit |
| 2 | Assembly | Produce the exact artifact the buyer receives | Sellable artifact exists at a durable path and matches the offer |
| 3 | QA Gate | Prove product and delivery are safe | Build, tests, purchase-to-delivery, support, and refund handling pass |
| 4 | Packaging | Prepare a truthful purchasable offer | Listing copy, assets, price, files, and payment route ready |
| 5 | Approval | Sponsor accepts exact public release | Valid human approval exists for this exact run |
| 6 | Dispatch | Release to an external customer | Approved product is purchasable at a verified live URL |
| 7 | Telemetry | Observe real market and fulfilment outcomes | At least seven days of views and sales recorded against the original prediction |
| 8 | Money in Bank | Convert a genuine sale to spendable banked revenue | Positive customer money settled in Sadeq's bank and reconciled to the order |

## Line-level derivation

- Find My Table remains an individual product lane at Blueprint. Its candidate,
  packet, assumptions, and authority remain product-bound.
- Factory Daily / BoothSignal remains a separate typed product lane. Build and
  QA + Packaging are `TESTED`; the Publish Gate is sponsor-completed; the $9
  listing with 10 saved tags is publicly purchasable at
  `https://salbaharna.gumroad.com/l/boothsignal`.
- Those typed BoothSignal states accept the Factory line through P6 Dispatch.
- P7 Telemetry is current and `UNVERIFIED` until the required seven-day market
  observation is accepted. P8 Money in Bank remains future until positive
  settled customer funds are reconciled.

## Current state

The portfolio derives wheel maturity from typed individual product-lane state,
selecting the furthest evidence-backed stage without merging lane authority. A
persisted `FactoryRun` remains authoritative within its own operational lane but
cannot override the line projection until its product identity and evidence are
bound into the governed catalog. The final phase cannot be entered without
`bankedRevenue > 0` and a non-empty `bankSettlementReference`.

Until that proof exists, Factory remains **not successful**, regardless of how
many artifacts were built or listings were published.

## Evidence index

- `lib/logic/product_factory.dart` — forward-only evidence gates and human
  perimeter.
- `lib/services/core/kai_factory_service.dart` — persisted run, evidence,
  approvals read path, and project synchronization.
- `lib/services/core/kai_project_service.dart` — frozen nine-phase project view.
- `lib/services/core/kai_factory_daily_lane.dart` records typed BoothSignal
  station evidence, preserves Find My Table maturity, and deterministically
  derives the line-level maximum stage.
- `lib/services/core/kai_delivery_box_catalog.dart` — the 23-box Factory
  decomposition. It preserves scan-only status, sponsor-owned candidate votes
  and Blueprint authority, public Dispatch, and Money in Bank.
- The Factory conveyor and Pizza read the same governed delivery-box states;
  neither UI may award progress independently of the `FactoryRun`/scan ledger.
- `test/product_factory_test.dart` — deterministic safety and bank-settlement
  gates.
- `test/kai_project_portfolio_test.dart` — project phase and advancement mapping.
- `test/kai_delivery_box_test.dart` — shared Factory/Pizza box authority,
  sponsor refusal, scan-only state, and bank-gate semantics.

## Latest acceptance evidence — 2026-08-10

The typed line-maturity model and HUD projection are `TESTED`: 27/27 focused
tests and 61/61 proportional Factory/Pizza/conveyor/bank-gate tests pass. The
Windows Release build passes with `app.so` SHA-256
`361EB66DC8A26B961247269872C8C9A5C3839C358968EFC5E03AC18FD7AC5BA0`.

Real-HUD proof is `UNVERIFIED`. No room was launched because ordinary desktop
startup invokes Firebase project metadata updates while this focused brief
explicitly forbids Firebase mutation. Core PID 127176 and watchdog PID 89468
remain healthy and untouched. Evidence receipt:
`docs/evidence/FACTORY_LINE_MATURITY_P6_2026-08-10.json`.

## Portfolio reconciliation — 2026-08-15

The accepted portfolio evidence packet binds BoothSignal's public URL, $9
price, 10 saved tags, buyer ZIP/app/Start Here guide, storefront copy, cover,
thumbnail, QA evidence, and package receipt at commit `1bbc936`. The Factory
wheel therefore accepts P0 Signal Scan through P6 Dispatch and makes P7
Telemetry the current open phase. This is line-level maturity from BoothSignal;
Find My Table remains its own Blueprint lane, with its Tested 88/88 internal
Assembly component at `424b87e` insufficient to close the full Assembly exit.

No accepted seven-day market observation, sale, fee, refund, receipt, settled
payment, or bank reconciliation exists. BoothSignal First Payment is the active
nested Daily Product gate. P8 Money in Bank remains future and `UNVERIFIED`.
