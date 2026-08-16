# Response to the Restaurant Profit Intelligence brief

**From:** Claude, engineering collaborator
**Date:** 21 July 2026
**Status:** Rebuttal and counter-proposal. The brief asked not to be agreed with.

---

## 0. Where the brief is right, briefly

So the disagreements are legible against it.

- **"The product is not the dashboard."** Correct, and tonight's numbers prove it: 33 analytical sections running on 44% real data.
- **AI must not be the authoritative calculator.** Correct and already how the console works.
- **The Finding as a durable domain object** rather than prose generated on demand. This is the single best idea in the document.
- **"Manual input is the emergency exit, not the front door."** Correct.
- **Never show a problem without the safest next action.** Correct.
- **"Treat recoverable profit as an estimate until an action is completed and measured."** This is the sentence that separates this brief from marketing.
- **Prompt injection from invoices and supplier PDFs.** A real threat, correctly identified, and rarely considered at this stage.

Everything below assumes those are settled.

---

## 1. The central rebuttal: the brief assumes data that does not exist

Every worked example in the document requires recipes.

> *"Chicken prices increased by 14%, pushing six high-volume dishes above their target cost…"*

To produce that sentence the system needs: a recipe for each of the six dishes, a priced chicken ingredient, a unit conversion, a sales volume per dish, and a net-of-tax menu price. Five inputs, all of them per-item.

Here is the state of those inputs **on the founder's own venue**, after months of work, with the founder personally motivated:

| Input | Coverage |
|---|---|
| Menu items with a recipe | **45 of 152** — and only 25 of those 45 ever sell |
| Ingredients priced | **202 of 368** |
| Ingredients with a unit conversion | **203 of 368** |
| POS lines matched to a costed item | **38 of 271** |
| Revenue covered by a costed item | **25%** |
| Stock counts ever taken | **0** |
| Batch recipes wired to anything that sells | **3 of 153** |
| **Overall data completeness** | **44%** |

This is the best-case tenant. An external pilot will be worse, because nobody there has spent three months on it.

**The consequence for the MVP acceptance criteria.** The brief states:

> *"the owner reaches a useful first finding quickly, with a working target of under 30 minutes after providing prepared exports"*

For the class of finding the brief describes — margin, repricing, recipe cost — **this is not achievable in 30 minutes, or 30 days, because no export on earth contains recipes.** The brief acknowledges this in §7 ("no file exists for this") and then builds an MVP that depends on it anyway.

This is not a scheduling problem. It is a product-definition problem, and it invalidates Stage 1 as written.

---

## 2. Counter-proposal: build the MVP on findings that need no recipes

This is the strongest thing in this document, so it is stated plainly.

**There is an entire class of profit leak that is computable from imports alone** — POS, goods received, and attendance — with zero chef involvement, zero recipes, and zero stock counts. All three of those files now import.

### Findings available with no recipe data

| Finding | Inputs | Evidence it works |
|---|---|---|
| **Prime cost vs benchmark** | daily sales + purchases + attendance | computed end-to-end tonight in under 5 minutes on a blank console |
| **Labour not matched to trade** | attendance + daily sales | found 72 hours rostered against **zero sales** on a Wednesday |
| **Sales per labour hour by day** | same | 3.18 against a 25 floor |
| **Overtime and premium concentration** | attendance | 6 of 12 staff over 48h; a 70.00 weekend premium nobody had costed |
| **Menu price vs what you actually bank** | product list + item sales | a consistent **15% gap** — VAT and service — making every margin flatter than reality |
| **Purchase price drift** | two goods-received exports | needs only two files a month apart |
| **Supplier concentration** | goods received | top-5 share of spend |
| **Uncategorised spend** | goods received | found 29.80 the source sheet was already flagging and nobody read |
| **Impossible values** | any import | found an ingredient priced at **−26**, making 12 recipes look cheaper than they are |
| **Dead menu items** | item sales + product list | 114 of 152 items had never sold once |
| **Effort aimed at the wrong dishes** | item sales | top 20 sellers = 43% of revenue; 10 of them not costed at all |

Every row is deterministic, testable, and needs nothing a chef has to sit down and write.

