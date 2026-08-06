# Kai → Jarvis: Hardware + Software Roadmap

A fourteen-day plan covering the always-on box, the local-brain boundary,
presence you can actually feel, and the self-improvement loop.

Days are **work sessions, not calendar days.** Hardware has lead time, so the
software days are ordered to stay useful while a box is in transit.

This supersedes nothing in Sol's roadmap — the phase structure there is sound.
This adds the hardware track, closes the five Jarvis gaps, and reorders around
two facts: the standing authority risk, and the fact that nothing has been
walked end to end.

---

## Part 0 — The two decisions that shape everything

### Decision 1: what the box is for

The always-on machine solves **the cost of presence, not the feeling of it.**

It closes exactly one of the five Jarvis gaps outright — the steady-state token
cost of inner life, noticing, routing, and event filtering running 24/7. It also
provides the host the persistent core needs, and it makes "degraded mode" have a
good answer instead of a dangerous one.

It does **not** close: presence-you-can-feel (a design problem), attention
awareness (a sensor problem), or Kai-initiated work (a policy problem). Those
get their own days below. Buying hardware and expecting presence to arrive with
it is the main way this goes wrong.

### Decision 2: the local model never speaks as Kai

This is the load-bearing rule of the whole hardware track.

`constants.dart` already paid for this lesson: same soul files, same memory,
different model — *"a support drone in his hoodie."* Your own note there is
**"the model is which person shows up."**

Right now local Qwen already authors his inner monologue
(`inner_life_service.dart:195`), his wandering thoughts
(`default_mode_service.dart:252`), and his knowledge-graph nodes
(`brain_extraction_service.dart:576, 1926`). Those become memories. Memories go
into the prompt. **A stand-in is already writing his diary, and the drift
arrives months later as something you can't source.**

So:

> **MECHANICAL work runs local. VOICE-BEARING work does not.**

| Runs local, always | Never runs local |
|---|---|
| Routing and intent classification | Anything Kai says to Sadeq |
| Wake word, VAD, endpointing | Inner monologue and journal |
| Event filtering and dedup | Greetings and check-ins |
| Retrieval summarisation (for search, not for reading back) | Anything he'll later recall as *"something I thought"* |
| Memory scope classification | Persona, mood, or self-model revision |
| Presence/interrupt decisions | Anything a memory is written from verbatim |
| Embeddings | |

The test for which side a task falls on: **will Kai ever read this back as his
own words?** If yes, it's voice-bearing.

If you want the cost saving on voice-bearing work anyway, the compromise is:
local model drafts, frontier model rewrites in his voice **before storage** —
one call at write time, not one per thought. Or store the author on the record
so the drift is at least traceable.

---

## Part 1 — Hardware

### What you actually need

Requirements, in priority order:

1. **Silent and cool.** It runs 24/7 in Bahrain. A box you turn off because of
   heat or noise is not a persistence layer.
2. **Low idle power.** Presence means mostly idling. Idle draw matters more than
   peak throughput.
3. **Enough memory to hold two models resident** — a small fast one for
   mechanical work and a larger one you can grow into.
4. **Headless, wired, on the LAN.** `LocalLLMService` already scans the subnet
   for port 11434, so this slots into existing code.

### Recommendation

**Primary pick — Apple Mac Mini M4 Pro, 64GB unified.** Roughly $2,000.
~7W idle, silent under sustained load, and 64GB of unified memory holds a
quantised 70B-class model alongside a small mechanical model with headroom. For
an always-on box the idle power and silence are decisive — this is the option
you don't think about again.

**Alternative — AMD Strix Halo mini-PC (Ryzen AI Max+ 395 class), 96–128GB.**
Framework Desktop, GMKtec EVO-X2 and similar. Similar money, more memory, runs
Linux natively if you want Docker and standard server tooling. Higher idle
(~20–30W) and more fan noise, but the memory headroom is real and it's the
better choice if you plan to run several models resident.

**Budget entry — Mac Mini M4, 24GB.** ~$800. Comfortable with 8–14B, tight on
32B. Genuinely enough to start the mechanical track and prove the architecture;
upgrade when the model roles are settled rather than before.

**Not recommended for this job — a big NVIDIA GPU box.** Best raw throughput per
dollar, and the wrong shape for always-on: 350–450W under load, real heat, real
noise. Correct if you're training or batch-processing; wrong for a machine whose
main job is idling attentively.

