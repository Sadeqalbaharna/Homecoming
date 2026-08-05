// Tests for prediction_ledger.dart — pre-registration for the scout.
//
// The load-bearing test is `a prediction locked AFTER the evidence is refused`.
// Everything else here supports it. Without that one rule, calibration learns
// from descriptions dressed as forecasts and reports rising accuracy that never
// happened.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/prediction_ledger.dart';

const rationale =
    'Marketplace shows 40 competitors but all above £80; the sub-£30 band is '
    'empty and reviews complain about setup time.';

void main() {
  Prediction pred({
    String runId = 'r1',
    double ps = 0.7,
    double pe = 0.3,
    String why = rationale,
    int lockedAt = 100,
  }) =>
      lockPrediction(
        runId: runId,
        market: 'salon stock sheets',
        pSurvives: ps,
        pEarns: pe,
        rationale: why,
        nowUnix: lockedAt,
      );

  Outcome out({
    String runId = 'r1',
    bool survived = true,
    double revenue = 10,
    int firstEvidenceAt = 200,
  }) =>
      Outcome(
        runId: runId,
        survived: survived,
        revenue: revenue,
        firstEvidenceAt: firstEvidenceAt,
      );

  group('the ordering rule — the whole point', () {
    test('a prediction locked BEFORE the evidence is admissible', () {
      expect(grade(pred(lockedAt: 100), out(firstEvidenceAt: 200)).admissible,
          isTrue);
    });

    test('a prediction locked AFTER the evidence is refused', () {
      final g = grade(pred(lockedAt: 300), out(firstEvidenceAt: 200));
      expect(g.admissible, isFalse);
      expect(g.refusal, contains('description, not a forecast'));
    });

    test('locked at EXACTLY the evidence timestamp is refused', () {
      // Simultaneity is indistinguishable from hindsight; refuse rather than
      // give the benefit of the doubt to the party being graded.
      expect(grade(pred(lockedAt: 200), out(firstEvidenceAt: 200)).admissible,
          isFalse);
    });

    test('an outcome with no evidence timestamp cannot be graded', () {
      expect(grade(pred(), out(firstEvidenceAt: 0)).admissible, isFalse);
    });
  });

  group('tamper detection', () {
    test('an unedited rationale verifies', () {
      expect(pred().rationaleIntact, isTrue);
    });

    test('a rationale rewritten after the fact fails the checksum', () {
      final p = pred();
      final tampered = Prediction(
        runId: p.runId,
        market: p.market,
        pSurvives: p.pSurvives,
        pEarns: p.pEarns,
        rationale: 'I always said this one would work',
        lockedAt: p.lockedAt,
        rationaleChecksum: p.rationaleChecksum, // the OLD checksum
      );
      expect(tampered.rationaleIntact, isFalse);
      expect(grade(tampered, out()).refusal, contains('checksum'));
    });

    test('the checksum is stable across calls', () {
      expect(checksumOf(rationale), checksumOf(rationale));
    });

    test('different text gives a different checksum', () {
      expect(checksumOf(rationale) == checksumOf('$rationale.'), isFalse);
    });
  });

  group('malformed predictions', () {
    test('a rationale too thin to be a real forecast is refused', () {
      expect(grade(pred(why: 'dunno'), out()).admissible, isFalse);
    });

    test('an out-of-range probability is refused', () {
      expect(grade(pred(ps: 1.7), out()).admissible, isFalse);
    });

    test('a prediction for a different run is refused', () {
      expect(grade(pred(runId: 'r1'), out(runId: 'r2')).admissible, isFalse);
    });
  });

  group('scoring', () {
    test('a perfect prediction scores 0', () {
      expect(grade(pred(ps: 1, pe: 1), out(survived: true, revenue: 5)).brier,
          closeTo(0, 1e-9));
    });

    test('a maximally wrong prediction scores 1', () {
      expect(grade(pred(ps: 0, pe: 0), out(survived: true, revenue: 5)).brier,
          closeTo(1, 1e-9));
    });

    test('a coin flip scores exactly the chance baseline', () {
      expect(grade(pred(ps: 0.5, pe: 0.5), out()).brier,
          closeTo(CalibrationReport.kCoinFlipBrier, 1e-9));
    });

    test('overconfidence reads as positive bias', () {
      expect(
          grade(pred(ps: 0.9, pe: 0.9), out(survived: false, revenue: 0)).bias,
          greaterThan(0));
    });

    test('underconfidence reads as negative bias', () {
      expect(grade(pred(ps: 0.1, pe: 0.1), out(survived: true, revenue: 5)).bias,
          lessThan(0));
    });
  });

  group('aggregate calibration', () {
    test('inadmissible predictions are excluded, not scored', () {
      final report = gradeAll(
        [pred(runId: 'r1', lockedAt: 100), pred(runId: 'r2', lockedAt: 300)],
        [out(runId: 'r1'), out(runId: 'r2')],
      );
      expect(report.graded, 1);
      expect(report.refused, 1);
    });

    test('a prediction with no matching outcome is refused, not ignored', () {
      final report = gradeAll([pred(runId: 'r9')], [out(runId: 'r1')]);
      expect(report.graded, 0);
      expect(report.refused, 1);
    });

    test('fewer than three graded runs yields no verdict at all', () {
      final report = gradeAll([pred()], [out()]);
      expect(report.verdict, isNull);
    });

    test('predictions worse than chance are called out as unusable', () {
      final preds = [
        for (var i = 0; i < 4; i++) pred(runId: 'r$i', ps: 0.95, pe: 0.95),
      ];
      final outs = [
        for (var i = 0; i < 4; i++)
          out(runId: 'r$i', survived: false, revenue: 0),
      ];
      final report = gradeAll(preds, outs);
      expect(report.betterThanChance, isFalse);
      expect(report.verdict, contains('worse than guessing'));
      expect(report.verdict, contains('Do not calibrate'));
    });

    test('good predictions are reported as better than chance', () {
      final preds = [
        for (var i = 0; i < 4; i++) pred(runId: 'r$i', ps: 0.9, pe: 0.9),
      ];
      final outs = [
        for (var i = 0; i < 4; i++)
          out(runId: 'r$i', survived: true, revenue: 5),
      ];
      final report = gradeAll(preds, outs);
      expect(report.betterThanChance, isTrue);
      expect(report.verdict, contains('better than chance'));
    });
  });
}