**Reframe the wedge accordingly:**

> **The Profit Audit tells you where the money went using only the files your POS already produces. Recipes make it sharper. They are not the price of entry.**

Recipes then become the natural upsell rather than the barrier: *"we found this without touching your kitchen — give us your top twenty dishes and we can find the rest."* That sequencing also fixes the failure the brief's own §7 identifies, because item sales tell you which twenty.

### What this changes about Stage 1

The brief's Stage 1 says "import menu/recipe, sales, purchases, and labour." **Drop recipe from the Stage 1 import list.** It is the only one of the four that cannot be imported, and including it is what makes the 30-minute promise false.

---

## 3. Rebuttal: Market Lens should be cut, not deferred

The brief places Market Lens at Stage 3. I would remove it from the roadmap until something else has been sold, for three reasons — one legal, one methodological, one fatal.

**Legal.** Competitor pricing lives on delivery aggregators whose terms prohibit scraping. The brief acknowledges this and proposes "approved sources," but does not name one that exists in Bahrain. An approved-source registry with nothing in it is not a stage, it is a placeholder.

**Methodological.** The comparability list — portion, protein, sides, service level, catchment, channel, tax treatment, promotional status — is a genuinely hard research problem. It is harder than everything else in the brief combined, and it is scheduled after two stages that are themselves unbuilt.

**Fatal, and this is the real objection.** Consider the brief's own example:

> *"Recommendation: Test BD 4.700. At current volume, estimated additional monthly gross contribution is BD 310."*

That number requires **price elasticity** — how much volume falls when the price rises. Nothing in the proposed system measures elasticity. "At current volume" silently assumes elasticity is zero, which is the one thing we know is false about a price increase.

So the flagship recommendation of Market Lens is a confident figure resting on an assumption nobody made deliberately. That is **precisely the false-precision risk the brief itself names in §17** — and Market Lens is the worst offender in the document. A confidence rating on top does not fix it, because the confidence is attached to the comparison, not to the elasticity.

**Alternative that survives.** Keep the pricing *analysis* and drop the market claim: *"This dish is at 41% food cost against your 35% target. A price of BD 4.700 brings it to target. We cannot tell you what that does to volume."* Honest, useful, needs no scraping, and ships with what exists today.

---

## 4. Rebuttal: the price point and the architecture are incompatible

You said: *price it within range of cafés and mom-and-pop shops.*

The brief describes server-side tenancy, per-tenant AI report generation daily, scheduled market observation, supplier catalogue normalisation, and outcome measurement. That is a **$200–500/month cost structure**, and MarketMan sits at $199–249 with an onboarding fee of $500–1,500.

Café pricing is realistically BD 15–40/month. The gap is not a discount, it is a different business.

Two coherent products exist. **Pick one deliberately, because they diverge on the first architectural decision:**

**A. The cheap deterministic tool.** Local-first, no server, no per-report AI cost, no market data. Sold at café prices, near-zero marginal cost, support is the only real expense. This is roughly what exists today.

**B. The advisory product.** Server, AI reporting, outcome tracking. Priced at BD 80–150, sold to operators with 3+ sites or serious volume — people who can measure a BD 300/month recovery and care.

The brief describes B. Your pricing instinct describes A. **This is a business decision, not an engineering one, and it should be made before Stage 0 rather than discovered at Stage 2.**

My own read, offered as opinion rather than analysis: A gets you paying customers this quarter and teaches you what B should be. B is the better company if it works, and you cannot currently fund finding out.

---

## 5. What the brief misses entirely: completeness as a gate

The brief lists "Data Health" as one of six nav items. It is more important than that.

**Data completeness determines which findings are honest**, and therefore has to gate them. The console already implements this and the brief has no concept for it:

- 15 measured tasks across setup / daily / weekly / monthly
- A **trust score** — the weighted share of the console running on real data rather than blanks
- A list of screens that **refuse to compute** at current completeness

The last one matters most. Right now the console names five screens that decline to show a number they cannot stand behind. Under the brief's Finding model, this becomes: `data_quality: "insufficient"` suppresses the finding rather than publishing it with low confidence.

