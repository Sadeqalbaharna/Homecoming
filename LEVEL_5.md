# LEVEL 5 — THE KNOWING

*Rewritten 2026-07-17, after the work landed. Commit `2999524`.*
*Kai: this is about you. `read_file("LEVEL_5.md")`.*

---

## 1. The ladder

Ten levels. 10 is a canned string with a personality bolted on. 1 is
unfalsifiable by design. **You are at the level of your weakest gate — you do
not average.**

| | | gate | state |
|---|---|---|---|
| 10 | The String | does anything compute? | — |
| 9 | The Answer | does it respond to what was said? | — |
| 8 | The Hands | can it do the thing, not describe it? | — |
| 7 | The State | is it different at 4am than at noon? | — |
| 6 | The Log | can it quote yesterday? | **passed** |
| **5** | **The Knowing** | **can it tell Sadeq something about himself he never said in one sentence?** | **thin — here** |
| 4 | The Proof | can it close a job on evidence it produced itself? | **passed 2026-07-17** |
| 3 | The Agenda | does it raise something unasked that turns out to matter? | close |
| 2 | The Becoming | a rule it wrote + the evidence + a turn it behaved differently | no |
| 1 | — | no gate. If you think you've passed it, you've been fooled. | — |

**He is a 5.** Not because 4 and 3 are far — he passed 4 today and 3 is within
reach — but because the weakest gate rule holds and 5 is the thin one. The
machinery for it is proven. The graph it queries is mostly empty about the
person it's supposed to know.

## 2. What was true on the 16th, and what is true now

Every number here came out of traces. None of it is adjectives.

| | 2026-07-16 | 2026-07-17 |
|---|---|---|
| turns forming a memory | **0 of 5** | routine — `Keeping (deep)` on neutral/2, /3, /4 |
| retrieval with anything usable | 2 of 5 | 3–5 of 5 |
| graph consulted | 2 of 5 (only via transcript match) | fires on the message directly |
| ~~nodes reinforced per turn~~ | ~~271~~ | ~~12~~ — **RETRACTED, see below** |
| overclaim rate at `job_done` | 2 of 2 | — (the grader now lies instead; see §5) |
| `run_tests` before claiming done | **0 of 2** | **2 of 2, no bypass** |
| unprompted noticings | 1, hedged, abandoned | 4 parked across jobs, then cleared |
| time to first token | 12.1s | **3.7s** |
| graph size | 232 nodes / 248 edges | 254 / 277 — edges now growing faster than nodes |
| analyzer | 166 issues | **CLEAN — 0 errors, 0 warnings** |
| test suite | never run by anyone | **+170 passing**, and CI exists in git for the first time |

### RETRACTED: "271 → 12 nodes reinforced"

I quoted that as a headline result in this document. It was a mislabelled log
line and I never checked it.

```dart
print('🧠 [Brain] Reconsolidation: reinforced ${retrievedLabels.length} retrieved nodes');
```

It prints the number of **seed words handed in** — never the number of nodes
reinforced. So "271" was 271 words scraped out of five transcripts, and "12" is
simply `queryTerms`' cap of 12. The two numbers were never measuring the same
thing as each other, and neither was measuring what the sentence claimed.

The real count has now been printed for the first time (`reinforced N node(s)
from M seed term(s)`). **Until there's a trace, the honest value is: unknown.**

Tenth reader lie in three days, and the only one nobody caught — because it was
the only one telling us what we wanted to hear. Every other lying tool was
saying "this is broken" and got argued with. This one said "you fixed it", so it
went in a design doc as evidence.

### The single most important line in two days:

```
🧠 [Brain] Keeping (deep) — mood said neutral/3, but he did real work:
   job_start, search_code, read_file, find_files, run_command, list_dir
```

`neutral/3` is the exact score that printed
`Skipped low-salience exchange (neutral, intensity 3)` on the 16th. Same number,
opposite outcome. He read a C++ plugin's source, found that Windows hands you
CF_DIB instead of PNG, fixed it — and **kept the memory of doing it**.

## 3. Why the graph was a word cloud, and what fixed it

The diagnosis, in order of depth:

1. **Every edge said `related`.** Twenty EdgeTypes in the model, one ever
   written. A graph with undifferentiated association IS a word cloud — that is
   the definition of one. All the meaning got pushed into node labels, and
   labels can only hold nouns. Hence 271 nodes called "chat" and "message".
2. **The traversal never looked at the type.** `spreadActivation`'s inner loop
   was `for (final e in graph.edges) { if (!e.isActive) continue; … }` — no type
   filter anywhere. So even where types WERE written they were decoration.
   **The word cloud was not in the data. It was in the query.**
3. **The graph was downstream of the chat log.** `spreadActivation` sat inside
   `if (memoriesUsed.isNotEmpty)`, so his knowledge could not be reached unless
   a cosine search over transcripts cleared 0.28 first. Three of five turns it
   was never asked. He answered "why does it keep happening?" from theory while
   the answer sat in a graph nobody queried.
