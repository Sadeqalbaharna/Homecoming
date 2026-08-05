// scout_calibration.dart — how the factory gets better instead of just busier.
//
// Sadeq's fourth goal: "study view, clicks, sales, reviews data to teach
// himself how to improve the next products."
//
// ── The trap this module exists to avoid ────────────────────────────────────
//
// The lazy version of "learning" is asking the model to read its own sales
// numbers and reflect. That produces a paragraph of plausible narrative —
// "I should have targeted a more niche audience" — which feels like insight,
// costs a token fortune, and changes nothing about the next run. It's the
// horoscope failure wearing a business-intelligence hat.
//
// Real learning here is narrow and boring: for each axis he scored BEFORE
// shipping, compare the score he gave to what the market actually did, and
// carry forward a correction. If he keeps rating distribution 4/5 on products
// that then sell three copies, his distribution scoring is optimistic by a
// measurable amount, and the fix is to subtract it next time — not to write an
// essay about it.
//
// So: predictions in, outcomes in, numeric corrections out. No prose, no model
// call, no opinion. Deterministic and free.
//
// ── Why bias is tracked per-AXIS and not overall ────────────────────────────
//
// "That product failed" teaches nothing — it doesn't say WHICH judgement was
// wrong. A product can have a genuinely great gap and still die because the
// channel was wrong. Only per-axis attribution can distinguish "I picked a bad
// market" from "I picked a good market and listed it where nobody looks", and
// those two mistakes have opposite remedies.
//
// Pure: zero imports. Provable in about a second.
library;

/// What a finished run actually did in the market.
class Outcome {
  final String runId;

  /// The scores the scout gave BEFORE shipping, 0–5 per axis name
  /// ('distribution', 'monetization', 'headroom', 'feasibility').
  final Map<String, int> predicted;

  final int views;
  final int sales;

  /// Average review score 0–5, when there are any reviews at all.
  final double? rating;

  /// Days of live data. Short windows are noise and are excluded.
  final int observedDays;

  const Outcome({
    required this.runId,
    required this.predicted,
    required this.views,
    required this.sales,
    this.rating,
    this.observedDays = 0,
  });

  /// Sales per hundred views. The honest headline number: it survives a product
  /// getting lots of traffic and converting none of it, which raw sales hides.
  double get conversionPer100 => views <= 0 ? 0 : (sales / views) * 100;
}

/// Minimum days before an outcome may vote. Matches the factory's own gate:
/// learning from noise is worse than not learning.
const int kMinCalibrationDays = 7;

/// Minimum finished runs before ANY correction is emitted. One product's
/// result is an anecdote; corrections built on anecdotes are superstition.
const int kMinRunsForCorrection = 3;

/// A product that sells at least this per 100 views counts as validated.
/// Deliberately low: for a paid digital product, 1-in-100 browsers buying is a
/// real result, not a triumph.
const double kSuccessConversion = 1.0;

/// How wrong one axis has been, and what to do about it.
class AxisCorrection {
  final String axis;

  /// Positive = he has been OVER-scoring this axis (optimistic).
  /// Negative = he has been UNDER-scoring it (pessimistic).
  final double bias;

  /// How many runs this is based on. Small samples get small corrections.
  final int sampleSize;

  const AxisCorrection({
    required this.axis,
    required this.bias,
    required this.sampleSize,
  });

  /// The integer adjustment to apply to future scores on this axis.
  ///
  /// Rounded toward zero and clamped to ±2, because a calibration that can
  /// swing a score by 5 isn't calibration, it's an override — and one unlucky
  /// quarter would erase a working rubric.
  int get adjustment {
    final a = -bias; // correct in the opposite direction to the error
    final r = a.abs() < 1.0 ? 0 : a.truncate();
    return r > 2 ? 2 : (r < -2 ? -2 : r);
  }

  bool get isActionable => adjustment != 0;

  String get note {
    if (!isActionable) {
      return '$axis: within tolerance across $sampleSize run(s) — leave it alone.';
    }
    final dir = adjustment < 0 ? 'OVER' : 'UNDER';
    return '$axis: consistently ${dir}-scored across $sampleSize run(s) '
        '(bias ${bias.toStringAsFixed(1)}) — apply $adjustment to future scores.';
  }
}

/// The whole verdict on how well the scout has been predicting.
class Calibration {
  final List<AxisCorrection> corrections;
  final int runsConsidered;
  final int runsExcluded;

  /// Null when there isn't enough evidence to say anything, which is a real and
  /// frequent answer.
  final String? refusal;

  const Calibration({
    this.corrections = const [],
    this.runsConsidered = 0,
    this.runsExcluded = 0,
    this.refusal,
  });

  bool get hasVerdict => refusal == null;

  List<AxisCorrection> get actionable =>
      corrections.where((c) => c.isActionable).toList(growable: false);

  /// Apply the learned corrections to a fresh set of scores, clamped 0–5.
  /// This is the ONLY place learning is allowed to touch a future decision —
  /// it adjusts inputs to the same rubric, it never bypasses the rubric.
  Map<String, int> applyTo(Map<String, int> scores) {
    final out = <String, int>{};
    scores.forEach((axis, v) {
      final c = corrections.where((x) => x.axis == axis);
      final adj = c.isEmpty ? 0 : c.first.adjustment;
      final n = v + adj;
      out[axis] = n < 0 ? 0 : (n > 5 ? 5 : n);
    });
    return out;
  }
}

/// Grade past predictions against what the market actually did.
///
/// The comparison is deliberately crude: a score of 0–5 is mapped onto the
/// success the product actually had, and the gap is the bias. Crude and honest
/// beats sophisticated and unfalsifiable.
Calibration calibrate(List<Outcome> outcomes) {
  final usable = outcomes
      .where((o) => o.observedDays >= kMinCalibrationDays && o.views > 0)
      .toList(growable: false);
  final excluded = outcomes.length - usable.length;

  if (usable.length < kMinRunsForCorrection) {
    return Calibration(
      runsConsidered: usable.length,
      runsExcluded: excluded,
      refusal: 'Only ${usable.length} usable run(s); need $kMinRunsForCorrection '
          'before correcting anything. Corrections built on anecdotes are '
          'superstition.',
    );
  }

  // Per axis: average (predicted score) − (what the market justified).
  final sums = <String, double>{};
  final counts = <String, int>{};

  for (final o in usable) {
    // What the outcome says the score SHOULD have been, on the same 0–5 scale.
    // At or above the success threshold the product earned a 4; well above, a 5;
    // no sales at all earned a 0.
    final conv = o.conversionPer100;
    final deserved = conv >= kSuccessConversion * 3
        ? 5.0
        : conv >= kSuccessConversion
            ? 4.0
            : conv > 0
                ? 2.0
                : 0.0;

    o.predicted.forEach((axis, score) {
      sums[axis] = (sums[axis] ?? 0) + (score - deserved);
      counts[axis] = (counts[axis] ?? 0) + 1;
    });
  }

  final corrections = <AxisCorrection>[];
  sums.forEach((axis, total) {
    final n = counts[axis] ?? 0;
    if (n == 0) return;
    corrections.add(AxisCorrection(
      axis: axis,
      bias: total / n,
      sampleSize: n,
    ));
  });

  corrections.sort((a, b) => b.bias.abs().compareTo(a.bias.abs()));

  return Calibration(
    corrections: corrections,
    runsConsidered: usable.length,
    runsExcluded: excluded,
  );
}
