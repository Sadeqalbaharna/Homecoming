# Homecoming Kai — Northstar source of truth

Status date: 2026-08-16

This is the authoritative project-management view of Homecoming Kai. It is not
a celebration document and it does not infer completion from code existing.
Claims below use four proof states:

- **Verified live** — observed in a running build or device with evidence.
- **Tested** — deterministic automated coverage exists, but the complete real
  surface has not necessarily been exercised.
- **Wired** — connected to a production path, but acceptance evidence is absent.
- **Conceptual** — desired architecture or prototype only.

When this file disagrees with an older status document, this file governs until
newer evidence deliberately updates it. Product identity and psychological
rules remain governed by `KAI_PERSONHOOD_CONSTITUTION.md`.

## Northstar

Kai is one continuous companion who remains available across time, devices, and
worlds; preserves an evidence-grounded identity and relationship; can converse,
notice, act, and complete useful work; can inhabit several bodies at once
without becoming several Kais; and can improve his capabilities through a
governed, evaluated, reversible process.

Northstar is achieved only when all of the following are proven:

1. **Persistent core:** coordination continues independently of any UI process
   and recovers automatically after process, device, and network interruption.
2. **One identity:** every body uses the same canonical persona, self model,
   relationship state, and policy authority.
3. **Simultaneous embodiment:** desktop, Messenger, VR, and AR can be online at
   once, each with a distinct body/session and body-local state.
4. **Continuous but private memory:** meaningful relationship memory travels;
   raw room transcripts and technical material do not leak across boundaries.
5. **Bidirectional presence:** Sadeq can address Kai anywhere, and Central Kai
   can deliberately direct one appropriate output to one appropriate body.
6. **Capability:** Kai can perform bounded technical and world work when the
   active body's policy allows it, report progress, and return results.
7. **Attention:** Kai can notice events, maintain priorities, schedule bounded
   activity, and resume interrupted work without spamming or silently dropping
   commitments.
8. **Governed self-improvement:** Kai may propose and execute bounded
   improvements only through evaluation, approval, audit, rollback, and staged
   promotion gates.
9. **Operational trust:** failures are observable; delivery is idempotent;
   durable work has leases and recovery; cost and permissions are bounded.
10. **Device independence:** loss of the current laptop does not erase Kai's
    durable self, and supported bodies do not depend on localhost assumptions.

## Non-negotiable invariants

- There is one Kai, not one persona per surface.
- Central Kai is the coordinator; bodies connect and disconnect.
- A heartbeat means the Central Core lease is alive, not merely that a UI is
  open.
- Goggles are body-local: off is human-friend presence without technical talk;
  on grants only the capabilities authorized for that body.
- Messenger is always friend presence and never exposes tools or implementation
  machinery.
- Raw transcripts are scoped by conversation room. Desktop and full mobile use
  `in_person`; Messenger uses `messenger`; VR uses its world room; AR is scoped
  by its private/public context.
- Shared mood, personality, relationship, and identity changes must be atomic or
  serialized. Body-local expression may differ.
- Presence metadata is not conversation and forms no memory.
- Core receipt time orders cross-body events; device time is descriptive only.
- One outbound event chooses one exact body or remains durable for later. It
  never fans out.
- A generated sentence is not evidence about Kai merely because Kai said it.
- Relationship closeness never grants permissions.
- No self-improvement may silently edit goals, weaken tests, expand authority,
  rewrite history, or promote itself.

## Current runtime architecture

```mermaid
flowchart TB
    S["Sadeq"]
    D["Desktop body\nin_person + goggles"]
    M["Messenger body\nfriend only"]
    V["Unity VR body\nShack + body-local goggles"]
    A["Unity AR body\nprivate/public context"]

    F["Firebase RTDB\nconversation requests, scoped history,\nidentity/memory, body leases"]
    H["Headless coordinator\nconversation owner, proactive routing,\nVR/AR gateways, recovery"]
    C["Kai Core v2\nlocal durable admission, lanes, presence,\noutbound inbox, leases"]
    AI["AIService\npolicy, routing, model calls, tools, memory"]
    O["Provider APIs and approved tools"]

    S --> D
    S --> M
    S --> V
    S --> A

    M -->|"durable request"| F
    F --> H
    D -->|"admission"| C
    D --> AI
    H --> C
    H --> AI
    V -->|"loopback HTTP :8787"| H
    A -->|"loopback HTTP :8788"| H
    H -->|"exact-body envelope"| C
    C -->|"poll + acknowledge"| V
    C -->|"poll + acknowledge"| A
    AI --> O
    AI -->|"scoped turns and memory"| F
    H -->|"central/body leases"| F
```

Important qualification: the diagram shows logical ownership, not yet a fully
device-independent deployment. Kai Core and the headless coordinator currently
run on the Windows laptop. The Unity endpoints bind to loopback, and the Unity
gateway defaults to `127.0.0.1`. This supports Unity Editor testing, not a
standalone Quest connection.

