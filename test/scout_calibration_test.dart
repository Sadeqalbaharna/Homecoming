// Tests for scout_calibration.dart — the loop that makes run N+1 better than N.
//
// The tests that matter most here are the REFUSALS again. A calibrator that
// always has advice is the same failure as a scout that always finds a gap:
// it manufactures confidence out of noise. Learning from three runs is thin;
// learning from one is superstition.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/scout_calibration.dart';

void main() {
  const scored4 = {
    'distribution': 4,
    'monetization': 4,
    'headroom': 4,
    'feasibility': 4,
  };

  List<Outcome> repeat(Outcome o, int n) =>
      List.generate(n, (i) => Outcome(
            runId: '${o.runId}-$i',
            predicted: o.predicted,
            views: o.views,
            sales: o.sales,
            rating: o.rating,
            observedDays: o.observedDays,
          ));

  group('refusals', () {
    test('one run is an anecdote, not a lesson', () {
      final c = calibrate([
        const Outcome(
          runId: 'r1',
          predicted: scored4,
          views: 1000,
          sales: 0,
          observedDays: 10,
        )
      ]);
      expect(c.hasVerdict, isFalse);
      expect(c.refusal, contains('superstition'));
    });

    test('short observation windows are excluded entirely as noise', () {
      final c = calibrate(repeat(
        const Outcome(
          runId: 'r',
          predicted: scored4,
          views: 1000,
          sales: 0,
          observedDays: 2, // under the 7-day floor
        ),
        5,
      ));
      expect(c.hasVerdict, isFalse);
      expect(c.runsExcluded, 5);
    });

    test('zero views is excluded rather than dividing by zero', () {
      final c = calibrate([
        const Outcome(
          runId: 'r1',
          predicted: scored4,
          views: 0,
          sales: 0,
          observedDays: 30,
        )
      ]);
      expect(c.hasVerdict, isFalse);
    });
  });

  group('detecting systematic error', () {
    test('persistent optimism produces a downward correction', () {
      final c = calibrate(repeat(
        const Outcome(
          runId: 'flop',
          predicted: scored4, // scored 4s...
          views: 1000,
          sales: 0, // ...and sold nothing
          observedDays: 10,
        ),
        4,
      ));
      expect(c.hasVerdict, isTrue);
      expect(c.corrections.every((x) => x.bias > 0), isTrue);
      expect(c.corrections.every((x) => x.adjustment < 0), isTrue);
    });

    test('persistent pessimism produces an upward correction', () {
      final c = calibrate(repeat(
        const Outcome(
          runId: 'win',
          predicted: {
            'distribution': 1,
            'monetization': 1,
            'headroom': 1,
            'feasibility': 1,
          },
          views: 1000,
          sales: 40, // 4 per 100 — strong
          observedDays: 10,
        ),
        4,
      ));
      expect(c.corrections.every((x) => x.adjustment > 0), isTrue);
    });

    test('accurate scoring yields nothing actionable', () {
      final c = calibrate(repeat(
        const Outcome(
          runId: 'ok',
          predicted: scored4,
          views: 1000,
          sales: 12, // ~1.2 per 100 — deserved roughly a 4
          observedDays: 10,
        ),
        4,
      ));
      expect(c.actionable, isEmpty);
    });

    test('corrections are clamped so one bad quarter cannot erase the rubric', () {
      final c = calibrate(repeat(
        const Outcome(
          runId: 'disaster',
          predicted: {
            'distribution': 5,
            'monetization': 5,
            'headroom': 5,
            'feasibility': 5,
          },
          views: 5000,
          sales: 0,
          observedDays: 30,
        ),
        6,
      ));
      expect(c.corrections.every((x) => x.adjustment.abs() <= 2), isTrue);
    });

    test('bias is attributed PER AXIS, not blamed on the product as a whole', () {
      // Only distribution was over-scored; the rest were right.
      final c = calibrate(repeat(
        const Outcome(
          runId: 'mixed',
          predicted: {
            'distribution': 5,
            'monetization': 4,
            'headroom': 4,
            'feasibility': 4,
          },
          views: 1000,
          sales: 12,
          observedDays: 10,
        ),
        4,
      ));
      final dist = c.corrections.firstWhere((x) => x.axis == 'distribution');
      final mon = c.corrections.firstWhere((x) => x.axis == 'monetization');
      expect(dist.bias, greaterThan(mon.bias));
    });
  });

  group('applying what was learned', () {
    test('corrections adjust inputs and stay inside 0-5', () {
      final c = calibrate(repeat(
        const Outcome(
          runId: 'flop',
          predicted: scored4,
          views: 1000,
          sales: 0,
          observedDays: 10,
        ),
        4,
      ));
      final out = c.applyTo({
        'distribution': 1,
        'monetization': 0,
        'headroom': 5,
        'feasibility': 3,
      });
      expect(out.values.every((v) => v >= 0 && v <= 5), isTrue);
    });
  });

  group('what counts as success', () {
    test('conversion drives the verdict, not raw sales volume', () {
      const bigTrafficFewSales =
          Outcome(runId: 'a', predicted: scored4, views: 100000, sales: 50, observedDays: 10);
      const smallTrafficGoodRate =
          Outcome(runId: 'b', predicted: scored4, views: 100, sales: 5, observedDays: 10);
      expect(bigTrafficFewSales.sales, greaterThan(smallTrafficGoodRate.sales));
      expect(smallTrafficGoodRate.conversionPer100,
          greaterThan(bigTrafficFewSales.conversionPer100));
    });
  });
}
