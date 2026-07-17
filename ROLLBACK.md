# ROLLBACK — save points for the night of 2026-07-16/17

## Why this file exists instead of git

The obvious save point is `git commit`. **It is a trap here, and it looks safe.**

Measured tonight:

```
mount says:  16273 bytes   (lib/services/ai/usage_tracking_service.dart)
HEAD blob:   16273 bytes
real file:   larger — the mount is serving a size frozen around commit time
```

The sandbox mount freezes a file's cached size the first time bash touches it
(§4.1 — full mechanism in `LEVEL_5.md`). So a `git add` run from the sandbox
**reads the truncated working tree and stages the truncation**, permanently
destroying the tail of 31 source files inside a commit that looks clean. Git is
not lying; it is faithfully committing what it was handed. Same disease as
everything else this week.

**The real checkpoint is `git add -A && git commit` run from WINDOWS.** Do that
first thing. Nothing here replaces it.

Until then, this file is the save point: every edit recorded precisely enough to
reverse by hand, newest last.

## How to use it

Each entry has the file, the exact `old_string` that was there before, and the
`new_string` that replaced it. **To roll back: apply them in reverse order,
swapping old and new.** Entries are self-contained — you can revert one without
reverting the others unless a dependency is noted.

New FILES are listed under CREATED. Rolling those back means deleting them —
check the `unwires` note first, because deleting a file something imports will
break the build.

---

## CHECKPOINT 0 — last known-good

**Commit:** the one made earlier this session ("okay, we are committed").
Everything below is uncommitted work on top of it.

**State at checkpoint 0:** `flutter analyze` → 166 issues, **0 errors**.
That is the number to get back to.

---

## BATCH A — the efficiency pass (verified: analyze clean at the time)

Already reported and analyzed on Windows at 166 issues / 0 errors. Listed for
completeness; low rollback risk.

- `ai_service.dart` — parallel setup (`historyFuture`/`memoryFuture` hoisted
  above the first `await`), curiosity prefetch (`_pendingQuestion`),
  `markQuestionAsked` made unawaited.
- `tavern_status_service.dart`, `tavern_menu_service.dart` — early return on
  `kaiDbUsesRest`.
- `code_workspace_service.dart` — `│` gutter + header note.
- `tool_policy_service.dart` — the four work-stack policies.

## BATCH B — UNVERIFIED. Nothing below has ever been compiled.

**This is the batch to suspect if the build breaks.** In rough dependency order —
revert from the bottom up.

### CREATED (rollback = delete)
| file | unwires |
|---|---|
| `lib/services/core/kai_noticed_service.dart` | remove the import + `promptBlock` call in `kai_context_block.dart`, and the `note_noticed` / `noticed_done` cases in `tool_executor_service.dart` |
| `test/tools_for_route_test.dart` | none — pure test |
| `test/run_tests_tool_test.dart` | none — pure test |
| `test/salience_test.dart` | none — pure test |
| `test/noticed_test.dart` | none — pure test |
| `LEVEL_5.md`, `ROLLBACK.md` | none — docs |

### EDITED

**`edit_gate.dart`**
- Added `renderDiffForKai(...)` above `_computeDiff`. Rollback: delete the function.
- `proposeWrite` / `proposeEdit` last lines changed from `return ws.writeRaw(...)`
  to capturing `res` and returning `'$res\n\n${renderDiffForKai(...)}'`.
  **Rollback:** restore `return ws.writeRaw(rel, content);` and
  `return ws.writeRaw(rel, updated);`
- Added `proposeEditRange(...)`. Rollback: delete the method AND the RANGE branch
  in `tool_executor_service.dart`'s `edit_file` case.
- `_isSafeCommand`: `return sub == 'analyze';` → `return sub == 'analyze' || sub == 'test';`
  **Rollback:** restore the original single-condition line.

**`tool_executor_service.dart`**
- `_mutatingTools` const added next to `_engineeringTools`. Rollback: delete it
  and remove `..addAll(_mutatingTools)` from the `contemplate` case.
- `run_tests` added to `_engineeringTools`. Rollback: remove the entry.
- `_runTests(...)` method added above `_invokeAndroid`. Rollback: delete it and
  the `case 'run_tests':` dispatch.
