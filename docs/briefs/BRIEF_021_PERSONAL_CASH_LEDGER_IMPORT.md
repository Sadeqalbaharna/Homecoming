# Brief 021 — Personal Cash ledger and statement intake

Owner: Homecoming implementation
Reviewer: Codex PM
Status: ACCEPTED LOCALLY; LIVE DESKTOP HANDOVER UNVERIFIED

## Goal

Personal Cash becomes a useful local cash-planning ledger: expected receivables
are date-bound, historical months contain editable transaction breakdowns, and
bank or card statements can be reviewed and imported without surrendering
privacy or silently changing totals.

## In scope

- A typed receivable record with source, amount, expected date, and received state.
- A typed historical transaction with date, source, description, category,
  subcategory, income/expense direction, amount, and optional import identity.
- Migration of summary-only historical months into honest editable placeholder
  transactions without changing their totals.
- Local CSV, TXT, and text-based PDF extraction into an editable selection queue.
- Multiline and column-ordered account-statement parsing with bank-reference
  identity so genuine repeated purchases are preserved.
- Deterministic duplicate suppression and explicit review before import.
- Overview, Receivables, History, and Statement import views in the existing
  Personal Cash editor.
- A persistent category library that can be extended during review and is
  immediately selectable from statement and historical transaction rows.
- A local account-identity library with a user-defined display name, owner
  (`Mine`, `Wife`, `Company`, or `Other`), and reusable matching aliases.
- Deterministic statement recognition where the longest matching alias wins;
  recognised sources remain editable before and after import.
- A combined Savings & investments asset block whose entries retain a typed
  savings/investment distinction and roll up without affecting cash-flow proof.

## Out of scope

- Bank logins, APIs, cloud upload, Firebase, OCR, credentials, automatic
  categorisation by a model, or changing the live budget from imported history.
- Treating a parsed candidate as verified financial truth before user review.
- Inferring account ownership without a user-authored matching alias, or using
  account recognition to categorise, merge, or exclude transactions.

## Invariants

- All data remains in the existing local desktop snapshot.
- Original statement bytes/text are not persisted.
- Import never changes the live budget, debts, holdings, or receivables.
- Existing version 1/2 snapshots migrate without losing totals.
- Duplicate imported rows cannot be added twice.
- Account recognition only labels transaction source; it never changes amount,
  direction, category, month totals, or ownership of money.

## Pass criteria

- Receivables round-trip and remain editable.
- Historical totals derive from their editable transaction rows.
- Legacy history migrates with identical income, spending, and cash flow.
- Common CSV and statement-text formats produce deterministic review candidates.
- The supplied July account statement reconciles all 265 rows and matches its
  printed BD 5,940.395 debit and BD 5,959.347 credit totals.
- An import requires explicit selected-row confirmation and suppresses duplicates.
- Every extracted field is editable and added categories survive local reload.
- Named accounts, owner labels, and aliases survive local reload; filename or
  statement-text aliases select the most specific recognised account, while
  unmatched statements retain their original source label.
- Savings and investments round-trip separately and share an honest asset total.
- Focused model/parser/widget tests and the Windows Release build pass.

## Failure and rollback

Changes remain limited to this brief, the Personal Cash widget/model, its local
parser, and focused tests. The prior version 2 decoder remains supported. A
failed parse stores nothing and leaves the selected file untouched.

## Local acceptance evidence

- 2026-08-13: focused Personal Cash and shared widget suite PASS, 29/29.
- Focused analyzer PASS with no issues.
- Isolated Windows Release build PASS at `build-cash-ledger`; `data/app.so`
  SHA-256 `764DBCC835228A8863A1A30D748EB7A3F285F189FCAAFE872FBFBDCE98C033CB`.
- Named account persistence, owner validation, longest-alias recognition, unsafe
  short-alias refusal, and account editor layout are covered deterministically.
- Live Desktop display remains UNVERIFIED; no running Kai process was changed.

## Stop and report

Report files, behavior, exact tests, build/runtime evidence, unsupported formats,
and rollback state. Do not add bank connectivity or cloud storage.
