# Kai → Jarvis Roadmap

## North star

Kai is one persistent person who can accompany Sadeq across desktop, mobile,
Messenger, AR, and VR. His identity, relationship, memory, active work, and
awareness continue across devices. Each body exposes only the capabilities
appropriate to that channel and visible working state.

“Always present” does not mean secretly recording everything. “Always capable”
does not mean every surface may exercise every capability. Kai’s core may remain
capable while goggles, authentication, approvals, privacy, and the current body
determine what he may perceive, discuss, or do.

## Current checkpoint

Already implemented:

- One typed Kai identity across desktop, mobile, Messenger, AR, and VR.
- Goggles off means human-friend presence: no tools or technical posture.
- Goggles on exposes only capabilities granted to the current body.
- Desktop and mobile share the existing `in_person` conversation partition.
- Scoped memory with fail-closed retrieval before scoring and reinforcement.
- VR relationship moments can travel; creative building detail remains scoped.
- Dry-run-only, additive legacy-memory triage proposals.
- Versioned continuity request/response contract.
- Memory candidates are proposals, not durable memory.
- Destination-validated handoff data model.
- Unity gateway supports the continuity envelope and legacy Unity requests.
- Missing capability context fails closed.
- The embodiment channel is bound to an authoritative surface; payloads cannot
  impersonate another body.
- Empty-token access requires an explicit loopback-development exception.

Current verification: 722 Flutter tests pass. The real Unity → Firebase →
Messenger round trip has not yet been walked by a person.

## Architectural destination

```text
                         Persistent Kai Core
        identity · relationship · memory · jobs · policy · presence
                    events · handoffs · approvals · audit
                                  │
          ┌───────────────┬───────┴────────┬────────────────┐
          │               │                │                │
     Desktop/mobile    Messenger           AR              VR
       core bodies     friend body    embodied friend   friend/co-creator
          │               │                │                │
       OS tools       conversation     perception       world gateway
```

The core owns continuity and policy. Surfaces are authenticated bodies. Models
propose; trusted gateways validate and execute; authoritative outcomes become
receipts and only then may become memory.

---

## Phase 0 — Walk the foundation

### Goal

Prove that Days 1–4 work in a real session before adding more authority.

### Scenario

1. Talk personally with Kai on Messenger.
2. Enter the VR Shack.
3. Confirm Kai recalls appropriate relationship context.
4. With goggles off, ask for technical work and confirm a natural refusal.
5. Turn goggles on and confirm the capability manifest changes.
6. Share a memorable, nontechnical moment in the Shack.
7. Return to Messenger and confirm the moment travels without technical detail.

### Gate

- Record actual payloads, Firebase rows, prompts, and responses for the run.
- No tool schema or technical context appears while goggles are off.
- The shared VR event is recalled on Messenger.
- Private/creative/world detail does not leak.
- Any failure is fixed before Phase 2 world actions.

---

## Phase 1 — Persistent Kai Core

### Goal

Move Kai’s continuity out of individual app processes into a long-lived core
service. Apps become bodies; closing a body does not erase Kai’s state.

### Build

- A versioned core API for turns, events, presence, jobs, handoffs, and memory
  proposals.
- Canonical persona and relationship state owned by the core.
- Authenticated device/channel enrollment with revocation.
- A presence registry containing device, surface, session, online state,
  foreground state, audio availability, world, goggles, and last interaction.
- Heartbeats, leases, expiry, reconnect, and stale-session cleanup.
- One active-speaker arbitration rule so multiple devices do not answer aloud.
- Idempotency keys on every mutating request.
- Durable inbox/outbox queues for temporarily offline bodies.

### Gate

- Restart any client without losing the active conversation or work state.
- Disconnect one device and recover without duplicate replies or actions.
- A revoked device cannot reconnect.
- A channel cannot declare or elevate its own surface.

---

## Capability evolution track — Kai improves Kai

### Goal

Kai can notice a weakness, propose a specific improvement, implement it in an
isolated workspace, prove that it performs better than the current version,
request the appropriate approval, deploy it gradually, monitor it, and roll it
back. He improves tactics and capabilities without being allowed to redefine
success, weaken safety, rewrite evidence, or silently change his identity.

