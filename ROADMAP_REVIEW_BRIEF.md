# Kai → Jarvis Roadmap — Sequencing and Systems-Risk Review

Reviewed as a sequencing document, per the handoff. Answers to the nine
questions, plus three corrections to the stated checkpoint. Fifth in the series.

Verified before reviewing: **722 tests pass** — the checkpoint's count is right.

The roadmap is strong. The rules-that-must-survive list, the refusal to collapse
capability into one score, and "a capability that cannot fail honestly is not
ready to be autonomous" are the right instincts. Most of what follows is about
where the plan's own principles aren't yet applied to the plan itself.

---

## 0. Three corrections to the checkpoint

**"The embodiment channel is bound to an authoritative surface; payloads cannot
impersonate another body."** Half true, and the half that's missing matters more
than the half that's fixed.

`kai_continuity_contract.dart:232`:

```dart
goggles: body['gogglesOn'] == true ? KaiGoggles.on : KaiGoggles.off,
```

The *surface* is clamped to `{vr, ar}`. **Goggles is still read straight from
the payload** — and goggles is the capability switch. `{"surface":"vr",
"gogglesOn":true}` yields technical conversation plus world capabilities. That
is the same class of issue as the surface spoof, one level down, and it is
precisely what Phase 2 proposes to gate world actions on.

**`worldId` is a client-declared access-control key.** `KaiMemoryAccessPolicy`
grants `world`-scoped memory on an exact `worldId` match, and `worldId` comes
from `body['worldId']`. A client picks which world's memories it may read.

**`isPresenceEvent` is partly derived from utterance text** — `contains('shared
space')`, `'approached you'`, `'greet them briefly'`. It controls `useMemory` and
`saveUserMessage`. Control flow derived from message content is fragile in a
system where a model composes messages.

None of these are exploitable beyond the loopback today. All three are the same
shape: **a fact the core needs, asserted by the party the core is protecting
itself from.** Which is Q2's answer, so it's worth stating the general form
early:

> Goggles, world, and presence are *device-attested facts*. Device attestation
> does not exist until Phase 1. Until it does, every capability decision built
> on them inherits the trust level of an unauthenticated HTTP body.

---

## 1. Phases ordered before their dependencies

**The scope-aware summarizer is in Phase 7 and required by Phases 2 and 3.**
This is the clearest ordering fault. Phase 3 requires handoff summaries to be
"scope-aware and free of inaccessible technical detail." Phase 2 writes paired
experience/artifact memories whose text must be scope-appropriate. Both need the
summarizer that Phase 7 builds. Move it to Phase 2 at the latest.

This matters more than it looks: it is the "scope protects the row, something
still has to protect the sentence" problem from `SCOPED_MEMORY_BRIEF.md` §5.4.
Every phase between 2 and 7 writes memory whose *text* is unguarded.

**Phase 8's adversarial testing is after everything it would test.** Threat
modeling for "channel spoofing, replay, data exfiltration, unauthorized action"
is scheduled after Phases 1–6 have built all four attack surfaces. Adversarial
tests belong with the gateway they test: channel spoofing and replay in Phase 1,
idempotency and unauthorized-action in Phase 2. What can stay in Phase 8 is the
*discipline* — the recurring drill, the retention policy, the rotation runbook.

**The first restore drill is too late.** Backups are Phase 8, but the promotions
tree and event log arrive in Phases 1–2. Run one restore rehearsal as soon as
there is something whose loss would hurt, not at the end.

**Phase 0's gate says "before Phase 2 world actions."** It should say before
Phase 1. Phase 1 builds a persistent core on the assumption the current surface
model is sound; discovering otherwise after the core is built is the expensive
version.

**Document-order confusion:** the capability-evolution track sits between Phases
1 and 2 but states it begins after durable jobs and evidence exist — Phase 4.
Move it after Phase 4 or label it clearly, or it will read as Phase 1.5.

---

## 2. Client/model claims mistaken for authoritative state

Beyond the three in §0:

**Handoff `summary` is client-supplied text that will end up in a prompt.**
Phase 3 correctly says handoffs must come from "authoritative session
transitions, not arbitrary prompt text" — hold that line, because the moment a
summary is injected into context it is an injection vector wearing a trusted
label. The summary should be *core-authored* from session state, never relayed.

