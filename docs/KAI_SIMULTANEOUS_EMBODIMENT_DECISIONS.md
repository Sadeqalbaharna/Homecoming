# Kai simultaneous embodiment — decisions after review

## Invariants

- Central Kai is continuously present; bodies connect and disconnect.
- One shared mood/personality/affinity state, with body-local expression.
- Goggles are body-local and device-attested.
- Raw transcripts remain scoped to a conversation room.
- Two human-facing conversation lanes may run concurrently. Background work is
  a separate pool.
- Events are ordered by Core `receivedAt`, never device `occurredAt`.
- A proactive output chooses one body or a durable inbox; it never fans out.

## Resolved contradictions

### Handoff

The existing `handoff` wire/API name remains for compatibility, but its purpose
is `thread_continuation`. It carries an intentional compact summary when Sadeq
wants to continue a subject elsewhere. It does not move Kai, turn off the source
body, or grant the destination access to the source transcript.

### Shared `in_person` room

Desktop and the full mobile/core app are two windows onto one `in_person`
conversation room. A persisted reply is therefore visible in both by design.
Messenger remains its own `messenger` room and must never mirror raw turns into
`in_person`. In routing terms, desktop and core-mobile are two bodies on one
lane; Messenger is a separate lane.

### Embodiment concurrency

VR and AR each keep an ordered per-body guard instead of a global `_busy` flag.
Kai Core admits at most two distinct conversation lanes and never admits two
turns from the same conversation concurrently.

## Shared-state mutation audit

- Mood, personality, affinity: atomic RTDB increments; bounded reads self-heal.
- Awakenings: atomic increment; boot no longer rewrites the whole self model.
- Goals: append-only creation and per-goal updates; safe across bodies.
- Memories: append-only distinct keys; safe unless a later compactor rewrites a
  shared aggregate.
- Dream, purpose, identity revision: must be serialized as self-model revision
  work before multiple technical lanes can invoke them simultaneously.
- User model: distinct keys are safe. Competing writes to the same normalized
  key must surface a conflict rather than silently choosing a winner.
- Same-path filesystem writes: require a per-path lease.

## Event envelope

The minimum contract lives in `kai_body_event.dart`: `eventId`, `type`, device
`occurredAt`, Core `receivedAt`, distinct `bodyId` and `deviceId`, authoritative
`surface`, `sessionId`, `conversationId`, `laneId`, `correlationId`, optional
`causationId`, and `payload`.

Presence is pull-based context. Kai may query which bodies are active when it is
relevant; the active-body list is not injected into every prompt.

## Reverse attention routing

- Direct reply: originating body only; if absent, store for later.
- Proactive friend message: one foreground/recent friend-capable body.
- Completed work: origin first, then one work-capable body, otherwise inbox.
- Contradictory same-task instructions are never auto-resolved. Serialize the
  task and ask Sadeq.

## Open product decision

`fastChat` currently writes `sharedLife`, and `fastChat` is the router fallback.
Recommendation: do not make a routing confidence fallback decide memory scope.
Keep the current behavior until the two-surface walkthrough, then move scope
selection to an explicit memory-worthiness classifier plus surface policy.
