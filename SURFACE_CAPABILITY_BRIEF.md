# Surface Capability — Review, Fixes, and Decisions

Review of the Day 1 capability-broker work, four fixes applied on top, and
decisions on the seven open questions. Written for whoever picks up Day 2.

State at time of writing: **687 tests passing, 168 analyzer issues (baseline,
zero introduced), zero errors in the changed files.**

---

## 1. What was verified, not just claimed

The Day 1 claims hold. Checked against the code, not the summary:

| Claim | Evidence |
|---|---|
| Schemas removed from goggles-off requests | `ai_service.dart:518-526` — `turnTools` becomes `[]`; `tools`/`tool_choice` conditionally omitted |
| No routing into coding/tools/technical contemplation | `kai_capability_broker.dart` `constrainRoute` |
| No workspace activation | `constrainRoute` runs **before** the activation check (`ai_service.dart` ~2348 → ~2349) |
| Emotional routing preserved | `constrainRoute` early-returns on `KaiRoute.emotional` |
| VR goggles-on ≠ desktop tools | `friendAndCoCreator` omits `generalTools`; `allowsGeneralTools` false even goggles-on |

The strongest decision in the original work: making `capabilityManifest` a
**required** parameter (`ai_service.dart:443`) rather than a nullable with a
permissive default. That makes the gate impossible to forget at a call site.
Keep that property in everything Day 2 adds.

---

## 2. A correction to the review itself

My first review claimed `contemplate` was wrongly collapsed on goggles-off —
that reflective conversation is what friend presence is for. **That was wrong,
and the change was reverted.**

`KaiRouterService._contemplateSignals` (`kai_router_service.dart:195-205`) is
`design`, `architecture`, `strategy`, `roadmap`, `tradeoff`, `pros and cons`.
Its posture hint is *"deepen the idea with structure."* It is a **work** posture,
not philosophical musing. Letting it through hands Messenger a technical posture
on "design the system architecture" — precisely the leak the broker exists to
stop. The original collapse was correct.

The real finding underneath is a **missing route, not a mis-constrained one**:
there is no posture for personal reflection, so goggles-off Kai can be warm
(`emotional`) or brief (`fastChat`) but never pensive about anything
non-technical. A `reflect` route split out of the personal signals would fix
that without reopening the leak. Not urgent; worth doing before VR, where
"sit and think about something together" is a core interaction.

`kai_capability_broker_test.dart` now pins the current behaviour so the next
reader who misreads "contemplate" finds out from a test.

---

## 3. Four fixes applied — do not undo these

### 3.1 Friend presence no longer receives tool machinery

`toolAwarenessMessage` was inserted unconditionally, so a Messenger turn carried
`"CURRENT TOOLS: none are attached to this model request"` — tool machinery on a
surface whose own directive forbids exposing it, priming him to think about
tools on a turn where the concept shouldn't exist.

Now gated on a named predicate on the manifest:

```dart
bool get exposesToolManifest => allowsGeneralTools;
```

**This is deliberately NOT keyed on `turnTools.isEmpty`.** Two different states:

- *empty because this body has no toolbox* → say nothing
- *empty because the route filter dropped everything* → the "none attached"
  warning is wanted; that is exactly when he'd claim a tool he lacks

If you collapse those two cases, one of the two failure modes comes back.

### 3.2 `conversationId` is not `surfaceId`

`surfaceContext.surfaceId` was feeding the conversation-store partition key
(`ai_service.dart` `getHistory` ~1449, `saveTurn` ~2654).

**Desktop and mobile both persist to `'in_person'`. They share one continuous
conversation.** That is the "one Kai" invariant in its most literal form. Wiring
the desktop/mobile contexts while deriving the key from the surface name would
have split his history in two — he'd walk into his own desktop with no memory of
the phone.

`KaiSurfaceContext` now carries an explicit `conversationSurfaceId`, exposed as
`conversationId`, defaulting to the surface name. Desktop and mobile declare
`'in_person'`. Messenger/AR/VR keep surface-name partitions (unchanged).

