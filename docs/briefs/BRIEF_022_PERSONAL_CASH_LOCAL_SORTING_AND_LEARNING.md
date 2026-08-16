# Brief 022 — Personal Cash local sorting and learned categorisation

Owner: Homecoming implementation
Reviewer: Codex PM
Status: ACCEPTED LOCALLY; LIVE DESKTOP REFRESH UNVERIFIED

## Goal

Personal Cash turns reviewed history into reusable local knowledge: transactions
can be sorted and isolated for cleanup, explicit category assignments teach
deterministic merchant rules for future statements, and every month ends with a
readable category/account summary.

## In scope

- Sort history rows by date, amount, merchant, category, or account.
- Isolate uncategorised rows without deleting or hiding them from totals.
- Derive a stable merchant key from common statement boilerplate.
- Save an explicit category/subcategory rule when the user assigns a merchant.
- Apply exact merchant-key rules to future statement candidates and optionally
  to existing uncategorised history.
- Provide a separate Smart Category Assign action that previews a conservative
  batch using learned rules first and explicit merchant wording second, then
  requires confirmation before changing existing history.
- List and delete learned rules.
- Summarise monthly spending by category, net movement by account, and the
  remaining uncategorised count.
- Let the user approve a reviewed transaction with a checkbox, removing it from
  the working list without deleting it from history, totals, or summaries.
- Provide a Show approved toggle so approvals are reversible and auditable.
- Auto-approve rows categorised by an explicit learned-rule application or a
  confirmed Smart Category Assign batch; unmatched rows remain unapproved.
- Display live portfolio-wide and per-month pending-approval counts, including
  an explicit All approved state when the queue reaches zero.
- When one merchant is categorised, offer to apply that category to every
  matching pending row and approve the group in one confirmation.
- Provide Approve categorised to clear every already-categorised pending row
  while leaving uncategorised work visible.

## Out of scope

- AI/model inference, fuzzy merchant matching, cloud learning, bank access, or
  automatic changes to amount, direction, source account, date, or totals.
- Treating an automatic suggestion as more authoritative than user review.

## Invariants

- Learning is local, deterministic, visible, and reversible.
- Rules only fill `Uncategorised` transactions; they never overwrite a reviewed
  category.
- Ambiguous descriptions remain `Uncategorised`; smart assignment cannot infer
  a category merely because a transaction is a generic POS purchase.
- Sorting and filtering are presentation only and never affect stored order,
  duplicate fingerprints, or monthly totals.
- Approval is review state, never deletion; approved transactions continue to
  contribute to all financial calculations.
- Automatic approval is limited to the exact rows the batch action categorises
  and is reversible through Show approved.
- Merchant batching requires the same normalized merchant key and transaction
  direction, and never overwrites an existing reviewed category.
- Month summaries derive from transaction rows rather than a second ledger.

## Pass criteria

- A reviewed merchant assignment persists as a reusable rule.
- The same normalized merchant is categorized on a future import.
- An existing reviewed category cannot be overwritten by a rule.
- Learned rules can be inspected and deleted.
- Smart assignment reports its proposed category counts before confirmation.
- Every supported sort is deterministic and preserves all rows.
- Monthly category/account summaries reconcile to their source transactions.
- Approved rows disappear from the default review queue, reappear under Show
  approved, can be unapproved, and remain included in totals.
- Pending counts derive from durable transaction approval state and update after
  manual approval, unapproval, learned-rule application, and smart assignment.
- One group decision can categorise and approve all matching pending rows while
  preserving totals; Approve categorised never approves uncategorised rows.
- Focused analyzer, finance/widget regression suite, and isolated Windows
  Release build pass.

## Failure and rollback

The schema decoder retains versions 1–5 and defaults missing rules to empty.
Removing this brief's `categoryRules` field and UI controls returns to manual
categorisation without changing historical transaction values.

## Local acceptance evidence

- Focused analyzer PASS with no issues.
- Personal Cash plus shared widget regressions PASS, 38/38.
- Isolated Windows Release build PASS at `build-cash-ledger`; `data/app.so`
  SHA-256 `B0DD083F7E3901021656410103DEB098B3B604C7043C52800257DEA0C2C9798C`.
- Live Desktop display remains UNVERIFIED; no running Kai process was changed.

## Stop and report

Report files, tests, artifact hash, proof state, remaining risks, and whether a
live Desktop refresh is still required. Do not restart the running app without
separate authority.