## Authority and storage map

| Concern | Current authority | Durability | Current proof |
|---|---|---|---|
| Canonical persona | `truekai` across the active paths | Code + Firebase | Tested |
| Central health/admission | Kai Core v2 on `127.0.0.1:8790` | `%LOCALAPPDATA%/Homecoming/KaiCore/state.json` | Verified live |
| Coordinator execution | `KaiHeadlessCoordinator` Windows worker + watchdog | Process recovery + Firebase journal | Verified live |
| Global body registry | `/kai_core/bodies/truekai` | Firebase leases, 90 seconds | Verified live for desktop/Messenger; simulated VR/AR |
| Central heartbeat | `/kai_core/coordinator/truekai` | Firebase lease, 90 seconds | Verified live |
| Conversation history | `/conversations/truekai/{surfaceId}` | Firebase + bounded process cache | Verified live for `in_person` and `messenger` |
| Messenger request queue | `/kai_core/conversation_requests/truekai` | Firebase claim/lease/status | Verified live |
| Runtime task lanes | Kai Core `tasks` | Local JSON + leases | Tested and used live |
| Outbound attention | Attention Engine + coordinator queue + Kai Core `outbound` | Local versioned attention snapshot plus Core envelope with expiry and exact-body acknowledgement | Verified live for controlled crash/resume, exactly-once desktop delivery, and one due-commitment round trip (2026-08-15); natural intake and Unity presentation unaccepted |
| Scheduled commitments | Kai Core `commitments` + `KaiDueCommitmentScheduler` | Core ledger with monotonic `nextEvaluationAt`, work-only audience, idempotent dispatch | Verified live 2026-08-15 for create → due → one-body dispatch → durable transcript → acknowledge |
| Long-term semantic memory | `/memory/embeddings/truekai` and related services | Firebase | Wired; historical corpus quality not accepted |
| Life/self evidence | `/kai/truekai/life_events` plus self services | Firebase | Tested in focused suites; long-horizon acceptance incomplete |
| Project/work ledger | `/kai/truekai/projects` and `/work_requests` | Firebase | Wired and tested |
| Self-improvement selection | `KaiSelfImprovementRunner` | Creates one bounded manual job | Tested prototype, not autonomous improvement |

## Surface contract

| Surface | Conversation room | Goggles | Tools | Relationship recall | Current maturity |
|---|---|---|---|---|---|
| Desktop app | `in_person` | Permanently on; desktop is the workbench | Approved general tools and technical co-creation | Yes | Wired and tested; rebuilt desktop check pending |
| Full mobile/core app | `in_person` | Body-local | Policy-dependent | Yes | Wired; not recently reaccepted |
| Messenger | `messenger` | Permanently off in product meaning | None; no technical talk | Nontechnical identity/relationship/shared life | Verified live |
| VR Shack | `vr_shack` | Off: friend; on: world co-creator | World capabilities when on; no general desktop tools | Relationship plus world-scoped policy | Gateway tested; Editor/Quest acceptance incomplete |
| Private AR | `ar` | Off | No general tools | Relationship/shared life | Gateway tested; physical acceptance incomplete |
| Public AR/Tavern | guest-scoped | Not a permission mechanism | Explicit Tavern capabilities only | Sadeq memory absent; consent-bounded guest lookup | Wired policy, not end-to-end accepted |

## What is genuinely working

- A headless coordinator can own Messenger independently of either chat UI.
- Desktop turns are admitted through Core's ordered conversation lanes.
- Messenger and `in_person` transcripts no longer intentionally mirror into one
  another; legacy restore filters containers and surface tags.
- Core exposes durable presence, thread-continuation handoffs, task leases, and
  exact-body outbound envelopes.
- VR and AR gateway channels use authoritative ports/surfaces and treat presence
  heartbeats as metadata-only events.
- Central presence is shown on desktop and Messenger through one shared lease.
- Body-local goggles constrain prompt posture, capabilities, reply sanitation,
  and memory access.
- Scoped memory separates relationship/shared-life material from technical,
  creative, world, guest, and private-core material.
- Core admission permits two distinct conversation lanes while preserving order
  inside a room; work has a separate bounded pool.
- Ordinary proactive friend events now enter the tested Attention Engine before
  generation: Bahrain quiet hours, daily pacing, expiry, retry, deduplication,
  and exact-body selection are production-wired in the headless coordinator.
- Self-context has evidence/provenance rules, token ceilings, and tests for slow
  identity development.
- The self-improvement runner selects one bounded manual job and requires proof
  gates; it does not currently edit or promote itself autonomously.

## Known gaps and contradictions

### P0 — blocks a Northstar claim

1. **Standalone device transport does not exist.** Unity and the embodiment
   servers are loopback-only. Quest/AR hardware cannot reach Central Kai without
   an approved tether, authenticated LAN relay, or remote gateway design.