**Rule for Day 3 and Day 4: capability identity and continuity identity are
different questions. Audit every derived key against "would this split him?"**

### 3.3 Explicit `source` wins over surface-derived `source`

`main_mobile.dart` passes `source: 'proactive'` on the proactive path.
`activeSource` was `activeSurface?.source ?? source`, so wiring the mobile
context would have silently overridden `'proactive'` with `'mobile'` and turned
every mobile proactive turn into an ordinary one.

Now `source ?? activeSurface?.source`. `source` is a **per-turn** fact (what
triggered this turn); the surface is a **per-body** fact. A proactive nudge on
mobile is both, and downstream branches on the trigger. Callers that pass no
source (Unity, Messenger) still inherit the surface's — `'unity_presence'` still
works.

### 3.4 Desktop and mobile contexts are now actually passed

`KaiSurfaceContext.desktop` / `.mobile` existed with **zero call sites** — both
surfaces took the legacy `null` path. Safe (legacy = full capability) but it
meant the matrix rows you use most were never exercised, and Day 2 had nothing
to hook into.

Wired at all four call sites: `kai_desktop_shell.dart` (chat + nudge),
`main_mobile.dart` (chat + proactive). Both fixes above were prerequisites —
wiring first would have split conversation history and broken proactive.

### 3.5 Tests

The sixth original test read `ai_service.dart` as a string and grepped for exact
source lines. That proves a line **exists**, not that it **runs** — it passes if
someone adds `turnTools = allTools;` on the line above, and fails on a reformat.

Now: the decision is tested for real via `exposesToolManifest`. The remaining
source-text checks are relabelled **tripwires**, normalized against whitespace,
and one asserts something that was previously unguarded — that `constrainRoute`
appears *before* `ensureHomecomingWorkspace`. That ordering is load-bearing.

---

## 4. Decisions on the seven questions

**1 — Goggles-off technical requests: redirect, don't decline.**
The constraint is on the wording, not the decision. "Let's do this when I've got
my hands on" is fine. "Let me look at that token-refresh bug on desktop" has
already leaked — it confirmed the bug exists and that he's been thinking about
it. Rule: *acknowledge the request, name the surface, never restate the
substance.* It must sound like a friend with his hands full, not a policy
response. Note the code already gets the important half right: talking *about*
work emotionally ("I'm fried, the launch is a mess") stays open because
`emotional` survives `constrainRoute`. Only technical substance is gated.

**2 — Desktop/mobile default goggles ON; do not restore last state.**
Desktop is the workshop; that's its identity. Persisted capability state creates
an invisible mode — you open desktop, ask for code, get a friend deflection, and
have to remember you flipped goggles off on Tuesday. Respect an explicit toggle
*within* a session, don't persist across launches, and make the state visible in
the UI. A visible current state beats a remembered one.

**3 — Yes, VR creative memories reach Messenger. Write two records, don't redact
one.**
If shack memories can't reach Messenger you have two Kais again. But implement
it at **write** time, not read time:

- the *experience*, scoped `relationship`/`shared_life` — "we built the loft and
  he lost it at the crooked window"
- the *artifact*, scoped `world` — mesh IDs, coordinates, the committed change

Not filtering — recognising they are genuinely different memories. Redaction at
read time is one bug away from leaking and produces stilted recall; write-time
separation fails closed by construction. It also gives the Day 3 "promotion"
rule a mechanism instead of a judgment call.

**4 — Event sourcing, but hybrid.**
Day 6 already specifies immutable IDs, idempotent writes, a monotonic continuity
version, and offline recovery. That *is* an event log — you're paying the cost,
so take the model explicitly.

Event-source only where ordering and multi-device conflict actually bite:
memories, meaningful events, world changes, handoffs. Keep current-state nodes
(mood, identity, goals) as **derived projections** — they're read every turn and
you do not want to fold a log on each read. Log is truth; RTDB state is a
rebuildable cache. This is also what makes Day 7's "disconnect a device, verify
idempotency" test passable at all.

