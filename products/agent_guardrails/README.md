# Agent Guardrails for Dart & Flutter

Two small, dependency-free modules for people running AI agents with real capabilities: **a command guard** that decides which shell commands your agent may execute, and **a spend guard** that bounds an agent turn by money instead of by round count.

No framework. No services to sign up for. Two files you drop in, plus tests.

---

## Why this exists

Agents got hands faster than they got boundaries.

The moment you give an agent shell access, **every CLI on that machine becomes part of its capability surface** — including the parts you never intended. A storefront CLI that creates products also issues refunds. A cloud CLI that reads logs also deletes clusters. A package manager that installs also publishes.

The usual answer is a line in the system prompt: *"never run destructive commands."* That is advice, and advice is exactly what a model talks itself out of mid-task while trying to be helpful. If your boundary is a sentence the model can read, it is a boundary the model can reason past.

The second problem is money. The standard safety valve on an agent loop is a maximum iteration count — stop after 20 rounds. It's the wrong measure twice: it cuts off an agent making genuine progress on round 21, and it fails to stop expensive work, because **cost per round is not constant.** Every round re-sends the whole conversation, so spend grows *quadratically*. Twenty rounds isn't a budget; it's a number that feels safe.

---

## `command_guard.dart`

Default-deny allowlist for agent shell commands.

```dart
final policy = CommandPolicy(
  allowed: [
    ['products', 'list'],
    ['products', 'create'],   // creates a DRAFT — safe by construction
    ['files', 'upload'],
    ['sales', 'list'],
  ],
  requiresApproval: [
    ['products', 'publish'],  // consequential, but legitimate
  ],
  dangerNotes: {
    'refund': 'moves money back to a customer',
    'admin': 'account administration',
  },
);

final decision = guardCommand(args, policy, hasApproval: approvedByHuman);
if (!decision.isAllowed) {
  return 'Refused: ${decision.reason}';
}
```

**Default deny.** Anything not explicitly permitted is refused — *including commands that don't exist yet.* This isn't stylistic. A denylist is a promise that you thought of everything, and CLIs add subcommands in every release.

This is not hypothetical. While building this, a CLI's published README documented roughly twenty commands; the installed binary shipped closer to a hundred — including account administration, bulk customer export, and **two additional paths to publishing** the docs never mentioned. Every one was already blocked. Not by foresight — because unlisted meant denied.

Three further rules, each closing a specific hole:

**Command vs. data.** Only tokens before the first flag count as the command. Scanning every argument for dangerous words blocks honest work — `--name "Refund Policy Template"` is a legitimate value. Scanning nothing misses `sales refund`.

**No shell metacharacters in the command path.** Arguments should reach a process API as a list, which makes `;` and `&&` inert — but a boundary that depends on how the caller executes it isn't a boundary.

**Elevation flags are forbidden.** `--yes` and `--force` suppress a CLI's own confirmation prompts. Those prompts are a second safety net underneath this one, and an agent that can silence them has promoted itself.

**Approval doesn't widen the boundary.** A human approval unlocks exactly the commands on the approval list — never anything else. There's a test asserting that approval still won't unlock a refund.

---

## `spend_guard.dart`

Bounds a turn by tokens and detects genuine loops.

```dart
final guard = SpendGuard(tokenBudget: 500000);

final stop = guard.record(
  inputTokens: usage.input,
  outputTokens: usage.output,
  signature: '$toolName($serialisedArgs)',
);

if (stop != StopReason.none) {
  log(guard.explain(stop));
  break;
}
```

It distinguishes three stops, because *"finished"*, *"ran out of money"*, and *"went in circles"* need different responses:

- **`budgetExhausted`** — the turn cost what you said it could.
- **`loopDetected`** — the same call with identical arguments, repeatedly. That's stuck, not slow. Retrying won't change the result.
- **`iterationCeiling`** — a deliberately high backstop. If this fires regularly, your token budget is set too high to be doing its job.

`budgetFraction` is exposed so you can surface a live cost meter. Spend a user can't see is spend they can't object to.

---

## Install

Copy `lib/command_guard.dart` and `lib/spend_guard.dart` into your project. That's it — pure Dart, zero dependencies, no packages to add.

Run the tests with `dart test`.

---

## Design notes

**Both modules are pure and deterministic.** No IO, no clock, no network. That's what makes them exhaustively testable — and a security boundary you can't test exhaustively isn't one you should trust. The included tests cover the denials, not just the happy path.

**The guard has no `refund()` method — not even one that checks approval first.** Capability you don't build can't be misused by a confused agent mid-turn. That's a stronger guarantee than any check.

**Deliberately small.** These are ~400 lines total. You should read all of it before trusting it with your shell, and at this size that takes ten minutes.

---

## What this is not

- Not a sandbox. It governs which commands run, not what a command does once running.
- Not authentication. Keep credentials out of the agent's reachable environment — a token in a file the agent can read is a token the agent can use.
- Not a rate limiter or an observability platform.
- Not a substitute for least-privilege credentials. Guard *and* scope the token.

---

## Licence

MIT. Use it commercially, modify it, ship it. No attribution required.