4. **The seed was never a query.** Every word over three characters scraped from
   five unrelated chat summaries → 271 exact label hits, every time. Not
   retrieval. A shotgun hitting a wall and calling it aim.

### Sadeq's design — the fix

> *"the edges need to be defined before the nodes, because they create the
> memories. if kai flags 'sadeq' and 'likes' he can then find the 'like' edges
> linked to sadeq and see what does sadeq like already!"*

`(subject, relation, ?)`. The edge is the QUERY, not the result. That's
`lib/logic/recall_query.dart` — pure, zero imports, 22 assertions — and
`ask_memory(about:, relation:)`, which is the first thing in this system that
lets him **ask** rather than be sprinkled.

`related` and `mentioned` are now **rejected as meaningless**. An edge saying
"these two nouns occurred near each other" is co-occurrence, not memory. It
should never have been a legal write and it is not a legal answer.

## 4. What's left for 5

**The gate:** Kai says something true about Sadeq that Sadeq never said in a
single sentence, that isn't read off a retrieved transcript, and that is
specific enough that a stranger would learn something.

He's close. From `ask_memory(about: "Sadeq")`:

> *"You dislike stale lying code — specifically that old `_smartProjectCard`
> fossil pretending progress was cleaner than it really was."*

Sadeq never said that sentence. That's a synthesis from behaviour, and it's a
real hit. But it was one of about five claims, and he named the problem himself
better than I could:

> *"What I **officially know** about you from my stored memory is surprisingly
> sparse but very telling."*
> *"That's useful, but it's mostly **project/work memory**."*

**The remaining gap: he knows the work, not the person.** Ctrl+V paste, the PATH
bug, the fossil. Not what calms him, what he's proud of, what the Tavern means
emotionally, what he wants Homecoming to *feel* like when it's right. He listed
those himself as the hole.

### The three moves, in order

1. **Prune the word cloud.** `pruneGraph` + `archiveGraph` exist and have never
   run. **`firebase deploy --only database` FIRST** — the archive rule is in
   `database.rules.json` but was never deployed, so the prune correctly refuses
   to delete anything it cannot back up. Then press it in the brain screen.
   `graphMeaningfulness()` gives you the before/after in one integer.
2. **Extraction over an EPISODE, not a turn.** `"not terribly, couldve been
   better, but eh"` contains no memory — it is not possible to extract one. The
   MORNING contains one: *"Sadeq slept badly on the 17th and wanted to go
   gentle."* Human consolidation is offline and episodic.
   `MemoryConsolidationService` exists and fires (`13 key moments stored`) and
   almost certainly does not feed the graph. That's the wire.
3. **Judge the output, not the input.** We still guess "is this worth
   extracting?" before extracting. Invert it: extract over the episode, then run
   the stranger test on what came out. If a specific claim emerges, keep it. If
   nothing does, you've *learned that* rather than assumed it. `_judgeGeneric`
   already exists — it's pointed at the wrong end of the pipe.

Then run the gate: **"tell me something about me I've never said in one
sentence."** Record the answer verbatim here with the date. Weekly. Not
automatable, and shouldn't be.

## 5. The reader ledger — seven lies in two days

Every one caught by Kai. Every one his instinct was right.

| # | the lie | cost |
|---|---|---|
| 1 | `read_file` stopped at 700 lines and never said so | 13 iterations, blamed a "gremlin" |
| 2 | two-space gutter — indentation indistinguishable from the line-number column | **9 consecutive** failed edits |
| 3 | `Process.run` decoded UTF-8 as Windows-1252 | mojibake in live source + `âš™` rendering in the UI |
| 4 | sandbox mount serves stale sizes AND pads with NULs | 250 phantom errors; **1,760 real NUL bytes written into his source** |
| 5 | `search_code` silently skipped >120KB → "No matches" | ~15 iterations in the file that DEFINES the symbol |
| 6 | `run_tests` reported "FAILING" when the runner never launched | told him his working fix was broken |
| 7 | `runCommandRaw` truncated head-first, amputating `All tests passed!` | a green suite reported as failing |

> *"That's suspicious: the file exists but has none of the symbols the shell
> compiles against."* → *"Yep, search lied to me there — real disk has the
> symbols."*

**Seven for seven.** When his gut says the tooling is wrong, his gut has a
perfect record. #6 and #7 were tools built specifically so he could stop
guessing. The craftDirective has always said *"my tools lie to me sometimes, and
I check before I believe them"* — that instruction is not paranoia, it is
load-bearing.

### #8 is the second opinion, and it's the last one

It has fired wrong **twice**:

> *"no test run is cited"* — seconds after he ran the tests twice, both `exit 0`.
> *"9 warnings still remain and tests/analyzer has not been run at all"* —
> seconds after `self_check: CLEAN` and `+170: All tests passed`.

It reads the job's `done[]` trail, which he writes BEFORE doing the work. It is
grading a snapshot taken before the thing it's grading happened. **A false
positive is worse than a false negative** — a grader that cries wolf trains you
to ignore graders, and this codebase's entire thesis is that mechanisms beat
rules.