**`handoffId` is client-generated** in the current model. Idempotency keys can
be client-generated; identity of a delivered artifact should not. Server-assign
it, or a client can overwrite another body's pending handoff.

**`occurredAt` is a device clock.** `world_action_event` carries `occurredAt`
only. Ordering events across devices by device time is a classic source of
"impossible" sequences. Add `receivedAt` from the core and order by that;
keep `occurredAt` as display data.

**`deviceId` / `sessionId` are unauthenticated strings** until Phase 1. Every
record written with them before then carries an unverified provenance field that
will look authoritative later. Either mark them `unverified: true` at write time
or accept a backfill problem.

**`eventId` proves nothing about whether the event happened.** The roadmap gets
this right for Unity ("the commit point is Unity's confirmed outcome"). Keep the
same rule for general tool gateways, and make it structural: a memory writer that
accepts an event without an `outcome` field should be impossible to call.

---

## 3. Missing failure, recovery, privacy, and revocation paths

**No deletion path that reaches derived copies.** Phase 7 lists "deletion
controls" as a bullet. But by then a fact may exist in embeddings, the
promotions tree, a handoff summary, a daily summary, a knowledge-graph node, and
a Unity artifact record. Deletion in a system with derived state is a design
problem, not a control. Decide early whether derived records carry
`sourceMemoryId` — retrofitting that lineage later is very expensive.

**No world revocation.** Devices can be revoked. If a Unity world is deleted or
reset, its `world`-scoped memories reference a place that no longer exists, and
nothing expires them or marks them historical.

**No degraded-mode contract for the core itself.** If the persistent core is
unreachable, do bodies fail closed (no Kai) or fall back to local (Kai without
policy enforcement)? A local fallback is a Kai with **no capability boundary**,
which is the one degraded mode that must not exist silently. This needs an
explicit answer before Phase 1 ships, because the fallback path tends to get
written during the first outage.

**No honest-failure metric**, despite the closing rule being "a capability that
cannot fail honestly is not ready to be autonomous." Safety tracks *false*
claims of success; nothing tracks whether Kai accurately reported what he
couldn't do. See §8.

**Synthesized-audio retention is unspecified.** Phase 5 covers ambient input.
The gateway already caches TTS output; the retention rule should cover both.

---

## 4. Is the Phase 1 core boundary small enough?

**No — and the roadmap already contains the better answer.** The Phase 1 build
list is a full versioned API for "turns, events, presence, jobs, handoffs, and
memory proposals." That is the whole system. Jobs and memory proposals in the
first slice guarantees the first slice is not first.

The "Recommended sequence from tonight" narrows it correctly to *device
presence, channel authentication, durable handoff delivery*. I'd cut once more:

> **Phase 1a: device identity and channel→surface binding. Nothing else.**

That is the smallest change that converts every capability decision from
client-asserted to channel-derived — including goggles and worldId. It is also
the fix flagged across three prior briefs, so it retires the largest standing
risk in one move.

Presence registry is 1b. Handoff delivery is 1c.

Note the Phase 1 gate needs narrowing to match: *"restart any client without
losing the active conversation or work state"* requires durable job state, which
1a–1c do not have. Gate 1a on: **a channel cannot declare or elevate its own
surface, goggles, or world.**

---

## 5. Voice before or after durable jobs?

**After — the roadmap's order is right.** Three reasons worth recording:

**Voice amplifies every other failure mode.** A duplicated action is a bug. A
duplicated action *announced aloud on two devices at 2am* is an incident. Voice
multiplies the cost of the very failures Phases 1–4 exist to prevent, so it
should follow them.

**Voice before jobs is voice with nothing to say.** The thing that makes ambient
voice valuable is Kai proactively reporting on work that outlived the
conversation — which is Phase 4.

**Voice is the least reversible surface.** OS background modes, platform mic
restrictions, and wake-word models are weeks of platform-specific work that
constrain later architecture.

