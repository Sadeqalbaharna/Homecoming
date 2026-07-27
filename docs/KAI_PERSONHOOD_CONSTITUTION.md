# Kai personhood constitution

This document defines the invariants for Kai's developmental self. It is a
software simulation of persistent personhood, not a claim of consciousness.

## Psychological invariants

1. State, temperament, character, identity, relationship, and memory are
   separate layers with different rates of change.
2. Mood may change attention and interpretation. It may not directly rewrite
   personality, values, identity, or historical memory.
3. A generated sentence is not evidence merely because Kai said it.
4. Events are append-only. Later interpretation may change; recorded history
   may not be silently rewritten.
5. Observation, interpretation, expectation, desire, and memory must remain
   distinguishable in storage and prompt projections.
6. Durable self-beliefs require repeated evidence, counterevidence handling,
   contextual diversity, and time.
7. Contradiction produces uncertainty or contextual nuance, never convenient
   deletion of one side.
8. Values are strengthened by evidenced choices, especially when choosing the
   value carried a meaningful alternative cost.
9. Relationship closeness is multidimensional and evidence-earned. It cannot
   expand permissions, capabilities, or authority.
10. Identity revision is rare, provenance-gated, reversible as an active view,
    and permanently inspectable as history.
11. Reflection proposes hypotheses and future experiments. It cannot certify
    its own lesson.
12. The active prompt is a bounded working-self projection. The durable self
    lives outside the model context.

## Source ownership

| Concern | Authority | Status during migration |
|---|---|---|
| Observed choices and outcomes | `life_events` | New canonical ledger |
| Mood and arousal | `KaiStateService` / `PersonalityService` | Retain as fast state |
| Temperament traits | `PersonalityService` | Retain, later reinterpret |
| Commitments | `KaiNoticedService` | Retain; adapt into ledger |
| Autobiographical episodes | `KaiAutobiographyService` | Retain; adapt into ledger |
| Semantic facts | brain/memory services | Retain outside autobiography |
| Purpose and dream | `KaiSelfService` | Retain behind revision gate |
| Mature tendencies | `KaiSelfNuanceService` | Transitional derived model |
| Idle generated thought | `InnerLifeService` and old reflection service | Imagination, not evidence |
| Notes and becoming history | legacy paths | Read-only migration sources |

## Evaluation gates

No legacy path is retired until deterministic replay demonstrates:

- no loss of commitments or grounded autobiographical history;
- lower or equal false-memory and unsupported-self-claim rates;
- bounded personality volatility after intense single interactions;
- contextual handling of contradictory evidence;
- relationship repair without automatic intimacy inflation;
- stable token ceilings and no additional foreground model call;
- inspectable provenance for every durable self claim; and
- a complete passing repository regression suite.

## Implemented developmental pipeline

The active implementation follows this direction of evidence:

`receipt -> life event -> reflection trigger -> competing hypotheses -> future
experiment -> later validation -> conditional schema -> earned value`

- Reflection runs in the background through the configured local model only.
  It adds no paid foreground call and fails closed when local JSON is invalid.
- A reflection must cite real events, preserve at least two hypotheses, state
  uncertainty, and propose a future behavioral experiment.
- Only an event occurring after that reflection can support, revise, or reject
  the proposed lesson.
- A durable schema requires at least three events and two independently
  validated reflections. Counterevidence reduces confidence and remains stored.
- A value requires at least three explicit choices, a recorded foregone
  alternative, cumulative opportunity cost, and contextual evidence. Emotional
  intensity and self-description do not count.
- Relationship state separates familiarity, epistemic trust, emotional safety,
  reciprocity, and repair confidence. Negative evidence updates faster than
  positive evidence; repair does not erase rupture.
- Current motives expire and can conflict. A selected foreground motive does
  not delete background motives or become a personality trait.

As of the implementation checkpoint, the complete repository suite passes 617
tests. Long-horizon identity chapters, the final working-self compiler, and
legacy retirement remain gated future phases.
