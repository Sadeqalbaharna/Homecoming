# Product Factory — project source of truth

## Authority

This document governs the Factory project slice shown by Homecoming. The live
run remains authoritative for operational stage and evidence. The slice is a
read-only project-management view of that run; it cannot manufacture progress,
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
- A new run does not inherit evidence or approval from an older run.
- Revenue is zero for Northstar purposes until it settles in the bank.
- The final gate requires a positive amount and a reconciliation reference.
- Failed and rejected attempts remain useful history; they are not progress.

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

## Current state

The portfolio derives current phase and accepted prior gates from the persisted
`FactoryRun`. The final phase cannot be entered without `bankedRevenue > 0` and
a non-empty `bankSettlementReference`.

Until that proof exists, Factory remains **not successful**, regardless of how
many artifacts were built or listings were published.

## Evidence index

- `lib/logic/product_factory.dart` — forward-only evidence gates and human
  perimeter.
- `lib/services/core/kai_factory_service.dart` — persisted run, evidence,
  approvals read path, and project synchronization.
- `lib/services/core/kai_project_service.dart` — frozen nine-phase project view.
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