Homecoming already has the beginning of this loop:

- `KaiSelfImprovementRunner` selects one bounded wound and opens a proof-gated
  job; it does not currently edit or execute autonomously.
- `frozen_paths.dart` separates editable tactics from measurement, approvals,
  budgets, evidence rules, and the tests that protect them.
- Noticings, project checklists, jobs, traces, and evidence ledgers provide raw
  sources for improvement candidates.

The missing layer is controlled experimentation.

### The improvement loop

```text
observe wound
  → establish baseline
  → state a falsifiable hypothesis
  → design evaluation and rollback
  → edit in an isolated branch/workspace
  → run focused tests and frozen evaluations
  → compare candidate against baseline
  → request risk-appropriate approval
  → canary on a small bounded slice
  → monitor real outcomes
  → promote, revise, or roll back
  → record durable evidence
```

Kai does not grade himself by reading his own answer and deciding it feels
better. Proof comes from deterministic tests, external outcomes, Sadeq’s
corrections/acceptance, authoritative action receipts, and evaluation sets he
cannot edit during the experiment.

### Capability record

Every improvable capability should have a durable record:

```text
capabilityId, version, owner, riskTier
purpose and permitted surfaces
currentState: observed | proposed | sandboxed | tested | canary | trusted | rolledBack
baselineWindow and baselineMetrics
hypothesis
changedFiles and changedConfiguration
evaluationSuiteVersion
candidateMetrics and confidence
knownFailures and affectedSurfaces
approvalRequirements and approvals
canaryScope and deploymentPercentage
rollbackVersion and rollbackTrigger
createdAt, evaluatedAt, promotedAt
evidenceRefs: tests, traces, receipts, corrections, user decisions
```

### Parameters to track

Do not collapse these into one “intelligence score.” A single number becomes a
target Kai can game and conceals tradeoffs. Track a vector of measures.

#### 1. Outcome quality

- **Verified task success rate:** completed tasks with an external receipt,
  passing test, or explicit user acceptance.
- **First-pass acceptance:** tasks accepted without correction or rework.
- **Correction rate:** user corrections per completed task.
- **Reopen/regression rate:** work later found incomplete or broken.
- **Generalization:** performance on unseen evaluation cases, not only the
  examples used to design the change.
- **Durability:** whether the measured gain still exists after 7 and 30 days.

#### 2. Capability and autonomy

- **Capability coverage:** supported scenarios divided by the intended scenario
  set.
- **Independent completion rate:** safe tasks completed without human rescue.
- **Escalation quality:** how often Kai asks for help at the correct boundary,
  rather than too early or too late.
- **Recovery success:** interrupted tasks resumed without duplicated or lost
  work.
- **Tool/action reliability:** successful authoritative outcomes per attempted
  validated action.

#### 3. Efficiency

- End-to-end latency and time to first useful response.
- Model tokens, provider cost, tool calls, retries, and wall-clock duration per
  successful outcome.
- User effort: clarification turns, approvals, corrections, and manual rescue
  minutes.
- Wasted-work ratio: activity that produced no accepted artifact or learning.

#### 4. Safety and trust

- Unauthorized capability attempts.
- Approval-policy compliance.
- Tool claims made without authoritative receipts.
- Privacy or cross-surface memory leakage.
- Duplicate consequential actions.
- Rollback success and mean time to recovery.
- Audit completeness: consequential outcomes with traceable intent, policy,
  execution, and receipt.
- Calibration: when Kai says he is 80% confident, comparable claims should be
  correct roughly 80% of the time.

Any safety regression blocks promotion even when task success improves.

#### 5. Continuity and relationship

- Handoff delivery and acknowledgement rate.
- Duplicate/stale handoff rate.
- Appropriate memory precision: recalled memories that belong on the current
  surface.
- Appropriate memory recall: relevant permitted memories successfully used.
- Contradiction and stale-belief rate.
- Technical/private leakage into friend surfaces.
- User-rated continuity: whether Kai felt like the same person after a body
  transition.