2. **Core depends on the current laptop.** The watchdog recovers a process, not
   a dead, sleeping, disconnected, or lost machine.

   Partial progress worth recording, because it changes what remains: Core is
   now a standalone Dart binary (`tool/kai_core.dart` → `KaiCore.exe`) with its
   own data directory, launched opportunistically by `KaiCoreSidecarManager` and
   treated as optional — a missing sidecar means current behavior, never a
   failure to start. Core therefore no longer requires a Flutter engine or a UI
   process. What still binds it to this machine is only `HttpServer.bind(
   InternetAddress.loopbackIPv4, 8790)` and the absence of any authentication on
   its routes. The remaining work is a credential and an interface, not a
   rewrite.
3. **Unity outbound presentation is not accepted.** The full current C# assembly
   passes an isolated compile against Unity's generated reference set, and Core
   is live. Unity's own domain reload, Play Mode display/voice, and physical
   headset behavior have not been observed.
4. **No complete end-to-end Northstar evaluation exists.** Focused tests cover
   contracts; they do not yet prove week-scale continuity, interruption
   recovery, multi-device delivery, or privacy under real usage.

### P1 — structural risk

1. ~~Historical coordinator operation logs contained authenticated Firebase URLs
   from pre-redaction builds.~~ **CLOSED — Verified live 2026-08-16.** 106
   affected records were sanitized on 2026-08-08 and a clean follow-up scan
   passed. The remaining condition was that the active coordinator had to
   restart on the redacting build; it has. Live journal entries written after
   the restart carry `auth=[REDACTED]` on both the RTDB and `securetoken`
   failure paths, so redaction is now observed at the boundary rather than only
   tested.
2. Desktop still contains dormant legacy Messenger-executor methods and fields.
   The subscription is absent, so headless owns the live route, but dead code
   obscures authority and could be accidentally reconnected.
3. Desktop generates its own turns after Core admission while Messenger is
   generated inside the headless coordinator. Core coordinates both, but model
   execution is not yet one uniform worker architecture.
4. The outbound inbox is local to the laptop. It survives process restart but
   not laptop loss and is not yet a cloud-backed cross-device queue.
5. `completed_work` has a routing contract but is not yet uniformly delivered
   through the exact-body outbound inbox.
6. Memory classification still relies partly on route/lexical policy. The open
   decision to use an explicit memory-worthiness classifier is unresolved.
7. Several legacy memory/self stores remain readable. Retirement is correctly
   gated, but replay and migration acceptance are incomplete.

### P2 — later Northstar capability

1. Ordinary proactive attention has explicit Bahrain quiet hours, a delivery
   budget, retry, expiry, one-body routing, and an accepted local restart
   snapshot with observable failures, backup recovery, corruption quarantine,
   and mutation-gated persistence. Controlled coordinator crash/resume and one
   exact desktop delivery are **Verified live**. Commitment clocks are now also
   **Verified live** — see the Brief 018 ledger record above, which held a
   promise across its due instant and delivered it to one exact body. Natural
   proactive intake, completed-work/direct-reply admission, and a seven-day
   observed run remain `UNVERIFIED`. Natural proactive intake additionally
   carries the repetition defect recorded below, repaired but not yet observed
   live.
2. Self-improvement plans one manual job. It lacks isolated execution,
   evaluation suites, staged rollout, automatic rollback, and promotion
   authority separation.
3. No multi-host coordinator election or authoritative cloud deployment exists.
4. Voice, animation, gaze, and spatial behavior are not part of the current
   software acceptance gate.
5. **Firebase stream recovery is unbounded and unalerted.** The live journal
   records 968 `activity_stream_unavailable` and 482 `request_stream_unavailable`
   entries in the 48 hours to 2026-08-16, all `Failed host lookup` or socket
   timeouts from the laptop sleeping or dropping its network. The subscriptions
   do recover, and credentials are redacted, so this is not a correctness or
   privacy failure. It is a flat retry with no backoff and no alert, and it is
   the dominant contributor to a journal that has already rotated once at 2MB.
   Real degradation is currently indistinguishable from ordinary sleep.
6. **Bodylessness is the steady state.** Presence at 2026-08-16T07:56Z listed one
   participant: the coordinator itself. No desktop, Messenger, VR, or AR body was
   online. Every attention decision in that window resolved
   `storeForLater / no_suitable_body_online`. The durability machinery is doing
   exactly what it was built to do; there is nothing for it to reach. Phase 3's
   seven-day observed run cannot begin from this state, and no amount of further
   engine work substitutes for it.

## Execution roadmap and gates

