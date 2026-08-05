// prediction_ledger.dart — predictions locked before the evidence arrives.
//
// ── The hole this plugs ────────────────────────────────────────────────────
//
// `scout_calibration.dart` learns by comparing what Kai PREDICTED a market
// would do against what it actually did. That is the right mechanism, and it
// currently rests on an assumption nothing enforces: that the prediction was
// made *before* the outcome was known.
//
// Nothing stops a prediction being written into `RunEvidence.predictedScores`
// at any point in the run — including after the sales figures came in. Not from
// dishonesty; from ordinary convenience. The evidence object is assembled at
// the end, so the natural place to fill in a "prediction" is at the end, and a
// prediction recorded at the end is not a prediction. It is a description
// wearing a prediction's clothes, and calibrating on it teaches the model that
// it was right all along.
//
// This is the single most common way a self-improving loop fools itself, and it
// leaves no trace: the numbers all look correct, the calibration runs cleanly,
// and the reported accuracy climbs while the actual accuracy does not move.
//
// ── The fix: make the ORDER structural ─────────────────────────────────────
//
// A prediction is only admissible if it was locked before the first piece of
// evidence was harvested. Not "should be" — cannot be graded otherwise. The
// ledger refuses to grade a prediction whose lock timestamp is not strictly
// earlier than the first evidence timestamp, and it refuses to accept an edit
// to a locked prediction at all.
//
// This is pre-registration, borrowed from clinical trials, and it exists there
// for exactly this reason: the same researchers, with the same integrity,
// produce different results depending on whether the hypothesis was written
// down first.
//
// ── The checksum ───────────────────────────────────────────────────────────
//
// The rationale is checksummed at lock time. Not for security — nobody is
// attacking this — but so that a rationale silently rewritten to match the
// outcome fails to verify. Cheap, and it turns "I remember thinking that" into
// something checkable.
//
// ── What good calibration looks like ───────────────────────────────────────
//
// Brier score: mean squared error of probabilistic predictions, lower is
// better. 0.25 is what you get by always guessing 50%. Anything above that
// means the predictions are worse than useless — actively misleading — and it
// is far more common than people expect on early runs.
//
// Pure: zero imports. Deterministic. Provable in about a second.
library;

/// A prediction, locked at a moment in time and immutable thereafter.
class Prediction {
  final String runId;
  final String market;

  /// Probability in [0,1] that this run produces a surviving candidate.
  final double pSurvives;

  /// Probability in [0,1] that, if published, it earns anything at all.
  final double pEarns;

  /// Expected revenue in the first 30 days, in account currency. Nullable
  /// because a point estimate is sometimes genuinely unavailable — but the
  /// two probabilities are always required, because "I don't know" is itself
  /// a prediction of 0.5 and should be written as one.
  final double? expectedRevenue;

  /// Why. Free text, checksummed at lock time.
  final String rationale;

  /// Unix seconds. THE field this whole module exists to enforce.
  final int lockedAt;

  /// Checksum of `rationale` as it stood at lock time.
  final int rationaleChecksum;

  const Prediction({
    required this.runId,
    required this.market,
    required this.pSurvives,
    required this.pEarns,
    required this.rationale,
    required this.lockedAt,
    required this.rationaleChecksum,
    this.expectedRevenue,
  });

  bool get isWellFormed =>
      runId.trim().isNotEmpty &&
      market.trim().isNotEmpty &&
      lockedAt > 0 &&
      pSurvives >= 0 &&
      pSurvives <= 1 &&
      pEarns >= 0 &&
      pEarns <= 1 &&
      rationale.trim().length >= 20;

  /// Has the rationale been edited since lock?
  bool get rationaleIntact => checksumOf(rationale) == rationaleChecksum;
}