- `edit_file` schema rewritten (range mode) + `note_noticed` / `noticed_done` /
  `run_tests` schemas added. **Rollback:** restore the original edit_file schema:
  ```
  'required': ['path', 'old_string', 'new_string']
  ```
  and delete the three new schema blocks.
- `edit_file` dispatch rewritten. **Rollback:** restore
  ```dart
  case 'edit_file':
    return await EditGate.instance.proposeEdit(
      (args['path'] as String?)?.trim() ?? '',
      args['old_string'] as String? ?? '',
      args['new_string'] as String? ?? '',
    );
  ```
- `job_progress` dispatch now also calls `KaiNoticedService.add`. Rollback:
  restore the plain `await KaiJobService.instance.progress(...)` + `return 'Noted — next turn picks up from there.';`
- `job_done` now loops `job?.noticed` into `KaiNoticedService` before `finish()`.
  Rollback: delete the loop.

**`tool_policy_service.dart`**
- `emptyOkArgs` field added to `ToolPolicy` + used in the `missing` check.
  **Rollback:** remove the field, the constructor param, and restore
  ```dart
  if (value is String && value.trim().isEmpty) return true;
  ```
- `edit_file` policy: `requiredArgs` `{'path','old_string','new_string'}` →
  `{'path','new_string'}`, `emptyOkArgs: {'new_string'}` added.
  **Rollback:** restore the original three required args, drop emptyOkArgs.
- `run_tests`, `note_noticed`, `noticed_done` policies added. Rollback: delete.

**`ai_service.dart`**
- `_toolsUsedThisTurn` field added; `.clear()` at the top of `sendMessage`;
  `.add(fnName)` in the tool loop. Rollback: delete all three.
- Tool messages now carry `'name': fnName`. **Rollback:** delete that line —
  but note `_trimOldToolResults` reads it, so revert the trim together.
- `_trimOldToolResults` gained `keepMaterial` + the `materialTools` branch.
  **Rollback:** restore
  ```dart
  final cutoff = toolIdx.length > keepWhole ? toolIdx[toolIdx.length - keepWhole] : 0;
  for (final i in toolIdx) { ... if (i >= cutoff) { ... } }
  ```
  and drop `keepMaterial` from both signatures.
- `extractAndMerge` call now passes `toolsUsed` + `userCorrected`, with a
  snapshot taken before the async gap. Rollback: drop both args and the snapshot.

**`brain_extraction_service.dart`**  ← **HIGHEST RISK. Revert this first.**
- Added `import 'package:flutter/foundation.dart' show visibleForTesting;`
- Added `_depthForChange(...)`, `_decide(...)`, `salienceForTesting(...)`.
- `extractAndMerge` gained `toolsUsed` / `userCorrected` params.
- The trivial-filter + salience-gate block was replaced by a call to `_decide`.
  **Rollback:** restore
  ```dart
  if (_isTrivialExchange(userMessage, aiReply)) {
    print('🧠 [Brain] Skipped trivial exchange: "..."');
    return;
  }
  final depth = _depthFor(eventType, eventIntensity);
  if (depth == _Depth.skip) {
    print('🧠 [Brain] Skipped low-salience exchange (neutral, intensity $eventIntensity)');
    return;
  }
  ```
  …and delete the three new functions. This restores the old behaviour exactly:
  **memory formation gated on emotion alone, which recorded 0 of 5 turns.**

**`kai_context_block.dart`**
- Imports added: `code_workspace_service.dart`, `kai_noticed_service.dart`.
- `liveState` gained two `Future.wait` entries (workspace block, noticed block).
  Rollback: delete both entries and the imports.
- `engineerDirective` step 3 rewritten (range mode + diffs), step 5 PROVE added,
  old step 5 renumbered to 6. Rollback: restore the original 5-step text.

**`kai_capabilities.dart`**
- Added the `PROVE IT — run_tests` line and extended the edit line.
  Rollback: restore the two original strings.

