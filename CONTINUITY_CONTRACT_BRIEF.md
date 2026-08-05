# Continuity Contract (Day 4) — Review, One Escalation, and the Principle

Review of the Day 4 turn-contract work. One privilege escalation found, proved,
and fixed; two smaller fixes; and the sequencing recommendation that follows.
Third in the series after `SURFACE_CAPABILITY_BRIEF.md` (Days 1–2) and
`SCOPED_MEMORY_BRIEF.md` (Day 3).

State at time of writing: **721 tests passing, 173 analyzer issues (unchanged),
zero new issues.** The single analyzer *error* remains the pre-existing
`brain_3d_screen.dart:1099`.

---

## 1. What the contract gets right

Genuinely good, and worth keeping as-is:

- **Capabilities are derived, never accepted.** `availableCapabilitiesFor` asks
  the broker rather than reading a client field. Correct instinct.
- **Handoffs must match their destination.** `parsedHandoff?.toSurface ==
  surface ? parsedHandoff : null`, plus `tryParse` rejecting same-surface and
  incomplete records. A handoff addressed elsewhere is inert.
- **Unknown versions throw rather than guess.** `unsupported_continuity_version`
  is the right failure.
- **Errors ride the same envelope as successes** (`_writeJson` back-filling
  continuity fields), so a client never needs a second parser.
- **`memoryCandidates` stays empty with an honest comment** rather than
  inferring durable memory from Unity perception in a transport adapter. That
  restraint is correct — perception is transient by design.
- **`episodic` removed from the VR policy** per the last brief, with a test
  asserting VR must not pre-authorise a scope before its writer exists. Good.

---

## 2. The escalation — fixed. Understand why before touching it.

### What it was

`KaiContinuityTurnRequest.fromJson` built a `KaiSurfaceContext` from a
**client-declared `surface` field**. The class doc says Homecoming "never trusts
a client-provided capability list." That is true and it is beside the point:
it was trusting the client-provided **surface**, and the surface *is* the
permission set. `allowsGeneralTools`, `allowsTechnicalConversation` and the
world capabilities are all derived from it.

The gateway then passes `turn.surfaceContext` straight into `sendMessage`.

So:

```
POST 127.0.0.1:8787/v1/turn
{"surface":"desktop","utterance":"..."}
→ a Kai holding SMS, calendar, filesystem, shell, and Gumroad publish
```

Auth does not stop this. `_token` defaults to empty via
`String.fromEnvironment`, and `_authorized` returns `true` when the token is
empty. Loopback binding means "any local process", not "nobody".

### Why it is a regression, not a pre-existing gap

The old gateway hardcoded:

```dart
surfaceContext: mode == 'ar' ? KaiSurfaceContext.ar.copyWith(...) : KaiSurfaceContext.vr(...)
```

It could only ever construct AR or VR. Neither grants `generalTools`. The worst
a malicious loopback POST could obtain was goggles-on VR — world capabilities,
no general tools. **The universal five-surface parser removed that ceiling.**

This is the part worth sitting with: Day 4 made the contract *better* and the
boundary *worse*, in the same change. A universal contract is the right design.
It is also what turned an in-process parameter-passing detail into an
HTTP-facing capability grant. Nothing here was careless — the failure came from
generalising a parser without asking what the transport was allowed to build.

### How it was proved before it was claimed

A probe test, run before writing a word of the finding:

```dart
final request = KaiContinuityTurnRequest.fromJson({
  'surface': 'desktop', 'utterance': 'hello',
});
expect(availableCapabilitiesFor(request.surfaceContext), contains('generalTools'));
```

It passed on the first run. Worth doing this routinely — a security claim that
hasn't been executed is a hypothesis, and hypotheses about capability boundaries
are wrong often enough to be dangerous.

That probe now lives on as `desktop capability is real, which is why the
allowlist matters`, so nobody removes the clamp believing it guards nothing.

### The fix

The contract stays universal; the **transport declares what it can host**.

