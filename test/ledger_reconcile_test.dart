// The ledger checks itself against the bank.
//
// A derived balance — totalIncome minus totalExpenses — has one failure mode
// that never announces itself: miss a single transaction and every balance
// after it is wrong by that amount, permanently, while continuing to add up
// perfectly. You act on a number that has been quietly lying for weeks.
//
// Bank alerts carry the balance, so every transaction notification is also an
// independent statement of truth. The DIFFERENCE between what the bank says and
// what the rows say is not an estimate of the error — it is the error, in
// dinars.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/ledger_ingest.dart';
import 'package:homecoming_app/logic/ledger_reconcile.dart';
import 'package:homecoming_app/services/core/kai_cash_statement_parser.dart';

KaiBalanceObservation obs(String account, double balance, DateTime at) =>
    KaiBalanceObservation(account: account, balance: balance, at: at);

KaiCashImportCandidate row(
  String date,
  double amount, {
  KaiCashImportDirection direction = KaiCashImportDirection.expense,
  String description = 'thing',
}) =>
    KaiCashImportCandidate(
      date: date,
      description: description,
      amount: amount,
      direction: direction,
      source: 'test',
    );

final d1 = DateTime(2026, 8, 10, 9);
final d5 = DateTime(2026, 8, 15, 9);