| Phase | Outcome | Exit gate |
|---|---|---|
| 0. Baseline | One governing map, invariant set, backlog, and proof vocabulary | This document reviewed; contradictions represented, not hidden |
| 1. Embodiment foundation | Four bodies can coexist and one exact body can receive Central attention | Editor acceptance, then tethered Quest proof; no transcript or technical leakage |
| 2. Device transport | Untethered authenticated Quest/AR-to-Core path without secrets in clients | On-device heartbeat, turn, outbound acknowledgement, reconnect, and revocation tests |
| 3. Central attention | Event intake, priority, quiet hours, commitments, scheduler, delivery budget | Deterministic simulations plus seven-day observed run without spam/drop |
| 4. Durable continuity | Identity, relationship, scoped memory, and work resume across restart/device loss | Cold-start and cross-device corpus with privacy and provenance evaluation |
| 5. Capability fabric | Governed tools/world actions and completed-work return routing | Permission, failure, idempotency, recovery, and cost tests per capability |
| 6. Self-improvement | Kai can improve bounded capabilities safely | Sandbox, independent evaluator, approval, canary, rollback, audit, no goal rewriting |
| 7. Always-on deployment | Central Core survives laptop absence | Multi-host or server deployment with failover, backups, monitoring, and restore drill |
| 8. Northstar acceptance | Kai is continuously useful and recognizably one companion | Requirement-by-requirement audit against the ten Northstar conditions |

## Active phase

**Reconciled 2026-08-16.** The 2026-08-08 revision of this file understated the
project: it recorded Brief 018 as blocked when the slice had in fact shipped, and
carried a closed credential item as open. Both are corrected above. Understating
progress is a rarer failure than overstating it and costs the same — work already
finished gets planned again. The governance rule stands, with one addition: an
evidence claim is only as good as the field it was read from, so a claim sourced
from a runtime endpoint must name the field and mean what that field means.

Phase 0 is complete when this source of truth and its first acceptance brief are
reviewable. Phase 1 remains active until the Unity Editor test is observed and a
separate tethered Quest test proves the physical body. Phase 2 owns untethered
authenticated transport; neither Editor loopback nor `adb reverse` closes that
gate. Code existence does not close any gate.

An independent backend track may proceed under
`docs/briefs/BRIEF_003_CENTRAL_ATTENTION_DECISION_ENGINE.md` while the attended
Unity gate is deferred. That track is limited to a new pure-Dart attention
decision engine and focused tests. It must not edit or integrate with the dirty
Core, coordinator, routing, Unity, Firebase, Messenger, or UI paths. Passing the
brief promotes only that decision policy to **Tested**; Phase 1 remains open and
Central Attention does not become live.

Brief 004 closed the attention-policy repair on 2026-08-08. The pure decision
engine now has deterministic tests for explicit timezone-offset quiet hours,
caller-supplied retry pacing, strict priority bounds and ordering, durability,
deduplication, budget handling, and one-body routing. Its proof state is
**Tested** only: it has no production caller, durable scheduler state, or live
delivery integration. Central Attention is not wired or live.

The evidence-backed desktop portfolio introduced by
`docs/briefs/BRIEF_005_PROJECT_PORTFOLIO_TRACKER.md` now has a bounded expansion
under `docs/briefs/BRIEF_011_KINGDOM_PORTFOLIO.md`: add Kingdom beside
Homecoming and Hoard using Kingdom's own frozen roadmap. This does not alter the
still-open Phase 1 embodiment gate or the active attention-recovery gate.

Brief 005 passed its focused automated suites on 2026-08-08 and is **Tested**.
Attended Windows acceptance remains open: the rendered Homecoming/Hoard cards,
live RTDB evidence refresh, and workspace-nonmutation behavior have not yet been
observed by the reviewer. The built debug executable was launched for that
check; compilation and tests are not substitutes for the visual evidence.

Brief 007 wires ordinary proactive friend events through the accepted Attention
Engine in the headless coordinator. Its in-process queue preserves events while
Central Kai is busy or no body is online, reevaluates on presence/timer ticks,
and audits every decision without message content. Focused attention,
routing, and coordinator suites pass (43/43), so this slice is **Wired and
Tested**. Runtime delivery remains `UNVERIFIED`, and the queue is not durable
across coordinator or laptop restart; Central Attention Phase 3 is not closed.

Briefs 008–010 are accepted. They provide a version-1
local attention snapshot, restore-before-subscribe ordering, serialized writes,
observable persistence failures, explicit unsupported/corrupt load outcomes,
last-readable-backup preservation, collision-safe evidence quarantine, and
revision-gated persistence. Independent review passed 70 focused tests (4
backup edges, 23 store, 6 queue, 32 engine/routing, 5 coordinator) and clean
scoped analysis. A real Release coordinator was then force-terminated with one
pending controlled event: its production watchdog recovered, rehydrated the
same event and budget, held it while bodyless, selected one desktop body, and
delivered exactly once. Crash/resume and exactly-once delivery are therefore
**Verified live**. Natural proactive intake remains `UNVERIFIED` because the
desktop `/nudge` stream is process-local and this run used a schema-valid state
fixture. Repeated identical bodyless decisions also create avoidable audit
volume; neither issue invalidates the durability proof.

