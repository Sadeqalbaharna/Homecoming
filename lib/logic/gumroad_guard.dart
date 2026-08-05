// gumroad_guard.dart — which storefront commands Kai is allowed to run.
//
// ── Why this file exists ────────────────────────────────────────────────────
//
// The Gumroad CLI is genuinely excellent for agents, and that is exactly the
// problem. Its command surface includes:
//
//     gumroad sales    refund
//     gumroad payouts  list, view, upcoming
//     gumroad licenses disable, revoke, rotate
//     gumroad auth     login, logout
//
// Kai has an unrestricted shell. So the moment that CLI is installed and holds
// a token, the factory's approval gate — which refuses to publish without
// Sadeq — becomes decoration: he could publish, refund a customer, or read
// payouts directly from `run_command`. The gate guarded the front door while
// the CLI opened a window. That was a real hole in the first design.
//
// ── The posture: allowlist, never denylist ─────────────────────────────────
//
// A denylist is a promise to have thought of everything, and the CLI can add
// commands in any release. So the rule here is DEFAULT DENY: if a command is
// not explicitly named safe, it is refused — including commands that do not
// exist yet. New CLI features arrive switched off, which is the only way this
// stays true over time.
//
// Two further protections:
//   • The token is never passed as an argument (it would show up in the process
//     list); the service injects it into the environment per invocation.
//   • Arguments are passed as a LIST, never a shell string, so `;` and `&&`
//     are inert data rather than command separators.
//
// Pure: zero imports. Provable in about a second.
library;

enum GuardVerdict {
  /// Safe. Kai may run this unsupervised.
  allowed,

  /// Permitted only with Sadeq's approval for this specific run.
  requiresApproval,

  /// No code path. Money, customer harm, or ambient authority.
  denied,
}

class GuardDecision {
  final GuardVerdict verdict;
  final String reason;
  const GuardDecision(this.verdict, this.reason);

  bool get isAllowed => verdict == GuardVerdict.allowed;
  bool get isDenied => verdict == GuardVerdict.denied;
}

/// Commands Kai may run on his own. Everything here is read-only or produces a
/// DRAFT — nothing goes live and nothing moves money.
///
/// `products create` and `products update` are safe precisely because a created
/// product is unpublished until `publish` runs, and `publish` is gated below.
const List<List<String>> kAllowedCommands = [
  ['user'],
  ['products', 'list'],
  ['products', 'view'],
  ['products', 'create'],
  ['products', 'update'],
  ['products', 'skus'],
  // Unpublishing is the SAFE direction — it takes something off sale. Kai may
  // always stop selling; he may not start.
  ['products', 'unpublish'],
  ['files', 'upload'],
  ['files', 'complete'],
  ['files', 'abort'],
  // Reading sales is the whole point of the learning loop.
  ['sales', 'list'],
  ['sales', 'view'],
];

/// Gated: allowed only with a valid approval for the current run.
const List<List<String>> kApprovalCommands = [
  ['products', 'publish'],
];

/// Named purely so the refusal can say WHY rather than "not allowed". These are
/// denied by the default-deny rule anyway — this list only improves the message.
const Map<String, String> kDangerNotes = {
  'refund': 'moves money back to a customer',
  'payouts': 'reads financial payout data',
  'licenses': 'can disable or revoke a paying customer\'s access',
  'auth': 'creates or destroys ambient authority',
  'delete': 'destructive and irreversible',
  'offer-codes': 'creates discounts, which is money',
  'webhooks': 'can redirect where sales data is sent',
  'subscribers': 'customer personal data, not needed to ship a product',
  'resend-receipt': 'contacts customers directly',
  'ship': 'contacts customers directly',
  // ── Found by reading the installed binary's own command list, NOT the README.
  // The published docs describe a far smaller tool than the one that shipped.
  // None of these were reachable anyway — default-deny had them covered before
  // anyone knew they existed, which is the argument for default-deny.
  'admin': 'Gumroad staff operations: issuing payouts, adding account credits, '
      'suspending users, disabling two-factor, resetting passwords',
  'emails': 'sends email to real customers',
  'pages': 'publishes storefront pages',
  'upsells': 'changes what buyers are offered at checkout',
  'refund-policy': 'changes the account-wide refund policy',
  'export': 'bulk customer data export',
  'buyers': 'customer personal data',
  'variants': 'changes what is sold and at what price',
  'variant-categories': 'changes what is sold and at what price',
  'custom-fields': 'changes what data is collected from buyers',
};

