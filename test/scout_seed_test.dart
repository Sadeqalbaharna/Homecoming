// Tests for scout_seed.dart — the history the policy starts from.
//
// A seed is the easiest place in a learning system to lie, because nothing
// checks it against reality and a flattering one produces nicer graphs
// immediately. So most of this file is internal-consistency arithmetic: the
// arms must add up to the records, the records must add up to the log, and the
// one market that survived must not also carry a kill.
//
// The behavioural tests then confirm the seed actually steers the policy —
// otherwise it is a document with Dart syntax.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/scout_seed.dart';
import 'package:homecoming_app/logic/scout_learning.dart';
import 'package:homecoming_app/logic/evidence_ledger.dart';

void main() {
  group('the seed adds up', () {
    test('every arm: attempts = survivals + kills', () {
      for (final a in kSeedMarketArms) {
        final killed = a.kills.values.fold<int>(0, (s, n) => s + n);
        expect(a.attempts, a.survivals + killed,
            reason: '${a.market} does not reconcile');
      }
    });

    test('the attempt log has one entry per attempt', () {
      final attempts =
          kSeedMarketArms.fold<int>(0, (s, a) => s + a.attempts);
      expect(kSeedAttemptLog.length, attempts);
    });

    test('survivals in the log match survivals in the arms', () {
      final survivals =
          kSeedMarketArms.fold<int>(0, (s, a) => s + a.survivals);
      expect(kSeedAttemptLog.where((b) => b).length, survivals);
    });

    test('there is one kill record per killed attempt', () {
      final killed = kSeedMarketArms.fold<int>(
          0, (s, a) => s + a.kills.values.fold<int>(0, (x, n) => x + n));
      expect(kSeedScoutRecords.length, killed);
    });

    test('every record cites something — no uncited conclusions', () {
      for (final r in kSeedScoutRecords) {
        expect(r.isCited, isTrue, reason: '${r.market} has no citation');
        expect(r.note.trim().length, greaterThan(20),
            reason: '${r.market} has no readable note');
      }
    });

    test('every kill record belongs to a market that has an arm', () {
      final markets = kSeedMarketArms.map((a) => a.market).toSet();
      for (final r in kSeedScoutRecords) {
        expect(markets, contains(r.market));
      }
    });

    test('the surviving market carries no kill record', () {
      expect(
          kSeedScoutRecords.any((r) => r.market == 'restaurant operations software'),
          isFalse);
    });

    test('nothing is dated in the future', () {
      for (final r in kSeedScoutRecords) {
        expect(r.at, lessThanOrEqualTo(kSeedWrittenAt));
      }
    });
  });

  group('the seed steers the policy', () {
    test('the only market that ever produced anything ranks first', () {
      final ranked = rankMarkets(kSeedMarketArms);
      expect(ranked.first.market, 'restaurant operations software');
      expect(ranked.first.exploitTerm, greaterThan(0));
    });

    test('twice-failed markets rank below once-failed ones', () {
      final ranked = rankMarkets(kSeedMarketArms);
      final names = ranked.map((c) => c.market).toList();
      expect(names.last, anyOf('flutter/dart developer tools', 'llm infrastructure'));
    });

    test('the cheapest kill is checked first — saturation killed the most', () {
      expect(checkOrder(kSeedMarketArms).first, KillCause.saturated);
    });

    test('no-monetization is checked second', () {
      expect(checkOrder(kSeedMarketArms)[1], KillCause.noMonetization);
    });

    test('convergence reads as improving, because it did', () {
      final c = measureConvergence(kSeedAttemptLog);
      expect(c.improving, isTrue);
      expect(c.earlyRate, 0.0, reason: 'every searched market died');
      expect(c.recentRate, greaterThan(0));
      expect(c.verdict, contains('Converging'));
    });

    test('the seed does not flatter itself with a smooth curve', () {
      // The first eight attempts all failed. A seed showing steady improvement
      // would be a nicer story and a false one.
      expect(kSeedAttemptLog.take(8).any((b) => b), isFalse);
      expect(kSeedAttemptLog.skip(8).every((b) => b), isTrue);
    });
  });

  group('the seed steers the evidence ledger', () {
    MarketAdvice advise(String m, {int? at}) => adviseMarket(
        market: m, allRecords: kSeedScoutRecords, nowUnix: at ?? kSeedWrittenAt);

    test('the winning market reads as never scouted — it came from his own workbook', () {
      expect(advise('restaurant operations software').advice,
          ScoutAdvice.neverScouted);
    });

    test('the operator-fit market is blocked, not merely skipped', () {
      expect(advise('flutter/dart developer tools').advice,
          ScoutAdvice.blockedOnOperator);
    });

    test('freshly killed markets are skipped today', () {
      for (final m in const [
        'llm infrastructure',
        'consumer fintech',
        'etsy ai printables',
        'restaurant training saas',
        'restaurant documents and templates',
      ]) {
        expect(advise(m).shouldScout, isFalse, reason: m);
      }
    });

    test('saturation findings expire after 120 days and reopen', () {
      const later = kSeedWrittenAt + 130 * 86400;
      expect(advise('consumer fintech', at: later).advice, ScoutAdvice.rescoutStale);
      expect(advise('etsy ai printables', at: later).advice, ScoutAdvice.rescoutStale);
    });

    test('"nobody pays for this" outlives "it is crowded"', () {
      const later = kSeedWrittenAt + 130 * 86400;
      expect(advise('llm infrastructure', at: later).advice,
          ScoutAdvice.skipStillValid);
    });

    test('operator fit never expires on the clock, even after ten years', () {
      const decade = kSeedWrittenAt + 3650 * 86400;
      expect(advise('flutter/dart developer tools', at: decade).advice,
          ScoutAdvice.blockedOnOperator);
    });

    test('the revisit queue is empty on day one and fills as findings age', () {
      expect(revisitQueue(allRecords: kSeedScoutRecords, nowUnix: kSeedWrittenAt),
          isEmpty);
      final later = revisitQueue(
          allRecords: kSeedScoutRecords, nowUnix: kSeedWrittenAt + 130 * 86400);
      expect(later, isNotEmpty);
    });
  });

  group('what is deliberately absent', () {
    test('the lesson is recorded as evidence, not as an instruction', () {
      // If this ever turns into "always do X", it has become a directive, and
      // directives are what this codebase does not trust.
      expect(kSeedLesson, isNot(contains('you must')));
      expect(kSeedLesson, contains('Ten markets, two survivors'));
    });
  });
}