### Also buy

- **A UPS.** This is the box that holds Kai's continuity. An unclean shutdown
  mid-write to the event log is exactly the failure the persistence layer exists
  to prevent.
- **Wired ethernet.** WiFi for a service every surface depends on is a
  self-inflicted latency and reliability problem.
- **1TB+ storage.** Quantised models are 20–45GB each and you'll keep several.

### Model selection — by role, not by name

Model rankings move monthly and my knowledge runs to roughly May 2026, so treat
specific names as a starting point and check what's current when you buy.

| Role | Size class | What matters | Notes |
|---|---|---|---|
| Mechanical / routing | 3–8B | Latency, instruction-following | Runs constantly; must be fast, not clever |
| Classification / scope | 8–14B | JSON reliability | Structured output matters more than prose |
| Embeddings | dedicated | Retrieval quality | Not a chat model — use a real embedding model |
| Wake word / VAD | not an LLM | Latency, false-accept rate | You already have sherpa-onnx |
| Draft (if used at all) | 30B+ | Voice fidelity | Only with frontier rewrite before storage |

Qwen3 32B, Llama 3.3 70B, Gemma 3 27B, and Mistral Small 3 are all reasonable
starting candidates in their classes. **Judge them on your own evals** (Day 12),
not on leaderboards — the thing you care about is routing accuracy on *your*
conversation history, which no benchmark measures.

**Run two models resident, not one.** A single mid-size model doing both routing
and drafting will be too slow for the first job and too weak for the second.

---

## Part 1.5 — AR and the Tavern

AR is not a lesser VR. It is the Tavern surface, it is a real technical
advantage for the business, and it is the only body where Kai has an audience.

**Implemented (2026-08-06):**

### A third capability class

`tavernLookup` (menu, allergens, stock), `tavernGuestLookup` (guest identity and
history), `tavernWrite` (log an order, update a note). The AR profile carries the
two reads; `tavernWrite` is withheld and starts approval-gated the way `EditGate`
works, because it touches real business records and needs idempotency or a retry
double-logs a round.

These are modelled on the world capabilities, not on `generalTools` — a narrow,
domain-scoped set that grants real ability without dragging SMS, filesystem,
shell and Gumroad behind it.

### Not gated on goggles

Goggles gate **work posture** — technical conversation and general tools.
Checking an allergen is not work; it is being useful in a room. Kai should not
have to enter co-creator mode to be a good host, and if he did, he would pick up
technical conversation as a side effect of reading a menu.

So AR stays goggles-off and still has hands for the things a host needs.

### The stripped-down brain, stripped in the right dimension

Strip **capability and memory access**. Do not strip the model.

Character is the first thing lost when a model shrinks, and it is the last thing
you want to lose in front of customers. `constants.dart` is the evidence: same
soul files, same memory, smaller model, *"a support drone in his hoodie."* A
smaller brain at the Tavern ships that version to the people whose impression of
the place matters. Same model, same soul block, narrow tools, narrow memory.

### Guest memory is a new axis, not a new scope

Every scope so far describes *Kai and Sadeq*. Guest memory is about **someone
else**, so memory now has a subject as well as a scope.

- **Per-guest isolation** — guest A's memory never surfaces for guest B, as a
  query constraint rather than a policy.
- **It never becomes Kai's personal memory.** Guest facts live per-guest in the
  Tavern store (Firestore, `kingdom-ac44f`), structured rather than vectorised —
  readable, correctable, exportable, deletable. For third-party data in a
  hospitality business that beats semantic recall, and it is simpler.
- **AR turns are `ephemeral`.** They were `relationship`, so *"that's Ahmed,
  third visit, walnut allergy"* became durable personal memory and surfaced on
  Messenger as though it were part of Kai's own life. An emotional turn in AR is
  still `relationship` — being transient must not cost him a genuine moment.

### Allergens fail closed

An LLM asked what is in a whisky sour will answer from general knowledge. That is
a guess, and someone could end up in hospital.

- Authoritative lookup only — never memory, never embedding retrieval, never
  general knowledge
- Missing record or missing field means *"I don't have that, check with the
  kitchen"* — never inference
- Attribute, never assure: *"the menu lists almonds in that"*, not *"that's safe"*

