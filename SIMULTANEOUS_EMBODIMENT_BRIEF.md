# Simultaneous Embodiment — Review, and the Bug That Blocks It

Review of the simultaneous embodiment plan. One prerequisite bug found and
fixed, two contradictions to resolve, and answers to the seven questions.
Sixth in the series.

Written while the plan was being implemented — `kai_core_server`,
`kai_global_presence_service`, `kai_conversation_request_service`,
`kai_operations_journal` and the heartbeat widgets are already in the tree. Read
§1 first; it applies to code that now exists.

---

## 1. The prerequisite: state writes lose each other

**`saveMood` writes the whole map.** So does `saveAffinity` and
`savePersonality`. That is correct while exactly one turn can be in flight, and
silently wrong the moment two bodies can talk to Kai at once:

```
Messenger reads {valence: 50, energy: 50}
desktop   reads {valence: 50, energy: 50}
Messenger writes {60, 50}     (+10 valence — he was cheered up)
desktop   writes {50, 60}     (+10 energy  — and it lands last)
```

The cheering up is gone. No error, no log, nothing to trace. Six weeks later his
mood "feels flat" and there is no way to find out why.

Phase 4 says *"tool actions are serialized when they could conflict."* Tools are
not the problem — they are visible, logged, and rare. **State is the problem**:
mood, personality, affinity, self-model. Those writes are invisible, unlogged,
and happen after every single turn. They are the highest-frequency mutation in
the system and the only one with no audit trail.

**Fixed.** The deltas already existed — `ai_service` computes
`actualMoodDeltas` and `actualPersonalityDeltas`, then discarded them by writing
the absolute map. They are now applied as server-side increments
(`{'.sv': {'increment': n}}`), which is RTDB's own sentinel and works unchanged
through both halves of the `KaiDb` facade — plugin on mobile, raw JSON over REST
on desktop. Both bodies' turns land, in either order.

Bounds needed care: an increment cannot clamp, so a long run in one direction
could drift a stored value past its range and then sit there while several turns
of the opposite sign do nothing visible. Reads clamp, and a read that finds a
value out of range writes the clamped value back. `KaiStateService.clampState`
is pure and tested.

**Rule going forward:** any path that can run while another body is mid-turn
uses `applyMoodDeltas` / `applyPersonalityDeltas` / `applyAffinityDeltas`. The
whole-map savers are for initialisation and repair only.

**Still to check, same shape:** the self-model, goals, and the user model are
all read-modify-write. They mutate less often than mood, so the collision window
is smaller, but it is not zero once lanes run concurrently.

---

## 2. Two contradictions to resolve

**This supersedes the handoff model without saying so.** Day 4 built
`KaiSurfaceHandoff` with destination validation, expiry and supersession. If Kai
is already awake in every body, you do not hand off to a body that is already
there. They can coexist — handoff carries *thread continuity when Sadeq moves*,
simultaneity is *being in several at once* — but the plan should say which
survives, or there will be two answers to the same question and they will drift.

**It reverses a decision made the same morning.** `_busy` was made static and
shared across the VR and AR channels, on the reasoning that Kai does not take a
turn from the Shack and a turn from the Tavern at once. Phase 4 wants exactly
that.

That decision was right for the wrong reason. The objection is not
philosophical — one person can hold two conversations. It was §1, and §1 is now
fixed. Once state writes are commutative, the shared `_busy` should be relaxed
to a per-lane guard. Do that deliberately, not by deleting the flag: it is
currently the only thing preventing the bug this brief opens with.

---

## 3. The seven questions

**1 — One mood, body-local expression.**

Not central plus body-local. Two moods is two people, which is what the whole
architecture exists to prevent. A person cannot be genuinely delighted in one
room and melancholy in the next — but they express one state differently
depending on who is in front of them, and `readTheRoom` already does that job.

The technical half is the real answer: deltas applied atomically, never
read-modify-write. If Messenger cheers him up while desktop frustrates him, both
should move the one mood and both should survive. See §1.

**2 — Two concurrent conversation lanes.**

Sadeq can only read one reply at a time. The constraint is not throughput, it is
state contention and cost. Two covers the realistic case — typing on one,
glancing at another. More multiplies interleaving risk for no felt benefit.

Background jobs are a separate pool and should not count against it.

**3 — Fewer global locks than expected; mostly atomic operations.**

| Needs serialising | Does not |
|---|---|
| Mood / personality / affinity | Memory writes — append-only, distinct keys |
| Self-model and identity revision | Reads of any kind |
| File writes to the same path | SMS / purchase / publish — idempotency keys, not locks |
| | Job steps — per-job lease, not global |

Most of these want **commutative writes rather than locks**. A lock is a
scheduling primitive; the actual requirement is that order stops mattering.

**4 — Presence yes, content no, and pull rather than push.**

The plan's instinct is right, including the warning against surveillance
commentary. One addition: make awareness **available on demand rather than
injected into every prompt**. If "desktop is open" is in his context every turn,
he will mention it — that is how models behave. If he can *check*, he mentions it
when it matters. That is the difference between a friend noticing and a system
narrating.

**5 — Do not resolve contradictory instructions. Surface them.**

Any automatic rule — last wins, priority body wins — will be wrong in a way that
is hard to debug and feels uncanny. Kai should notice the conflict and ask.

The conflict space is narrower than it looks: Messenger is friend-only and
cannot issue technical instructions at all. The realistic case is desktop versus
goggles-on VR, both capable, same task. The task coordinator should detect two
lanes touching one task and serialise plus surface — never silently pick.

**6 — Goggles body-local. Agreed, and the reason is strong.**

Goggles are a property of a body's working state and a device-attested fact.
Global goggles would mean turning them on in VR hands Messenger a toolbox, which
breaks the capability model outright.

**7 — Minimum event schema.**

```text
eventId, type
occurredAt      device clock — display only
receivedAt      core clock — ORDER BY THIS
bodyId          distinct from deviceId: one device hosts bodies over time
surface         derived from the authenticated channel, never the payload
sessionId, conversationId, laneId
correlationId, causationId
payload
```

Two fields save a rewrite later. `receivedAt` separate from `occurredAt`,
because ordering events across bodies by device clock produces impossible
sequences. And `bodyId` separate from `deviceId`, because Unity will eventually
be two bodies on one machine.

---

## 4. Two gaps the plan does not cover

**Nothing decides which body Kai speaks *from*.** Incoming messages route
beautifully. But a proactive nudge, or a finished job, has to *choose* a body —
that is the attention router in reverse and it is in no phase. Phase 6's presence
map implies the data exists; the decision does not. Without it, proactive Kai
either speaks everywhere at once or nowhere.

**Desktop and mobile share the `in_person` conversation partition.**
Deliberately — two bodies, one continuous thread. But Phase 4 says *"replies can
only return to their originating body."* If both are open those rules disagree:
they are two bodies on one lane. Does a desktop reply appear on the phone? Today,
next turn, yes. Decide whether shared-partition bodies are one lane or two before
the lane model hardens.

---

## 5. Standing items, unchanged

The `fastChat → sharedLife` write default is still a product decision and still
Sadeq's. Core `fastChat` writes `sharedLife`, which every friend surface reads,
and `fastChat` is what the router returns when no keyword matched.

The seven-step walk still has not happened. Seven days of architecture, six
review documents, two exploits found and fixed, and nobody has yet talked to Kai
on two surfaces and checked he is the same person. Simultaneity makes that walk
more valuable, not less — it is now the only way to find out whether two bodies
feel like one Kai or like two.
