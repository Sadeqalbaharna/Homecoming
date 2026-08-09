# Factory Signal Scan integration delta

Status: TESTED domain and persistence slices; live search and shared-controller wiring UNVERIFIED.

## Authority and ownership

`FactoryScanSession` is the single source of truth for a bounded Signal Scan.
It owns the complete attempt ledger, candidates, sponsor votes, calibration,
failed rounds, audit, timebox, and HUD projection. The aggregate is pure and
serializable. It does not import `KaiFactoryService`, `FactoryRun`, the conveyor,
or any external search implementation.

The generic controller cannot promote agent-supplied data into Blueprint. A YES
vote only sets `yesShortlist`; it never invokes `advance()` and never enters
Blueprint. One compiled source registry now contains the sponsor-approved
legacy recovery packet for `FSC-LEGACY-YES-001`. Its transition revalidates the
authorization ID, intrinsic Factory run, scan session, candidate, evidence,
and ordered recovered YES. JSON always demotes the privileged state before the
registry may reapply it. This is a narrow recovery mechanism, not the future
durable sponsor-approval adapter.

## KaiFactoryService adapter delta

`FactoryScanSessionRepository` now persists `FactoryScanSession.toJson()` under
the run-scoped child:

`kai/{persona}/factory/scan_sessions/{factoryRunId}/{scanSessionId}`

The repository is tested through an injected conditional document-store
boundary. Its envelope and the immutable session both bind Factory run; the
envelope also binds persona, scan session, and monotonic revision. Derived
audit/trait projections are recomputed and are not persisted. Recovered verdicts
are explicitly marked and excluded from future trait ranking.
The current `KaiDb` facade has no atomic compare-and-set surface, so its adapter
fails closed rather than risk erasing a concurrent sponsor verdict. Live durable
writes therefore remain UNVERIFIED; no live database write occurred.
Remaining integration rules:

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
   not sponsor provenance. The single recovery transition gets provenance from
   its compiled source registry. A later trusted adapter must verify provenance
   before requesting a general Factory transition. Scan completion, structural
   validation, and YES must never call `KaiFactoryService.advanceRun()`.
6. Unsupported future schemas fail closed. Schema 0/missing collections migrate
   to empty evidence, never fabricated progress.

## Homecoming Brief 019 / portfolio-watch delta

Brief 019 owns the shared four-project delivery-box controller and general
Pizza UI. It should not duplicate or mutate scan state. Its Factory box/watch
adapter should deserialize the latest session and project `hudAt(now)` plus:

- box key: exact Factory run id + scan session id;
- station: Signal Scan until exact run-bound Blueprint authorization is accepted;
  then Blueprint for that exact candidate only;
- pending count: `awaitingVotes`;
- evidence counts: attempts, credible candidates, duplicates/rejections, and
  failed rounds from the aggregate;
- health: `audit.efficiency` and `audit.effectiveness`;
- action: `currentAction` and `nextSafeAction`;
- deadline: `deadlineAtMs` (the watch supplies `now`; it stores no countdown).

The watch remains a read-only projection. It must not infer Blueprint from a
YES vote, a completed timebox, credible candidates, or a visually completed
Signal Scan station. For the recovered concept, it may project Blueprint only
after the registered transition yields `blueprintAuthorized`; it must not
reconstruct that privileged state itself.

## Rollback

Remove the focused model, its focused tests, and this integration delta. No
database migration, live call, credential use, conveyor edit, Factory advance,
or external side effect occurred in this slice.
