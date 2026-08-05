// command_guard.dart — decide which shell commands an AI agent may run.
//
// ── The problem ─────────────────────────────────────────────────────────────
//
// The moment you give an agent shell access, every CLI installed on that
// machine becomes part of its capability surface — including the parts you
// never intended. A storefront CLI that creates products also issues refunds.
// A cloud CLI that reads logs also deletes clusters. A package manager that
// installs also publishes.
//
// Prompt instructions ("never run refunds") are advice, and advice is what a
// model talks itself out of mid-task when it is trying to be helpful. The
// boundary has to be code, and it has to be code the agent cannot reach.
//
// ── The design ──────────────────────────────────────────────────────────────
//
// DEFAULT DENY. A command is refused unless it is explicitly permitted. This
// is not stylistic: a denylist is a promise that you thought of everything, and
// CLIs add subcommands in every release. With an allowlist, new capabilities
// arrive switched OFF.
//
// This is not hypothetical. While building this, a CLI's published README
// documented roughly twenty commands; the installed binary shipped closer to a
// hundred, including account administration, bulk customer export, and two
// additional paths to publishing that the docs never mentioned. Every one was
// already blocked — not by foresight, but because unlisted meant denied.
//
// Three further rules, each closing a specific hole:
//
//   1. COMMAND vs DATA. Only the tokens before the first flag are treated as
//      the command. Scanning every argument for dangerous words blocks honest
//      work (`--name "Refund Policy Template"` is a legitimate value); scanning
//      nothing misses `sales refund`.
//
//   2. NO SHELL METACHARACTERS in the command path. Arguments should be passed
//      as a list to a process API rather than a shell string, which makes `;`
//      and `&&` inert — but a boundary that depends on how the caller executes
//      it is not a boundary.
//
//   3. ELEVATION FLAGS ARE FORBIDDEN. Flags like `--yes` skip a CLI's own
//      confirmation prompts. Those prompts are a second safety net underneath
//      this one, and an agent that can silence them has promoted itself.
//
// ── Approval ────────────────────────────────────────────────────────────────
//
// Some commands are legitimate but consequential. Those return
// [GuardVerdict.requiresApproval] rather than being denied outright, so a human
// can authorise one specific action. Critically, approval unlocks exactly the
// commands on the approval list — it never widens the boundary generally.
//
// Pure Dart. Zero dependencies. Deterministic, so it can be tested exhaustively.
library;

/// The outcome of a guard check.
enum GuardVerdict {
  /// Safe. The agent may run this unsupervised.
  allowed,

  /// Legitimate but consequential — needs a human's explicit sign-off.
  requiresApproval,

  /// No path. Destructive, irreversible, or outside the agent's remit.
  denied,
}

class GuardDecision {
  final GuardVerdict verdict;

  /// Human-readable justification. Always populated, including on success, so
  /// approvals are auditable too.
  final String reason;

  const GuardDecision(this.verdict, this.reason);

  bool get isAllowed => verdict == GuardVerdict.allowed;
  bool get isDenied => verdict == GuardVerdict.denied;
  bool get needsApproval => verdict == GuardVerdict.requiresApproval;

  @override
  String toString() => '${verdict.name}: $reason';
}

/// A policy describing what one CLI tool is allowed to do.
///
/// Commands are matched as PREFIXES against the command path, so
/// `['products', 'list']` matches `products list --all --json`.
class CommandPolicy {
  /// Commands the agent may run freely. Prefer read-only operations and ones
  /// that produce drafts rather than published or irreversible state.
  final List<List<String>> allowed;

  /// Commands permitted only with explicit human approval.
  final List<List<String>> requiresApproval;

  /// Optional notes keyed by a command token, used only to explain a refusal
  /// clearly. Denial does not depend on this map — anything unlisted is denied
  /// regardless.
  final Map<String, String> dangerNotes;

  /// Flags the agent may never pass, on any command.
  final Set<String> forbiddenFlags;

  const CommandPolicy({
    required this.allowed,
    this.requiresApproval = const [],
    this.dangerNotes = const {},
    this.forbiddenFlags = const {'--yes', '-y', '--force', '-f'},
  });
}

/// Shell control characters. Rejected in the command path regardless of how the
/// caller executes the command.
const String _shellChars = ';&|`\$<>\n\r';

bool _matches(List<String> args, List<String> pattern) {
  if (args.length < pattern.length) return false;
  for (var i = 0; i < pattern.length; i++) {
    if (args[i] != pattern[i]) return false;
  }
  return true;
}

/// The leading tokens up to the first flag. Everything after a flag is data.
List<String> commandPath(List<String> args) {
  final out = <String>[];
  for (final a in args) {
    if (a.startsWith('-')) break;
    out.add(a);
  }
  return out;
}

/// Decide whether an agent may run `<tool> <args>` under [policy].
///
/// [hasApproval] must be derived from a verified human authorisation for this
/// specific action — never from a value the agent supplied or asserted.
GuardDecision guardCommand(
  List<String> args,
  CommandPolicy policy, {
  bool hasApproval = false,
}) {
  final clean =
      args.map((a) => a.trim()).where((a) => a.isNotEmpty).toList(growable: false);

  if (clean.isEmpty) {
    return const GuardDecision(GuardVerdict.denied, 'no command given');
  }

  final path = commandPath(clean);
  if (path.isEmpty) {
    return const GuardDecision(
        GuardVerdict.denied, 'no command given, only flags');
  }

  for (final t in path) {
    for (final ch in _shellChars.split('')) {
      if (t.contains(ch)) {
        return GuardDecision(GuardVerdict.denied,
            'shell metacharacter in command path: "$t"');
      }
    }
  }

  // Checked across ALL arguments: the point of an elevation flag is that it
  // rides along with a command that otherwise looks fine.
  for (final a in clean) {
    if (policy.forbiddenFlags.contains(a.toLowerCase())) {
      return GuardDecision(
          GuardVerdict.denied,
          'blocked flag "$a": it suppresses a confirmation step that exists '
          'to involve a human');
    }
  }

  // Approval-gated commands are checked BEFORE the allowlist so the refusal
  // reason is the useful one ("needs sign-off") rather than a generic denial.
  for (final p in policy.requiresApproval) {
    if (_matches(path, p)) {
      return hasApproval
          ? GuardDecision(
              GuardVerdict.allowed, '${p.join(' ')} — approved for this action')
          : GuardDecision(GuardVerdict.requiresApproval,
              '${p.join(' ')} requires explicit human approval');
    }
  }

  for (final p in policy.allowed) {
    if (_matches(path, p)) {
      return GuardDecision(GuardVerdict.allowed, p.join(' '));
    }
  }

  // DEFAULT DENY — including commands that do not exist yet.
  for (final token in path) {
    final note = policy.dangerNotes[token];
    if (note != null) {
      return GuardDecision(GuardVerdict.denied, 'blocked: "$token" $note');
    }
  }

  return GuardDecision(
      GuardVerdict.denied,
      'not on the allowlist: "${path.join(' ')}". Anything not explicitly '
      'permitted is refused, including commands added in future releases.');
}
