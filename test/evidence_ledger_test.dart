// Tests for evidence_ledger.dart — what was tried, and when it stops counting.
//
// Two opposite failures are being tested here at once: re-scouting a market
// that was already killed three times (amnesia), and never revisiting a market
// killed on an eleven-month-old competitor count (permanent write-off). The
// asymmetry test — operatorFit never expiring on time — is the one that
// protects the axis Sadeq insisted on.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/evidence_ledger.dart';

const int day = 86400;
const int now = 1000000000;

ScoutRecord rec(KillKind kind, int daysAgo,
        {String market = 'x', List<String> cites = const ['https://example.com/a']}) =>
    ScoutRecord(
      market: market,
      killedBy: kind,
      at: now - daysAgo * day,
      citations: cites,
    );

MarketAdvice advise(String m, List<ScoutRecord> rs) =>
    adviseMarket(market: m, allRecords: rs, nowUnix: now);

void main() {
  group('never scouted', () {
    test('an unknown market is worth a look', () {
      expect(advise('salons', const []).advice, ScoutAdvice.neverScouted);
      expect(advise('salons', const []).shouldScout, isTrue);
    });

    test('records for OTHER markets do not block this one', () {
      expect(advise('salons', [rec(KillKind.saturated, 1, market: 'bakeries')])
          .advice, ScoutAdvice.neverScouted);
    });

    test('market matching is case-insensitive', () {
      expect(advise('SALONS', [rec(KillKind.saturated, 1, market: 'salons')])
          .advice, ScoutAdvice.skipStillValid);
    });
  });

  group('shelf life by kill kind', () {
    test('a fresh saturation kill means skip', () {
      expect(advise('x', [rec(KillKind.saturated, 10)]).advice,
          ScoutAdvice.skipStillValid);
    });

    test('saturation expires — a competitor count is a snapshot, not a law', () {
      expect(advise('x', [rec(KillKind.saturated, 121)]).advice,
          ScoutAdvice.rescoutStale);
    });

    test('"nobody pays for this" outlives "it is crowded"', () {
      expect(advise('x', [rec(KillKind.noMonetization, 121)]).advice,
          ScoutAdvice.skipStillValid);
      expect(advise('x', [rec(KillKind.saturated, 121)]).advice,
          ScoutAdvice.rescoutStale);
    });

    test('noMonetization does eventually expire', () {
      expect(advise('x', [rec(KillKind.noMonetization, 731)]).advice,
          ScoutAdvice.rescoutStale);
    });

    test('"I found nothing" expires fastest — it is a fact about the search', () {
      expect(advise('x', [rec(KillKind.noEvidence, 91)]).advice,
          ScoutAdvice.rescoutStale);
      expect(advise('x', [rec(KillKind.noEvidence, 89)]).advice,
          ScoutAdvice.skipStillValid);
    });

    test('confidence decays linearly across the shelf life', () {
      expect(rec(KillKind.saturated, 60).confidence(now), closeTo(0.5, 1e-9));
      expect(rec(KillKind.saturated, 0).confidence(now), closeTo(1.0, 1e-9));
      expect(rec(KillKind.saturated, 200).confidence(now), 0);
    });
  });

  group('the operatorFit asymmetry', () {
    test('an operator-fit kill does not expire after ten years', () {
      expect(advise('x', [rec(KillKind.operatorFit, 3650)]).advice,
          ScoutAdvice.blockedOnOperator);
    });

    test('it overrules a fresher, weaker kill', () {
      expect(
          advise('x', [
            rec(KillKind.saturated, 1),
            rec(KillKind.operatorFit, 2000),
          ]).advice,
          ScoutAdvice.blockedOnOperator);
    });

    test('the reason names the human fix, not a waiting period', () {
      final a = advise('x', [rec(KillKind.operatorFit, 10)]);
      expect(a.reason, contains('Time does not clear this one'));
      expect(a.shouldScout, isFalse);
    });
  });

  group('amnesia — the expensive repeat', () {
    test('a market killed three times for the same reason is not re-bought', () {
      final rs = [
        rec(KillKind.saturated, 10),
        rec(KillKind.saturated, 40),
        rec(KillKind.saturated, 80),
      ];
      expect(advise('x', rs).advice, ScoutAdvice.skipRepeatedly);
      expect(advise('x', rs).reason, contains('same answer at full price'));
    });

    test('one kill is a skip; two of the same kind is a stronger skip', () {
      expect(advise('x', [rec(KillKind.saturated, 10)]).advice,
          ScoutAdvice.skipStillValid);
      expect(
          advise('x', [rec(KillKind.saturated, 10), rec(KillKind.saturated, 20)])
              .advice,
          ScoutAdvice.skipRepeatedly);
    });
  });

  group('uncited findings', () {
    test('a conclusion with no citation cannot go stale because it was never fresh', () {
      final r = rec(KillKind.saturated, 1, cites: const []);
      expect(r.confidence(now), 0);
      expect(advise('x', [r]).advice, ScoutAdvice.rescoutStale);
    });
  });

  group('the revisit queue', () {
    test('surfaces only expired markets', () {
      final rs = [
        rec(KillKind.saturated, 200, market: 'expired'),
        rec(KillKind.saturated, 5, market: 'fresh'),
        rec(KillKind.operatorFit, 500, market: 'blocked'),
      ];
      final q = revisitQueue(allRecords: rs, nowUnix: now);
      expect(q.map((a) => a.market), ['expired']);
    });

    test('fewer past kills rank first — least-burned market first', () {
      final rs = [
        rec(KillKind.saturated, 200, market: 'thrice'),
        rec(KillKind.saturated, 210, market: 'thrice'),
        rec(KillKind.saturated, 220, market: 'thrice'),
        rec(KillKind.saturated, 200, market: 'once'),
      ];
      final q = revisitQueue(allRecords: rs, nowUnix: now);
      expect(q.first.market, 'once');
    });

    test('an empty ledger yields an empty queue', () {
      expect(revisitQueue(allRecords: const [], nowUnix: now), isEmpty);
    });
  });

  group('savings', () {
    test('counts the scouting the ledger prevented', () {
      final rs = [
        rec(KillKind.saturated, 5, market: 'a'),
        rec(KillKind.noMonetization, 5, market: 'b'),
        rec(KillKind.saturated, 500, market: 'c'), // expired, not a saving
      ];
      final line = savingsLine(rs, now, 2.0);
      expect(line, contains('2 market(s)'));
      expect(line, contains('4.00'));
    });
  });
}