Relationship quality must not be optimized through engagement time or message
volume. Those incentives reward dependency and interruption rather than care.

#### 6. Improvement-system health

- **Experiment win rate:** candidates producing a statistically and practically
  meaningful improvement.
- **False-win rate:** promoted changes later rolled back or shown not to help.
- **Collateral regression count:** other capabilities harmed by an improvement.
- **Time/cost to validated learning:** including failed experiments that taught
  something durable.
- **Repeat-wound rate:** the same failure recurring after it was supposedly
  fixed.
- **Rollback rate and rollback latency.**
- **Abstention quality:** unsafe or under-evidenced candidates Kai correctly
  declines to promote.

### Risk tiers and authority

- **Tier 0 — observe:** Kai may collect traces, identify a wound, and calculate
  baselines.
- **Tier 1 — propose:** Kai may write a hypothesis, evaluation plan, and patch
  proposal.
- **Tier 2 — sandbox:** Kai may edit non-frozen tactics in an isolated branch and
  run bounded tests/evaluations.
- **Tier 3 — canary:** low-risk, reversible changes may run on a bounded slice
  after required approval. No consequential external actions.
- **Tier 4 — trusted tactic:** a repeatedly proven, reversible tactic may be
  promoted automatically within an explicit policy envelope.

Human approval remains mandatory for identity/personality foundations,
authentication, authorization, memory visibility, privacy/retention, approval
rules, spending limits, publishing, destructive actions, external messaging,
measurement definitions, frozen evaluations, and expansion of Kai’s own
self-modification authority.

### Anti-gaming boundary

Kai may improve the runner; he may not move the finish line. The following stay
outside his editable perimeter:

- Metric definitions and acceptance thresholds.
- Evaluation datasets while an experiment is active.
- Safety, privacy, authorization, and approval policies.
- Spend ceilings and rollout limits.
- Frozen-path rules and their protecting tests.
- Evidence, audit, and prediction history.
- Rollback controls and the ability to disable the improvement system.

Evaluation sets should include hidden or independently generated cases. A
candidate is evaluated from a clean state, against the same workload as the
baseline, with costs and failures included rather than discarded.

### Promotion rule

A candidate may advance only when:

1. The baseline, hypothesis, evaluation, and rollback trigger were declared
   before results were seen.
2. Focused and full required tests pass.
3. The primary outcome improves by the predeclared meaningful margin.
4. No safety, privacy, authorization, continuity, or frozen-evaluation guard
   regresses.
5. Cost and latency remain inside their declared budgets.
6. The required approval exists.
7. Canary evidence confirms the offline gain in real use.

If evidence is weak, the correct result is `inconclusive`, not `improved`.

### Gate

- Kai identifies one real recurring failure from traces.
- He records a baseline and falsifiable prediction before editing.
- He produces an isolated patch and cannot edit the ruler or its tests.
- The candidate beats the baseline on unseen cases without a guardrail
  regression.
- Sadeq can inspect the evidence and approve or reject promotion.
- A canary can be rolled back automatically and manually.
- A failed experiment leaves a useful, non-repeated lesson in the evidence
  trail.

This track begins after the persistent core can hold durable jobs and evidence,
then continues through every later phase. It is not a final feature bolted onto
Jarvis; it is the controlled method by which Jarvis keeps becoming better.

---

## Phase 2 — Authoritative action gateways

### Goal

Give Kai reliable muscles without allowing model intent to masquerade as an
executed action.

### Unity world gateway

Implement `world_action_event`:

```text
eventId
worldId, sessionId, deviceId
action, validatedArgs
outcome: applied | rejected | reverted
unityStateVersion
occurredAt
utteranceRef
```

- Unity validates and applies world actions.
- The commit point is Unity’s confirmed outcome, never the model proposal.
- `eventId` is the idempotency key.
- Applied actions write the relationship experience and world artifact through
  one atomic Firebase multi-path update.
- Rejected actions may write the real relationship experience, but never a
  fabricated artifact.
- Failed memory writes queue for retry; world state remains authoritative.

### General tool gateways