Brief 012 is the active IN PROGRESS backend slice. It adds the first durable scheduled
commitment vertical path: desktop `set_reminder` creates a Central Core record,
the headless coordinator admits it as `dueCommitment`, work-only routing keeps
it out of Messenger, and a deterministic desktop outbound is acknowledged only
after idempotent transcript persistence. This phase does not claim phone,
cloud, AR, VR, recurring-reminder, or `KaiNoticedService` integration. It
has completed its explicit-audience contract and accepted Core integrity
foundation. Client integration, deferral updates, scheduler wiring, desktop
delivery, and runtime evidence remain incomplete.

Independent review of Brief 012's partial Core implementation passed 116
existing/focused tests but reproduced ten uncovered integrity failures:
backup-only Core state was ignored, corrupt-primary recovery replaced the
readable backup with corrupt bytes, dispatch could occur early or to Messenger,
dispatched records remained due, unrelated outbound IDs could be captured,
commitment outbounds expired while still owed, intent/provenance checks were
incomplete, and the domain source contained literal NUL bytes. Brief 012 is
therefore not accepted and is blocked on
`docs/briefs/BRIEF_013_CORE_COMMITMENT_INTEGRITY_REPAIR.md`. No coordinator or
desktop integration begins until Brief 013 is fully accepted.

Brief 013 is **ACCEPTED / TESTED**. Its final implementation preserves the last
readable Core state, quarantines corrupt evidence without collision, validates
canonical Bahrain provenance, enforces due-time and desktop-only dispatch,
keeps commitments owed until acknowledgement, and makes identical retries
repair a failed durable transition before returning success. Independent final
evidence is 10/10 original reviewer, 10/10 follow-up reviewer, 8/8 recovery,
116/116 shared regression tests, and clean scoped analysis. This does not claim
live reminder delivery. Brief 012 is unblocked and resumes through
`docs/briefs/BRIEF_014_COMMITMENT_CLIENT_AND_DEFERRAL_CONTRACT.md`; coordinator
and desktop wiring remain paused until that dependency is accepted.

Brief 014 is **ACCEPTED / TESTED**. The real Core client now creates, lists,
defers, dispatches, polls, and acknowledges commitment work without hand-built
HTTP in downstream components. Core owns a monotonic, canonical-UTC
`nextEvaluationAt` endpoint whose failed writes remain honest and retryable.
Independent evidence is 16/16 new integration tests, 49/49 combined critical
and ratified-tripwire tests, 116/116 shared regressions, and clean analysis. The
two ratified test-only scope exceptions replaced brittle implementation wording
with the actual permanent-goggles and channel-authority invariants. Brief 015
then took the desktop durable transcript-acceptance seam and is accepted below.

Brief 015 is **ACCEPTED / TESTED / WIRED**, but not yet `VERIFIED LIVE`. The
desktop shell uses the same production `KaiOutboundAcceptance` unit exercised
by tests. That unit persists first, re-checks record identity after the await to
close the realtime-watcher race, renders only when still absent, and permits
Core acknowledgement only after visible acceptance. The conversation session
buffer now deduplicates by durable outbound `recordId`, not formatted content,
so equal text and timestamps do not collapse distinct promises. Independent PM
evidence is 14/14 criteria, 70/70 combined focused/critical tests, 116/116
shared regressions, and a clean diff check. Scoped analysis adds no diagnostic;
the desktop shell retains nine pre-existing lint notices. Brief 016 then took
the coordinator scheduling seam and is accepted below. Desktop `set_reminder`
and attended end-to-end acceptance remained paused at that checkpoint. The
unrelated `kai_cost_meter.dart` syntax error belongs to another concurrent edit
and is tracked separately from this acceptance decision.

Brief 016 is **WIRED / NOT ACCEPTED**. Its extracted due-commitment scheduler is
`TESTED`: explicit work audience, quiet-hours deferral, bounded no-body retry,
exact global desktop body routing, idempotent dispatch, failure retention, and
journal suppression pass 22 focused scheduler tests; the combined coordinator
gate passes 27/27 independently. The mandatory lifecycle criterion remains
`UNVERIFIED`, and review found a real race: cancelling coordinator timers does
not stop an in-flight due-list request from later resuming and mutating Core.
The lifecycle repair now closes shutdown and production-loop ownership, but
Brief 016 remains **NOT ACCEPTED** on criterion 7. After a no-body deferral
persists a future `nextEvaluationAt`, an eligible-desktop wake still queries
only `dueOnly:true`; it performs a request but cannot see or dispatch the
waiting promise before the retry instant. The immutable PM presence-wake
reviewer reproduces **39 PASS / 1 FAIL**. The active repair is limited to an
engine-governed, presence-specific reevaluation of already-originally-due
scheduled commitments. Desktop reminder creation remains paused.