void main() {
  group('reading the balance the bank volunteered', () {
    KaiBalanceReading? read(String body) => KaiLedgerIngest.readBalance(
          KaiBankAlert(sender: 'NBB', body: body, receivedAt: d1),
        );

    test('the common shapes are understood', () {
      for (final body in const [
        'BHD 12.500 spent at TALABAT. Bal: BHD 487.500',
        'BHD 12.500 spent. Balance BHD 487.500',
        'Purchase BHD 12.500. Available balance: 487.500',
      ]) {
        expect(read(body)?.balance, 487.5, reason: body);
      }
    });

    test('the account is picked up when the alert names it', () {
      expect(
        read('BHD 5.000 spent on card ending 1234. Bal: BHD 100.000')?.account,
        '1234',
      );
      expect(
        read('Debit from account XXXX5678. Balance BHD 100.000')?.account,
        '5678',
      );
    });

    test('an unattributed balance is kept, not forced into an account', () {
      // Still evidence that SOME account held that value. Guessing which one is
      // exactly the invention this avoids.
      expect(read('Spent BHD 5.000. Bal BHD 100.000')?.account, 'unknown');
    });

    test('no balance means null, never a guess', () {
      // A wrong balance is worse than none: it would reconcile a ledger that
      // should have raised its hand.
      expect(read('BHD 12.500 spent at TALABAT'), isNull);
      expect(read('Your statement is ready'), isNull);
    });
  });

  group('the gap is the amount unaccounted for', () {
    test('a complete ledger reconciles exactly', () {
      final r = KaiLedgerReconciler.reconcile(
        account: '1234',
        observations: [obs('1234', 500, d1), obs('1234', 470, d5)],
        rows: [row('2026-08-12', 30)],
      )!;
      expect(r.predictedBalance, 470);
      expect(r.gap, 0);
      expect(r.reconciled, isTrue);
      expect(r.verdict, 'reconciled');
    });

    test('a missing transaction surfaces as a number, not a silence', () {
      // The bank says 450. The rows only explain 30 of the 50 that left.
      final r = KaiLedgerReconciler.reconcile(
        account: '1234',
        observations: [obs('1234', 500, d1), obs('1234', 450, d5)],
        rows: [row('2026-08-12', 30)],
      )!;
      expect(r.gap, -20);
      expect(r.reconciled, isFalse);
      expect(r.verdict, 'unexplained_outflow');
    });

    test('unexplained money arriving is reported too', () {
      final r = KaiLedgerReconciler.reconcile(
        account: '1234',
        observations: [obs('1234', 500, d1), obs('1234', 600, d5)],
        rows: const [],
      )!;
      expect(r.gap, 100);
      expect(r.verdict, 'unexplained_inflow');
    });

    test('income and expense both move the prediction', () {
      final r = KaiLedgerReconciler.reconcile(
        account: '1234',
        observations: [obs('1234', 500, d1), obs('1234', 700, d5)],
        rows: [
          row('2026-08-12', 300, direction: KaiCashImportDirection.income),
          row('2026-08-13', 100),
        ],
      )!;
      expect(r.movementSinceAnchor, 200);
      expect(r.gap, 0);
    });

    test('a fils-level float tail is not a discrepancy', () {
      final r = KaiLedgerReconciler.reconcile(
        account: '1234',
        observations: [obs('1234', 500, d1), obs('1234', 470.001, d5)],
        rows: [row('2026-08-12', 30)],
      )!;
      expect(r.reconciled, isTrue);
    });
  });

  group('anchoring keeps drift from accumulating', () {
    test('only rows in the interval count', () {
      // A row after the latest observation belongs to the NEXT interval.
      // Counting it here would manufacture a gap out of a transaction the bank
      // simply has not reported a balance for yet.
      final r = KaiLedgerReconciler.reconcile(
        account: '1234',
        observations: [obs('1234', 500, d1), obs('1234', 470, d5)],
        rows: [
          row('2026-08-05', 999), // before the anchor: already settled
          row('2026-08-12', 30), // in the interval
          row('2026-08-20', 999), // after the latest: not yet reported
        ],
      )!;
      expect(r.rowsSinceAnchor, 1);
      expect(r.gap, 0);
    });

    test('a same-day row is counted, and the ambiguity is reported', () {
      // A statement line has a date and no time, so a row dated the same day as
      // the anchor could be either side of it. Counting risks double-counting;
      // excluding risks missing genuine same-day activity. Both make a phantom
      // gap, with opposite signs.
      //
      // It is counted — an observation at 09:00 really does precede a purchase
      // at 15:00 — but the count is surfaced so a caller can say "this gap may
      // be timing" rather than asserting money went missing.
      final r = KaiLedgerReconciler.reconcile(
        account: '1234',
        observations: [obs('1234', 500, d1), obs('1234', 500, d5)],
        rows: [row('2026-08-10', 40)],
      )!;
      expect(r.rowsSinceAnchor, 1);
      expect(r.ambiguousSameDayRows, 1);
      expect(r.gap, 40);
      expect(r.gapMayBeSameDayTiming, isTrue,
          reason: 'reported as possibly-timing, not asserted as missing money');
    });

    test('a gap with no same-day rows is a real discrepancy', () {
      final r = KaiLedgerReconciler.reconcile(
        account: '1234',
        observations: [obs('1234', 500, d1), obs('1234', 450, d5)],
        rows: [row('2026-08-12', 30)],
      )!;
      expect(r.ambiguousSameDayRows, 0);
      expect(r.gapMayBeSameDayTiming, isFalse,
          reason: 'nothing to blame on timing — this one is genuinely missing');
    });

    test('the first observation is an anchor, not a failure', () {
      final r = KaiLedgerReconciler.reconcile(
        account: '1234',
        observations: [obs('1234', 500, d1)],
        rows: const [],
      )!;
      expect(r.gap, isNull);
      expect(r.verdict, 'anchored');
      expect(r.reconciled, isTrue);
    });

    test('unsorted input cannot produce a wrong answer', () {
      final r = KaiLedgerReconciler.reconcile(
        account: '1234',
        observations: [obs('1234', 470, d5), obs('1234', 500, d1)],
        rows: [row('2026-08-12', 30)],
      )!;
      expect(r.anchorBalance, 500);
      expect(r.gap, 0);
    });
  });

  group('accounts are reconciled separately', () {
    test('a healthy account cannot hide an overdrawn one', () {
      final observations = [
        obs('1111', 500, d1), obs('1111', 500, d5),
        obs('2222', 500, d1), obs('2222', 300, d5),
      ];
      final rows = [row('2026-08-12', 50)];
      final a = KaiLedgerReconciler.reconcile(
          account: '1111', observations: observations, rows: rows)!;
      final b = KaiLedgerReconciler.reconcile(
          account: '2222', observations: observations, rows: rows)!;
      expect(a.gap, 50, reason: 'rows are not attributed per account yet');
      expect(b.gap, -150);
      expect(KaiLedgerReconciler.accountsIn(observations), ['1111', '2222']);
    });

    test('an unknown account yields nothing rather than a wrong answer', () {
      expect(
        KaiLedgerReconciler.reconcile(
          account: '9999',
          observations: [obs('1234', 500, d1)],
          rows: const [],
        ),
        isNull,
      );
    });
  });
}
