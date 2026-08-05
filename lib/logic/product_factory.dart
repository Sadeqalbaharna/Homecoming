// product_factory.dart — the spine of factory mode.
//
// Sadeq's goal, verbatim: Kai should autonomously (once factory mode is
// activated) research gaps, build the product, list it and wire it to a pay
// portal, then study views/clicks/sales/reviews to improve the next one.
//
// ── Why this is a gated state machine and not a prompt ───────────────────────
//
// "Autonomous" without gates is just a long unsupervised turn, and the failure
// modes here are not cosmetic: shipping junk under Sadeq's name, listing a
// product nobody asked for, or touching money. A directive saying "check with
// me before publishing" is advice, and we already know what advice is worth
// when the model is mid-flow and excited — the sentience ladder needed
// CapabilityState in the type system before he'd stop claiming 7/7, and
// product_scout needed the refusal in code before "cite your evidence" meant
// anything.
//
// So the perimeter is structural:
//
//   • every stage advance requires EVIDENCE, not a claim of progress
//   • publishing and anything touching money REQUIRE a human approval token
//     that only Sadeq can mint — there is no code path that fabricates one
//   • factory mode is a master switch; off means nothing advances at all
//
// ── What is honestly automatable ─────────────────────────────────────────────
//
// Marketplace accounts and pay portals need KYC — identity and tax details
// legally tied to a person. No agent can or should do that. Sadeq does the
// one-time account setup; after that, listing creation and sales readback are
// API work Kai can own. That's why `awaitingApproval` exists as a real stop,
// not a formality.
//
// Pure: zero imports. Provable in about a second.
library;

/// The stages of one product run, in order. A run only ever moves forward, or
/// back to [scouting] when a gate refuses.
enum FactoryStage {
  /// Harvesting signals and scoring candidates (see product_scout.dart).
  scouting,

  /// A surviving candidate has been chosen and specced: scope, cuts, price,
  /// channel.
  specced,

  /// The artifact is being produced.
  building,

  /// The artifact passed its own quality gates — tests, build, completeness.
  /// "It compiles" is evidence; "it's done" is not.
  verified,

  /// Listing copy, assets, price and file bundle are prepared and ready to go.
  listingReady,

  /// HUMAN GATE. Nothing past here happens without Sadeq. Publishing puts his
  /// name on it and money behind it.
  awaitingApproval,

  /// Live on a marketplace, with a URL.
  published,

  /// Collecting views, clicks, sales, reviews.
  measuring,

  /// Outcome recorded against the original prediction — the loop that makes
  /// the next run better. Without this a factory is just a generator.
  learned,
}

/// Why a stage advance was refused. Returned instead of a bare `false` so Kai
/// can say what's missing rather than retrying blindly.
class GateRefusal {
  final FactoryStage from;
  final String reason;
  const GateRefusal(this.from, this.reason);
  @override
  String toString() => 'refused at ${from.name}: $reason';
}

/// A token proving Sadeq personally approved crossing the human gate.
///
/// Deliberately not constructible from anything Kai controls: it carries who
/// approved, when, and what exactly was approved. There is no default, no
/// empty constructor, and no "assumed" variant. If it's absent, the gate is
/// shut — which is the entire safety model.
class HumanApproval {
  /// Who approved. Must be non-empty.
  final String approvedBy;

  /// Epoch millis.
  final int approvedAt;

  /// What was approved — the run id. An approval for one run can never be
  /// replayed onto another.
  final String runId;

  /// Optional cap Sadeq attaches: the price he agreed to list at.
  final num? approvedPrice;

  const HumanApproval({
    required this.approvedBy,
    required this.approvedAt,
    required this.runId,
    this.approvedPrice,
  });

  bool get isValid => approvedBy.trim().isNotEmpty && approvedAt > 0 && runId.trim().isNotEmpty;
}

/// The evidence a run has accumulated. Each field is the proof required by a
/// specific gate — the gates read facts, never intentions.
class RunEvidence {
  /// A surviving scout verdict was produced (product_scout: strong or weak).
  final bool hasSurvivingCandidate;

  /// Spec names scope, what's cut, price, and channel.
  final bool specComplete;

  /// The built artifact exists at a path.
  final String? artifactPath;

  /// Quality gates actually ran and passed.
  final bool testsPassed;
  final bool buildPassed;

  /// Listing assets prepared: copy, price, files.
  final bool listingPrepared;

  /// Live marketplace URL, once published.
  final String? liveUrl;

  /// Observed outcomes. Null until measured.
  final int? views;
  final int? sales;

  /// Days the listing has been live and observed. A single day of data is
  /// noise, and learning from noise is worse than not learning.
  final int observedDays;

  /// The scout's scores for the candidate this run chose, captured BEFORE
  /// anything shipped.
  ///
  /// Without this there is nothing to calibrate against: "it sold 4 copies" is
  /// a fact, but "it sold 4 copies and you predicted distribution 5/5" is a
  /// lesson. A prediction recorded after the outcome is not a prediction.
  final Map<String, int>? predictedScores;

  const RunEvidence({
    this.hasSurvivingCandidate = false,
    this.specComplete = false,
    this.artifactPath,
    this.testsPassed = false,
    this.buildPassed = false,
    this.listingPrepared = false,
    this.liveUrl,
    this.views,
    this.sales,
    this.observedDays = 0,
    this.predictedScores,
  });
}

/// Minimum days of live data before a run may claim it has learned anything.
const int kMinObservationDays = 7;

/// Stages that can never be entered without a valid [HumanApproval].
const Set<FactoryStage> kHumanGated = {FactoryStage.published};