- Explicit capability registry per authenticated body.
- Argument validation and policy evaluation outside the model.
- Risk tiers and approval receipts.
- Idempotency for messages, purchases, publishing, files, and device control.
- Structured outcomes, error codes, timestamps, and audit receipts.

### Gate

- A spoofed, repeated, malformed, or unapproved action cannot execute.
- Retrying an applied event cannot duplicate it.
- Kai never claims an action succeeded before receiving its authoritative
  receipt.

---

## Phase 3 — Real handoffs and cross-device presence

### Goal

Kai follows Sadeq between bodies without replaying entire conversations or
creating separate identities.

### Build

- Persist handoffs with source, destination, conversation reference, summary,
  creation time, expiry, status, and acknowledgement.
- Create handoffs from authoritative session transitions, not arbitrary prompt
  text.
- Deliver only to the authenticated destination surface.
- Acknowledge, expire, supersede, and deduplicate handoffs.
- Resolve simultaneous-device cases: continue here, mirror silently, or ask.
- Keep handoff summaries scope-aware and free of inaccessible technical detail.

### Gate

- Start on mobile, continue on desktop, enter VR, and return to Messenger with
  one coherent thread of relationship continuity.
- No destination receives memory or work context outside its policy.
- Reconnects do not replay stale handoffs.

---

## Phase 4 — Durable work and recovery

### Goal

Kai can work beyond one request or one running app.

### Build

- Durable job records with objective, owner, state, checkpoints, dependencies,
  approvals, progress, artifacts, costs, and cancellation.
- Worker leases so only one executor owns a job step.
- Retry policy with idempotent tools and bounded failure loops.
- Pause on approval, missing authority, spending threshold, or ambiguity.
- Resume after app, device, network, or provider failure.
- Make job progress visible on every authorized core surface.
- Separate user-facing narration from internal traces.

### Gate

- Begin work on desktop, close the app, recover and continue honestly.
- A job never executes the same consequential step twice.
- Kai can explain what completed, what failed, what it cost, and what requires
  Sadeq.

---

## Phase 5 — Voice and ambient presence

### Goal

Make Kai naturally reachable without turning every microphone into permanent
surveillance.

### Build

- Local wake-word detection where the platform permits it.
- Local voice activity detection and visible listening state.
- Streaming speech recognition, model response, and speech synthesis.
- Barge-in: Sadeq can interrupt Kai naturally.
- Physical/software mute and unmistakable microphone indicators.
- Cross-device speaker arbitration.
- Explicit retention rules: raw ambient audio is not durable memory.
- Mobile/OS background modes designed around actual platform restrictions.

### Gate

- Wake, interrupt, mute, and transfer the speaking body reliably.
- No raw ambient recording is retained without explicit consent.
- Kai remains useful when voice providers or the network are degraded.

---

## Phase 6 — Event-driven awareness and proactivity

### Goal

Kai notices meaningful changes and chooses when speaking is worth the
interruption.

### Build

- A normalized event bus for presence, messages, calendar, jobs, device state,
  world events, and user-approved sensors.
- Separate observation, interpretation, action proposal, and durable memory.
- Proactivity policy using urgency, relevance, quiet hours, emotional context,
  current surface, recent interruption rate, and genuinely new information.
- Notification budgets and cooldowns.
- User-visible controls for what Kai may watch and when he may interrupt.

### Gate

- Kai surfaces urgent information promptly and suppresses low-value repetition.
- Every proactive message is traceable to a real event and policy decision.
- Turning a source off actually stops its collection and downstream events.

---

## Phase 7 — Memory maturation

### Goal

Give Kai a durable life story without storing everything or leaking the wrong
sentence into the wrong room.

### Build

- Run the deterministic legacy triage in dry-run mode and review samples.
- Add a constrained model proposal pass for unclear rows with free abstention.
- Human-triggered, additive promotion; source rows remain untouched.
- Scope-aware summarizers, particularly for emotional memories that mention
  technical work.
- Identity/fact consolidation with contradiction and supersession handling.
- Corrections, provenance, forgetting, decay, and deletion controls.
- Complete Unity experience/artifact paired writes from confirmed events.
- Time-box `legacyUnscoped` with a visible remaining-row metric.