/// Flags Kai may never pass, whatever the command.
///
/// `--yes` skips the CLI's own confirmation prompts. Those prompts are a second
/// safety net underneath this guard, and an agent that can silence them has
/// quietly promoted itself. If a command needs confirming, it needs a human.
const Set<String> kForbiddenFlags = {'--yes', '-y'};

/// How many positional arguments a command may carry beyond its pattern.
///
/// One: `products view <id>`, `files upload <path>`. Nothing on the allowlist
/// legitimately takes two.
const int _kMaxPositionalArgs = 1;

/// Does the command path match this pattern?
///
/// ── This used to be a plain prefix match, and that was a real hole ─────────
///
/// `['user']` is on the allowlist because `gumroad user` just prints account
/// info. Under prefix matching, `user page publish` ALSO matched `['user']` —
/// and sailed straight through as allowed. That is a publish path, one of the
/// very ones this guard was written to close. A test caught it; the claim that
/// they were "already blocked by default-deny" was wrong, because default-deny
/// never got a look in: the allowlist matched first.
///
/// So a match now requires the pattern AND a length limit. `user` may carry an
/// argument; it may not carry a subcommand. Depth is authority.
bool _matches(List<String> args, List<String> pattern) {
  if (args.length < pattern.length) return false;
  if (args.length > pattern.length + _kMaxPositionalArgs) return false;
  for (var i = 0; i < pattern.length; i++) {
    if (args[i] != pattern[i]) return false;
  }
  return true;
}

/// Shell control characters. Args are passed to Process.run as a LIST, never a
/// shell string, so these are inert today — but a guard whose safety depends on
/// how the caller happens to execute it is not a boundary. Rejecting them here
/// keeps this file true even if the execution path changes later.
const String _shellChars = r';&|`$<>' '\n\r';

/// The leading tokens up to the first flag.
///
/// This distinction matters: a product name legitimately contains anything —
/// `--name "Refund Policy Template"` is a real listing. Scanning the whole
/// argument list for dangerous words would block honest work, and scanning
/// nothing would miss `sales refund`. The command is the part before the first
/// flag; everything after is data.
List<String> _commandPath(List<String> clean) {
  final out = <String>[];
  for (final a in clean) {
    if (a.startsWith('-')) break;
    out.add(a);
  }
  return out;
}

/// Decide whether Kai may run `gumroad <args>`.
///
/// [hasApproval] must come from a verified HumanApproval for the CURRENT run —
/// never from a tool argument, and never from anything Kai can assert.
GuardDecision guardGumroad(List<String> args, {bool hasApproval = false}) {
  final clean = args
      .map((a) => a.trim())
      .where((a) => a.isNotEmpty)
      .toList(growable: false);

  if (clean.isEmpty) {
    return const GuardDecision(GuardVerdict.denied, 'no command given');
  }

  final path = _commandPath(clean);
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

  // Forbidden flags are checked across ALL arguments, not just the command
  // path — the whole point of --yes is that it rides along with a command that
  // otherwise looks fine.
  for (final a in clean) {
    if (kForbiddenFlags.contains(a.toLowerCase())) {
      return GuardDecision(GuardVerdict.denied,
          'blocked flag "$a": it skips the CLI\'s own confirmation prompts, '
          'which are a safety net I do not get to switch off');
    }
  }

  // Approval-gated commands are checked BEFORE the allowlist so the refusal
  // reason is the honest one ("needs Sadeq") rather than a generic denial.
  for (final p in kApprovalCommands) {
    if (_matches(path, p)) {
      if (hasApproval) {
        return GuardDecision(GuardVerdict.allowed,
            '${p.join(' ')} — approved by Sadeq for this run');
      }
      return GuardDecision(
          GuardVerdict.requiresApproval,
          '${p.join(' ')} puts a product on sale under his name. '
          'That is his to authorise, not mine. Ask him.');
    }
  }

  for (final p in kAllowedCommands) {
    if (_matches(path, p)) {
      return GuardDecision(GuardVerdict.allowed, p.join(' '));
    }
  }

  // DEFAULT DENY — including commands that don't exist yet.
  for (final token in path) {
    final note = kDangerNotes[token];
    if (note != null) {
      return GuardDecision(
          GuardVerdict.denied, 'blocked: "$token" $note');
    }
  }
  return GuardDecision(GuardVerdict.denied,
      'not on the allowlist: "${path.join(' ')}". Anything not explicitly '
      'permitted is refused, including new commands.');
}
