# Checkpoint and Sequencing

Fourth and shortest of the series. No new technical findings — the previous
three carry those. This one covers where the work now lives, and one
recommended change to the order of the remaining days.

The reorder is **a recommendation from review, not an instruction.** Sadeq owns
the sequence.

---

## 1. The work is committed

Days 1–4 had accumulated across several sessions in a working tree with no
checkpoint, on top of changes that were already uncommitted before any of this
started. That is now saved on `codex/kai-self-context`:

```
3c2e6ec  feat(kai): one Kai across desktop, mobile, Messenger, AR and VR   124 files
78ac5d7  docs: briefs, product specs, and avatar pose assets                 36 files
e7b7e78  ← previous head
```

Two commits, not four. A split by concern was the intent and it wasn't honest to
do: `ai_service.dart` carries pre-existing changes, Day 1–4 work, and review
fixes interleaved in a single file, and `git add -p` isn't available in this
environment. Splitting by filename would have produced intermediate commits that
don't compile — bisectable in appearance only. Docs are separated because they
cannot affect behaviour; the code went in together with a message explaining the
strands.

**Verified after committing:** 721 tests pass, `lib/secrets.dart` remains
untracked, working tree otherwise clean.

**Held back deliberately:** `tavern_console/` contains a Firebase web key that
is not yet anywhere in the repo. That key type is public by design and two
others are already committed in `firebase_options.dart` and
`google-services.json`, so including it is almost certainly fine — but git
history is permanent, so it is Sadeq's call rather than a reviewer's. Do not
commit it on his behalf.

---

## 2. Recommendation: run a thin end-to-end slice before Day 5

**The plan's risk profile is upside down.** The proof is scheduled last, which
means Days 1–4 are four stacked layers of assumptions that have never met a real
session. Everything passes in tests. Nothing has been walked through by a person.

**Most of Day 7 does not need Day 5 or Day 6.** Mapped against the scenario as
written:

| Step | Runnable now? |
|---|---|
| 1. Talk personally on Messenger | ✅ |
| 2. Enter the VR Shack | ✅ |
| 3. Kai remembers the relationship context | ✅ |
| 4. Goggles off; a coding request is declined naturally | ✅ |
| 5. Goggles turn on | ✅ |
| 6. Collaborate using only Shack tools | ❌ Day 5 |
| 7. A creative decision is saved | ⚠️ partial — `scopeForTurn` writes it; no artifact yet |
| 8. Leave VR, return to Messenger | ✅ |
| 9. Kai remembers the shared event without technical leakage | ✅ |
| 10. Disconnect a device, verify recovery | ❌ Day 6 |

Seven of ten steps are runnable today.

**Step 9 is the one that most needs it.** That is the VR-stranding fix from
`SCOPED_MEMORY_BRIEF.md` §2. Its tests prove the *scope logic* is correct —
write scope composed with read policy. They do **not** prove the round trip: a
real Firebase write, from a real Unity session, read back through a real
Messenger turn. Those are different claims and only one of them is currently
verified. A green test for step 9 and a working step 9 are not the same thing.

**What the run costs:** roughly a day. **What it de-risks:** four.

If it works, Days 5 and 6 get built on confirmed ground. If it doesn't, the
fault is found now rather than after two more layers are stacked on it — and
the failure will be somewhere in the four days that have never been exercised
end to end, which is exactly where an unexercised assumption would be.

Worth writing down whatever the run reveals, including "it just worked". A
scenario that has been walked once is a different artifact from a scenario that
has only been specified.

---

## 3. Then the server-side boundary, then Day 5

Unchanged from `CONTINUITY_CONTRACT_BRIEF.md` §4, and now more pressing because
the escalation there was live rather than theoretical.

Before Day 5's world capabilities:

- the broker derives the surface from the **authenticated channel**, not the
  request body
- `KaiCapabilityBroker.forContext(null)` inverts from full-capability to
  fail-closed — correct for migration, dangerous the moment it is remote
- the embodiment token stops defaulting to empty

Day 5 adds a whole new capability class through the same parser that had to be
clamped last week. Landing the boundary first means world tools are built on it
rather than retrofitted onto it later, when there are more callers assuming the
payload can be trusted.

**Suggested order:** thin end-to-end run → server-side boundary → Day 5 →
Day 6 → full Day 7.

---

## 4. Open, and not to be closed unilaterally

**The write-classifier default** (`SCOPED_MEMORY_BRIEF.md` §3). Core `fastChat`
writes `sharedLife`, which every friend surface reads, and `fastChat` is what the
router returns when no keyword matched. Put to Sadeq and deliberately deferred —
the fix makes Messenger thinner, which is a product trade. This has now carried
across three briefs without a decision; that is the correct state, not an
oversight. Leave it.

**79 dead files** — `ARCHIVED_REDUNDANT/` (77 tracked, zero Dart imports, one
analyzer-exclusion reference), `lib/services/engineer/workspace_service.dart`
(zero importers, strict API subset of `CodeWorkspaceService`), and the
`animation_preloader_service.dart` stub. All confirmed dead, all tracked and
therefore recoverable. Deletion was blocked by permissions during review and
needs Sadeq to run it.

**The Day 6 / Day 7 collision** now has a third party: the Firebase restructure,
the promotions tree, and the end-to-end proof all land in the same 48 hours
under the same root. Moving the proof earlier, as recommended above, removes one
of the three.
