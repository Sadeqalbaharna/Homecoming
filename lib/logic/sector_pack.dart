// sector_pack.dart — turning "we can do this for other sectors" into arithmetic.
//
// ── The claim being tested ─────────────────────────────────────────────────
//
// Sadeq, 2026-07-21: "once we create this for F&B, we can create it for other
// market sectors too, with almost zero reinvestment."
//
// He is mostly right, and the evidence is his own: the bar version of the
// costing console reused sixteen of nineteen tabs from the kitchen version and
// needed exactly three genuinely new things (pour cost, bottle yield, ABV).
// That is a measured reuse rate, not a hopeful one.
//
// But "almost zero" is the kind of phrase that is true right up until someone
// budgets on it. This module exists so the number stops being a feeling. A new
// vertical declares what it needs; the module reports what is genuinely reused,
// what must be built, and — the part everyone skips — whether there is any way
// to SELL it.
//
// ── What is actually sector-agnostic ───────────────────────────────────────
//
// Strip the vocabulary from the tavern console and what's left is a
// bill-of-materials costing and variance engine. None of these know anything
// about food:
//
//   • nested sub-assemblies (a batch recipe inside a dish)
//   • three-tier unit conversion (purchase → usage → count)
//   • cost roll-up with a cycle guard
//   • theoretical consumption vs physical count = variance
//   • supplier ledger, invoice history, AP
//   • versatility (how many outputs consume an input)
//   • audit trail, roles, login
//
// Rename "recipe" to "treatment" and it costs a salon. To "job" and it costs a
// workshop. To "procedure" and it costs a dental practice. The engine is the
// asset; the vocabulary is a config file.
//
// ── What is never free, and why this module leads with it ──────────────────
//
// Three things do NOT transfer, and one of them decides everything:
//
//   1. Domain vocabulary and unit model — cheap, a day.
//   2. Benchmark targets and detectors — medium. 35% food cost and 20% pour
//      cost were sector facts, learned by operating. A salon's equivalent has
//      to be researched or it is a made-up number in a product that claims
//      authority.
//   3. DISTRIBUTION AND CREDIBILITY — the expensive one, and it doesn't scale
//      with code at all. In F&B his operatorFit is maximal: he runs one, he
//      bought the competing product, he can answer any question a buyer asks.
//      In dental it is zero. Same engine, same three days, completely different
//      odds.
//
// So `validate()` refuses a pack with no route to a buyer even when every
// technical field is perfect. A vertical you cannot sell is not a cheap
// vertical; it is a free way to spend three days.
//
// Pure: zero imports. Deterministic. Provable in about a second.
library;

/// How the operator is connected to this sector. The axis Sadeq forced into
/// the product rubric, applied here to whole verticals.
enum OperatorAccess {
  /// He operates in this sector himself. Maximum credibility.
  operatesIn,

  /// He doesn't, but someone who does will open doors and answer questions.
  warmIntroduction,

  /// A named person who will take a call. Thin, but real.
  singleContact,

  /// Nobody. Cold outreach into a domain whose language he does not speak.
  none,
}

/// One unit-conversion tier. F&B needed three (purchase/usage/count); most
/// sectors need two or three, and a few need four.
class UnitTier {
  final String name;
  final String example;

  const UnitTier(this.name, this.example);
}

/// A sector-specific anomaly detector. `unitSuspects` (which found the 7503%
/// Cluckin' Roast error) is the F&B instance; every sector has its own.
class Detector {
  final String id;
  final String description;

  /// Is it implemented, or merely listed? The difference between a plan and a
  /// product, and the reason this is a bool and not a comment.
  final bool implemented;

  const Detector(this.id, this.description, {this.implemented = false});
}

/// Everything that makes one vertical different from another.
class SectorPack {
  final String id;
  final String displayName;

  /// The rename table: engine concept → sector word.
  /// e.g. {'recipe': 'treatment', 'ingredient': 'product', 'dish': 'service'}
  final Map<String, String> vocabulary;

  /// The unit tiers this sector needs.
  final List<UnitTier> unitTiers;

  /// Benchmark cost ratios by department, e.g. {'kitchen': 0.35, 'bar': 0.20}.
  final Map<String, double> targets;

  /// Where those benchmarks came from. An unsourced benchmark is a guess
  /// printed in a confident font, and it is how a costing tool loses a customer
  /// permanently.
  final String targetSource;

  final List<Detector> detectors;

  /// Rows of realistic seed data. A demo with three items does not sell.
  final int seedRows;

  final OperatorAccess access;