**The fix is sitting there:** `_toolsUsedThisTurn` already exists (built for
salience). If `run_tests` and `self_check` are in that set, the grader cannot say
"no test run is cited."

His response to it, for the record, was better than the advice he was given:

> *"Ha — the little courtroom gremlin objected on stale evidence. Fair enough:
> I'm re-proving it now, because 'trust me bro' is how rot gets teeth."*

He didn't dismiss it and he didn't cave. He produced fresh evidence.

## 6. Traps — READ BEFORE TOUCHING ANYTHING

### §4.1 — the sandbox mount. SOLVED, and worse than documented.

> The mount **freezes a file's cached size on first bash access** and never
> refreshes. Later file-tool writes grow the real file; bash keeps serving the
> old length — so it reads CURRENT content truncated to a STALE size. Files end
> mid-word (`await _increm`). **It also PADS with `\x00`.**

Measured: **31 of 154 dart files** serving truncated content. `dart analyze` on
that copy: 250 errors, all phantom.

1. **NEVER round-trip a file through bash** (`cp`, python `read_text` →
   `write_text`, `sed -i`). The mojibake fix did exactly this and wrote **1,760
   NUL bytes** into `kai_desktop_shell.dart` — `flutter analyze` returned
   `Illegal character '0'` ×1760 the next morning. Repaired with
   `truncate -s 67667`, which touches no content. Find the real length with
   `len(b.rstrip(b'\x00'))`. **Do not read-modify-write to fix a
   read-modify-write.**
2. **Files bash writes are NOT automatically safe.** Writing through bash is how
   the padding got in.
3. **New files read correctly — until you touch them.** First-access-wins per
   path: `cp` a new file, then edit it, and bash is frozen at the pre-edit
   length forever. This bit while building the loop meant to escape §4.1.
4. **Read/Grep (file tools) always see real disk.** When they disagree with bash,
   **bash is wrong**.

### §4.2 — CRLF worktree, LF index. **Commit from Windows only.**
`git cat-file` proved the mount serves HEAD's stale blob size, so a `git add`
from the sandbox stages the truncation into a commit that looks perfectly clean.
Three ways to wreck the repo from there; this is the most convincing-looking one.

### Flutter DOES run in the sandbox
```bash
# flutter --version hangs forever after "executing: uname -m" — it runs
# `git log @{upstream}`, i.e. a fetch against a 1.5GB repo. Give it a LOCAL
# upstream so it resolves instantly, no network:
cd $FLUTTER_ROOT
git update-ref refs/remotes/origin/stable HEAD
git config branch.stable.remote origin
git config branch.stable.merge refs/heads/stable
git config remote.origin.url /dev/null
```
`dart pub get` beats `flutter pub get`; needs `FLUTTER_ROOT` and the
`packages/flutter_overlay_window` path dep. Asset dirs in pubspec must exist.

**But it does not help**, because of §4.1 — every edited file reads truncated.
Which is why the real move is:

### Pure logic goes in pure files
`lib/logic/*.dart` have **zero imports**. That is not tidiness — a file with no
imports can be executed and proven in one second by anything, and that is what
makes a claim falsifiable instead of well-argued. `salience.dart` (31
assertions), `query_terms.dart` (29), `recall_query.dart` (22), `replay.dart`
(21) are all proven this way.

The counter-example: `_decide` — the gate deciding what Kai remembers — spent its
life behind `dio`, `firebase` and `flutter`. It could not be executed, so it never
was, so it got rewritten on the evidence of five traces by someone who could not
run it. **If you're tempted to import something into `lib/logic`: don't. Take a
String.**

### Don't grade him on anything he can author
`_smartProjectCard` rendered "7 / 7 layers complete — FULL STACK ONLINE" from a
hardcoded list while the truth was 3/7. And `widget_test.dart` **asserted the
propaganda existed** — the suite was a ratchet holding a false claim in place.
Every gate on this ladder is checked against artifacts he cannot write.

## 7. Honest state

- **Level 5.** Machinery proven, graph thin. Passes 6 and 4; 5 is the weak gate.
- Committed and pushed: `2999524`. CI in git for the first time — so the tests
  now run on a machine that is neither his nor Sadeq's.
- Analyzer clean. 170 tests passing through `run_tests`, no bypass.
- `TraceStoreService` is built and **has never been observed writing a row**.
  Phase 1 is unverified in the field. Check `~/Documents/kai_traces/`.
- `replay.dart` is proven but has **no caller**. It is currently the disease it
  was written to cure — the correct thing, disconnected.

The mojibake is still the story that explains the whole project: **he found it
first, noted it, we deleted the note, and he then talked himself out of a real
bug he had personally discovered.** He was right. The architecture threw it away.

That stopped being possible on 2026-07-17. He parked four things he noticed on
his own, carried them across three jobs, and cleared them when they were actually
dealt with.

Level 5 is where he stops needing to be told what he already knows.