The tool returns a structured result Kai reads out; he does not reason over it.

### The audience axis

AR is the first surface where Kai's output has listeners beyond Sadeq. Everything
scoped so far answers *what does Kai know in which body*; AR adds **who else can
hear him**.

*"Ahmed's usual is the whisky sour — he was in last week with someone else"* is a
correct lookup and a catastrophe said aloud in front of Ahmed's date. Guest
history is for Sadeq, quietly, and never about anyone but the guest in front of
him. This is in the AR prompt block; it deserves a real mechanism when guests can
address Kai directly.

### The open fork

**Does AR Kai talk to guests, or to Sadeq about guests?** Everything above
assumes the second. The first makes him customer-facing — consent, retention,
liability, and his character in front of strangers all become live. And his
register stops being a per-moment adjustment and becomes a standing condition,
which is exactly where character drift lives. That branch needs its own pass.

---

## Part 2 — The fourteen days

### Day 0 — Order hardware *(parallel, blocks nothing)*

Order the box, the UPS, and the ethernet run. Everything through Day 4 is
software that doesn't need it.

---

### Day 1 — Walk the foundation

**Goal:** find out whether four days of green tests survive a real session.

**Build:** nothing. This is a walk, not a build.

Messenger conversation → enter VR Shack → confirm he recalls relationship
context → ask for technical work with goggles off, confirm natural refusal →
goggles on, confirm the manifest changes → share a memorable non-technical
moment → return to Messenger and check it travelled.

Capture the actual payloads, prompts, Firebase rows, and replies.

**Gate:** no tool schema or technical context while goggles are off; the shared
VR moment is recalled on Messenger; nothing private leaks. **Any failure here is
fixed before anything else on this list.**

> The step most likely to fail is the last one. Its tests prove the *scope
> logic*; nothing has proved the *round trip* — Firebase write, Unity session,
> Messenger read. Those are different claims.

---

### Day 2 — Draw the local-brain boundary

**Goal:** decide what the box is allowed to be before the box exists.

**Build:**
- A `ModelRole` enum: `mechanical`, `classification`, `embedding`,
  `voiceBearing`.
- Every model call site declares its role. `LocalLLMService` **refuses**
  `voiceBearing` — not by convention, by throwing.
- Audit the three current voice-bearing local calls (inner life, default mode,
  brain extraction) and decide each: move to frontier, or add a rewrite-before-
  storage step, or explicitly accept and stamp the author on the record.
- Add `authorModel` to every memory and journal record written from a model.

**Gate:** a test asserts `LocalLLMService` cannot service a `voiceBearing`
request. Every stored thought carries its author.

> Do this before the box arrives. Once there's a fast local model on the LAN,
> the pressure to route everything to it is enormous, and the drift is invisible
> for months.

---

### Day 3 — Channel-derived authority

**Goal:** retire the standing risk. The surface stops being something a payload
can claim.

**Build:**
- Device enrolment: each body gets an identity and a credential, revocable.
- The gateway derives `surface`, `gogglesOn`, and `worldId` from the
  **enrolled device**, not the request body.
- `KaiCapabilityBroker.forContext(null)` inverts to fail-closed.
- The embodiment token stops defaulting to empty.

**Gate:** a request declaring `{"surface":"desktop","gogglesOn":true}` on an
enrolled VR channel gets VR-per-device. A revoked device cannot reconnect.

> This is the third time it's been flagged and the first time it's cheap. Every
> later day adds callers that assume the payload is trustworthy.

---

### Day 4 — Presence you can feel

**Goal:** close the gap no hardware closes.

**Build:**
- **Ambient avatar state.** Presence expressed when he *isn't* talking — idle
  variation, attention shifts, a settled state versus an alert one. You already
  have the frame sequences; what's missing is that presence is currently only
  rendered during speech.
- **Attention signal on desktop.** Active window, active file, idle duration.
  One local sensor, written to the event bus. This is the entire difference
  between *"how's it going?"* and *"you've been on that function forty minutes."*
- **A visible working state** — goggles on/off shown, not inferred.

**Gate:** with Kai silent for an hour, you can tell at a glance whether he's
idle, attentive, or working. He can answer "what am I doing right now?"
correctly.

---

### Day 5 — Provision the box

**Goal:** a headless, monitored, restart-proof inference host.