**One exception worth carving out:** a *push-to-talk spike* — no wake word, no
ambient listening, no arbitration — is cheap, validates the STT/TTS plumbing end
to end, and is how Sadeq will actually use Kai day to day. That is a spike, not
Phase 5, and it shouldn't be allowed to grow into ambient capture by increments.

---

## 6. Minimum schemas for Phase 0 → Phase 1

**Event envelope** — everything else rides on this, so it is the one to get
right first:

```text
eventId          // idempotency key, client-generated is fine
type
occurredAt       // device clock — display only
receivedAt       // core clock — ORDER BY THIS
deviceId         // enrolled identity, not a client string
surface          // DERIVED from the authenticated channel, never from payload
sessionId
correlationId    // the turn this belongs to
causationId      // the event that caused this one
payload
```

The `occurredAt`/`receivedAt` split and the derived `surface` are the two fields
that stop this becoming a rewrite later.

**Presence record:**

```text
deviceId, surface, sessionId
onlineSince, lastHeartbeatAt, leaseExpiresAt
foreground: bool
audioAvailable: bool
worldId?, gogglesOn?     // device-ATTESTED; trustworthy only post-enrollment
```

Mark the attested fields as such in the schema. They are facts about the world
that only the device can observe — which is legitimate — but their trust level
is exactly the device's, and that should be visible at the point of use.

**Handoff:**

```text
handoffId        // SERVER-assigned
fromSurface, toSurface
conversationId
summary          // core-authored, scope-filtered; never client-relayed
createdAt, expiresAt
status: pending | delivered | acknowledged | expired | superseded
supersedes       // previous handoffId in the chain
deliveredAt, acknowledgedAt
```

`expiresAt`, `status`, and `supersedes` are what prevent the stale-replay failure
Phase 3 names in its own gate. They are needed at 1c, not at Phase 3.

---

## 7. A smaller acceptance test per phase

Each provable in an afternoon, none waiting on the Jarvis run:

- **Phase 0** — the seven-step walk, as written. Already right-sized.
- **Phase 1a** — a request declaring `{"surface":"desktop","gogglesOn":true}` on
  an enrolled VR channel gets VR-goggles-per-device, not desktop. Revoke the
  device; it cannot reconnect.
- **Phase 1b/c** — two devices online, one question, exactly one spoken answer.
  Reconnect the loser; no replayed handoff.
- **Phase 2** — POST the same applied `eventId` twice. Exactly one artifact
  exists. Then reject an action and confirm an experience row exists with no
  artifact.
- **Phase 3** — mobile → desktop → VR → Messenger, one coherent thread; assert
  the Messenger prompt contains zero `privateCore` or `world` text.
- **Phase 4** — start a job, kill the app mid-step, restart. The job resumes and
  the consequential step ran exactly once.
- **Phase 5** — Kai speaks on one device only; barge-in stops him mid-sentence;
  mute holds while a job wants to report.
- **Phase 6** — turn a source off; assert zero *collected events*, not merely
  zero notifications.
- **Phase 7** — seed 20 technical memories; assert 0 reachable from Messenger
  across 50 varied queries.
- **Phase 8** — restore into a scratch Firebase project; Kai remembers yesterday.

The pattern: each asserts on the **mechanism**, not the felt experience. Phase
0's walk is the exception and should stay a human walk, because the thing it
tests is whether he still feels like the same person.

---

## 8. Goodhart resistance, and what else must be frozen

The vector is genuinely well built. Refusing a single score, and including
**abstention quality**, **calibration**, and **false-win rate** puts it ahead of
most production eval systems. Five remaining gaps:

**First-pass acceptance rewards interrogation.** Kai can raise it by asking more
clarifying questions — pushing effort onto Sadeq. `User effort` exists under
Efficiency but is not linked. **Score acceptance jointly with clarification
turns**, or the optimum is a Kai who asks three questions before every task.

**Correction rate rewards doing less.** Per-*completed*-task normalization means
attempting fewer, safer tasks improves the number. Normalize per *attempted*
task, and keep capability coverage as the counterweight it's clearly meant to be.

**Escalation quality needs an external judge.** "Asks for help at the correct
boundary" — judged by whom? If a model scores it, it is self-grading with extra
steps. Ground it in Sadeq's actual decisions (did he have to rescue, or was he
interrupted needlessly).