**`test/tool_result_trim_test.dart`**
- `tool()` gained a `name` param defaulting to `'self_check'`; `read()` helper
  added; a new group at the end. Rollback: restore the original `tool()` and
  delete the new group.

**`test/tool_policy_service_test.dart`**
- New group prepended before `group('ToolPolicyService', ...)`. Rollback: delete it.

**`lib/screens/kai_desktop_shell.dart`** — the mojibake repair.
- 165 mangled em-dashes fixed + `âš™` → `⚙` at ~line 1341. Written through bash
  (safe: bash had a fresh cached size for that file).
- **Rollback:** `git checkout -- lib/screens/kai_desktop_shell.dart` **from
  Windows** — but that also reverts Kai's fossil removal from the same session.
  Verified intact afterwards: 1797 lines, class closes correctly, CRLF count
  unchanged at 1797.

---

## BATCH C — the pure-logic extraction (PARTIALLY VERIFIED — read this)

This batch is different from B. **The logic in it has actually been executed and
proven**, with a real Dart compiler, in the sandbox. What has *not* been verified
is the wiring — the delegation edits into `brain_extraction_service.dart`, which
lives behind the stale mount.

So: if the morning build breaks, suspect the **wiring**, not the logic.

### The insight that produced this batch

`lib/tools/replay.dart` turned out to be runnable in the sandbox for exactly one
reason: **it has zero imports.** Meanwhile `_decide` — the gate deciding what Kai
remembers, the single most important function in the level-5 path — sat behind
`dio`, `firebase` and `flutter`, in a file the mount serves truncated. It could
not be executed, so it never had been. It was rewritten on five traces by someone
who could not run it.

**Pure decisions belong in pure files.** Not for tidiness — because a file with
no imports can be proven in one second by anything, and that is the property that
makes a claim falsifiable instead of well-argued.

### CREATED (rollback = delete)
| file | verified? | unwires |
|---|---|---|
| `lib/logic/salience.dart` | **YES — 31 assertions, all pass** | see wiring below |
| `lib/tools/replay.dart` | **YES — 21 assertions, all pass** | none — nothing imports it yet |
| `lib/services/core/trace_store_service.dart` | no | remove the import + `TraceStoreService.instance.record(...)` line in `brain_debug_service.dart` |

What was actually proven, run against the real trace shapes:

- `salience.dart` — "sure go ahead" (neutral/4) + a 20-iteration refactor → deep.
  "chat is still not starting…" (neutral/3) → deep. "do it"/"okay"/"sure" + real
  work → deep, but bare → skip. Corrections → deep with no tools and a flat mood.
  The −100..+100 cliff at exactly 8. Work never downgrades a felt moment.
- `replay.dart` — `timeToFirstToken` computes **7056ms** from the real 16:09
  trace timestamps. Overclaim detection, wasted-tool counting (9 gutter failures),
  `ratio()` never emitting a bare percentage, and a throwing decision being
  skipped rather than counted as a change.

### EDITED

**`brain_debug_service.dart`**
- Added `import 'core/trace_store_service.dart';`
- In `completeTrace`, added `TraceStoreService.instance.record(_currentTrace!);`
  above the `_history.add(...)`.
  **Rollback:** delete both lines. `_history` keeps its ten in RAM exactly as
  before — which is to say, the dataset goes back in the bin.

**`brain_extraction_service.dart`**  ← **the wiring. Suspect this first.**
- Added `import '../../logic/salience.dart' as sal;`
- `enum _Depth { skip, shallow, deep }` → `typedef _Depth = sal.SalienceDepth;`
- `_decide`, `_depthFor`, `_depthForChange` are now one-line delegates to
  `sal.salienceDepth` / `sal.feltDepth` / `sal.changeDepth`.
- **DELETED**: the bodies of `_depthForChange` and `_depthFor`, and the whole
  30-line `_isTrivialExchange` (a comment marks where it was).

  **Rollback:** restore `enum _Depth { skip, shallow, deep }`, restore the three
  function bodies and `_isTrivialExchange` from `lib/logic/salience.dart` —
  the code is identical, only the enum name and the `String eventType` vs
  `EmotionalEventType` boundary differ. Then drop the import.

  **Known-good call sites that must still resolve** (checked against real disk,
  not the mount): `_Depth.skip` at ~244, `_Depth.deep` at ~472, ~503, ~905,
  ~959, ~1649, and `_Depth depth = _Depth.shallow` as a default parameter
  at ~878. The typedef preserves all of them.