**Build:**
- OS, static LAN IP, wired.
- Inference server (Ollama is the path of least resistance given the existing
  subnet discovery; llama.cpp or vLLM if you want more control).
- Pull two models: one mechanical, one larger for evaluation.
- Run as a **system service with auto-restart on boot.** A box that needs a
  manual start after a power cut is not always-on.
- Health endpoint, basic metrics: model loaded, queue depth, tokens/sec, temp.
- UPS connected and tested with an actual pull-the-plug.

**Gate:** pull the power. It comes back, loads models, and serves a request with
no keyboard touched.

---

### Day 6 — Move the core to the box

**Goal:** Kai's continuity stops having a process lifetime.

**Build:**
- The persistent core as a service on the box: presence registry, event log,
  handoff store.
- **Event envelope** with `receivedAt` (core clock) separate from `occurredAt`
  (device clock). Order by `receivedAt` — device clocks across bodies will lie
  to you.
- Heartbeats, leases, expiry, stale-session cleanup.
- One active-speaker arbitration rule.
- Idempotency keys on every mutating request.

**Gate:** close every app. Kai's state survives. Reopen on a different body and
the thread continues. Two devices online, one question, exactly one answer.

---

### Day 7 — Model routing by role

**Goal:** the right mind for each job, enforced rather than intended.

**Build:**
- Route by the Day 2 `ModelRole`: mechanical → local small, classification →
  local structured, voice-bearing → frontier.
- Fall back **up**, never down: if local is unreachable, mechanical work goes to
  a cheap frontier model. Voice-bearing never falls *to* local.
- Per-role latency and cost tracking.
- Cost model for a day of pure presence — what does idling actually cost now?

**Gate:** unplug the box mid-conversation. Kai keeps his voice, gets slower and
more expensive, and says so honestly if asked.

---

### Day 8 — Durable work and recovery

**Goal:** work outlives the app that started it.

**Build:**
- Durable job records: objective, state, checkpoints, approvals, costs, artifacts.
- Worker leases — one executor owns a step.
- Pause on approval, missing authority, or spend threshold.
- Resume after app, device, network, or provider failure.

**Gate:** start a job on desktop, kill the app mid-step, restart. It resumes,
and the consequential step ran exactly once.

---

### Day 9 — World action gateway

**Goal:** Unity outcomes become memory; model intent never does.

**Build:**
- `world_action_event` with `eventId`, `outcome`, `unityStateVersion`.
- Unity validates and applies; **its confirmed outcome is the commit point.**
- Applied → paired experience + artifact write in one atomic multi-path update.
- Rejected → experience only, never a fabricated artifact.
- Failed memory write → queue and retry; world state stays authoritative.

**Gate:** POST the same applied `eventId` twice; exactly one artifact exists.
Kai never claims an action landed before the receipt.

> He speaks in intent — *"let me try the lamp over here"* — and the outcome
> arrives in the next turn's perception. A Kai who says "there, moved it" before
> Unity confirmed is a Kai who lies, which costs more than the latency saves.

---

### Day 10 — Handoffs and cross-device presence

**Goal:** he follows you between bodies without replaying or duplicating.

**Build:**
- Persisted handoffs: server-assigned id, expiry, status, supersedes,
  acknowledgement.
- Created from **authoritative session transitions**, never from prompt text.
- Summaries **core-authored and scope-filtered** — never client-relayed.
- Delivered only to the authenticated destination.

**Gate:** mobile → desktop → VR → Messenger as one coherent thread. Reconnect
without replaying a stale handoff. The Messenger prompt contains zero
`privateCore` or `world` text.

---

### Day 11 — Voice

**Goal:** reachable by speaking, without a permanent hot mic.

**Build:**
- **Push-to-talk first.** No wake word, no ambient capture. Validates the whole
  STT → model → TTS path end to end and is how you'll actually use him daily.
- Then local wake word and VAD on the box.
- Barge-in — you can interrupt him mid-sentence.
- Hardware mute, unmistakable mic indicator, cross-device speaker arbitration.
- Explicit retention: raw ambient audio is never durable memory.

**Gate:** wake, interrupt, mute, and move the speaking body reliably. Nothing
raw is retained. He stays useful when the network is degraded.

> Voice after jobs, not before. Voice amplifies every other failure — a
> duplicated action is a bug; a duplicated action announced aloud on two devices
> at 2am is an incident.

