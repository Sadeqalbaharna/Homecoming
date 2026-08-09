# Find My Table Internal Operator — Integration Delta

Packet: `FSC-LEGACY-YES-001-BP-IC-v3`  
Factory run: `factory-run-legacy-recovery-20260809-tablefinder-01`  
Candidate: `FSC-LEGACY-YES-001`  
Assembly authorization: `FAA-20260809-FSC-LEGACY-YES-001-ASSEMBLY-01`  
Proof state: **TESTED LOCALLY WITH SYNTHETIC DATA; LIVE UNVERIFIED**

## Outcome

The Assembly slice adds a separate pure-domain Find My Table operator and a
run-scoped persistence boundary. It does not edit or become a second authority
for `KaiFactoryService`, Factory conveyor, Brief 019 portfolio/Pizza UI, or any
live tool.

## Truth ownership

| Concern | Owner | Consumers |
|---|---|---|
| Player/DM/slot synthetic records | `FindMyTableOperator` packet | tests; later internal operator adapter |
| Match proposals, reasons, waitlist and lifecycle | `FindMyTableOperator` packet | later read-only HUD projection |
| Revisioned durable snapshot | `FindMyTableOperatorRepository` | later repository adapter |
| YES and Blueprint authority | existing Factory scan/authorization registry | Factory conveyor and project view |
| Assembly authority | compiled exact Find My Table Assembly registry | operator creation/reload only |
| Public, live, payment and later-station authority | sponsor-controlled existing Factory perimeter | none in this slice |

Persisted operator JSON deliberately omits Assembly authority. Repository load
returns an unprivileged packet unless the caller supplies the compiled exact
authorization ID and all packet/run/session/candidate identities match. Copied,
future-schema or mismatched envelopes fail closed.

## Proposed KaiFactoryService adapter

No `KaiFactoryService` edit is part of this slice. A later separately reviewed
adapter may load the authoritative operator packet and expose one immutable
projection containing only:

- schema version and exact packet/run/session/candidate IDs;
- synthetic/live proof state;
- eligible player and approved-DM counts;
- proposal counts by proposed/approved/rejected;
- proposals awaiting operator review;
- confirmation counts by state;
- waitlist count;
- unmatched-reason and duplicate counts;
- tables by proposed/approved/delivered/billed/settled/bank-reconciled state;
- measured coordination minutes when available;
- net-new-seat share when explicitly sourced;
- attribution `available/unavailable`, with reason;
- current safe action and exact next gate.

The adapter must derive this projection on read. It must not copy operator state
into a second mutable store, call lifecycle mutations, infer unavailable
economics, or reapply authority from serialized data.

## Brief 019 portfolio-watch delta

Brief 019 may display the immutable projection inside the existing Factory box.
It must not:

- implement matching or dedupe;
- approve or reject a table;
- change participant or revenue states;
- display private accessibility/content-boundary values;
- label synthetic, proposed, billed or processor-held amounts as settled;
- mint or reuse Assembly/public/live authority;
- redesign the general Pizza controller or four-project model.

Suggested compact text fields are: `assembly: tested synthetic`, `review: N`,
`confirmed: N`, `unmatched: N`, `duplicates: N`, `attribution: unavailable|BHD
X modeled`, and `next: exact safe gate`. Counts remain projections of one source,
not independently maintained dashboard truth.

## Privacy boundary

Public/player-facing projections include opaque player ID, supported systems,
languages and commitment only. They exclude identity fingerprint, acquisition
source, accessibility needs and content boundaries. The approved DM brief may
include only aggregated operational accessibility requirements and content
boundaries, never which player supplied them.

Accessibility and boundary lists carry separate disclosure flags, so an empty
undisclosed value is not silently treated as an affirmative statement that no
need or boundary exists.

The operator schema requires no real name, email, phone, home address, live
location, payment identifier or credential. This is a structural constraint,
not proof that a future caller will never add sensitive free text; later intake
and UI work requires separate privacy review.

## Economics boundary

The attribution calculator accepts only explicit bills, contribution margin,
incremental overhead, DM cost and per-seat net-new classification. Missing
inputs return `unavailable`. At the Blueprint central fixture:

- four BHD12 bills = BHD48 gross;
- four net-new seats at 40% margin, BHD5 overhead and BHD10 DM cost = BHD4.20
  modeled incremental contribution;
- replacing one net-new seat with a transferred existing customer removes
  BHD4.80 and yields -BHD0.60.

The synthetic operator may record proposed → approved → delivered → billed for
test evidence. It refuses settled and bank-reconciled states. No value in this
slice is Northstar revenue.

## Future wiring gate

Before any runtime adapter or UI wiring:

1. approve the exact adapter file list;
2. define the durable CAS-capable store—the default KaiDb adapter currently
   refuses blind writes;
3. approve real-data fields, consent, retention and access policy;
4. verify operator projection tests against the actual Factory view;
5. retain separate sponsor authority for contact, live venue use, payment and
   public action.

No such wiring or live authority is included here.