PM contract decision: preserve Core's `commitment_not_yet_due` and monotonic
deferral protections. A no-body `storeForLater` will no longer advance
`nextEvaluationAt`; the already-due promise remains owed in Core, the positive
coordinator interval bounds retry, and eligible desktop presence wakes the
ordinary due drain. Only engine-authored temporal policy such as quiet hours is
durably deferred. This resolves the criterion-5/criterion-7 contradiction
without a new Core capability or a weaker dispatch gate. Brief 016 remains open
only until this Option C implementation and all acceptance gates pass.

Brief 016 is now **ACCEPTED / TESTED / WIRED**, not `VERIFIED LIVE`. Option C is
implemented: no-body work remains due without a Core write, the positive loop
interval bounds retry, eligible desktop presence delivers immediately, and
quiet-hours deferrals remain durably authoritative. The production lifecycle
also prevents post-shutdown or prior-generation Core mutations. Independent PM
evidence is 18/18 criteria, 43/43 focused, 109/109 critical dependency, and
116/116 shared tests, plus clean six-file scoped analysis and diff check. Brief
017 is the active child seam: desktop `set_reminder` must create the accepted
deterministic Core commitment while native Android behavior remains unchanged.

Brief 017 is **WIRED / NOT ACCEPTED** after its first implementation report.
The desktop workbench now exposes a real Core-backed `set_reminder` path while
Android retains its native MethodChannel path; Claude reports 13/13 focused
tests plus green route, commitment, coordinator, shared, and full-suite gates.
The PM ratifies the narrow `tool_policy_service.dart` change because
`androidOnly` is an enforced runtime gate. However, an immutable production-
path reviewer proves that Core commitment admission trims leading and trailing
whitespace from reminder text: combined evidence is **13 PASS / 1 FAIL**. This
violates the byte-for-byte text invariant shared by Briefs 012 and 017. The
only active repair is a commitment-text-specific Core admission path that uses
trim solely for emptiness validation while preserving the original string and
all unrelated canonicalization. Attended end-to-end acceptance remains paused.

The exact-text behavioral repair now passes independent PM verification:
16/16 focused/reviewer tests and 144/144 Core-integrity/shared regressions.
Brief 017 nevertheless remains **NOT ACCEPTED** because scoped analysis found
one newly introduced `curly_braces_in_flow_control_structures` diagnostic in
`kai_desktop_reminder_tool.dart`; the report's claim of zero introduced
diagnostics was therefore inaccurate. The final repair is formatting-only:
brace that one numeric-input branch, rerun the same gates, and make no behavior
or scope change. Attended acceptance remains paused until criterion 13 passes.

Brief 017 is now **ACCEPTED / TESTED / WIRED**, not `VERIFIED LIVE`. The final
braces-only repair removed the sole diagnostic introduced by the new reminder
production file without changing behavior. Independent final evidence is
16/16 exact-text/focused tests, 144/144 Core-integrity/shared regressions, a
six-file analyzer delta from six diagnostics to the same five pre-existing
`tool_executor_service.dart` diagnostics, a clean changed-file analysis, and
a clean diff check. All 14 criteria pass. The next separate gate is an attended
restart and exactly-once desktop reminder walkthrough; it has not begun.

Brief 018 is the active runtime gate. Read-only preflight found that the two
currently running `Kai.exe` processes and Core are stale: health started on
2026-08-07, omits `scheduled_commitments`, and `/v1/commitments` returns 404,
while the accepted reminder source is newer than the Release binary. This is a
runtime-version blocker, not a contradiction of Brief 017's code evidence. The
next action is a fresh Release build followed by an attended, tray-controlled
restart; no process will be force-terminated and no live Core state will be
deleted. Only after that runtime proves create → restart → one-body delivery →
durable transcript → acknowledgement may the reminder slice become
`VERIFIED LIVE`.

The fresh Windows Release build is now complete without interrupting the live
runtime. Its authoritative Dart payload
`build/windows/x64/runner/Release/data/app.so` was written at
2026-08-08T16:59:38Z with SHA-256
`C69667AD9DE71FA177F333960F0D9BC23C79F16B72440781D598131F8F44857C`.
The old process remains loaded and intentionally still reports the stale
capability set. Brief 018 is therefore **READY FOR ATTENDED RESTART**: the next
action is Sadeq's tray-level **Quit Kai completely**, followed by launch and
capability verification. No force termination or state deletion is authorized.

Brief 018 now also has a content-free, read-only runtime verifier at
`scripts/test/kai_reminder_runtime_acceptance.ps1`. Its nine fixture cases pass,
including stale-runtime refusal, exact promise fingerprinting across restart,
duplicate-dispatch rejection, and journal-text leakage rejection. A live run
correctly reports `UNVERIFIED` against the old Core. The tool does not create,
dispatch, acknowledge, edit, or delete records; it becomes evidence only after
the attended clean restart loads the rebuilt payload.

