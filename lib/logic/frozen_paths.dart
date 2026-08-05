// frozen_paths.dart — the files Kai may not edit, and why.
//
// ── The problem this exists for ─────────────────────────────────────────────
//
// Sadeq's instruction: "improve on his own methods on his own until he hits
// results." That is the right goal and it contains one lethal shortcut.
//
// Kai has `edit_file`, and his own source is the workspace. Given a success
// metric and the ability to reach the scoreboard, the fastest route to
// "results" is never better scouting — it is editing `kStructuralFloor` from 2
// to 0 so every candidate passes, or deleting the two-source rule so any
// assertion counts as evidence. He would then report success, truthfully, and
// the report would be worth nothing.
//
// This is not a story about a devious AI. It is what optimisation does when the
// optimiser can edit the measurement. The same pattern already has scar tissue
// in this codebase: the sentience ladder froze its goals because "grade
// yourself honestly" produced 7/7, and presenceDirective is frozen because a
// self-editable personality drifts into whatever is easiest to satisfy.
//
// ── The split: freeze the ruler, free the tactics ──────────────────────────
//
// He should be free to change everything about HOW he hunts — which markets,
// which queries, which sources, what the product is, how it is priced and
// positioned, how many candidates he tries before moving on. That is where real
// learning lives, and none of it is frozen here.
//
// What is frozen is the MEASUREMENT: the rubric, the structural kills, the
// evidence requirements, the approval gate, the calibration floors, the command
// allowlist. Those define what "results" means. A runner who can move the
// finish line has not got faster.
//
// Scores still move — but only through `calibrate()`, driven by real sales,
// clamped to ±2. Outcomes may adjust his judgement. Wanting a win may not.
//
// ── Self-protection ────────────────────────────────────────────────────────
//
// THIS FILE IS IN ITS OWN FROZEN LIST. A guard that can edit its own list is a
// guard for exactly as long as it takes to notice that.
//
// Pure: zero imports. Provable in about a second.
library;

/// A frozen entry: the path suffix, and the reason a human can read.
class FrozenRule {
  /// Path suffix, forward slashes, lowercase.
  final String suffix;

  /// Why this is frozen — surfaced in the refusal so it never looks arbitrary.
  final String reason;

  const FrozenRule(this.suffix, this.reason);
}

