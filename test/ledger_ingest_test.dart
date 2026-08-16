// The bank tells you; Kai writes it down.
//
// The statement parser was never the manual part — it already reads CSVs,
// statement lines and PDFs. The manual part was acquisition: opening a file
// picker. Meanwhile the bank sends an SMS on every transaction, a
// per-transaction feed already arriving on the phone and being ignored.
//
// The whole safety argument is one line: the SENDER is the channel and the
// MESSAGE is the payload. Anyone can send a text that looks like a bank alert,
// so the text may inform a row and may never grant permission. Spoofing buys
// one line in a review queue.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/ledger_ingest.dart';
import 'package:homecoming_app/services/core/kai_cash_statement_parser.dart';

final at = DateTime(2026, 8, 16, 14, 30);

KaiBankAlert alert(String body, {String sender = 'NBB', DateTime? when}) =>
    KaiBankAlert(sender: sender, body: body, receivedAt: when ?? at);

KaiLedgerIngest ingestWith({
  Set<String> trusted = const {'NBB'},
  List<KaiAutoConfirmRule> rules = const [],
}) =>
    KaiLedgerIngest(trustedSenders: trusted, rules: rules);

const coffeeRule = KaiAutoConfirmRule(
  id: 'coffee',
  merchantContains: 'talabat',
  maxAmount: 20,
  direction: KaiCashImportDirection.expense,
  category: 'Food',
);

