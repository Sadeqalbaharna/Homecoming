# Kai self-context architecture

## Invariant

Kai may freely express a present interpretation as uncertain. He may express a
memory, commitment, historical identity, or completed action as fact only when
the current typed `KaiSelfContext` contains a supporting record.

The model proposes and phrases. Deterministic code admits, persists, retrieves,
budgets, and labels durable continuity.

## Ownership

- `KaiLifeEventService` is the canonical append-only experiential ledger.
- `KaiStructuredReflectionService` stores hypotheses and later experiment
  validations; reflection cannot validate itself.
- `KaiSelfSchemaService` stores conditional self-knowledge earned across
  repeated validated reflections.
- `KaiEarnedValueService` derives values only from repeated costly choices.
- `KaiRelationshipModel` derives differentiated relationship state and owns no
  permissions or authority.
- `KaiMotiveField` selects temporary, potentially conflicting motives without
  promoting them into identity.
- `KaiSelfService` remains a legacy authority for identity, values, purpose,
  dream, and temporary focus until the working-self migration is complete.
- `KaiNoticedService` remains authoritative for observations and now also stores
  explicit commitments. Existing observation rows remain compatible.
- `KaiAutobiographyService` stores Kai-subject episodes: a choice, its observed
  outcome, its meaning, and evidence identifiers.
- `KaiSelfContext` is an immutable read projection. It owns no persistence.
- `KaiContextBlock` retrieves the projection and applies route-specific budgets.
- `ToolPolicyService` remains separate and cannot be edited through selfhood.

## Mutation rules

Dream and purpose are no longer written directly. A `SelfRevisionProposal` must:

1. differ from the current value;
2. contain a non-trivial rationale;
3. name the concrete triggering experience;
4. carry a trusted tool-call receipt; and
5. pass the deterministic admission function.

Admitted revisions append a receipt under
`kai/{persona}/self_revision_receipts`. Refused revisions change nothing.

## Commitments

`NoticedKind` distinguishes observations, promises, intentions, open questions,
and responsibilities. A commitment is considered Kai-authored only when it has
an author receipt minted by the trusted `make_commitment` executor path. A
transcript or stored Boolean claiming `authoredByKai: true` is insufficient.

Resolution archives the record through the existing noticed archive path rather
than erasing the evidence that it existed.

## Autobiography

Autobiographical episodes are deliberately narrower than the knowledge graph.
The graph stores facts about Sadeq, projects, and the world. Autobiography stores
receipt-backed choices Kai made and outcomes that followed.

The first live episode sources are:

- admitted dream revisions;
- admitted purpose revisions; and
- explicit commitments.

Fast chat retrieves zero episodes. Tool, coding, emotional, and contemplative
routes retrieve progressively larger but capped sets, all inside the existing
self-context token ceiling.

## Token and trace receipts

Self-context rendering produces `SelfContextRenderReceipt` with:

- configured token budget;
- estimated tokens and rendered characters;
- truncation status; and
- provenance class for identity, values, purpose, and dream.

`AIService` attaches this receipt to the brain trace alongside the existing
prompt-component measurements.

Ordinary turns use the `compact-v1` continuity register rather than replaying
the full identity narrative. It contains stable values, current focus,
receipt-backed commitments, recent earned consequences, and an epistemic
boundary. Short record handles point back to the durable source without copying
that source into every prompt. The rich renderer remains available for explicit
self-inspection.

Route ceilings are 120 approximate tokens for fast chat, 160 for tool turns,
180 for coding, 320 for emotional turns, and 450 for contemplation. These are
ceilings, not targets; whole-line fitting may use less.

## Situation-aware selection and slow nuance

The active register is selected deterministically from a larger candidate set.
Topic overlap carries the most weight, followed by route fit, current mood,
personality posture, evidence kind, and recency. Mood changes relevance only; it
cannot create a durable trait or historical claim. Semantic memory remains a
separate factual source and does not silently become autobiography.

After a turn, only personality movement that already survived
`PersonalityService` resistance is counted toward self-nuance. A tendency stays
hidden until it appears on at least three turns. Opposing mature tendencies are
reconciled: a clear evidence lead wins, while balanced evidence becomes an
explicit context-dependent tension. Nuance not observed for 180 days leaves the
active prompt but remains in storage. Mature tendencies render as bounded `N:`
handles; commitments use `C:` and grounded consequences use `E:`.

## Known limitations

- Tool receipt prefixes provide an application trust boundary, not cryptographic
  integrity. Firebase rules or a trusted backend must prevent arbitrary database
  writers from forging complete records.
- Revision writes and receipt appends are not yet one atomic transaction.
- Autobiography retrieval is currently recent-and-route-capped, not semantic.
- The renderer estimates tokens from characters. Provider-aware token accounting
  can replace this without changing the contract.
- Legacy purpose and dream values remain readable but are explicitly labeled as
  legacy wording until a gated revision supersedes them.
- Mature schemas, earned values, relationships, and motives are not yet compiled
  into the route-bounded working-self register.
- Identity chapters and lifespan consolidation are not implemented yet.
