// Tests for scout_economics.dart — the bandit that knows attempts cost money.
//
// The headline test is `cost-aware ranking prefers the cheap arm`, paired with
// `plain survival-rate ranking would prefer the expensive one`. Together they
// show the two policies actually disagree on realistic numbers — otherwise this
// module would be elaborate agreement with what already existed.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/scout_economics.dart';

void main() {
  // 50% survival at £2/attempt → a survival costs £4.
  const cheap = CostedArm(market: 'cheap', attempts: 10, survivals: 5, totalCost: 20);
  // 60% survival at £9/attempt → a survival costs £15.
  const rich = CostedArm(market: 'rich', attempts: 10, survivals: 6, totalCost: 90);
  // Cheapest per attempt of all, and has never produced anything.
  const dud = CostedArm(market: 'dud', attempts: 10, survivals: 0, totalCost: 1);

  group('unit economics', () {
    test('cost per survival', () {
      expect(cheap.costPerSurvival, closeTo(4.0, 1e-9));
      expect(rich.costPerSurvival, closeTo(15.0, 1e-9));
    });

    test('an arm that never produced costs infinity per survival, not zero', () {
      expect(dud.costPerSurvival, double.infinity);
      expect(dud.hasProduced, isFalse);
    });

    test('cost per attempt is not the same question as cost per survival', () {
      expect(dud.costPerAttempt, lessThan(cheap.costPerAttempt));
      expect(dud.costPerSurvival, greaterThan(cheap.costPerSurvival));
    });

    test('net and roi', () {
      const earner = CostedArm(
          market: 'e', attempts: 5, survivals: 2, totalCost: 10, totalRevenue: 25);
      expect(earner.net, closeTo(15, 1e-9));
      expect(earner.roi, closeTo(2.5, 1e-9));
    });
  });

  group('ranking', () {
    test('a higher survival RATE does not win if it costs more per survival', () {
      // Survival rate says rich (60% vs 50%). Economics says cheap (£4 vs £15).
      expect(rich.survivals / rich.attempts,
          greaterThan(cheap.survivals / cheap.attempts));
      expect(rankByEfficiency([cheap, rich]).first.market, 'cheap');
    });

    test('the cheapest arm loses if it has never produced anything', () {
      final r = rankByEfficiency([cheap, dud]);
      expect(r.first.market, 'cheap');
      final dudChoice = r.firstWhere((c) => c.market == 'dud');
      expect(dudChoice.efficiencyTerm, 0,
          reason: 'otherwise the loop optimises into doing nothing, carefully');
    });

    test('a never-scouted market ranks above everything', () {
      const fresh = CostedArm(market: 'fresh');
      expect(rankByEfficiency([cheap, rich, fresh]).first.market, 'fresh');
    });

    test('the best producing arm is normalised to efficiency 1.0', () {
      final r = rankByEfficiency([cheap, rich]);
      expect(r.firstWhere((c) => c.market == 'cheap').efficiencyTerm,
          closeTo(1.0, 1e-9));
    });

    test('ranking is deterministic and total', () {
      final a = rankByEfficiency([cheap, rich, dud]).map((c) => c.market).toList();
      final b = rankByEfficiency([dud, rich, cheap]).map((c) => c.market).toList();
      expect(a, b);
      expect(a.length, 3);
    });

    test('an empty arm list ranks to nothing rather than throwing', () {
      expect(rankByEfficiency(const []), isEmpty);
    });

    test('rationale says which case this is', () {
      expect(rankByEfficiency([const CostedArm(market: 'f')]).first.rationale,
          contains('never scouted'));
      expect(rankByEfficiency([dud]).first.rationale,
          contains('nothing has ever survived'));
    });
  });

  group('the number that decides whether to continue', () {
    test('cost of the next survival is the cheapest observed', () {
      expect(costOfNextSurvival([cheap, rich]), closeTo(4.0, 1e-9));
    });

    test('it is infinite when nothing has ever survived anywhere', () {
      expect(costOfNextSurvival([dud]), double.infinity);
    });

    test('under three attempts, no verdict is offered', () {
      expect(economics([const CostedArm(market: 'a', attempts: 2)]).verdict, isNull);
    });

    test('no revenue yet: the verdict leads with the cost of the next win', () {
      final v = economics([cheap, rich]);
      expect(v.profitable, isFalse);
      expect(v.verdict, contains('next surviving candidate costs about 4.00'));
      expect(v.verdict, contains('not the convergence curve'));
    });

    test('profitable is reported plainly', () {
      const winner = CostedArm(
          market: 'w', attempts: 5, survivals: 3, sales: 1,
          totalCost: 10, totalRevenue: 40);
      expect(economics([winner]).verdict, contains('Profitable'));
    });

    test('earning but losing money is not called profitable', () {
      const loser = CostedArm(
          market: 'l', attempts: 5, survivals: 3, sales: 1,
          totalCost: 40, totalRevenue: 10);
      final v = economics([loser]);
      expect(v.profitable, isFalse);
      expect(v.verdict, contains('Losing money'));
      expect(v.verdict, contains('Narrowing'));
    });
  });
}