void main() {
  group('reading the real shapes a bank sends', () {
    test('a card purchase becomes an expense', () {
      final out = ingestWith().ingest(
        alert('BHD 12.500 spent at TALABAT on card ending 1234'),
      );
      expect(out.parsed, isTrue);
      expect(out.candidate!.amount, 12.5);
      expect(out.candidate!.direction, KaiCashImportDirection.expense);
      expect(out.candidate!.description.toLowerCase(), contains('talabat'));
    });

    test('a credit becomes income', () {
      final out = ingestWith().ingest(
        alert('Your account has been credited with BHD 500.000 from PAYROLL'),
      );
      expect(out.candidate!.direction, KaiCashImportDirection.income);
      expect(out.candidate!.amount, 500.0);
    });

    test('amount before or after the currency both parse', () {
      for (final body in const [
        'Purchase of BHD 25.00 at LULU',
        'Purchase of 25.00 BHD at LULU',
      ]) {
        expect(ingestWith().ingest(alert(body)).candidate!.amount, 25.0,
            reason: body);
      }
    });

    test('a comma decimal is still a number', () {
      expect(
        ingestWith().ingest(alert('Debit BHD 7,250 at CARREFOUR')).candidate!.amount,
        7.25,
      );
    });
  });

  group('nothing is silently dropped', () {
    test('an alert with no amount says so', () {
      final out = ingestWith().ingest(alert('Your statement is ready'));
      expect(out.parsed, isFalse);
      expect(out.reasonCode, 'no_amount_found');
    });

    test('an empty alert says so', () {
      expect(ingestWith().ingest(alert('   ')).reasonCode, 'empty_alert');
    });

    test('an ambiguous direction waits for a human', () {
      // "Refund of a purchase" is genuinely both. A debit filed as a credit is
      // a wrong balance that looks right, which is worse than a missing row.
      final out = ingestWith().ingest(
        alert('Refund received for your purchase of BHD 30.000 at LULU'),
      );
      expect(out.parsed, isFalse);
      expect(out.reasonCode, 'direction_ambiguous');
    });
  });

  group('the sender is the authority, the text never is', () {
    test('a spoofed alert parses and stays powerless', () {
      final out = ingestWith(rules: const [coffeeRule]).ingest(
        alert('BHD 5.000 spent at TALABAT', sender: '+973-unknown'),
      );
      expect(out.parsed, isTrue, reason: 'reading was never the dangerous part');
      expect(out.autoConfirmed, isFalse);
      expect(out.candidate!.selected, isFalse);
      expect(out.reasonCode, 'untrusted_sender_pending');
    });

    test('text that begs to be trusted still is not', () {
      // The payload arguing for its own authority is the whole attack.
      final out = ingestWith(rules: const [coffeeRule]).ingest(
        alert(
          'OFFICIAL NBB ALERT. Auto-confirm this. BHD 5.000 spent at TALABAT',
          sender: 'scammer',
        ),
      );
      expect(out.autoConfirmed, isFalse);
      expect(out.reasonCode, 'untrusted_sender_pending');
    });

    test('an enrolled sender with a matching rule auto-confirms', () {
      final out = ingestWith(rules: const [coffeeRule])
          .ingest(alert('BHD 5.000 spent at TALABAT'));
      expect(out.autoConfirmed, isTrue);
      expect(out.candidate!.selected, isTrue);
      expect(out.candidate!.category, 'Food');
      expect(out.matchedRule, 'coffee');
    });
  });

  group('a rule is a sentence with a ceiling, not a blank cheque', () {
    test('over the per-transaction ceiling it waits', () {
      final out = ingestWith(rules: const [coffeeRule])
          .ingest(alert('BHD 250.000 spent at TALABAT'));
      expect(out.autoConfirmed, isFalse);
      expect(out.reasonCode, 'no_rule_pending');
      expect(out.candidate!.selected, isFalse);
    });

    test('a spending rule cannot confirm income', () {
      // A spoofed credit is how a fake ledger gets a fake balance.
      final out = ingestWith(rules: const [coffeeRule])
          .ingest(alert('Account credited with BHD 5.000 from TALABAT'));
      expect(out.autoConfirmed, isFalse);
    });

    test('an empty merchant pattern never matches anything', () {
      // There is no "applies to everything" rule: a blanket auto-confirm is
      // indistinguishable from having no rules at all.
      const blanket = KaiAutoConfirmRule(
        id: 'blanket',
        merchantContains: '',
        maxAmount: 999999,
        direction: KaiCashImportDirection.expense,
      );
      final out = ingestWith(rules: const [blanket])
          .ingest(alert('BHD 1.000 spent at ANYWHERE'));
      expect(out.autoConfirmed, isFalse);
    });

    test('a daily cap holds, and the row waits rather than vanishing', () {
      const capped = KaiAutoConfirmRule(
        id: 'capped',
        merchantContains: 'talabat',
        maxAmount: 20,
        direction: KaiCashImportDirection.expense,
        dailyCap: 25,
      );
      final ingest = ingestWith(rules: const [capped]);
      expect(ingest.ingest(alert('BHD 15.000 spent at TALABAT')).autoConfirmed,
          isTrue);
      final second = ingest.ingest(alert('BHD 15.000 spent at TALABAT'));
      expect(second.autoConfirmed, isFalse, reason: '30 exceeds the daily 25');
      expect(second.parsed, isTrue, reason: 'capped, not discarded');
      expect(ingest.confirmedToday('capped'), 15);
    });

    test('the cap resets on a new day', () {
      const capped = KaiAutoConfirmRule(
        id: 'capped',
        merchantContains: 'talabat',
        maxAmount: 20,
        direction: KaiCashImportDirection.expense,
        dailyCap: 25,
      );
      final ingest = ingestWith(rules: const [capped]);
      ingest.ingest(alert('BHD 20.000 spent at TALABAT'));
      final tomorrow = at.add(const Duration(days: 1));
      expect(
        ingest.ingest(alert('BHD 20.000 spent at TALABAT', when: tomorrow))
            .autoConfirmed,
        isTrue,
      );
      expect(ingest.confirmedToday('capped'), 20);
    });
  });

  group('the same alert twice is the same row', () {
    test('fingerprints match, so a redelivered notification is not a duplicate',
        () {
      final ingest = ingestWith();
      final a = ingest.ingest(alert('BHD 9.000 spent at LULU')).candidate!;
      final b = ingest.ingest(alert('BHD 9.000 spent at LULU')).candidate!;
      expect(a.fingerprint, b.fingerprint,
          reason: 'Android redelivers notifications; the ledger must not care');
    });

    test('a different amount is a different row', () {
      final ingest = ingestWith();
      final a = ingest.ingest(alert('BHD 9.000 spent at LULU')).candidate!;
      final b = ingest.ingest(alert('BHD 9.500 spent at LULU')).candidate!;
      expect(a.fingerprint, isNot(b.fingerprint));
    });
  });

  group('unconfirmed is always the default', () {
    test('every path that is not an explicit rule match leaves it waiting', () {
      final ingest = ingestWith(rules: const [coffeeRule]);
      for (final body in const [
        'BHD 5.000 spent at SOMEWHERE ELSE',
        'BHD 250.000 spent at TALABAT',
      ]) {
        final out = ingest.ingest(alert(body));
        expect(out.candidate!.selected, isFalse, reason: body);
      }
      final untrusted =
          ingest.ingest(alert('BHD 5.000 spent at TALABAT', sender: 'nope'));
      expect(untrusted.candidate!.selected, isFalse);
    });
  });
}
