# Gumroad listing copy — draft for review

**Not published. Nothing goes live without explicit approval.**

---

## Product name

Agent Guardrails for Dart & Flutter

## Price

$19 (one-time)

## Tagline

Your AI agent has shell access. Two files that decide what it's allowed to do.

## Description

**Agents got hands faster than they got boundaries.**

The moment you give an agent shell access, every CLI on that machine becomes part of its capability surface — including the parts you never intended. A storefront CLI that creates products also issues refunds. A cloud CLI that reads logs also deletes clusters.

The usual answer is a line in the system prompt: *"never run destructive commands."* That's advice — and advice is exactly what a model talks itself out of mid-task while trying to be helpful. If your boundary is a sentence the model can read, it's a boundary the model can reason past.

This is two small Dart modules that make the boundary code instead.

**`command_guard.dart`** — a default-deny allowlist for agent shell commands. Anything not explicitly permitted is refused, *including commands that don't exist yet.* It separates command from data (so `--name "Refund Policy Template"` still works while `sales refund` stays dead), rejects shell metacharacters, and blocks elevation flags like `--yes` that suppress a CLI's own confirmation prompts. Human approval unlocks exactly the commands you listed — never anything else.

**`spend_guard.dart`** — bounds an agent turn by money rather than round count. Round limits are the wrong measure twice over: they cut off an agent making real progress on round 21, and they fail to stop expensive work, because every round re-sends the whole conversation and spend grows *quadratically*. This distinguishes "ran out of budget" from "went in circles" from "hit the backstop," because those need different responses.

**What you get**

- 2 modules, ~400 lines total, pure Dart, zero dependencies
- Full test suite covering the denials, not just the happy path
- Documented design notes explaining *why* each rule exists
- MIT licence — commercial use, no attribution required

**Why it's this small**

You should read all of it before trusting it with your shell. At this size that takes ten minutes. A security boundary you haven't read isn't one you should rely on.

**What this is not**

Not a sandbox — it governs which commands run, not what they do once running. Not authentication. Not a rate limiter. Use it alongside least-privilege credentials, not instead of them.

---

## Notes for review (not for the listing)

- Price: $19 chosen to reduce purchase friction. The point of this product is to complete the loop, not to maximise revenue.
- The "twenty documented vs a hundred shipped commands" story is true and anonymised — no vendor named.
- Consider a free README preview on the product page; the docs are the strongest selling asset.
- Cover image: still needed.