/// A small, stable, dependency-free string checksum (FNV-1a, 32-bit).
///
/// Not cryptographic and not pretending to be. It only needs to notice an
/// honest edit, and it does that for the cost of one pass over the string.
int checksumOf(String s) {
  var hash = 0x811c9dc5;
  for (var i = 0; i < s.length; i++) {
    hash ^= s.codeUnitAt(i);
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Create a locked prediction. The only way to make one with a valid checksum.
Prediction lockPrediction({
  required String runId,
  required String market,
  required double pSurvives,
  required double pEarns,
  required String rationale,
  required int nowUnix,
  double? expectedRevenue,
}) {
  return Prediction(
    runId: runId,
    market: market,
    pSurvives: pSurvives,
    pEarns: pEarns,
    rationale: rationale,
    lockedAt: nowUnix,
    rationaleChecksum: checksumOf(rationale),
    expectedRevenue: expectedRevenue,
  );
}

/// What actually happened.
class Outcome {
  final String runId;
  final bool survived;
  final double revenue;

  /// Unix seconds of the FIRST evidence harvested for this run. The comparison
  /// point that makes the prediction admissible or not.
  final int firstEvidenceAt;

  const Outcome({
    required this.runId,
    required this.survived,
    required this.revenue,
    required this.firstEvidenceAt,
  });

  bool get earned => revenue > 0;
}

/// The result of grading — or the reason grading was refused.
class Grade {
  final bool admissible;
  final String? refusal;

  /// Squared error on the survival prediction, in [0,1].
  final double survivalError;

  /// Squared error on the earnings prediction, in [0,1].
  final double earningsError;

  /// Signed: positive means Kai was OVERCONFIDENT about this run.
  final double bias;

  const Grade.refused(this.refusal)
      : admissible = false,
        survivalError = 0,
        earningsError = 0,
        bias = 0;

  const Grade.scored({
    required this.survivalError,
    required this.earningsError,
    required this.bias,
  })  : admissible = true,
        refusal = null;

  /// Mean Brier component for this single run.
  double get brier => (survivalError + earningsError) / 2;
}

/// Grade one prediction against one outcome.
///
/// Every refusal below is a case where scoring would produce a number that
/// looks like information and isn't. Returning a wrong number is strictly worse
/// than returning none, because a wrong number gets averaged into calibration
/// and quietly moves the rubric.
Grade grade(Prediction p, Outcome o) {
  if (p.runId != o.runId) {
    return const Grade.refused(
        'prediction and outcome are for different runs — not gradeable');
  }
  if (!p.isWellFormed) {
    return const Grade.refused(
        'prediction is malformed (missing ids, out-of-range probabilities, or '
        'a rationale too thin to have been a real forecast)');
  }
  if (!p.rationaleIntact) {
    return const Grade.refused(
        'the rationale was edited after lock — checksum mismatch. This is '
        'exactly the failure the ledger exists to catch, so the run is '
        'excluded rather than scored.');
  }
  if (o.firstEvidenceAt <= 0) {
    return const Grade.refused('outcome has no evidence timestamp to compare against');
  }
  if (p.lockedAt >= o.firstEvidenceAt) {
    return const Grade.refused(
        'the prediction was locked at or after the first evidence arrived. '
        'That is a description, not a forecast, and calibrating on it would '
        'teach confidence that was never earned.');
  }

  final actualSurvive = o.survived ? 1.0 : 0.0;
  final actualEarn = o.earned ? 1.0 : 0.0;
  final se = (p.pSurvives - actualSurvive) * (p.pSurvives - actualSurvive);
  final ee = (p.pEarns - actualEarn) * (p.pEarns - actualEarn);
  final bias = ((p.pSurvives - actualSurvive) + (p.pEarns - actualEarn)) / 2;

  return Grade.scored(survivalError: se, earningsError: ee, bias: bias);
}

/// Aggregate calibration across many graded runs.
class CalibrationReport {
  final int graded;
  final int refused;
  final double brier;

  /// Mean signed bias. Positive = systematically overconfident.
  final double bias;

  const CalibrationReport({
    required this.graded,
    required this.refused,
    required this.brier,
    required this.bias,
  });

  /// 0.25 is the score for always saying "50%". Worse than that means the
  /// predictions carry negative information.
  static const double kCoinFlipBrier = 0.25;

  bool get betterThanChance => graded > 0 && brier < kCoinFlipBrier;

  /// Null when there is not enough history to say anything honest. Three is
  /// the same floor `scout_calibration` uses, deliberately.
  String? get verdict {
    if (graded < 3) {
      return null;
    }
    final b = brier.toStringAsFixed(3);
    if (!betterThanChance) {
      return 'Brier $b across $graded run(s) — worse than guessing 50% every '
          'time. The predictions are not just uninformative, they are pointing '
          'the wrong way. Do not calibrate the rubric on these.';
    }
    final dir = bias > 0.1
        ? 'systematically OVERconfident (+${bias.toStringAsFixed(2)})'
        : bias < -0.1
            ? 'systematically UNDERconfident (${bias.toStringAsFixed(2)})'
            : 'roughly unbiased';
    return 'Brier $b across $graded run(s), better than chance, $dir.'
        '${refused > 0 ? ' $refused prediction(s) excluded as inadmissible.' : ''}';
  }
}

CalibrationReport gradeAll(List<Prediction> predictions, List<Outcome> outcomes) {
  final byRun = <String, Outcome>{};
  for (final o in outcomes) {
    byRun[o.runId] = o;
  }

  var graded = 0;
  var refused = 0;
  var brierSum = 0.0;
  var biasSum = 0.0;

  for (final p in predictions) {
    final o = byRun[p.runId];
    if (o == null) {
      refused++;
      continue;
    }
    final g = grade(p, o);
    if (!g.admissible) {
      refused++;
      continue;
    }
    graded++;
    brierSum += g.brier;
    biasSum += g.bias;
  }

  return CalibrationReport(
    graded: graded,
    refused: refused,
    brier: graded == 0 ? 0 : brierSum / graded,
    bias: graded == 0 ? 0 : biasSum / graded,
  );
}