---

## BATCH D — LEVEL 5: the graph cut loose from the chat log

### CREATED
| file | verified? |
|---|---|
| `lib/logic/query_terms.dart` | **logic YES — 29 of 31 assertions passed. See caveat.** |

**The caveat, stated plainly.** 31 assertions ran. 29 passed. The 2 failures were
real and useful: `"sure go ahead"` yielded `{ahead}` — "ahead" was not in the
stopword list, so it would have seeded spreading activation with a preposition
and lit every node containing it. The 271-node problem in miniature, caught by a
test, shipped by the person who wrote the comment about the 271-node problem.

The fix (adding 'ahead' and other fillers to `kStopwords`) is **data, not logic**,
and it was **NOT re-executed** — because copying the file to the sandbox again
returned the pre-edit truncated version. §4.1 bit inside the loop built to escape
§4.1: the mount caches size on FIRST access per path, so a file you cp, then
edit, is frozen at its pre-edit length forever.

What IS confirmed: the file on real disk is syntactically whole (const set closes,
`queryTerms` intact, `worthAsking` at the end, 121 lines) — read via the file
tools, which see real disk.

### EDITED

**`ai_service.dart`** ← **the level-5 change. Suspect this if retrieval breaks.**
- Added `import '../../logic/query_terms.dart';`
- **REMOVED** from inside `if (memoryResult != null && ...)`: the whole
  `if (memoriesUsed.isNotEmpty) { retrievedWords... reinforceNodes...
  spreadActivation... }` block.
- **ADDED**, after the `if/else` and before the `catch`: a `seedTerms =
  queryTerms(text)` block that calls `reinforceNodes` + `spreadActivation`
  **unconditionally**, seeded from Sadeq's message.

  **Rollback:** delete the new block and the import, then restore inside the
  `if`, immediately after `memoriesUsed = ...toList();`:
  ```dart
  if (memoriesUsed.isNotEmpty) {
    final retrievedWords = memoriesUsed
        .expand((s) => s.toLowerCase().split(RegExp(r'\W+')))
        .where((w) => w.length > 3)
        .toSet()
        .toList();
    _brain.reinforceNodes(personaId, retrievedWords)
        .catchError((e) => print('⚠️ [Brain] reinforceNodes error: $e'));
    try {
      final spreadBlock = await _brain.spreadActivation(
          personaId, retrievedWords, currentMood: mood);
      if (spreadBlock.isNotEmpty) {
        memoryContext += '\n\n$spreadBlock';
      }
    } catch (e) {
      print('⚠️ [Brain] spreadActivation error: $e');
    }
  }
  ```
  That restores the old behaviour exactly: **the graph consulted only when a
  transcript search clears 0.28 first — 2 of 5 turns — and 271 nodes reinforced
  every time.**

### How to tell if it WORKED (not just compiled)

The tell is a turn where the transcript finds nothing but the graph still speaks:

```
💭 Using 0 memory contexts (threshold: 0.28)
🕸️ [Brain] Graph answered on: mojibake, encoding
```

Under the old code that pairing was impossible — 0 contexts meant the graph was
never asked. If you never see it, Phase 3 didn't land.

Also watch `reinforced N retrieved nodes`. It was ~271 every turn. It should now
be small and it should CHANGE between turns. If it's still 271, the seed is still
coming from transcripts.

---

## If the build is broken in the morning

1. `flutter analyze` from Windows. Note the error count.
2. If errors are in `brain_extraction_service.dart` → revert BATCH B's entry for
   it first. It is the largest and least verified change.
3. If errors are `undefined_method` on `KaiNoticedService` → the import in
   `kai_context_block.dart` or `tool_executor_service.dart` is missing.
4. If errors mention `_increment`, `validate`, or anything ending mid-word —
   **that is not a real error.** That is §4.1. You are reading a sandbox
   artifact, not your file.
