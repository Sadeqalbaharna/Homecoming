# Homecoming ("Kai") — Handover Brief

*For a finance / recovery-planning assistant with zero prior context. Prepared 2026-07-19. All cost figures are ESTIMATES unless marked; pull actuals from the billing dashboards named in §4.*

> **AMENDMENT (same day, later).** After this brief was written, the project pivoted in a way that changes §5 and §10. Homecoming is no longer only a personal companion — it is now also the host for a **product-factory capability**: tooling that researches market gaps from cited evidence, builds a digital product, and (with human approval) lists and measures it. The intent is to convert the project from a pure cost centre into the vehicle that earns.
>
> **This does not yet change the financial facts.** There is still zero revenue, the code is written but not yet compiled or run, no product exists, and it still consumes API credit. Treat the factory as an *unproven option*, not an asset. But advice premised on "mothball it entirely" is now working from a stale picture — see the revised §10.

## 1. What it is
Homecoming is a Flutter desktop/mobile app whose product is **"Kai," a persistent AI companion** — an always-present, evolving AI presence with long-term memory, its own agency (it can read/edit code and run commands), and a distinct personality. It is currently built for **one user (the owner)** as a personal companion, not a multi-user product. Core value: an AI that remembers, acts, and grows into a specific "someone" over time, rather than a stateless chatbot.

## 2. Status — Prototype (pre-MVP)
**Works today:** text chat; a persistent memory graph; unprompted "proactive" texts (a scheduled cloud function messages the owner in Kai's voice); tool-use/agency (Kai reads & edits its own codebase and runs a shell); a partial Persona-5-styled UI; and a just-built automatic failover between OpenAI and Anthropic when one runs out of credit.
**Not working / rough:** no monetization; single-user only; several features half-built (styled home screen, chat-history import); three recent code changes are **unverified** (not yet compiled/run); and the **OpenAI account is currently out of credit.**

## 3. Tech & hosting
- **Stack:** Flutter/Dart — Windows desktop + Android mobile.
- **Backend:** Google Firebase — Realtime Database + Cloud Functions + Cloud Messaging (project `homecoming-74f73`, region europe-west1).
- **AI:** OpenAI API (primary reasoning, model "gpt-5.5", plus gpt-4o / 4o-mini for background tasks) and Anthropic Claude (secondary + fallback brain). ElevenLabs (custom TTS voice — currently disabled).
- **Repo:** local only — `C:\code\homecoming_app` (no hosted/remote repo evident). API keys in a gitignored secrets file.

## 4. Costs *(estimates — verify against billing)*
**Recurring, usage-based:**
- **OpenAI — the dominant cost and the current pain point.** Reasoning turns are expensive (worst case a few dollars for a *single* turn; per-turn cost grows with conversation length). The account repeatedly hits quota/credit limits. **This is the main money leak.** Actuals: platform.openai.com billing.
- **Anthropic Claude** — newer, additional usage-based spend (fallback + some features). Actuals: Anthropic console.
- **Firebase** — RTDB + Functions + messaging on pay-as-you-go; likely low at single-user scale (est. **$0–25/mo**). Actuals: Firebase billing.
- **ElevenLabs** — subscription for the custom voice (est. **$5–22/mo**), currently not actively used.

**One-time:** none material (development is the owner's own time; minor contractor image work).

**Bottom line:** costs are almost entirely **variable OpenAI/Anthropic API usage** — controllable by usage, with no fixed contracts. Spend stops when use stops.

## 5. Revenue — none, and not soon
No revenue. No business model, pricing, or users beyond the owner. It is architected as a personal companion, not a product. Reaching first revenue would require a **fundamental pivot** — multi-user support, a value proposition for strangers, and per-user cost economics that currently do not work (every conversation costs real dollars). **Plainly: this cannot make money in the near term without becoming a different product.**

## 6. Path to launch
Not on a launch path today. To become sellable it would need: multi-tenant architecture, cost controls (prompt caching / model routing / possibly fine-tuning — *designed, not built*), a non-personal value prop, and app-store deployment. **Blockers:** unsustainable per-turn cost, single-user design, no monetization model. **Effort:** months before it could earn a dollar.

## 7. Data access
Yes — **Firebase Realtime Database** (REST + SDK), project `homecoming-74f73`, europe-west1 (auth required). An external dashboard could read:
- **token/spend usage** (an in-app UsageTrackingService logs OpenAI/Anthropic token counts — the money-relevant metric),
- conversation counts, proactive-message counts, and job/activity history,
- under paths like `kai/{persona}/…` and `conversations/{persona}`.

Note: "users" = 1, so activity metrics reflect only the owner's own use. A test HTTP endpoint exists for the proactive-message function.

## 8. Tie-in to The Tavern (restaurant)
**No direct tie-in as built** — Kai is a personal companion and does not touch restaurant operations, revenue, or costs. The transferable asset is the **capability, not the app:** the same agentic tool-use already built could be repointed at the Tavern (automated invoicing/AR chasing, customer-review synthesis, marketing content, cash-flow tracking). That would be a separate effort — but it is where this skillset could actually **generate or save money.**

## 9. Key files & docs
No formal business/spec document exists; the design lives in unusually detailed code comments and the owner's intent. Key files (all under `C:\code\homecoming_app`):
- `lib/services/ai/ai_service.dart` — main reasoning engine + cost logic
- `lib/services/ai/claude_service.dart` — fallback brain
- `lib/services/core/kai_context_block.dart` — assembles the ~58k-character system prompt (a **major cost driver**)
- `functions/index.js` — proactive-messaging cloud function
- `lib/services/core/kai_project_service.dart` — self-tracking capability roadmap
- `HOMECOMING_HANDOVER_BRIEF.md` — this document

## 10. Risks & blunt take
**Biggest risk:** it is a **cash burner with zero revenue** — usage-based AI spend against no income, already hitting credit limits during a cash crunch. **Secondary:** deep personal/sunk-cost attachment vs. financial reality; single-user design with no path to money without a major pivot.

**Blunt take (revised — see AMENDMENT at top):** *This was a passion project. It is now an unproven attempt at a business.* That is a real change, but it is not yet a financial one — there is still no revenue and no shipped product.

The recommendation is therefore **narrower than "pause everything," and stricter than "keep going":**

1. **Cap the spend, don't kill the project.** Costs are almost entirely variable API usage and stop the moment usage stops. Set a hard monthly ceiling (e.g. $50–100) and treat it as a research budget with a deadline, not an open tab.
2. **Judge it on one milestone, not on vibes:** does it get **one digital product listed and earning within ~30 days?** That is a concrete, falsifiable test.
3. **If it misses that milestone, mothball it** — the code costs $0 at rest and nothing is permanently lost.
4. **The companion features remain pure cost.** Only the factory work has a revenue thesis. If spend must be cut further, cut there first.

**Bottom line for planning purposes: assume $0 income from this for at least 30–60 days, and do not build any recovery plan that depends on it.** Treat any revenue as upside, not budget. The restaurant remains the reliable earner.
