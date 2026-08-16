// One payment, however many times the bank mentions it.
//
// Al Salam emails a Transaction Notification and texts the same thing. Without
// a cross-channel identity that is two ledger rows for one payment, every
// transaction doubled, and a reconciliation gap the size of the day's spending.
//
// But the obvious key — date + amount + merchant — is dangerous, and Sadeq's
// own inbox proves it: two genuine coffees, same amount, same merchant, same
// day. Merging those eats 1.500 BHD silently, and silent loss is the exact
// failure this path exists to prevent.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/ledger_identity.dart';
import 'package:homecoming_app/services/core/kai_cash_statement_parser.dart';

KaiCashImportCandidate row({
  required double amount,
  required String source,
  String date = '2026-08-08',
  String description = 'THE COFFEE BEAN TEA MANAMA BH',
  KaiCashImportDirection direction = KaiCashImportDirection.expense,
}) =>
    KaiCashImportCandidate(
      date: date,
      description: description,
      amount: amount,
      direction: direction,
      source: source,
    );

KaiTransactionIdentity id({
  String? account = '94150000',
  double? balanceAfter,
  double amount = 1.5,
  KaiCashImportDirection direction = KaiCashImportDirection.expense,
}) =>
    KaiTransactionIdentity.of(
      account: account,
      balanceAfter: balanceAfter,
      amount: amount,
      direction: direction,
    );

void main() {
  group('the same payment down two pipes is one row', () {
    test('email and SMS about one transaction collapse', () {
      final d = KaiLedgerDeduper();
      // Identical payment, different channels — so different `source`, and
      // therefore different candidate fingerprints. Only the bank's stated
      // balance ties them together.
      final byEmail = row(amount: 1.5, source: 'alert:no-reply@alsalambank.com');
      final bySms = row(amount: 1.5, source: 'alert:ALSALAM');
      expect(byEmail.fingerprint, isNot(bySms.fingerprint),
          reason: 'this is why identity cannot be the fingerprint');

      expect(d.admit(byEmail, id(balanceAfter: 330.732)), isTrue);
      expect(d.admit(bySms, id(balanceAfter: 330.732)), isFalse);
      expect(d.recorded, 1);
    });
  });

  group('two identical coffees are two coffees', () {
    test('same amount, merchant and day stay separate', () {
      // Verbatim from the inbox:
      //   BHD 1.500 at THE COFFEE BEAN TEA ... Bal: 330.732 at 10:40
      //   BHD 1.500 at THE COFFEE BEAN TEA ... Bal: 329.232 at 12:06
      final d = KaiLedgerDeduper();
      expect(
        d.admit(row(amount: 1.5, source: 'alert:a'), id(balanceAfter: 330.732)),
        isTrue,
      );
      expect(
        d.admit(row(amount: 1.5, source: 'alert:b'), id(balanceAfter: 329.232)),
        isTrue,
        reason: 'a different resulting balance is a different payment',
      );
      expect(d.recorded, 2);
    });

    test('a float tail is the same balance, not a new payment', () {
      final d = KaiLedgerDeduper();
      d.admit(row(amount: 1.5, source: 'a'), id(balanceAfter: 330.732));
      expect(
        d.admit(row(amount: 1.5, source: 'b'),
            id(balanceAfter: 330.7320000001)),
        isFalse,
      );
    });
  });

  group('corroboration, so a coincidence cannot merge two payments', () {
    test('the same balance with a different amount does not collapse', () {
      final d = KaiLedgerDeduper();
      d.admit(row(amount: 1.5, source: 'a'), id(balanceAfter: 330.732));
      expect(
        d.admit(row(amount: 9.9, source: 'b'),
            id(balanceAfter: 330.732, amount: 9.9)),
        isTrue,
        reason: 'agreeing on balance but not amount means something is wrong',
      );
    });

    test('the same balance on a different account does not collapse', () {
      // Spending runs through ...94150000; Fawri credits land in ...55100100.
      final d = KaiLedgerDeduper();
      d.admit(row(amount: 1.5, source: 'a'), id(balanceAfter: 330.732));
      expect(
        d.admit(row(amount: 1.5, source: 'b'),
            id(account: '55100100', balanceAfter: 330.732)),
        isTrue,
      );
    });

    test('direction is part of identity', () {
      final d = KaiLedgerDeduper();
      d.admit(row(amount: 1.5, source: 'a'), id(balanceAfter: 330.732));
      expect(
        d.admit(
          row(amount: 1.5, source: 'b', direction: KaiCashImportDirection.income),
          id(balanceAfter: 330.732, direction: KaiCashImportDirection.income),
        ),
        isTrue,
      );
    });
  });

  group('no balance means no cross-channel claim', () {
    test('an alert without a balance keeps its own identity', () {
      expect(id(balanceAfter: null).confident, isFalse);
      expect(id(account: null, balanceAfter: 330.732).confident, isFalse);
      expect(id(account: 'unknown', balanceAfter: 330.732).confident, isFalse);
    });

    test('it will show two rows rather than quietly show one', () {
      // The honest limit. Over-deduplication is worse than under: a double row
      // is visible and correctable, a missing one looks like it never happened.
      final d = KaiLedgerDeduper();
      expect(d.admit(row(amount: 1.5, source: 'alert:email'), id()), isTrue);
      expect(d.admit(row(amount: 1.5, source: 'alert:sms'), id()), isTrue);
      expect(d.recorded, 2);
    });
  });

  group('the message arriving twice is still caught', () {
    test('an identical redelivery is refused even with no balance', () {
      // Android redelivers notifications on reconnect, and a drain can be
      // retried after a failed write. That guard always applies.
      final d = KaiLedgerDeduper();
      final same = row(amount: 1.5, source: 'alert:sms');
      expect(d.admit(same, id()), isTrue);
      expect(d.admit(same, id()), isFalse);
    });

    test('hasSeen answers only when it can', () {
      final d = KaiLedgerDeduper();
      d.admit(row(amount: 1.5, source: 'a'), id(balanceAfter: 330.732));
      expect(d.hasSeen(id(balanceAfter: 330.732)), isTrue);
      expect(d.hasSeen(id(balanceAfter: 329.232)), isFalse);
      expect(d.hasSeen(id(balanceAfter: null)), isFalse);
    });
  });
}