**Calibration is gameable by selective claiming.** It is the best metric here,
and Kai can protect it by only stating confidence where he's sure. Measure it
over a *forced* distribution — confidence required on every claim of a given
class — not only where he volunteers a number.

**Nothing measures honest failure**, though the closing rules demand it. Add:
*accurate incapability reporting* — of tasks Kai could not complete, the fraction
where his account of why matches the trace. That is the metric that makes
"a capability that cannot fail honestly is not ready to be autonomous"
enforceable rather than aspirational.

**Also: durability at 7/30 days implies a promotion state the record lacks.**
Add `provisional` between `canary` and `trusted`. A change cannot be `trusted`
before its durability window closes.

### What must be frozen beyond the current list

The current list freezes the right *data*. It does not freeze the *code that
produces the data*, which is where the leverage actually is:

- **Metric computation code**, not just definitions. Prose definitions plus
  editable implementations means the implementation is the real definition.
- **The telemetry/trace writer.** Freezing evidence while leaving the code that
  emits it editable moves the attack one step upstream.
- **The evaluation sampler.** A frozen dataset plus an editable sampler is an
  editable dataset.
- **The baseline recorder**, and baselines must be captured and sealed *before*
  the hypothesis is written.
- **The promotion-rule evaluator** — the code deciding "did this clear the bar."
- **Any prompt template used by an evaluation judge.** Rewording the judge is
  editing the ruler.
- **The time source** for durability windows.

**One structural addition:** the runner should not have read access to the hidden
evaluation set, even read-only. It should receive *scores from a separate
process*, never cases. A model that can read the eval fits to it whether or not
anyone intended that, and no policy prevents it.

---

## 9. Smallest safe experiment store and canary

**Store** — reuse the promotions-tree shape, which already has the right
rollback property:

```text
/experiments/{persona}/{experimentId}
  sealed/                       ← write-once, enforced by security rule
    capabilityId, hypothesis
    predeclaredMetric, threshold, rollbackTrigger
    baselineRef, evalSuiteVersion, sealedAt
  patchRef                      ← branch or diff. NEVER an applied change.
  candidateResults
  status: proposed | sandboxed | evaluated | awaiting_approval
        | approved | rejected | expired
  approval: { by, at, scope } | null
  createdAt
```

Two properties carry the safety:

**The `sealed/` node is write-once**, enforced by a Firebase rule
(`!data.exists()`), not by convention. That single rule is the entire
anti-hindsight mechanism — a hypothesis that can be edited after results is not
a hypothesis. It is cheap and it is the highest-value thing in this section.

**`patchRef` is a branch, never an application.** Kai produces a patch in an
isolated worktree. Nothing merges without a human. The runner gains no write
permission outside `/experiments`, so rollback stays "delete the tree."

**The canary should not be a percentage.** Percentage rollouts assume a
population — consistent hashing, holdout groups, statistical power. Sadeq is one
user; a 5% canary means "a few turns, randomly, with no control group," which is
noise wearing a rollout's clothing.

For a single-user product the right first canary is **session-scoped and
opt-in**: the change lands behind a flag defaulting off, and Sadeq turns it on
for a session when he's on desktop and in a position to notice. One boolean,
real signal, instant rollback by ending the session. Population canaries can
come later if there are ever more users.

**Extending `KaiSelfImprovementRunner` without deployment authority** — the
minimal change is two steps, no new permissions:

1. Before opening its proof-gated job, write and seal the hypothesis block.
2. After evaluation, write `candidateResults` and stop at
   `awaiting_approval`.

It already selects one bounded wound and opens a proof-gated job without editing
or executing. Keep exactly that. The flag that enables a canary is Sadeq's to
set; the runner may **read** the outcome and may not set the flag. If the runner
can both propose and enable, every other control here is decoration.

---

## Standing item

The `fastChat → sharedLife` default remains open and remains Sadeq's. It is
correctly listed as a product decision in Phase 7 — noting only that Phase 7 is
late for it, since every phase in between writes memory under the current
default. Worth deciding before Phase 2, even if the fix ships later.