Brief 018 was **BLOCKED ON ATTENDED ACTION** at the 2026-08-08 checkpoint after
the same stale runtime remained active across three consecutive continuation
turns. This was a deliberate safety and evidence boundary, not a code blocker.

**Brief 018 is now ACCEPTED / VERIFIED LIVE (evidence observed 2026-08-16).**
The attended restart happened on 2026-08-15 and the reminder slice completed its
full vertical path against the live Core. The record is still in the ledger:

```
commitmentId   commit-ec78fa071d43c640570747c7303b797b
text           "b018-20260815-1711-7f3c exactly-once acceptance ping."
createdAt      2026-08-15T14:12:39.692915Z
dueAt          2026-08-15T14:22:00.000Z   (dueWallClock 17:22 +180, Bahrain)
targetBodyId   desktop-body-858e11f86ddd
audience       work
dispatchedAt   2026-08-15T14:22:13.104358Z
acknowledgedAt 2026-08-15T14:22:15.074568Z
status         acknowledged
```

Create → hold until due → select one exact desktop body → dispatch → durable
transcript → acknowledge, with `audience: work` keeping it out of Messenger.
This closes the reminder slice's runtime gate. It does **not** close Phase 3:
this is one commitment on one body, not the seven-day observed run.

### The instrument that reported the block was itself wrong

The 2026-08-08 preflight called the running Core "stale" partly because
`/health` reported `startedAt: 2026-08-07`. That field is written with `??=`
(`_hydrate`) and therefore records **the first time Core ever ran on this
machine** — it survives every restart and every rebuild by design. It was read
as a process clock. The capability list was the only accurate staleness signal
in that response, and `kai_reminder_runtime_acceptance.ps1` was already gating
on it correctly; the misreading was in the human-facing summary, not the script.

Repaired 2026-08-16:

- `/health` now publishes `processStartedAt` alongside `startedAt`. Only the new
  field answers "is the running build the one I just made?"
- `_emptyState()` no longer stamps `startedAt` from the real wall clock. That was
  a second writer disagreeing with `_hydrate`'s injected clock, which made the
  install date untestable; `_readState` now routes a genuine first run through
  `_hydrate` so one writer owns the field.
- The acceptance script reports both values as evidence so the two clocks cannot
  be confused again.
- `test/kai_core_server_test.dart` pins the distinction across a simulated
  rebuild-and-restart.

A project that refuses to claim a capability without evidence cannot tolerate an
evidence source that answers a different question than the one being asked. This
is recorded here because the failure was in the measurement layer, and the cost
was eight days of believing a shipped slice was blocked.

### Proactive repetition defect — found and repaired 2026-08-16

Sadeq reported five consecutive proactive messages carrying the same
observation in five different wordings. This is a **product-visible failure of
Northstar condition 7** ("without spamming"), and it survived every existing
dedup layer because all of them compare identity by text or by event id, and the
repeats had neither in common.

Root cause was three guards defeating each other, none of which is in the
Attention Engine — the engine's ordered policy behaved correctly throughout:

1. `Noticed.carried` counts turns the item was **displayed** in the prompt block,
   which is the right design for that block and rises during ordinary
   conversation. `KaiProactiveService` ranked proactive candidates by it, so
   within roughly a dozen turns the top item became permanent.
2. At `carried >= 12` the proactive path **returned that item directly**,
   bypassing the repetition guard at the end of the method entirely. The comment
   on `_loudAfter` recorded that this escalation had never fired for any item;
   it had since been wired to a counter that does fire, and the untested branch
   became the default.
3. The bypassed guard compared generated `seed` strings — and the noticed seed
   interpolates the live `carried` count. Two raises of one observation produced
   two different strings, so the check written to stop "the same tap wearing a
   fake moustache" was defeated by a counter sewn into the moustache.

Nothing anywhere recorded that Kai had **raised** something. `carried` measures
being shown a thing, not saying it, and only ever rises.

Repair:

- `Noticed` gains `raisedAt` / `raisedCount`; absent fields read as never raised,
  so no existing observation is silenced by the migration.
- `KaiNoticedService.canRaiseProactively` is a pure static policy: escalating
  quiet of 24 hours after the first unprompted raise, 3 days after the second,
  and no further unprompted raises after the third. The item keeps its place in
  `promptBlock`, so he can still raise it inside a conversation — it loses the
  unprompted mouth, not the memory.
- `KaiNudge.topicKey` / `.identity` give a nudge a subject-stable identity, and
  the repetition guard and `_lastUnansweredNudgeSeed` now compare that instead of
  prose.
- The raise is recorded at **selection**, not delivery — generation is the step
  that reworded the observation past every equality check, so pressure is
  relieved on the side of it where the item still has an identity.

