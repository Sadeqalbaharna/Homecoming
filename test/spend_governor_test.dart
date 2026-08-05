// Tests for spend_governor.dart — the brake on overnight churn.
//
// The important tests here are the two that halt a factory which is still
// INSIDE its budget: `deadMoney` and `barren`. A ceiling only caps the damage;
// those two catch the failure while the damage is still small. Everything else
// in this file is arithmetic.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/spend_governor.dart';

const int day = 86400;
const int now = 1000000;

RunLedgerEntry e(int at, double spend,
        {bool survived = false, bool published = false, double revenue = 0}) =>
    RunLedgerEntry(
      at: at,
      spend: spend,
      survived: survived,
      published: published,
      revenue: revenue,
    );

SpendDecision run(List<RunLedgerEntry> ledger, double cost,
        {SpendLimits limits = const SpendLimits(),
        int at = now,
        List<SpendAuthorization> auths = const []}) =>
    authorizeRun(
      ledger: ledger,
      limits: limits,
      estimatedCost: cost,
      nowUnix: at,
      authorizations: auths,
    );

void main() {
  group('ceilings', () {
    test('a first run on an empty ledger is allowed', () {
      expect(run(const [], 1.0).allowed, isTrue);
    });

    test('a run above the per-run cap is refused', () {
      expect(run(const [], 5.0).cause, HaltCause.runTooExpensive);
    });

    test('the check happens BEFORE the spend, not after', () {
      // 8.00 already spent today against a 10.00 cap. A 2.50 run would land at
      // 10.50, so it is refused now — "we went slightly over" is not something
      // a governor gets to say afterwards.
      final ledger = [e(now - 3600, 8.0, survived: true)];
      expect(run(ledger, 2.5).cause, HaltCause.dailyExhausted);
      expect(run(ledger, 1.5).allowed, isTrue); // 9.50 fits
    });

    test('the daily cap blocks, then clears itself as the window rolls', () {
      final ledger = [e(now - 3600, 9.5, survived: true)];
      expect(run(ledger, 1.0).cause, HaltCause.dailyExhausted);
      expect(run(ledger, 1.0, at: now + day + 10).allowed, isTrue);
    });

    test('daily exhaustion does NOT need a human — it waits itself out', () {
      final ledger = [e(now - 3600, 9.5, survived: true)];
      expect(run(ledger, 1.0).needsHuman, isFalse);
    });

    test('the lifetime cap blocks a factory that is otherwise earning', () {
      final ledger = [
        for (var i = 1; i <= 60; i++)
          e(now - day * i - 100, 1.0, survived: true, revenue: i == 1 ? 2.0 : 0),
      ];
      final d = run(ledger, 1.0);
      expect(d.cause, HaltCause.lifetimeExhausted);
      expect(d.needsHuman, isTrue);
    });

    test('an authorization grants more budget without erasing history', () {
      final ledger = [
        for (var i = 1; i <= 60; i++)
          e(now - day * i - 100, 1.0, survived: true, revenue: i == 1 ? 2.0 : 0),
      ];
      final auth = const SpendAuthorization(
        authorizedBy: 'sadeq',
        authorizedAt: now,
        additionalLifetime: 20.0,
      );
      expect(run(ledger, 1.0, auths: [auth]).allowed, isTrue);
      expect(totalSpend(ledger), 60.0); // the record survives the top-up
    });

    test('a malformed authorization grants nothing', () {
      final ledger = [
        for (var i = 1; i <= 60; i++)
          e(now - day * i - 100, 1.0, survived: true, revenue: i == 1 ? 2.0 : 0),
      ];
      const bad = SpendAuthorization(
          authorizedBy: '  ', authorizedAt: now, additionalLifetime: 50);
      expect(run(ledger, 1.0, auths: const [bad]).allowed, isFalse);
    });
  });

  group('dead money — the brake that matters', () {
    test('halts on spend with zero revenue, while budget remains', () {
      final ledger = [
        for (var i = 0; i < 13; i++) e(now - day * (i + 2), 2.0, survived: true),
      ];
      final d = run(ledger, 1.0);
      expect(d.cause, HaltCause.deadMoney);
      expect(d.needsHuman, isTrue,
          reason: 'a loop that can clear its own halt has a pause, not a governor');
      expect(totalSpend(ledger) < const SpendLimits().lifetime, isTrue,
          reason: 'budget was NOT the thing that ran out — evidence was');
    });

    test('any revenue at all clears the dead-money brake', () {
      final ledger = [
        for (var i = 0; i < 13; i++)
          e(now - day * (i + 2), 2.0, survived: true, revenue: i == 0 ? 5.0 : 0),
      ];
      expect(run(ledger, 1.0).allowed, isTrue);
    });

    test('with no revenue, dead money fires far below the lifetime cap', () {
      final ledger = [
        for (var i = 0; i < 26; i++) e(now - day * (i + 2), 1.0, survived: true),
      ];
      expect(run(ledger, 1.0).cause, HaltCause.deadMoney);
      expect(totalSpend(ledger), 26.0);
    });
  });

  group('barren streak', () {
    test('halts after consecutive runs with nothing surviving', () {
      final ledger = [for (var i = 0; i < 8; i++) e(now - day * (i + 2), 0.5)];
      expect(run(ledger, 1.0).cause, HaltCause.barren);
    });

    test('seven barren runs is still bad luck, not a broken loop', () {
      final ledger = [for (var i = 0; i < 7; i++) e(now - day * (i + 2), 0.5)];
      expect(run(ledger, 1.0).allowed, isTrue);
    });

    test('a single survival resets the streak', () {
      final ledger = [e(1, 1.0), e(2, 1.0, survived: true), e(3, 1.0)];
      expect(barrenStreak(ledger), 1);
    });

    test('barren catches a cheap broken loop that dead money would miss', () {
      // 8 runs at 0.50 = 4.00 spent, nowhere near the 25.00 dead-money line.
      final ledger = [for (var i = 0; i < 8; i++) e(now - day * (i + 2), 0.5)];
      expect(totalSpend(ledger), 4.0);
      expect(run(ledger, 1.0).cause, HaltCause.barren);
    });
  });

  group('misconfiguration', () {
    test('a daily cap below the per-run cap is refused, not guessed at', () {
      expect(run(const [], 1.0, limits: const SpendLimits(perRun: 5, perDay: 3))
          .cause, HaltCause.misconfigured);
    });

    test('an unreachable dead-money brake is refused', () {
      expect(run(const [], 1.0, limits: const SpendLimits(deadMoneyThreshold: 99))
          .cause, HaltCause.misconfigured);
    });

    test('defaults are coherent', () {
      expect(const SpendLimits().incoherences, isEmpty);
    });
  });

  group('reporting', () {
    test('an empty ledger says so plainly', () {
      expect(spendReportLine(const []), contains('has not run yet'));
    });

    test('a losing ledger reports net negative', () {
      final ledger = [e(now, 10.0, survived: true, revenue: 4.0)];
      expect(spendReportLine(ledger), contains('net -6.00'));
    });

    test('a winning ledger reports net positive', () {
      final ledger = [e(now, 4.0, survived: true, published: true, revenue: 10.0)];
      expect(spendReportLine(ledger), contains('net +6.00'));
    });
  });
}