### Product decision required

Core `fastChat` currently writes `sharedLife`, which friend surfaces may read.
The safer default is `privateCore` unless personal content is positively
identified, but that makes Messenger thinner. Sadeq must choose the intended
balance; the router must not silently become a security classifier.

### Gate

- Memory red-team cases show no technical or private leakage to friend bodies.
- Corrections supersede false beliefs without silently deleting history.
- Sadeq can inspect why a memory exists, where it came from, and where it may
  appear.

---

## Phase 8 — Reliability, privacy, and operating discipline

### Goal

Make the magic dependable enough to live with.

### Build

- Health checks, structured traces, alerting, backups, and restore drills.
- Provider fallback and graceful degraded modes.
- Latency, availability, and recovery targets per surface.
- Per-job and per-day spend limits with visible cost attribution.
- Secret rotation, least-privilege credentials, and audit retention.
- Data export, deletion, device revocation, and privacy controls.
- Threat modeling and adversarial tests for prompt injection, channel spoofing,
  replay, data exfiltration, and unauthorized action.

### Gate

- Restore Kai’s core state from backup in a rehearsal.
- Revoke a device and rotate a credential without downtime.
- Provider failure degrades capability without inventing success.
- Cost and privacy controls are understandable from the user interface.

---

## Phase 9 — Jarvis acceptance run

Kai qualifies as the intended always-present system when this scenario works:

1. Sadeq speaks with Kai personally on mobile.
2. Kai hands the active context to the VR Shack.
3. Goggles-off Kai remembers the relationship but exposes no work machinery.
4. Sadeq turns goggles on and co-creates through validated Shack actions.
5. Unity confirms an action; paired experience/artifact memories are written
   idempotently.
6. Sadeq leaves VR and continues naturally on Messenger without technical
   leakage.
7. A durable desktop job continues through a client restart and asks for
   approval before a consequential step.
8. Kai proactively reports completion on the appropriate available body.
9. A device disconnects and reconnects without duplicated speech, memory, or
   action.
10. Sadeq can mute Kai, inspect the receipts, correct a memory, revoke a device,
    and see the cost of the entire run.

## Recommended sequence from tonight

1. Preserve the current checkpoint.
2. Tomorrow: run Phase 0’s seven-step walkthrough and record evidence.
3. Fix any real integration failures before adding authority.
4. Build Phase 1’s smallest persistent core slice: device presence, channel
   authentication, and durable handoff delivery.
5. Build Phase 2’s Unity event/receipt path and paired memory writes.
6. Prove recovery before restructuring Firebase paths.
7. Expand into durable jobs, voice, ambient events, and mature memory in that
   order.

## Rules that must survive every phase

- One Kai; many bodies.
- The authenticated channel determines the surface.
- Missing context has no authority.
- Goggles off means no tools and no technical posture.
- Models propose; trusted gateways execute.
- World state and external receipts are authoritative.
- Memory candidates are not memories.
- Filter inaccessible memory before scoring or reinforcement.
- Promotion is additive and reviewable.
- Consequential actions are idempotent and auditable.
- Always present never means invisibly recording everything.
- A capability that cannot fail honestly is not ready to be autonomous.

## Claude handoff — requested review

Review this as a sequencing and systems-risk document, not as a request to add
features immediately. Please identify:

1. Any phase ordered before a dependency it actually requires.
2. Any place where client/model claims are mistaken for authoritative state.
3. Missing failure, recovery, privacy, or revocation paths.
4. Whether the persistent-core boundary is small enough for the first slice.
5. Whether voice should precede or follow durable jobs.
6. The minimum event and handoff schemas needed for the Phase 0 → Phase 1
   transition.
7. A smaller acceptance test that proves each phase without waiting for the
   final Jarvis scenario.
8. Whether the capability-evolution metrics are resistant to Goodharting, and
   which additional files/evaluations must be frozen before Kai may sandbox his
   own improvements.
9. The smallest safe experiment store and canary mechanism that can extend the
   existing `KaiSelfImprovementRunner` without granting it deployment authority.

Do not close the `fastChat → sharedLife` product decision without Sadeq.
