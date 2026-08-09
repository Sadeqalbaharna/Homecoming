# Factory Signal Scan integration delta

Status: TESTED domain slice; live search and runtime persistence wiring UNVERIFIED.

## Authority and ownership

`FactoryScanSession` is the single source of truth for a bounded Signal Scan.
It owns the complete attempt ledger, candidates, sponsor votes, calibration,
failed rounds, audit, timebox, and HUD projection. The aggregate is pure and
serializable. It does not import `KaiFactoryService`, `FactoryRun`, the conveyor,
or any external search implementation.

The controller has no method that mutates a candidate into Blueprint. It can
only structurally check an exact-session/exact-candidate external record, and
that check remains insufficient until a future sponsor-owned, agent-read-only
adapter verifies provenance. A YES vote only sets `yesShortlist`; it never
invokes `advance()` and never enters Blueprint.

## KaiFactoryService adapter delta

A later narrow adapter may persist `FactoryScanSession.toJson()` under a new
run-scoped child such as:

`kai/{persona}/factory/scan_sessions/{factoryRunId}/{scanSessionId}`

Required adapter rules:

1. Reads/writes session JSON only; it must not mirror mutable counts or audit
   fields elsewhere.
2. Search execution accepts `ScanWorkPacket` and records only a genuine
   `ScanAttemptResult` returned by the existing governed search seam.
3. No production search adapter is supplied in this block. Live execution is
   UNVERIFIED and pending packets must never be displayed as completed.
4. Sponsor Blueprint authorization must be stored on a sponsor-writable,
   agent-read-only path containing `sessionId`, `candidateId`, `approvedBy`, and
   `approvedAtMs`.
5. `checkBlueprintAuthorization()` verifies identifiers and verdict ordering,
   not sponsor provenance. A later trusted adapter must verify provenance before
   requesting the existing Factory transition. Scan completion, structural
   validation, and YES must never call `KaiFactoryService.advanceRun()`.
6. Unsupported future schemas fail closed. Schema 0/missing collections migrate
   to empty evidence, never fabricated progress.

## Homecoming Brief 019 / portfolio-watch delta

Brief 019 owns the shared four-project delivery-box controller and general
Pizza UI. It should not duplicate or mutate scan state. Its Factory box/watch
adapter should deserialize the latest session and project `hudAt(now)` plus:

- box key: exact Factory run id + scan session id;
- station: Signal Scan until exact run-bound Blueprint authorization is accepted;
- pending count: `awaitingVotes`;
- evidence counts: attempts, credible candidates, duplicates/rejections, and
  failed rounds from the aggregate;
- health: `audit.efficiency` and `audit.effectiveness`;
- action: `currentAction` and `nextSafeAction`;
- deadline: `deadlineAtMs` (the watch supplies `now`; it stores no countdown).

The watch remains a read-only projection. It must not infer Blueprint from a
YES vote, a completed timebox, credible candidates, or a visually completed
Signal Scan station.

## Rollback

Remove the focused model, its focused tests, and this integration delta. No
database migration, live call, credential use, conveyor edit, Factory advance,
or external side effect occurred in this slice.
