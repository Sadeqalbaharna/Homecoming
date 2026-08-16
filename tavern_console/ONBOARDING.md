# Onboarding a new venue

**Goal: get to a working console from files, not typing.**

Most of what this app needs already exists inside the client's POS. The honest
ceiling is **around 80%** — six exports will fill everything except two things,
and those two are the same two every time:

- **Recipes.** No POS holds them unless the client runs the inventory module,
  which independents almost never do.
- **A physical stock count.** Somebody has to walk the walk-in with a clipboard.

Everything else is a file.

---

## What to ask the client for

Send this list verbatim. Report names differ between systems — Foodics, Square,
Toast, Micros and Sapaad each call them something slightly different — so ask by
*what the report contains* rather than by name, and take whatever format comes
out. CSV, Excel and PDF are all workable; CSV is fastest.

> **Six exports, covering the last full month:**
>
> 1. **Product / menu list** — every item you sell, with its category and price
> 2. **Item sales report** — units sold and revenue per item
> 3. **Daily sales summary** — sales and covers per day
> 4. **Tax / tender summary** — one day is enough; it shows VAT and service
> 5. **Purchases / goods received** — supplier, date, item, quantity, cost
> 6. **Timesheets / payroll summary** — hours per person, and wage rates
>
> Plus, if they have it: an **inventory item list**, and a **PDF of the menu**.

Anything they can't produce, we work around. Nothing on this list blocks the
others.

---

## The order of operations

Each step is worth doing in this order, because each one makes the next
cheaper. Times are for a 150-item menu.

### 1 — Tax and service rates · 1 minute

**File:** tax / tender summary
**Populates:** VAT %, service charge %

**Do this first.** Every cost percentage in the console divides by what the
business actually banks, not what's printed on the menu. On the Tavern's real
data that gap was 15%, which moved dishes from a comfortable 24% food cost to
28% — the difference between fine and at-the-ceiling. Getting this wrong makes
every other number quietly optimistic.

If the export is unclear, take one item: menu price ÷ what the till reports for
it. That ratio *is* the answer.

---

### 2 — Menu · 5 minutes

**File:** product / menu list, or the menu PDF
**Populates:** menu items, prices, categories, kitchen/bar split
**Unlocks:** the whole costing frame — there is nothing to cost until items exist

The product list is better than the PDF: it carries the POS item codes, which
makes step 3 match cleanly instead of by fuzzy name. Use the PDF only when the
POS can't export.

**Watch for:** modifiers exported as separate items (`ADD Cheese`, `ADD Bacon`).
They're real revenue but not dishes. Leave them as items — they cost something
too — but don't be alarmed by the count.

---

### 3 — Item sales · 2 minutes

**File:** item sales report
**Populates:** units sold per item
**Unlocks:** theoretical vs actual, menu engineering, over-pour totals — three
screens that cannot compute at all without it

Loads into the **Sales import** screen for review. Exact name matches apply;
anything uncertain waits for a human. This is not caution for its own sake — on
the Tavern's real export, fuzzy matching proposed *Dirty martini → Espresso
Martini* and *Bowl O' Chili → Bowl of Nuts*. A wrong sales volume is worse than
none, because it flows into food cost as a number nobody can trace back.

**This step also tells you which twenty dishes matter**, which decides the whole
recipe effort in step 7.

---

### 4 — Trading week · 3 minutes

**File:** daily sales summary
**Populates:** sales and covers per day
**Unlocks:** prime cost, sales per labour hour, the weekly report

Cross-check the total against step 3. If the two disagree by more than a few
percent, stop and find out why before going further — on the Tavern that gap was
39%, and it was the difference between a 104% prime cost and a 63% one.

---

### 5 — Purchases · 5 minutes

**File:** purchases / goods received
**Populates:** invoice log, supplier ledger, **and ingredient prices**
**Unlocks:** cost of sales, supplier spend, the price history that drives
price-shock warnings

This is the quiet win. A receiving export usually carries **cost per unit per
ingredient**, which is the single most tedious thing to type and the thing the
starter catalogue deliberately refuses to guess. If the client has this file,
ingredient pricing stops being a job.