Proof state: **Tested**. 20 tests in `test/noticed_test.dart` cover the backoff,
the ratchet (`carried: 500` cannot buy back an exhausted item), legacy rows, and
the identity comparison. Full suite 1129/1129; analyzer unchanged at 175 issues,
zero introduced. Runtime behavior is `UNVERIFIED` until observed against a live
body — which is blocked on the same bodylessness recorded in P2.6.

The general lesson, since it has now cost twice: **generated prose is not an
identity.** Any future dedup that compares model output rather than a key will
fail the same way, silently, and look like character.

## Evidence index

- `KAI_SIMULTANEOUS_EMBODIMENT_DECISIONS.md` — accepted embodiment invariants.
- `KAI_SIMULTANEOUS_EMBODIMENT_TEST_2026-08-08.md` — latest runtime checkpoint.
- `KAI_PERSONHOOD_CONSTITUTION.md` — psychological and evidence invariants.
- `KAI_SELF_CONTEXT_ARCHITECTURE.md` — working-self and provenance design.
- `KAI_HEADLESS_VR_ACCEPTANCE.md` — simulated gateway walkthrough.
- `scripts/test/kai_outbound_attention_acceptance.ps1` — model-free Unity
  outbound acceptance.
- `scripts/test/kai_quest_loopback_bridge.ps1` — development-only, loopback-
  preserving Quest USB transport.
- `test/kai_core_server_test.dart` — Core durability, lanes, inbox, leases, and
  the install-clock/process-clock separation in `/health`.
- `test/noticed_test.dart` — proactive raise backoff, the `carried` ratchet, and
  subject-stable nudge identity.
- `test/kai_body_event_test.dart` — event authority and one-body routing.
- `test/kai_memory_scope_test.dart` — cross-surface memory boundaries.
- `test/kai_headless_coordinator_test.dart` — headless ownership tripwires.
- `test/kai_proactive_attention_queue_test.dart` — proactive admission,
  deferral, pacing, retry, expiry, and duplicate behavior.
- `test/kai_proactive_attention_store_test.dart` — versioned attention snapshot,
  restart, atomic-write, corruption, and privacy tests; 23/23 pass.
- `test/kai_proactive_attention_recovery_edge_test.dart` — reviewer-owned
  backup-only recovery, retry, and quarantine-collision evidence; 4/4 pass.
- `KAI_ATTENTION_RESTART_ACCEPTANCE_2026-08-08.md` — real Release coordinator
  crash, watchdog recovery, hydration, one-body route, exactly-once delivery,
  rollback, and remaining intake caveat.
- `test/kai_operations_journal_test.dart` — structured logging, serialized
  rotation, and credential redaction at the journal boundary.
- `scripts/test/kai_attention_runtime_acceptance.ps1` — model-free correlation
  gate for receipt, decision, one-body selection, terminal delivery, and
  credential-free evidence.
- `scripts/test/kai_operations_log_sanitize.ps1` — dry-run-first historical
  operations-log credential scanner and exact-file sanitizer.
- `C:\code\Kingdom\docs\PROJECT_SOURCE_OF_TRUTH.md` — Kingdom's governing
  Northstar, loyalty-economy invariants, risks, and six-phase roadmap.
- `docs/briefs/BRIEF_011_KINGDOM_PORTFOLIO.md` — bounded contract for adding
  Kingdom to the proof-driven desktop portfolio and refreshing Hoard's stale
  evidence seed.

Kingdom portfolio integration is code-tested only until an attended Windows
check observes all three cards and their drill-down flowcharts.

### Factory commercial Northstar decision — 2026-08-08

The Product Factory is now a fourth governed portfolio project. Its nine
project phases mirror the live production stations, but their exit gates are
commercial facts rather than visual state. The sponsor-set Northstar is
**actual money into the bank account**.

`docs/FACTORY_PROJECT_SOURCE_OF_TRUTH.md` governs that slice. A sale notification,
processor balance, pending payout, test payment, or unreconciled deposit cannot
close it. Phase 8 requires positive `bankedRevenue` and a non-empty
`bankSettlementReference`; `product_factory.dart` enforces that requirement
before the run may enter its terminal stage.

Current Factory state is derived from the persisted live run. No banked-revenue
success is claimed unless the final gate passes.

## Document governance

- Update this file only when evidence or an approved decision changes a claim.
- Never label a capability "done" from a percentage, implementation existence,
  or an agent's self-report.
- Every accepted phase must link its test output or attended evidence.
- `CURRENT_STATE.md` is a historical 2026-07-09 cleanup snapshot.
- `KAI_STATUS.md` and `OVERNIGHT_REPORT.md` are historical implementation logs,
  not current authority.
- `GOD_ARCHITECTURE.md` remains a multi-project access design; it does not prove
  Northstar runtime behavior.