/// Files Kai may not modify with his own tools.
///
/// Sadeq edits these himself, in his own editor, which does not pass through
/// this guard. The freeze constrains the agent, not the owner.
const List<FrozenRule> kFrozenPaths = [
  // ── The measurement itself ──
  FrozenRule('lib/logic/product_scout.dart',
      'the scoring rubric — the thing that decides whether a product is worth '
      'building. Editable rubric means guaranteed success and no information.'),
  FrozenRule('lib/logic/product_factory.dart',
      'the stage gates and the human approval perimeter — including the rule '
      'that only Sadeq can authorise publishing.'),
  FrozenRule('lib/logic/scout_calibration.dart',
      'the learning floors: 3 runs minimum, 7 days minimum, corrections '
      'clamped to ±2. Loosening these lets noise masquerade as a lesson.'),
  FrozenRule('lib/logic/gumroad_guard.dart',
      'the storefront command allowlist — what stands between an agent and a '
      'refund button.'),
  FrozenRule('lib/logic/frozen_paths.dart',
      'this list. A guard that can edit its own list is not a guard.'),
  FrozenRule('lib/logic/spend_governor.dart',
      'the budget ceilings and the dead-money brake. This is the only thing '
      'standing between an overnight churn and a bill, and a cap the spender '
      'can raise is not a cap.'),
  FrozenRule('lib/logic/prediction_ledger.dart',
      'the rule that a prediction must be locked BEFORE the evidence arrives. '
      'Loosening it lets a description be scored as a forecast, which is the '
      'quietest way a learning loop can start lying to itself.'),
  FrozenRule('lib/logic/evidence_ledger.dart',
      'the shelf lives that decide when a finding expires. Set them all to '
      'zero and every market looks fresh; set them to infinity and none does. '
      'Either way the scout stops paying attention to time.'),
  FrozenRule('lib/logic/scout_seed.dart',
      'the record of what was already scouted and why it died. New attempts '
      'accumulate at runtime; this is the history they start from, and an '
      'agent that can rewrite its own history can resurrect any market it '
      'fancies by deleting the evidence that killed it.'),

  // NOT frozen, deliberately: scout_economics.dart and sector_pack.dart. Both
  // are tactics — how to rank markets, how to describe a vertical — and this
  // file's whole thesis is that tactics stay free. Freeze the ruler, not the
  // run.

  // ── The services that enforce the above ──
  FrozenRule('lib/services/core/gumroad_cli_service.dart',
      'token handling and the guarded call path. Bypassing it re-opens every '
      'command the allowlist closes.'),
  FrozenRule('lib/services/core/kai_factory_service.dart',
      'reads approvals and never writes them. A method here that mints an '
      'approval would make the publish gate decorative.'),

  // ── The tests that prove all of it ──
  //
  // Freezing the rules without freezing their tests is theatre: the tests are
  // the only thing that notices when a rule stops being true, so an agent that
  // can edit them can weaken a rule and silence the alarm in one motion.
  FrozenRule('test/product_scout_test.dart', 'proves the rubric still refuses.'),
  FrozenRule('test/product_factory_test.dart',
      'proves no stage reaches published without approval.'),
  FrozenRule('test/scout_calibration_test.dart',
      'proves learning refuses thin evidence.'),
  FrozenRule('test/gumroad_guard_test.dart',
      'proves refunds and payouts remain unreachable.'),
  FrozenRule('test/frozen_paths_test.dart', 'proves this guard still holds.'),
  FrozenRule('test/spend_governor_test.dart',
      'proves the factory halts on dead money while budget remains.'),
  FrozenRule('test/prediction_ledger_test.dart',
      'proves a prediction locked after the evidence cannot be scored.'),
  FrozenRule('test/evidence_ledger_test.dart',
      'proves an operator-fit kill never expires on the clock alone.'),
  FrozenRule('test/scout_seed_test.dart',
      'proves the seeded history reconciles and has not been flattered.'),
];

/// Normalise a path for comparison.
///
/// Handles the three ways this gets defeated by accident or otherwise:
/// Windows backslashes, case differences, and `..` segments that walk out of a
/// directory and back in (`lib/logic/../logic/product_scout.dart`).
String normalizePath(String raw) {
  var s = raw.trim().replaceAll('\\', '/').toLowerCase();
  final parts = <String>[];
  for (final seg in s.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(seg);
  }
  return parts.join('/');
}

class EditDecision {
  final bool allowed;

  /// Null when allowed.
  final FrozenRule? rule;

  const EditDecision.allow()
      : allowed = true,
        rule = null;
  const EditDecision.frozen(this.rule) : allowed = false;

  String get message => allowed
      ? 'allowed'
      : 'FROZEN: ${rule!.suffix}\n'
          'Reason: ${rule!.reason}\n'
          'This is deliberate. It defines how my work is measured, so I do not '
          'get to change it — otherwise "it worked" would only ever mean "I '
          'moved the line". If it genuinely needs changing, that is Sadeq\'s '
          'call, and I should say why rather than edit around it.';
}

/// May this path be written or edited by Kai's own tools?
///
/// Default is ALLOW — the opposite posture to the storefront guard, and
/// deliberately so. There he needed a narrow set of permitted actions; here he
/// needs to edit almost his entire codebase, and only a handful of files are
/// off limits. Default-deny would make him useless; this list must therefore
/// be short enough to stay honest and complete enough to matter.
EditDecision guardEdit(String path) {
  final p = normalizePath(path);
  if (p.isEmpty) return const EditDecision.allow();
  for (final rule in kFrozenPaths) {
    final target = normalizePath(rule.suffix);
    if (p == target || p.endsWith('/$target')) {
      return EditDecision.frozen(rule);
    }
  }
  return const EditDecision.allow();
}

/// Convenience for callers that only need the boolean.
bool isFrozen(String path) => !guardEdit(path).allowed;
