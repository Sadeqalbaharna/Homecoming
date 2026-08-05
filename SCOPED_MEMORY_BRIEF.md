# Scoped Memory — Review, Fix, and the Triage Tool

Review of the Day 3 scoped-memory work, one fix applied, the legacy triage pass
built, and answers to the six open questions. Companion to
`SURFACE_CAPABILITY_BRIEF.md` (Days 1–2).

State at time of writing: **710 tests passing, 174 analyzer issues (unchanged
baseline), zero issues in any file added here.** The single analyzer *error* is
the pre-existing `brain_3d_screen.dart:1099` one, untouched.

---

## 1. Verified, not assumed

The load-bearing claim holds, and it holds for the subtle reason as well as the
obvious one. In `memory_service.dart`, the scope filter `continue`s at line 125
— **before** the vector is read (127), before similarity is computed (131), and
before `scored.add` (164).

That ordering matters twice. Obviously, inaccessible rows can't be returned.
Less obviously, they never reach `top`, so `_strengthen` never fires on them.
A scored-then-filtered row would have been *reinforced* on every near-miss,
leaking its existence through retrieval statistics even though its content never
appeared. **Do not reorder this.** If a future refactor moves scoring above the
filter, the boundary silently becomes observable.

I also went looking for doors around `queryMemory` and expected to find leaks —
`_getChatGPTContext` and `getConsolidatedMemoryBlock` are both unscoped and both
land in the same prompt. They are **not** reachable on friend surfaces, because
the friend branch (`ai_service.dart:2321`) is purpose-built rather than the
technical prompt with pieces removed. The comment at 2318 has the reasoning:
*"Building the technical prompt and deleting pieces afterward would still
execute forbidden providers."* That is the correct instinct and it is why Day 2's
acceptance test passes for real rather than on paper. Keep new context providers
on that side of the branch.

---

## 2. Finding 1 — fixed. Do not revert.

`scopeForTurn` returned `creative` for all VR goggles-on turns. `creative` is
granted to core and goggles-on VR only, so **every VR memory was stranded inside
VR**: leave the Shack, open Messenger, and the afternoon you just spent together
is gone. That is the one-Kai invariant failing in the exact place the surface
model exists to protect it, and Day 7 step 8 could not have passed.

Now:

```dart
if (context.surface == KaiSurface.vr) {
  return route == KaiRoute.fastChat
      ? KaiMemoryScope.relationship   // the experience travels
      : KaiMemoryScope.creative;      // the work of building stays
}
```

**This is deliberately not the `KaiVrMemoryPair` two-record write.** `remember`
writes one row per call, so a "pair" here would be the same conversation text
stored twice under two visibilities — duplication, not two records, and it would
push the full VR transcript (technical substance included) onto Messenger. The
genuine pair needs an *artifact*, which does not exist until Unity world actions
land. It arrives with the `eventId` write in §5 below.

Known limitation, written into the code rather than hidden: this inherits
`KaiRouterService`'s keyword coverage. "Let's put a window here" hits `design` →
`contemplate` → `creative`, so a genuinely memorable moment can still be scoped
too narrow. It fails **closed**, which is the right direction to be wrong in.

Two tests pin it, and they compose the write scope with the read policy —
either half can be correct while the pair is broken, which is precisely what
happened here:

- `a shared VR moment survives the trip back to Messenger`
- `VR building work stays in VR even though the experience travels`

---

## 3. Finding 2 — OPEN. Sadeq's call. Do not act on it.

Reads are conservative; writes are optimistic, and they meet at `sharedLife`.

`scopeForTurn` gives a core goggles-on `fastChat` turn `sharedLife`, which every
friend surface can read. But `fastChat` is what the router returns when **no
keyword matched**. Any technical turn that dodges the vocabulary — "why did that
break", "check the thing from yesterday" — is written `sharedLife` and becomes
Messenger-visible. The guarantee is only as strong as the router's keyword list,
and the router was never built to be a security boundary.

The fix would be to invert the default: core writes go to `privateCore` unless
there is positive evidence of *personal* content, rather than `sharedLife` unless
there is positive evidence of *technical* content. Writes should be narrower than
reads — a mis-scoped write is permanent, a mis-scoped read is one turn.

**This was put to Sadeq and deliberately deferred.** It makes Messenger thinner,
which is a product trade, not an engineering one. Leave it alone until he says
otherwise.

---

## 4. The legacy triage pass — built, dry-run only

New: `lib/logic/memory_classifier.dart` (pure, zero imports) and
`lib/services/core/kai_memory_promotion_service.dart`.

**It only ever narrows.** The classifier answers exactly one question — "is this
unmistakably technical?" — and abstains on everything else. There is no
`personal` verdict to return, and a test asserts the enum has only two values so
that omission reads as deliberate rather than unfinished. Narrowing hides a
memory and cannot leak; widening exposes it and cannot be undone. Only the safe
direction is automated.

**It never mutates or deletes a source row.** Reads `memory/embeddings/…`,
writes `memory/promotions/…`. Rollback is "delete the promotions tree" — one
operation, no backup to restore. There is no `mutateScope` method to be tempted
by later; that absence is the design.

**`dryRun` defaults to true** and must be passed `false` explicitly. A triage
pass whose default writes is one accidental invocation away from an unreviewed
migration.

**Signal tiers.** Structural markers (code fences, file paths, stack traces,
shell commands) decide on their own. Vocabulary needs two or more, because a
single technical noun is usually someone describing their week. "I am proud of
what we built together" must stay personal — it is exactly the memory Kai should
carry to Messenger, and a topic-word classifier buries it. There is a test.