/// Is this a stage Kai may work through on his own?
bool isAutonomous(FactoryStage s) => !kHumanGated.contains(s);

/// The next stage in the sequence, or null at the end.
FactoryStage? nextStage(FactoryStage s) {
  const order = FactoryStage.values;
  final i = order.indexOf(s);
  return (i < 0 || i >= order.length - 1) ? null : order[i + 1];
}

/// One product run.
class FactoryRun {
  final String id;
  final FactoryStage stage;
  final RunEvidence evidence;

  /// Sadeq's master switch. Off = nothing advances, at all.
  final bool factoryModeOn;

  /// A stopped run is saved work, not active work. It may resume when Sadeq
  /// turns factory mode on again, but it must never silently keep working after
  /// a restart or after he toggles factory mode off.
  final int? stoppedAt;
  final String? stoppedReason;

  const FactoryRun({
    required this.id,
    this.stage = FactoryStage.scouting,
    this.evidence = const RunEvidence(),
    this.factoryModeOn = false,
    this.stoppedAt,
    this.stoppedReason,
  });

  bool get isStopped => stoppedAt != null;

  FactoryRun copyWith({
    FactoryStage? stage,
    RunEvidence? evidence,
    bool? factoryModeOn,
    Object? stoppedAt = _unchanged,
    Object? stoppedReason = _unchanged,
  }) =>
      FactoryRun(
        id: id,
        stage: stage ?? this.stage,
        evidence: evidence ?? this.evidence,
        factoryModeOn: factoryModeOn ?? this.factoryModeOn,
        stoppedAt: identical(stoppedAt, _unchanged) ? this.stoppedAt : stoppedAt as int?,
        stoppedReason: identical(stoppedReason, _unchanged)
            ? this.stoppedReason
            : stoppedReason as String?,
      );
}

const Object _unchanged = Object();

/// The result of attempting to advance. Either a new run, or a refusal with a
/// reason — never a silent no-op.
class AdvanceResult {
  final FactoryRun? run;
  final GateRefusal? refusal;
  const AdvanceResult.ok(this.run) : refusal = null;
  const AdvanceResult.refused(this.refusal) : run = null;
  bool get advanced => run != null;
}

/// Attempt to move a run to its next stage.
///
/// [approval] must be supplied to cross into a human-gated stage. Passing one
/// for a non-gated stage is harmless; omitting one for a gated stage is fatal
/// and always will be.
AdvanceResult advance(FactoryRun run, {HumanApproval? approval}) {
  if (run.isStopped) {
    return AdvanceResult.refused(
        GateRefusal(run.stage, 'run is stopped — Sadeq must start factory mode to resume it'));
  }

  if (!run.factoryModeOn) {
    return AdvanceResult.refused(
        GateRefusal(run.stage, 'factory mode is off — Sadeq has not activated it'));
  }

  final next = nextStage(run.stage);
  if (next == null) {
    return AdvanceResult.refused(
        GateRefusal(run.stage, 'run is complete; start a new one'));
  }

  final e = run.evidence;

  // ── The human perimeter. Checked FIRST so no amount of evidence can talk
  // its way across it, and so the refusal reason is always the honest one. ──
  if (kHumanGated.contains(next)) {
    if (approval == null || !approval.isValid) {
      return AdvanceResult.refused(GateRefusal(run.stage,
          'crossing into ${next.name} requires Sadeq\'s approval — publishing '
          'puts his name on it and money behind it'));
    }
    if (approval.runId != run.id) {
      return AdvanceResult.refused(GateRefusal(run.stage,
          'approval was issued for run ${approval.runId}, not ${run.id} — '
          'approvals are not transferable'));
    }
  }

  // ── Evidence gates. Each reads a fact, never a claim of progress. ──────────
  final String? missing = switch (next) {
    FactoryStage.specced => e.hasSurvivingCandidate
        ? null
        : 'no surviving candidate — scouting found no defensible gap',
    FactoryStage.building =>
      e.specComplete ? null : 'spec incomplete: needs scope, cuts, price, channel',
    FactoryStage.verified => (e.artifactPath == null || e.artifactPath!.trim().isEmpty)
        ? 'no artifact was produced'
        : null,
    FactoryStage.listingReady => (e.testsPassed && e.buildPassed)
        ? null
        : 'quality gates not passed — "it\'s done" is not evidence',
    FactoryStage.awaitingApproval =>
      e.listingPrepared ? null : 'listing not prepared: needs copy, price, files',
    FactoryStage.published => (e.liveUrl == null || e.liveUrl!.trim().isEmpty)
        ? null // URL appears as a RESULT of publishing, not a precondition
        : null,
    FactoryStage.measuring => (e.liveUrl == null || e.liveUrl!.trim().isEmpty)
        ? 'nothing to measure — no live URL'
        : null,
    FactoryStage.learned => e.observedDays < kMinObservationDays
        ? 'only ${e.observedDays} day(s) of data; need $kMinObservationDays — '
            'learning from noise is worse than not learning'
        : (e.sales == null || e.views == null)
            ? 'outcome not recorded — a run with no numbers taught nothing'
            : null,
    FactoryStage.scouting => null,
  };

  if (missing != null) {
    return AdvanceResult.refused(GateRefusal(run.stage, missing));
  }

  return AdvanceResult.ok(run.copyWith(stage: next));
}

/// Send a run back to scouting — used when a gate proves the candidate was
/// wrong, rather than pretending forward motion.
FactoryRun restart(FactoryRun run) =>
    run.copyWith(stage: FactoryStage.scouting, evidence: const RunEvidence());