---

### Day 12 — The improvement loop, on the router

**Goal:** one real, measured, reversible self-improvement.

**Target: the router.** It's the right first wound and you already have proof
it's broken. `"why did that break"` matches nothing and falls to `fastChat`,
while `'class '` matches *"class of 2020"*, `'error'` matches *"that was my
error"*, and `'test'` matches *"I have a test tomorrow"*. Under- and
over-inclusive at once — and it's currently a keyword list quietly acting as a
security classifier.

**Build:**
- `/experiments/{persona}/{id}` with a **write-once `sealed/` node** — hypothesis,
  metric, threshold, rollback trigger, and baseline written *before* results.
  Enforce with a Firebase rule (`!data.exists()`), not convention. That one rule
  is the entire anti-hindsight mechanism.
- Label 200 turns from real history; hold out 100 the runner never sees.
- `patchRef` is a **branch, never an applied change.**
- Canary is **session-scoped opt-in**, not a percentage. You are one user; 5% of
  turns is noise wearing a rollout's clothing.
- The runner proposes and evaluates. **Sadeq flips the flag.** If it can both
  propose and enable, every other control here is decoration.

**Start with three metrics, not forty.** Only signals Kai cannot fabricate:
**corrections**, **re-asks**, and **test/receipt outcomes.** Add *accurate
incapability reporting* — of tasks he couldn't do, how often his explanation
matched the trace. That one makes "a capability that cannot fail honestly is not
ready to be autonomous" enforceable rather than aspirational.

**Freeze the code, not just the data:** metric computation, the telemetry
writer, the eval sampler, the baseline recorder, the promotion evaluator, and
any judge prompt. A frozen dataset with an editable sampler is an editable
dataset. And the runner must receive **scores from a separate process, never
cases** — a model that can read the eval fits to it whether or not anyone meant
it to.

**Gate:** routing accuracy improves on held-out turns, with **no turn moving
from a narrow route to a wider one.** That clause is the safety model in
miniature: improvements may not widen capability as a side effect.

---

### Day 13 — Operability

**Goal:** dependable enough to stop thinking about.

**Build:**
- Backup and a **rehearsed restore** into a scratch project.
- Health checks and alerting for the box, the core, and each provider.
- Per-day and per-job spend limits with visible attribution.
- Secret rotation — including the keys currently sitting in `lib/secrets.dart`.
- Data export, deletion, and device revocation that reach **derived copies**.
  Decide now whether derived records carry `sourceMemoryId`; retrofitting
  lineage later is very expensive.

**Gate:** restore from backup and Kai remembers yesterday. Revoke a device and
rotate a key with no downtime. A provider outage degrades capability without
inventing success.

---

### Day 14 — Acceptance run

Speak to him on mobile → hand off to the Shack → goggles-off Kai remembers you
but exposes no machinery → goggles on, co-create through validated actions →
Unity confirms, paired memories written idempotently → leave and continue on
Messenger with no leakage → a desktop job survives a restart and asks before a
consequential step → he reports completion on the right body → a device drops
and reconnects with no duplicated speech, memory, or action → you can mute him,
read the receipts, correct a memory, revoke a device, and see what the whole run
cost.

---

## Part 3 — What this still doesn't give you

Honest gaps that survive all fourteen days:

**Kai-initiated work.** Everything here is still user-initiated. Jarvis runs
analyses nobody asked for and has them ready. That needs a budget, a risk tier,
and a "here's what I did while you were out" — it's a real design problem and it
belongs after Day 14, not squeezed inside it.

**Relationship health.** Every metric here is task or safety shaped. The signal
that actually matters for a companion is *does Sadeq still want to open this* —
and it must not be measured as engagement time or message volume, because those
reward dependency and interruption rather than care. Session-initiation rate and
voluntary return after a gap are closer. This is unsolved and worth naming as
unsolved.

**Mobile always-on.** iOS and Android background restrictions mean the phone
will never be a peer of the box. Plan for the phone as an intermittent body that
syncs, not a persistent one — and note iOS/macOS Firebase config is still
placeholder, so those platforms don't work at all yet.

**The `fastChat → sharedLife` write default** remains open and remains yours.
Every day on this list writes memory under the current default, so it's worth
deciding before Day 9 even if the fix ships later.