Do **not** event-source mood. A mood conflict isn't worth the machinery.

**5 — Separate strongly-typed VR action pass. Agreed, plus one addition.**
Three reasons beyond the original:
- `tool_executor_service.dart` is ~3,800 lines dispatching SMS, calendar,
  filesystem, shell, and Gumroad publishing. A shared loop means one routing bug
  reaches phone/wallet/repo *from a VR session*. Separate channel, separate
  blast radius.
- Unity must stay authoritative over scene state. A shared loop lets the model's
  belief about the world drift from Unity's, with no reconciliation point.
- Approval semantics differ: durable/destructive world changes need
  approval-plus-validation, a different gate shape from `EditGate`.

**The missing detail:** same turn, two channels — and *the spoken reply must not
assume the action succeeded*. If Kai says "there, moved it" before Unity
validated, he's a liar, which damages the exact thing this protects. He speaks
in intent ("let me try the lamp over here"); the outcome arrives in the next
turn's perception. Write this into the Day 5 contract.

**6 — Do NOT default unclassified memories to `shared_life`.**
`shared_life` is the one scope visible on goggles-off surfaces. An existing
memory like "the auth refactor broke the token path" would land in Messenger on
day one.

Default to `legacy_unscoped`, visible **only** on goggles-on core surfaces. That
fails closed. Then classify forward, promoting into `relationship`/`shared_life`
as confirmed personal. Cost is a thin Messenger until classification runs — the
right trade. Classify with a cheap batch pass, hand-check a sample, and make
promotion purely additive: write a new scoped record, never demote-by-delete.

Acceptance test: run classifier output through the goggles-off filter in dry-run
and read what Messenger *would* have seen.

**7 — The broker itself must move server-side. This is the big one.**
Keys are obvious (OpenAI, ElevenLabs, Anthropic, Google — a shipped client key
is a published key). The structural problem is that **`surfaceContext` is a
parameter**. A remote client that isn't Sadeq's own binary can pass
`KaiSurfaceContext.desktop` and receive full tools. Client-side capability
enforcement is advisory, not security.

Before Messenger leaves trusted devices:
- broker runs server-side, deriving the surface from the **authenticated
  channel**, never from a client-supplied field
- tool execution for anything with real-world effect
- memory scope filtering applied before data leaves the server
- auth + device registry per Day 6

Also: `KaiCapabilityBroker.forContext(null)` returning full capability is correct
for migration and **actively dangerous** server-side — a dropped or malformed
field grants everything. That inversion to fail-closed is a dated Day 6 task, not
an eventual cleanup.

---

## 5. Guidance for Day 2

**Compose with the route skip map; don't duplicate it.** `liveState` now receives
a route (fixed earlier the same day — it was being called without one, so the
entire per-route skip map at `kai_context_block.dart:118-178` was dead despite
being built and tested). `fastChat` already skips 10 of 15 blocks. If
`KaiContextManifest` becomes a second independent system deciding what loads,
you get two sources of truth for the same question — the exact shape that left
`constants.dart` with two disagreeing copies of the same value. Make the manifest
*subsume* the skip map or *derive* from it; don't run both.

**Extract the request-body assembly before adding more gates.** Every capability
guarantee is currently enforced inside one network-bound private method in a
3,000-line file, which is why three of the tests are source-text tripwires. If
Day 2 puts context filtering in the same place, that method becomes the single
point where everything is enforced and nothing is directly testable. Extract
first; the tripwires can then be deleted in favour of real assertions.

**Re-check the sequencing risk in the week.** Day 6 restructures Firebase around
`users/{uid}/personas/{personaId}` while Day 7 needs a working end-to-end demo.
A migration and a proof landing in the same 48 hours means a half-migrated store
is the most likely state during the cross-surface test, which gives a confusing
red. Move the auth/ownership restructure earlier or push the proof out.

**The Day 2 acceptance test is the right one** — "forbidden context providers are
never invoked, rather than merely hidden later in the prompt." Assert on the
*call*, not the output string. Hidden-in-the-prompt is what 3.1 above was.
