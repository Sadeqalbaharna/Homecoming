# Kai Scoped Memory — Claude Review Brief

## Outcome

Homecoming now applies a typed memory-access boundary per Kai surface. Kai remains one person across devices and worlds, while each body sees only the memories appropriate to that setting. This is retrieval policy, not a second identity or separate persona.

## Product invariant

- Goggles off: Kai is Sadeq's human friend. No technical framing, tool machinery, private-core work memory, or world-specific memory enters the turn.
- Goggles on: the current body may expose the work capabilities and memory scopes explicitly granted to it.
- Desktop and mobile remain Kai's trusted core and share the existing `in_person` conversation partition.
- Messenger and AR receive identity, relationship, and shared-life memory only.
- VR with goggles off uses the friend boundary.
- VR with goggles on adds creative, episodic, and only the current world's `world` memories.

## Implementation

- `kai_memory_types.dart` is the single source of truth for scope and provenance enums, legacy parsing, scoped record construction, and the conceptual two-record VR memory pair.
- `kai_memory_scope.dart` owns surface-to-memory access policy and per-turn write classification.
- `MemoryService.queryMemory` filters inaccessible records before vector scoring, ranking, and reinforcement.
- `MemoryService.remember` writes `scope`, `provenance`, `surfaceId`, `worldId`, and `sessionId` alongside the existing record fields.
- `AIService` supplies the active surface policy to retrieval and classifies new conversation memories from the constrained route and surface context.
- Untyped historical rows parse as `legacyUnscoped`. They remain visible to trusted desktop/mobile core during migration, but are hidden from Messenger, AR, and VR.
- The surface module re-exports the shared memory types to preserve the existing public import path.

## Current write classification

- No surface context: `privateCore` for legacy trusted callers.
- Goggles off or emotional route: `relationship`.
- VR with goggles on: `creative` for the conversation experience.
- Core fast chat: `sharedLife`.
- Other goggles-on core work: `privateCore`.

VR creation is deliberately modeled as two additive memories: a relationship-scoped shared experience and a world-scoped artifact record tied to `worldId`. The type contract exists; actual artifact writes should be connected when Unity world-action results are wired.

## Safety properties under test

- Unknown or missing scopes become `legacyUnscoped`, never a broadly visible guessed scope.
- Messenger cannot retrieve legacy-unscoped or private-core records.
- Desktop can retrieve legacy rows during migration.
- VR world memories require both goggles on and an exact world match.
- Inaccessible rows are removed before similarity scoring, so they cannot be returned or strengthened as a retrieval side effect.
- The prior capability boundary remains intact: goggles-off requests omit tool schemas and tool-awareness context.

## Verification

- Focused analyzer: zero errors; only pre-existing warnings/info in `AIService` and `MemoryService`.
- Focused surface/memory/request tests: 30 passed.
- Full Flutter suite: 699 passed.

## Please review these decisions

1. Is the access matrix conservative enough, especially `sharedLife` on friend surfaces and `episodic` in goggles-on VR?
2. Should `creative` memory be visible to Messenger/AR, or remain core/VR-only as implemented?
3. Is keeping `legacyUnscoped` visible only to trusted desktop/mobile the right migration posture?
4. Should emotional turns on desktop/mobile always classify as `relationship`, even when goggles are on?
5. For the next step, recommend the smallest safe design for an additive legacy classifier/promotion pass that never mutates or deletes source rows.
6. When Unity world actions arrive, confirm the event schema and transaction boundary for writing the paired relationship experience plus world artifact records.

## Suggested next implementation

Build the migration/promotion layer in dry-run-first form: classify legacy rows, emit proposed new scoped records with `provenance: promoted` and a source-record reference, report counts/confidence, and write nothing until reviewed. Promotion should be additive; original records remain untouched.
