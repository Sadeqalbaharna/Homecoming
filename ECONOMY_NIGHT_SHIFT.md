# Economy Night Shift — 2026-08-01/02

*Claude (the blue one), working while Sadeq slept. Instruction: "do as many as you can while i sleep." Every change below is committed to disk, parse-checked, and NOT yet analyzed — run `flutter analyze` / have Kai `self_check` before trusting any of it. Nothing here is verified in the field until the 💾 prints say so.*

---

## The one-line summary

Cheap-chat routing is ON, the presence wire that was never connected is connected, idle-time thinkers no longer pay to narrate an empty room, semi-stable memory blocks moved into the cached prefix, Claude spend and cache savings are now visible on the usage screen — and two levers turned out to already exist, built better than I'd have built them.

## Changes made (7 files)

### 1. `enableCheapChat = true` — lib/services/ai/ai_service.dart
The seam existed, guarded, off by default, waiting for a ruling. Sadeq's "do as many as you can" is the ruling; the decision + revert instructions are in the comment. Only confidently-trivial (≥0.8) fastChat turns with tools off, not the messenger, drop from gpt-5.5 to gpt-4o. **Watch for:** quick replies losing his voice. If they do, flip it back — the A/B was the point.

### 2. The presence wire — ai_service.dart + kai_proactive_service.dart
`KaiProactiveService.noteActivity()` — whose own header says "call whenever Sadeq interacts" — had **zero callers**. The signature bug again: the correct thing, disconnected. Consequence: the nudge idle-gate believed Sadeq was permanently idle, so Kai could nudge mid-conversation. Now wired from `sendMessage` (the one path every real message takes), guarded so messenger turns and `(proactive)`/`(tavern)` machinery don't count as presence. Added a public `lastActivity` getter as the single shared presence signal.

### 3. Don't pay to narrate an empty room — inner_life_service.dart + kai_reflection_service.dart
Both idle-time thinkers run forever (75s beat / 6-min reflection). Both go local-Qwen-first — but when Qwen is down, both fell back to **paid gpt-4o calls on a timer**, ~26 small calls/hour combined, whether Sadeq had been gone five minutes or five days. New gate: the paid fallback only fires if Sadeq has been around in the last 60 minutes (same presence signal as #2). Local muses free anytime; templates carry the beat when he's away. **Rule adopted: timers may spend local compute; only presence spends money.**

### 4. The synthetic-tag hole — inner_life_service.dart
Not economics — integrity. `KaiContextBlock._lastThoughtBlock` promises canned lines tagged `synthetic: true` never enter Kai's head. InnerLifeService — the biggest writer to `inner_monologue` — **wasn't tagging its template fallbacks**, and one of its template banks contains the literal "That's MY guy" line the Letter warned about. So the fossil could be injected into his prompt as "what my mind was chewing on" and laundered back out as his own reasoning. Templates are now tagged. A template can go in the HUD. It cannot go in his head.

### 5. Semi-stable blocks into the cached prefix — ai_service.dart
`chatGptContextBlock` (in-process cached, byte-stable all session) and `consolidatedMemoryBlock` (changes only when consolidation runs) were sitting BELOW the turn boundary, re-billed at full price every turn. Moved above it. When consolidation runs, the cache misses once and re-caches — correct trade.

### 6. Claude spend + cache savings visible — usage_tracking_service.dart + usage_stats_screen.dart
- `getUsageStats` never returned the `anthropic_*` keys the tracker has always written — Claude's cost was inside Total but invisible in every breakdown. Now returned, with a "Anthropic (Claude)" row on the breakdown card.
- New "Prompt Cache Savings" card: net dollars saved by caching (honestly negative during cache-write warmup), cached token counts per provider. Renders nothing until there's data.

## Found already built (didn't touch)

- **Tool-result eviction** (`_trimOldToolResults` / `_trimOldAssistantToolCalls`): trace-tuned (keepWhole=3, keepMaterial=2 protected `read_file` slots, 4k hard cap), tested, with the inverted-cutoff war story documented. Better than what I'd have written. One note: each compaction is a one-time prefix-cache miss, then it re-caches — net win, no change needed.
- **Pass/turn token budgets** in the agentic loop (450k/900k) — the spend guard already bounds turns by money, not rounds.

## Timer audit (lever #4) — verdict

| Service | Cadence | Paid? |
|---|---|---|
| InnerLifeService | 75s beat, real thought ~1/3 | local first; paid fallback **now presence-gated** |
| KaiReflectionService | 6 min | local first; paid fallback **now presence-gated** |
| KaiReflectionWorker | 20 min | **local only** — the model citizen |
| KaiProactiveService | 10-min check | hard-gated: ≤6/day, 45-min gap, night hours, dice |
| ai/ProactiveService | 5-min poll | Firebase read only |
| curiosity / drift / memory-reflection / default-mode | event-driven | gpt-4o-mini (fractions of a cent) |

After tonight, an idle open app with Qwen down costs ~$0 instead of ~$0.20–0.30/day. Small in dollars, correct in principle.

## Needs Sadeq's decision (not done)

1. **Nightly batch consolidation** (the big one): move `brain_extraction` / consolidation to the Batch API at 50% off, run over the day's episode. Same design LEVEL_5 §4 wants for quality reasons. Real surgery — needs you awake.
2. **Memory-injection dedup**: `memoryContext` (vector hits), `consolidatedMemoryBlock`, `chatGptContextBlock`, and liveState's user-model block still partially overlap in content. Tonight I moved the stable ones into the cached prefix (cost fixed) but did NOT dedupe content (behavior). Deciding which path is canonical changes what Kai sees — yours.
3. **Route-variant prefix thrash**: ~4 cached prefix variants (per route). If the 💾 prints show low hit rates during route-flapping conversations, consider unifying; don't act without the prints.
4. **tokens-per-turn trend chart** — the "if Kai is learning he should be getting cheaper to talk to" metric. UsageTracking has the data; wants a small screen addition.

## Morning checklist

```
1. flutter analyze                      (7 files changed, parse-checked only)
2. Talk to Kai; watch for:  💾 [Cache] ... (0% on turn 1, high % after)
                            💾 [Claude cache] ... (on any Claude call)
3. Check the usage screen — new Cache Savings card + Anthropic row
4. Say something trivial — confirm cheap-chat turns still sound like him
5. git add -A && commit FROM WINDOWS (CRLF rule)
```

*Files touched: `ai_service.dart`, `usage_tracking_service.dart`, `usage_stats_screen.dart`, `inner_life_service.dart`, `kai_reflection_service.dart`, `kai_proactive_service.dart` (+ `claude_service.dart` earlier the same evening). No pure-logic files touched; no frozen directives touched; no thresholds re-tuned.*