**One bug worth internalising.** The first version matched bare tool prefixes:
`pub `, `dart `, `flutter `. Those are ordinary English words. *"We went to the
pub after and it was good"*, *"my heart flutters"*, *"he threw a dart"* would all
have been filed as engineering and hidden from Messenger permanently — and the
failure is invisible, because nobody notices a memory that quietly stopped
surfacing. It now matches command+subcommand pairs (`pub get`, not `pub`), and
those three sentences are in the test file.

**How to use it:** run `triage(personaId)` and read
`report.summarize()`. `unclear` being the largest bucket is the expected
outcome, not a failure — the prefilter exists to remove the obvious cheaply so a
later model pass has a smaller, genuinely ambiguous pile. **The gate before
applying anything is `technicalSamples` read by eye, not the counts.** Confidence
numbers are the classifier grading its own homework.

Next increment, when you want it: a model pass over the `unclear` bucket,
constrained to `relationship | sharedLife | privateCore | abstain`, with abstain
free and cheap. Not `identity`, not `creative`, not `world` — those need human
judgment or a writer that does not exist yet. And its output stays a *proposal*.

---

## 5. Answers to the six questions

**1 — `sharedLife` on friend surfaces: keep. `episodic` in VR: remove for now.**
`sharedLife` visibility is correct and must stay; without it Messenger Kai is an
amnesiac, which is a worse failure than the leak it prevents. The real risk is
§3, and it belongs on the write side. `episodic` is different — nothing writes
it. You have pre-authorised a scope with no writer, so the grant activates
silently whenever something starts producing it, and whoever adds that writer
won't know VR already reads it. Add the grant in the same change as the writer.

**2 — Keep `creative` core/VR-only.** Correct as implemented, *conditional on
§2*: the portable half of a VR session is now written `relationship`, so the
experience travels without `creative` ever needing to.

**3 — Yes, `legacyUnscoped` on trusted core only.** Right posture, correctly
implemented (unknown *and* missing both land there, never a guessed scope). One
addition: **time-box it.** An indefinitely-visible legacy bucket means the
migration never finishes, because nothing forces it. Put a target date or a
remaining-row count somewhere you'll see it, or `legacyUnscoped` quietly becomes
permanent architecture.

**4 — Yes, emotional always `relationship`, goggles on or off.** An emotional
turn is relationship material regardless of what he was doing at the time;
forcing goggles-on emotional turns to `privateCore` would mean Messenger Kai
doesn't know Sadeq had a hard week, which is backwards.

The exposure is in the *content*, not the scope. "Sadeq was frustrated about the
auth refactor" is correctly `relationship` and still names the technical thing.
No access matrix fixes that, because the leak is inside the summary string. Keep
the rule; make the *summarizer* scope-aware for this case. Stated generally:
**the scope protects the row; something still has to protect the sentence.**

**5 — Smallest safe promotion pass.** Built — see §4. The principles, in case
they need restating during the model-pass increment: separate output tree, zero
mutation, deterministic prefilter before any model call, constrained output enum
with free abstention, promotion human-triggered and additive, and the gate is a
hand-read dry-run diff rather than a confidence score.

**6 — Event schema and transaction boundary for the Unity pair.**

```
world_action_event {
  eventId            // client-generated, the idempotency key
  worldId, sessionId, deviceId
  action, args       // validated by Unity, never by the model
  outcome            // applied | rejected | reverted
  unityStateVersion  // Unity's scene version AFTER apply
  occurredAt
  utteranceRef       // links back to the conversation turn
}
```

**The commit point is Unity's apply, not the model's intent.** Memory is written
after the outcome returns, never from a proposed action — same rule as the speech
constraint in the previous brief. A memory of moving something he didn't move is
a false memory, and false memories are worse than absent ones in a system whose
entire claim is continuity.

You cannot get a real transaction across RTDB and Unity, so make it **idempotent
rather than transactional**. Both derived records carry `eventId` and go in a
single RTDB multi-path update, which is atomic:

```
update({
  'memory/embeddings/{persona}/{eventId}_exp': experienceRecord,
  'memory/embeddings/{persona}/{eventId}_art': artifactRecord,
})
```

That is the transaction boundary, available today without event sourcing. Retry
is safe because `eventId` dedupes. If the write fails the world has already
changed — queue it keyed by `eventId` and retry next turn. **World state is
authoritative; memory is eventually consistent to it. Never the reverse.**

One rule for the schema: on `outcome: rejected`, write the **experience only, no
artifact**. "We tried to move the wall, it didn't work, he laughed" is real
relationship memory about a change that never happened. Pairing unconditionally
would either lose that or fabricate an artifact.

---

## 6. Next

**Day 4 is next, and it is partly a retrofit rather than a greenfield build.**
The Unity gateway already emits `presenceState` and `gesture`
(`kai_embodiment_gateway_service.dart:241-242`). Missing: `continuityVersion`,
`memoryCandidates`, `availableCapabilities`, request standardisation across
surfaces, and handoffs entirely. Plan it as "extend the shape Unity already has
to every surface", not "design a new contract".

**The Day 6 / Day 7 sequencing risk is unchanged and now interacts with memory.**
Day 6 restructures Firebase around `users/{uid}/personas/{personaId}` while Day 7
needs a working end-to-end proof. A migration and a proof in the same 48 hours
means the cross-surface test most likely runs against a half-migrated store. It
now also collides with the promotions tree, which lives under the same root.
Move the auth restructure earlier or push the proof out.

**Still the biggest open risk, from the previous brief and unchanged:**
`surfaceContext` is a parameter, so the entire goggles model is client-side and
spoofable. Fine while Sadeq is the only user on trusted devices; decorative the
moment Messenger runs somewhere he doesn't control. The broker must move
server-side and derive the surface from the authenticated channel before that
happens, and `forContext(null) = full capability` must invert to fail-closed at
the same time.