---

### 6 — Labour · 3 minutes

**File:** timesheets / payroll summary — **or the fingerprint scanner export**
**Populates:** employees, daily hours (wage rates are typed)

Most Gulf venues run a biometric device rather than a payroll timesheet.
ZKTeco and its cousins export `user_id, timestamp, IN/OUT`, and the layout is
user-configurable — so it goes through the same column mapper as everything
else. The console pairs the raw punches into shifts and reports what it could
not pair rather than guessing. **No attendance export contains wage rates**;
those are typed once on the Labour tab and then stay put.
**Unlocks:** labour %, prime cost, overtime detection

Wage rates are personal data. They stay in the file on the machine and go
nowhere. Say that out loud to the client — it's usually their first question.

---

### 7 — Recipes · the real work

**No file exists for this.** This is the wall, and pretending otherwise is how
onboarding fails.

Do **not** work through the menu in order. Use step 3 to rank by revenue and do
the top twenty. On the Tavern, the top 20 items were 43% of all revenue, while
114 of 152 costed items had never sold once — a lot of effort spent on the wrong
dishes because the workbook set the order instead of the till.

Three things that make it survivable:

- **Never hand a chef a blank form.** Generate a draft from the catalogue and
  ask them to correct it. Correcting is a fraction of the effort of authoring,
  and it flatters expertise rather than demanding admin.
- **Measure their units once.** Weigh a ladle, a handful, a scoop. Then the chef
  can keep speaking in ladles forever and the system converts.
- **Capture at prep, not in a meeting.** The marination gets made on Tuesday.
  That's the appointment.

---

### 8 — First stock count · 45 minutes, on site

**No file. Physical.**
**Unlocks:** true cost of sales instead of purchases, and the variance that
exposes waste, over-portioning and theft

Until this happens the console reports *spend*, not *consumption*. Worth
scheduling for the end of the first month rather than day one.

---

## What each file is worth

| Step | File | Trust score contribution |
|---|---|---|
| 1 | Tax summary | rates — small field, large blast radius |
| 2 | Product list | menu prices, categories |
| 3 | Item sales | sales mix — unblocks 3 screens |
| 4 | Daily sales | sales + covers |
| 5 | Purchases | ingredient prices, invoice log, allocation |
| 6 | Timesheets | hours, rates |
| — | **From files alone** | **~75–85%** |
| 7 | Recipes | the last major block — human only |
| 8 | Stock count | variance — physical only |

---

## What the POS can never give you

State these up front. A client who discovers them in week three feels misled;
one who's told in week one treats them as the plan.

1. **Recipes.** Unless they run POS inventory.
2. **Yield percentages.** Trim loss on a beef fillet is a kitchen fact.
3. **True consumption.** Only a physical count produces it.
4. **Why a number moved.** The console shows the gap; a human explains it.

---

## Build status

What exists today, and what this document assumes but hasn't been built yet.

| Importer | Status |
|---|---|
| Workbook JSON (restore/backup) | **built** |
| Item sales → review queue | **built** |
| Ingredient starter catalogue (285 items with unit models) | **built** |
| Product / menu list | **built** |
| Daily sales + covers | **built** |
| Purchases / goods received | **built** — sets ingredient prices from unit cost |
| Timesheets / payroll | **not built** |
| Attendance / fingerprint scanner | **built** — pairs raw punches into shifts |
| Tax summary → rates | **not built** (rates are manual, which is fine) |
| Menu PDF parse | **not built** |

All three arrive through one **Import from POS** screen rather than three
parsers. It sniffs the delimiter, finds the header row under whatever title
lines the export opens with, maps columns by header synonyms, then shows you the
mapping it guessed so you can correct it before anything is written. A layout
nobody anticipated costs two dropdowns instead of a code change — which is the
difference between onboarding a customer this week and promising them next
month.

Still to build: **payroll timesheets** (only needed where there is no biometric
device) and **menu PDF parsing** (only needed when the POS cannot export a product
list at all).
