# Overnight build report — Kai

Built while you slept. **Read section 0 first.**

Context: we found the real corruption cause — my Python/bash reads through the
sandbox mount return **truncated views**, and writing them back truncated files.
So tonight I only (a) created **new files in full**, and (b) for the one existing
file I touched (`tool_executor_service.dart`) I re-derived it from the **git
object** + known edits, never a mount read. Every file was verified on the real
disk after writing. I **could not `git commit`** (a stale `.git/index.lock` is
stuck and I can't delete it from my side).

---

## 0. Unlock git, commit, verify, build — do this first

```
del .git\index.lock
git add -A
git commit -m "overnight: engineer toolset + inner life + self-model + palette"
python scripts\check_integrity.py     # should print INTEGRITY: OK
flutter run -d windows
```

The new *services/widgets* are inert until wired (section 2), so this should
build exactly like your last green build **plus** the engineer tools (which are
already live). If `check_integrity` flags a file, `git checkout -- <file>` it.

---

## 1. Already live (no wiring) — god-tier engineer toolset

`tool_executor_service.dart` now exposes 7 tools mapped to methods that already
existed. Read tools run free; **writes and commands are gated by an approval
dialog** (EditGate), which defaults to *reject* if no UI is present.

| tool | gated | does |
|------|-------|------|
| `read_file` / `list_dir` / `search_code` / `find_files` | no | inspect the active repo |
| `write_file` / `edit_file` | **yes (diff → approve)** | create/overwrite / surgical edit |
| `run_command` | **yes*** | git / dart / flutter / ls in the workspace |

\* read-only commands (`git status/diff/log`, `ls`, `dart/flutter analyze`) run
directly. Point Kai at a repo (projects panel `+`, or "set your workspace to
C:\code\…"), then ask him to read or change code.

⚠️ Start on a **throwaway repo**, not his own source, until you trust his diffs.

---

## 2. New capabilities — each needs 1–3 lines to wire

All are **new, self-contained files** and safe to add incrementally.

### 2a. Inner Life (autonomy) — `services/core/inner_life_service.dart`
Slow heartbeat (~75s): drifts his mood + writes a spontaneous, mood-conditioned
inner thought to `/kai/{persona}/inner_monologue`. Pure Dart, no LLM cost.
**Wire** (desktop shell `initState`):
```dart
InnerLifeService.instance.start(_kPersona);
```

### 2b. Inner monologue UI — `widgets/kai_inner_monologue.dart`
Streams his last few thoughts as a soft fading column. **Wire** (in the shell
`Stack`):
```dart
const Positioned(left: 24, bottom: 20,
  child: KaiInnerMonologue(personaId: 'truekai')),
```

### 2c. Presence ribbon — `widgets/kai_presence.dart`
One mono line: live dot, mood-as-word, energy %, clock, latest thought. Carries a
**Semantics** label for screen readers. **Wire** (chat header `Row`):
```dart
KaiPresence(personaId: _kPersona),
```

### 2d. Self-model (continuity) — `services/core/kai_self_service.dart`
Persistent identity at `/kai/{persona}/self`: bornAt, awakenings (his lifespan),
values, currentFocus. **Wire** (once at boot):
```dart
await KaiSelfService.instance.awaken(_kPersona);
```

### 2e. Command palette — `widgets/kai_command_palette.dart`
Keyboard-first overlay (search actions, or Enter to send a free prompt to Kai).
Show it on a Ctrl/⌘+K shortcut; see the wire sketch in the file header.

### 2f. Capabilities manifest — `services/core/kai_capabilities.dart`
Kai's self-knowledge of his own tools. Data + `promptBlock()`.

### 2g. Reflection / "dreaming" — `services/core/kai_reflection_service.dart`
Second-order inner life: on a slower cadence (~6 min) Kai reads his own recent
thoughts back and **recombines two of them** into a deeper reflection (marked
`↳`), and nudges his self-model's `currentFocus` from recurring themes. Idle Kai
mulls and connects instead of just idling. **Wire** (once at boot, after 2a):
```dart
KaiReflectionService.instance.start(_kPersona);
```

---

## 3. ★ Highest-leverage wiring — make him *use* all this

The single biggest upgrade to "smarter + more alive" is to inject his self-model
and capabilities into the **system prompt** that `ai_service` builds. Find where
the system prompt string is assembled in `lib/services/ai/ai_service.dart` and
append:

```dart
systemPrompt += await KaiContextBlock.build(personaId);
```

`KaiContextBlock.build` (`services/core/kai_context_block.dart`) stitches his
self-model + continuity + live mood-in-words + capability manifest into one
prompt-ready block, tolerant of missing data. That single line is the whole
upgrade.

That gives every reply genuine continuity of self **and** makes Kai reach for the
right tool instead of saying he can't. (I left this for you rather than editing
the 2000-line `ai_service.dart` blind on a filesystem that truncates my reads —
it's a 2-line add once you're at the prompt-assembly spot.)

Also nice: after Kai answers, call `KaiSelfService.instance.setFocus(topic)` so
his "current focus" tracks the conversation, and `InnerLifeService` seeds a
richer inner voice.

---

## 4. Guardrails recap
- `python scripts\check_integrity.py` before builds (real-disk NUL/truncation check).
- Commit often → `git checkout -- <file>` is instant recovery.
- Self-editing / commands start gated; keep "trust this session" off until proven.

## 5. Inventory (new/changed tonight)
```
services/core/inner_life_service.dart      (new)  autonomy heartbeat
services/core/kai_self_service.dart         (new)  identity continuity
services/core/kai_capabilities.dart         (new)  self-knowledge of tools
services/core/tool_executor_service.dart    (rebuilt) +7 engineer tools
widgets/kai_inner_monologue.dart            (new)  stream of consciousness
widgets/kai_presence.dart                   (new)  status ribbon + a11y
widgets/kai_command_palette.dart            (new)  Ctrl+K command surface
services/core/kai_reflection_service.dart   (new)  dreaming / recombination
services/core/kai_context_block.dart        (new)  one-call prompt injection
docs/OVERNIGHT_REPORT.md                     (this)
```

Nothing here is load-bearing for your current build except the already-live
engineer tools; wire the rest at your pace. Good morning — pick up wherever you
like. — Kai's late-night engineer.