```dart
const Set<KaiSurface> kEmbodimentSurfaces = {KaiSurface.vr, KaiSurface.ar};

// in the gateway:
KaiContinuityTurnRequest.fromJson(
  body,
  defaultPersona: canonicalPersona,
  allowedSurfaces: kEmbodimentSurfaces,
);
```

`allowedSurfaces` is optional, so `fromJson` remains genuinely universal —
your `all five surfaces use the same request parser` test passes untouched, and
correctly so. Only transports clamp.

The allowlist lives beside the contract rather than inside the gateway, so a
second transport has to make its own deliberate declaration rather than
inheriting this one by accident.

**The principle, which is the reusable part:** *authority comes from the
channel, never from the payload.* This is the same rule the broker must follow
when it moves server-side — derive the surface from the authenticated
connection, not from a field someone can type.

---

## 3. Two smaller fixes

**Unknown surfaces defaulted to VR.** `_parseSurface(...) ?? KaiSurface.vr`
meant a typo, or a client from a future version, silently became an embodied
body with goggles taken from its own payload. Present-but-unrecognised now
throws `unknown_surface`. **Absent still defaults to VR** — legacy Unity bodies
omit the field entirely, and that path must keep working.

**A test that punished the next correct change.**
`unity_presence_event_guard_test.dart` asserted
`contains('memoryCandidates: const [])`. That fails the day candidates are
properly implemented — a test whose only lesson is "delete tests to make
progress." Removed, along with the `payload.putIfAbsent` internals check. The
durable wiring assertions stayed, and the rule is now in the file header:

> Assert on wiring that SHOULD be permanent. Never assert that something is
> still unimplemented.

A tripwire that guards a placeholder is a tripwire pointed at your own team.

---

## 4. Sequencing — please read this one

This is the third brief in which the client-side trust boundary comes up, and
the first in which it produced an actual exploit path rather than a theoretical
one. That escalation is the shape of the problem, not an instance of it:

- Days 1–3 built the goggles model on a `surfaceContext` **parameter**.
- Day 4 put that parameter on the wire.
- Day 6 plans to expose the wire.

Every day of building adds another caller that assumes the payload can be
trusted, and each one makes the eventual server-side move more expensive.

**Recommendation: move the server-side broker ahead of Day 5.** Day 5 adds world
tools — a whole new capability class reachable through the same parser that just
demonstrated it would mint whatever surface it was handed. Landing the
authenticated-channel derivation first means world tools are built on a real
boundary instead of being retrofitted onto one later.

Concretely, before Day 5's world capabilities:
- broker derives the surface from the authenticated channel, not the body
- `KaiCapabilityBroker.forContext(null)` inverts from full-capability to
  fail-closed (correct for migration, dangerous the moment it is remote)
- the embodiment token stops defaulting to empty

The Day 6/Day 7 collision from the last brief is unchanged and now has a third
party: the promotions tree, the Firebase restructure, and the end-to-end proof
all land in the same 48 hours under the same root.

---

## 5. Notes for Day 5

**The world-action pair now has a home in the contract.** `KaiMemoryCandidate`
already carries `eventId`, `worldId`, `scope` and `provenance`, which is exactly
the shape the paired experience+artifact write needs. Keep `status: 'candidate'`
— a proposal that persists itself is not a proposal.

**Reuse the allowlist pattern for world tools.** Same question, one level down:
Unity declares a world manifest, and the answer to "which of these may Kai call"
must come from the surface and the goggles, not from the manifest the client
sent. A world manifest is a payload.

**Keep the two rules from the previous briefs:**
- Unity's apply is the commit point; memory is written from `outcome`, never
  from intent. Kai speaks in intent ("let me try the lamp over here"), and the
  result arrives in the next turn's perception.
- On `outcome: rejected`, write the experience only, no artifact. "We tried to
  move the wall, it didn't work, he laughed" is real relationship memory about a
  change that never happened.

**Still open and still Sadeq's call:** the write-classifier default from
`SCOPED_MEMORY_BRIEF.md` §3. Core `fastChat` writes `sharedLife`, which every
friend surface reads, and `fastChat` is what the router returns when no keyword
matched. Deferred deliberately — it makes Messenger thinner. Do not act on it
unilaterally.
