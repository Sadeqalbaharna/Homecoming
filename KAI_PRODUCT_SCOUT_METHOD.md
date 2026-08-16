# Kai Product Scout — Method Spec v1

*A transferable method for finding evidence-backed product gaps. Written from a real run on 2026-07-19, with worked examples and the mistakes that run exposed. This is the spec Kai executes — not a description of what a machine might do.*

---

## The founding rule

**Gaps are harvested, not imagined.**

If Kai generates market opportunities from his weights, he produces confident, generic, wrong answers — the horoscope failure mode. Every proposed gap must cite **external evidence**: a URL, a price, a count, a quoted complaint. No evidence, no gap. This is the same discipline as the `noticing` module: *a scout that always finds something is a horoscope.*

**Stranger test for gaps:** would this claim be equally true of a random other market? If yes, it's noise, not a gap.

---

## Stage 1 — HARVEST

Collect real demand signals. Never conclude at this stage; only gather.

**Signal types, ranked by honesty:**

| Signal | Why it's trustworthy |
|---|---|
| Price + sales/review counts on a marketplace | Someone actually paid. Hardest evidence there is. |
| 1–3 star reviews | A bad review *is* a gap statement, written by a paying customer. |
| Public revenue figures | Proves the category monetizes at all. |
| "Alternatives to X" articles | Reveals both saturation *and* what X fails at. |
| Forum/Reddit complaints | Real, but unverified and easily cherry-picked. |
| Trend/market-size articles | Weakest. Context only — never a gap on its own. |

**Query patterns that worked in the live run:**

- `<marketplace> best selling <category> <year> price sales count` → demand + saturation + price band
- `developers complain <problem> <year>` → pain language in their own words
- `<incumbent A> <incumbent B> limitations complaints` → where existing tools fail
- `<category> revenue solo developer <year> market` → does this category actually pay?

**Known limitation, discovered the hard way:** generic web search is *weak* at harvesting raw complaints. The query `Reddit "I wish there was" unmet need` returned almost nothing usable. Kai must go to **structured complaint sources directly** — marketplace review pages, GitHub issues, "alternatives to X" comparisons — rather than hoping a search engine surfaces forum threads.

---

## Stage 2 — SCORE

Every candidate gets scored on four axes. **Score distribution FIRST** — it's the axis that silently kills the most products, and the one everyone skips.

1. **Distribution** — does a channel with existing traffic already exist? A great product with no channel is a hobby. *Marketplace with search traffic > direct sale needing an audience.*
2. **Monetization proof** — is anyone already paying, and at what price? An empty category is usually empty for a reason.
3. **Saturation** — how many competitors, how well funded? High demand + high saturation = a bad solo bet.
4. **Build feasibility** — shippable in under two weeks on the stack already owned?

**Scoring rule:** a low score on *distribution* or *saturation* kills a candidate no matter how strong the other axes are.

---

## Stage 3 — SPEC → Stage 4 — BUILD → Stage 5 — SHIP & LEARN

Spec the winner (MVP scope, what to deliberately cut, price, listing copy), build it, ship it, then **feed real sales and reconciled bank-settlement data back in to grade the scout's own picks.** A sale notification or pending processor balance is not success; the Factory Northstar is actual customer money settled into the bank account.

The scoreboard is **dollars from products it chose** — not elegance of analysis. Without stage 5 it's a generator, not a machine.

---

## Worked examples from the live run

### ❌ Candidate A — Flutter templates on CodeCanyon → KILLED
- **Evidence:** 3,800+ Flutter items / 900+ templates already listed. Top sellers $39–79, with weekly sales in single digits (11, 7, 6).
- **Verdict:** Saturation extreme, price band low. Distribution exists (real search traffic) but is drowned out.
- **Lesson:** demand ≠ opportunity. This *was* the assistant's own earlier recommendation — evidence killed it.

### ❌ Candidate B — LLM cost/observability SaaS → KILLED
- **Evidence:** Helicone, Langfuse, LangSmith, Braintrust, Laminar, Cekura all active and funded. Market already segmented by spend tier (Helicone <$30K/mo, Langfuse $30K–200K).
- **Verdict:** Real pain, but a crowded field of funded incumbents. Bad solo entry.

### ✅ Candidate C — AI-agent app boilerplate → STRONGEST
- **Evidence:** SaaS boilerplate market crossed **$50M+ annually** in 2026. ShipFast: **8,300+ buyers at $199–299**, creator reportedly at ~$45K/month. Meanwhile agentic devs report **up to 50× overruns** vs flat subscriptions; **only 22% of orgs track AI spend per transaction**; routing/caching/batching cut spend **70–85%**.
- **The gap:** existing boilerplates (overwhelmingly Next.js/web) ship *auth + Stripe*. Almost none ship the genuinely hard part — a **production agentic loop**: tool-calling, memory, multi-provider failover, and cost controls baked in.
- **Why this operator:** every one of those components already exists in the Homecoming codebase, built and debugged the expensive way.
- **Open risk:** ShipFast's success rests on its creator's *audience*. Distribution is the unsolved axis here — see below.

### 🟡 Candidate D — open-source failover/routing package → MARKETING, NOT REVENUE
- Partially served (LiteLLM, OpenRouter). Weak as a product; strong as credibility and a funnel into C.

---

## The five lessons this run taught

1. **Search for saturation, not just demand.** Demand is easy to find and usually already served.
2. **Channel sets price.** The *same* asset sells at $39–79 on a marketplace and $199–299 direct. Choosing the channel is a pricing decision.
3. **Kill your own hypothesis.** Two of the assistant's own prior recommendations died on contact with evidence. That is the method *working*.
4. **Distribution is the real constraint** — not build capability. Score it first.
5. **Generic search is a weak harvester.** Go to structured complaint sources directly.

---

## Kai's operating checklist

```
1. Name the market. Do NOT propose ideas yet.
2. Harvest ≥4 signal types. Record URL + number for each.
3. List candidates. Every one carries citations.
4. Score: distribution → monetization → saturation → feasibility.
5. Kill anything failing distribution or saturation, however appealing.
6. Apply the stranger test to survivors.
7. Spec the winner. Name what you're cutting.
8. After shipping, record actual revenue against the prediction.
```

## Adaptive search parameters

When nothing survives, Kai adjusts the *search*, not the truth standard.

Allowed adaptations:

1. **Widen adjacent boring markets** — move sideways from the first niche into nearby operators with the same mundane workflow. Example: café inventory → concession stand inventory → small club/bar stock sheets → event-stall prep sheets.
2. **Widen evidence types** — look for paid prices, review counts, complaint threads, competitor counts, public revenue, and marketplace search-result counts. Do not rely on only one kind of proof.
3. **Widen channels** — check Etsy, Gumroad, Shopify stores, Reddit/forum complaints, app/template marketplaces, YouTube comments, Facebook groups when searchable, and plain Google results.
4. **Reduce preference restrictions** — if "boring small spreadsheet" returns nothing, allow boring PDF/checklist/Notion/Canva/template products before changing markets entirely.
5. **Keep hard evidence gates frozen** — no URL means no evidence; one domain cited three times is still one source; market-size alone proves nothing; no distribution or saturated headroom still kills.

Kai may loosen taste and format. Kai may not loosen citations, counts, prices, or the scorer verdict.

**Refusal condition:** if Kai cannot cite evidence, he must say *"no defensible gap found"* rather than inventing one. A scout that never returns empty-handed is not a scout.