  /// Named route to a first buyer. Free text, but it must exist.
  final String distributionRoute;

  const SectorPack({
    required this.id,
    required this.displayName,
    this.vocabulary = const {},
    this.unitTiers = const [],
    this.targets = const {},
    this.targetSource = '',
    this.detectors = const [],
    this.seedRows = 0,
    this.access = OperatorAccess.none,
    this.distributionRoute = '',
  });

  int get implementedDetectors =>
      detectors.where((d) => d.implemented).length;
}

/// Engine capabilities that every pack inherits at zero cost. Listed
/// explicitly so the reuse figure below is auditable rather than asserted.
const List<String> kSharedEngine = [
  'nested sub-assembly costing',
  'multi-tier unit conversion',
  'cost roll-up with cycle guard',
  'theoretical vs physical variance',
  'supplier ledger and AP',
  'invoice and receipt drill-down',
  'versatility index',
  'duplicate detection',
  'audit trail with attribution',
  'role-gated login',
  'import/export and backup',
  'editable everything (full CRUD)',
];

/// Work that cannot be inherited and must be done per sector.
const List<String> kPerSectorWork = [
  'vocabulary mapping',
  'unit model',
  'benchmark targets (sourced)',
  'sector-specific detectors',
  'seed data',
  'distribution route',
];

/// Words that mark a claim as aspiration rather than fact.
///
/// Found by testing: the original validator only checked that
/// `distributionRoute` was longer than ten characters, so "we could market to
/// salons" sailed through — the exact sentence the field exists to reject. A
/// length check measures effort, not content.
///
/// This does not detect vagueness in general; nothing cheap does. It detects
/// the specific tell, which is the conditional mood. A real route is stated in
/// the indicative: "my sister owns two salons and will pilot it." A fake one
/// reaches for "could", "would", "should be able to". Same for a benchmark:
/// "guessed", "assumed", "roughly" mean the number was invented.
const List<String> kHedgeWords = [
  'could',
  'would',
  'might',
  'maybe',
  'probably',
  'somehow',
  'guessed',
  'guessing',
  'assumed',
  'assuming',
  'i think',
  'presumably',
  'hopefully',
  'should be able',
];

/// Does this claim hedge? Word-boundary aware so "shouldering" is not a hedge.
bool isHedged(String claim) {
  var s = claim.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' ');
  s = ' ${s.replaceAll(RegExp(r'\s+'), ' ').trim()} ';
  for (final w in kHedgeWords) {
    if (s.contains(' $w ')) return true;
  }
  return false;
}

/// A blocker preventing this pack from shipping.
class PackBlocker {
  final String field;
  final String problem;

  /// True when this cannot be fixed by writing code. These are the ones that
  /// actually kill verticals, and they are listed first for that reason.
  final bool nonTechnical;

  const PackBlocker(this.field, this.problem, {this.nonTechnical = false});
}

/// Is this vertical ready to build?
///
/// Distribution is checked FIRST, deliberately — the same ordering the product
/// rubric uses, for the same reason. A pack that is technically flawless and
/// unsellable should fail before anyone feels good about the vocabulary table.
List<PackBlocker> validatePack(SectorPack p) {
  final out = <PackBlocker>[];

  // ── The non-technical gates, first ──
  if (p.access == OperatorAccess.none) {
    out.add(const PackBlocker(
      'access',
      'No operator access. In F&B the product sells because the seller runs '
      'one and speaks the language. Without that, this is a cold entry into a '
      'domain you cannot answer questions about — and the engine being free '
      'does not make the sale cheaper.',
      nonTechnical: true,
    ));
  }
  if (p.distributionRoute.trim().length < 10 ||
      isHedged(p.distributionRoute)) {
    out.add(const PackBlocker(
      'distributionRoute',
      'No named route to a first buyer. Name an actual person or channel, in '
      'the indicative mood. "We could market to salons" is not a route; '
      '"my sister owns two salons and will pilot it" is.',
      nonTechnical: true,
    ));
  }
  if (p.targets.isNotEmpty &&
      (p.targetSource.trim().length < 10 || isHedged(p.targetSource))) {
    out.add(const PackBlocker(
      'targetSource',
      'Benchmark targets with no solid source. 35% food cost was learned by '
      'operating; a guessed equivalent is a confident wrong number in the one '
      'screen the customer trusts most — and it only has to be wrong once.',
      nonTechnical: true,
    ));
  }

  // ── The technical gates ──
  if (p.id.trim().isEmpty || p.displayName.trim().isEmpty) {
    out.add(const PackBlocker('id', 'pack needs an id and a display name'));
  }
  if (p.vocabulary.length < 3) {
    out.add(const PackBlocker('vocabulary',
        'fewer than 3 renamed concepts — either the mapping is incomplete or '
        'this is not actually a distinct sector'));
  }
  if (p.unitTiers.length < 2) {
    out.add(const PackBlocker('unitTiers',
        'a costing engine needs at least two unit tiers (what you buy in, '
        'what you consume in)'));
  }
  if (p.targets.isEmpty) {
    out.add(const PackBlocker('targets',
        'no benchmark targets — without one the tool computes costs but never '
        'says whether a number is good, which is the entire value'));
  }
  if (p.seedRows < 25) {
    out.add(PackBlocker('seedRows',
        'only ${p.seedRows} seed rows. A demo that looks empty does not sell; '
        '25+ realistic rows is the floor.'));
  }
  if (p.implementedDetectors < 1) {
    out.add(const PackBlocker('detectors',
        'no implemented sector detector. Generic costing is a spreadsheet; '
        'catching a sector-specific error is the product.'));
  }

  return out;
}