**This should be a first-class part of the domain model**, not a nav item — because the single fastest way to destroy owner trust is a confident finding built on 25% coverage, and that is the default state of every new tenant.

---

## 6. Prototype audit

### Corrected facts

The brief describes "approximately 2,300 lines." The file is now **~480KB**, with 33 sections and 346 passing assertions. The brief was written against an earlier snapshot.

### Blocker #1 — already actioned, and it was worse than described

The brief is right that real data was embedded. Acting on it tonight found a leak the brief did not anticipate: **real supplier and menu names in code comments**, which survive any data-stripping process that only empties the data structures.

Now in place:

- `tavern_console_blank.html` — the distributable, generated **by script** from the real build so the two cannot drift
- Audited clean: zero employee names, supplier names, menu items, wage rates, keys, IBANs, or brand references
- `tavern_console.html` — private reference build, never shipped

### Reusable as-is

The deterministic calculation layer: costing with nested sub-assemblies, three-tier unit conversion, variance, versatility, the detector library, prime cost, punch pairing, the column-mapping importer, roles and audit. All of it is already pure functions over `DATA` and lifts out of the HTML with minimal surgery — the strangler approach the brief proposes is easier than it assumes.

### Genuine calculation risks

1. **Theoretical food cost currently reads 161%** on the real book. Not a formula error — an artefact of a lopsided 38-item sample where several have costs but no usable recipe. It is exactly the finding that should be suppressed by a data-quality gate rather than displayed.
2. **`yield` is applied but never validated.** A yield of 0 is silently treated as 1.
3. **Batch recipe cycles** are guarded, but the guard is untested against a deliberately circular recipe.
4. **`weeklySales` conflates a rate with a total.** It is units-per-week derived from a 28-week export. Any period other than a week needs an explicit period on the record.

---

## 7. What should not be built in the next 30 days

Answering brief question 19 directly:

- **Market Lens** — see §3
- **Smart Sourcing** — depends on a supplier catalogue nobody has
- **The server migration** — until a paying customer needs multi-user
- **AI report generation** — until deterministic findings are worth narrating
- **Any second sector** — retail, salons, gyms
- **POS API integrations** — imports work; integrations are a customer-specific ask
- **More analytical sections.** Thirty-three is past the point of diminishing returns. Nothing new until the trust score moves.

---

## 8. Recommended 30 days

| # | Work | Depends on | Done when |
|---|---|---|---|
| 1 | Confirm VAT + service rates, apply | you | every margin measures net |
| 2 | Deterministic finding objects for the eleven recipe-free diagnostics in §2 | — | each emits `{type, evidence_refs, measured, confidence, data_quality}` with fixtures |
| 3 | Data-quality gate: `insufficient` suppresses rather than publishes | 2 | no finding renders below its coverage threshold |
| 4 | Action Plan view: findings ranked by impact, with evidence links | 2, 3 | opens on findings, not modules |
| 5 | Cost the top 20 sellers | item sales | costed revenue 25% → ~45% |
| 6 | **Run it on two venues that are not yours** | 1–4 | two Profit Audits from files alone |

Step 6 is the only one that produces information you do not already have. The first five are execution; the sixth is the experiment.

---

## 9. Open decisions — yours, not mine

1. **Product A or product B (§4).** Everything downstream depends on it.
2. **VAT and service rates.** Still unset; every percentage in the app waits on them.
3. **Was the 12–18 July week genuinely slow, or under-recorded?** 61% of the till's average. It decides whether the venue has a rota problem or a recording problem.
4. **Who are the two external venues?** Named people, not a market segment. Nothing in this document is worth more than that answer.

---

## 10. Verdict

**Strongest:** the Finding object, the AI boundary, "never show a problem without the safest next action," and the refusal to claim savings before measuring them. These are the parts most products get wrong and they are right here.

**Weakest:** an MVP that depends on recipes that do not exist, a Market Lens whose flagship recommendation rests on unmeasured elasticity, and a cost structure that contradicts the intended price point.

**The one-line correction:**

> The brief proposes to tell owners where the money went **once the data is complete**. The opportunity is to tell them where it went **using the incomplete data they already have**, and to be explicit about what is still missing — which is also the thing that makes them finish the setup.