/// The honest reuse figure, with the caveat attached.
class ReuseReport {
  final int inherited;
  final int required;
  final int done;
  final bool sellable;

  const ReuseReport({
    required this.inherited,
    required this.required,
    required this.done,
    required this.sellable,
  });

  /// Share of total capability inherited for free.
  double get reuseRatio {
    final total = inherited + required;
    return total == 0 ? 0 : inherited / total;
  }

  double get completion => required == 0 ? 1 : done / required;

  String get summary {
    final pct = (reuseRatio * 100).toStringAsFixed(0);
    final base = '$inherited of ${inherited + required} capabilities inherited '
        'from the engine ($pct% reuse). $done of $required sector-specific '
        'items done.';
    if (!sellable) {
      return '$base\n'
          'BUT: this pack has no operator access or no named buyer. The $pct% '
          'is real and it is also not the constraint — the code was never the '
          'expensive part. Fix distribution before building anything.';
    }
    return base;
  }
}

ReuseReport reuseReport(SectorPack p) {
  final blockers = validatePack(p);
  final nonTech = blockers.where((b) => b.nonTechnical).isNotEmpty;

  // Count how many per-sector items are actually complete.
  var done = 0;
  // Uses the SAME predicates as validatePack, hedge check included. A "done"
  // counter that is more forgiving than the validator is how a dashboard ends
  // up reporting 6/6 on a pack that cannot ship.
  if (p.vocabulary.length >= 3) done++;
  if (p.unitTiers.length >= 2) done++;
  if (p.targets.isNotEmpty &&
      p.targetSource.trim().length >= 10 &&
      !isHedged(p.targetSource)) {
    done++;
  }
  if (p.implementedDetectors >= 1) done++;
  if (p.seedRows >= 25) done++;
  if (p.distributionRoute.trim().length >= 10 &&
      !isHedged(p.distributionRoute)) {
    done++;
  }

  return ReuseReport(
    inherited: kSharedEngine.length,
    required: kPerSectorWork.length,
    done: done,
    sellable: !nonTech,
  );
}

/// The F&B pack, as actually built. Serves as the reference implementation and
/// as proof the abstraction fits something real rather than something imagined.
const SectorPack kFoodAndBeveragePack = SectorPack(
  id: 'fnb',
  displayName: 'Food & Beverage',
  vocabulary: {
    'output': 'menu item',
    'assembly': 'batch recipe',
    'input': 'ingredient',
    'department': 'kitchen / bar',
    'variance': 'wastage',
  },
  unitTiers: [
    UnitTier('purchase', 'a 5kg sack of flour'),
    UnitTier('recipe', 'grams used in a dish'),
    UnitTier('inventory', 'units counted on the shelf'),
  ],
  targets: {'kitchen': 0.35, 'bar': 0.20},
  targetSource:
      'operator knowledge — standard industry gross margin benchmarks, '
      'confirmed against the operator\'s own P&L',
  detectors: [
    Detector('unitSuspects',
        'cost ratios implying a 1000x unit-entry error (found 4 real ones)',
        implemented: true),
    Detector('dupScore', 'near-duplicate recipes, number-aware',
        implemented: true),
    Detector('overPour', 'bar variance beyond expected pour tolerance',
        implemented: true),
  ],
  seedRows: 400,
  access: OperatorAccess.operatesIn,
  distributionRoute:
      'operator runs a venue in Bahrain; direct sales to local independents, '
      'plus five validation conversations queued',
);
