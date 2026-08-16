// The list of things Kai may read to build the ledger.
//
// Everything downstream trusts that whatever reached it came from a source
// Sadeq named. Nothing else in the ledger path checks provenance, because this
// is where provenance is decided.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/ledger_sources.dart';

KaiLedgerSource sms(String id, {bool enabled = true}) => KaiLedgerSource(
      channel: KaiLedgerChannel.sms,
      identifier: id,
      enabled: enabled,
    );

KaiLedgerSource email(String address, {String label = '', bool enabled = true}) =>
    KaiLedgerSource(
      channel: KaiLedgerChannel.email,
      identifier: address,
      label: label,
      enabled: enabled,
    );

void main() {
  group('nothing is enrolled until Sadeq enrols it', () {
    test('an empty registry reads nothing at all', () {
      // An earlier version shipped five guessed sender ids. That invented a
      // trust boundary instead of asking for one, and a wrong guess fails as
      // SILENCE — the ledger never fills and nothing reports an error.
      final sources = KaiLedgerSources();
      expect(sources.isEmpty, isTrue);
      expect(sources.allowsSms('NBB'), isFalse);
      expect(sources.allowsEmail('alerts@nbbonline.com'), isFalse);
      expect(sources.smsFilter, isEmpty);
    });
  });

  group('exact match, never a pattern', () {
    final sources = KaiLedgerSources([sms('NBB')]);

    test('the enrolled sender matches', () {
      expect(sources.allowsSms('NBB'), isTrue);
      expect(sources.allowsSms('nbb'), isTrue, reason: 'case is not identity');
      expect(sources.allowsSms('  NBB  '), isTrue);
    });

    test('a lookalike does not', () {
      // "Anything containing BANK" matching BANK-ALERT is the whole attack.
      for (final impostor in const [
        'NBB-ALERTS',
        'NBBB',
        'MYNBB',
        'NB',
        'NBB ',
        'N B B',
      ]) {
        if (impostor.trim().toUpperCase() == 'NBB') continue;
        expect(sources.allowsSms(impostor), isFalse, reason: impostor);
      }
    });

    test('empty and null never match', () {
      expect(sources.allowsSms(''), isFalse);
      expect(sources.allowsSms(null), isFalse);
      expect(sources.allowsSms('   '), isFalse);
    });
  });

  group('an email From header has two halves and one of them is a lie', () {
    final sources =
        KaiLedgerSources([email('alerts@nbbonline.com', label: 'NBB')]);

    test('the address matches, however it is wrapped', () {
      expect(sources.allowsEmail('alerts@nbbonline.com'), isTrue);
      expect(sources.allowsEmail('NBB Alerts <alerts@nbbonline.com>'), isTrue);
      expect(sources.allowsEmail('"NBB" <ALERTS@NBBONLINE.COM>'), isTrue);
    });

    test('a spoofed display name buys nothing', () {
      // The display name is chosen by the sender and means nothing. Matching on
      // it is the email-shaped version of trusting the payload.
      expect(
        sources.allowsEmail('"NBB Alerts" <noreply@totally-not-a-bank.ru>'),
        isFalse,
      );
      expect(
        sources.allowsEmail('alerts@nbbonline.com <attacker@evil.ru>'),
        isFalse,
        reason: 'the real address is the one in the brackets',
      );
    });

    test('a display name that is not an address is not an address', () {
      expect(sources.allowsEmail('NBB Alerts'), isFalse);
      expect(KaiLedgerSources.addressOf('NBB Alerts'), isNull);
    });

    test('a lookalike domain does not match', () {
      for (final impostor in const [
        'alerts@nbbonline.com.evil.ru',
        'alerts@nbbon1ine.com',
        'alerts@nbbonline.co',
        'notalerts@nbbonline.com',
      ]) {
        expect(sources.allowsEmail(impostor), isFalse, reason: impostor);
      }
    });
  });

  group('channels cannot be confused for each other', () {
    test('an sms id does not authorise an email of the same name', () {
      final sources = KaiLedgerSources([sms('NBB')]);
      expect(sources.allowsEmail('nbb@nbbonline.com'), isFalse);
    });

    test('an email address does not authorise an sms sender', () {
      final sources = KaiLedgerSources([email('alerts@nbbonline.com')]);
      expect(sources.allowsSms('alerts@nbbonline.com'), isFalse);
    });
  });

  group('disabling and revoking', () {
    test('disabled stays visible and stops capturing', () {
      // Deleting an enrolment you might want back encourages re-adding it
      // hastily; disabling leaves the decision recorded.
      final sources = KaiLedgerSources([sms('NBB')]);
      sources.setEnabled(KaiLedgerChannel.sms, 'NBB', false);
      expect(sources.allowsSms('NBB'), isFalse);
      expect(sources.all, hasLength(1));
      expect(sources.enabled, isEmpty);
      expect(sources.smsFilter, isEmpty);
    });

    test('removing genuinely removes', () {
      final sources = KaiLedgerSources([sms('NBB')]);
      sources.remove(KaiLedgerChannel.sms, 'nbb');
      expect(sources.all, isEmpty);
      expect(sources.allowsSms('NBB'), isFalse);
    });
  });

  group('the phone filter carries only what it can use', () {
    test('sms only, uppercased, enabled only', () {
      final sources = KaiLedgerSources([
        sms('NBB'),
        sms('bbk'),
        sms('OLD', enabled: false),
        email('alerts@nbbonline.com'),
      ]);
      expect(sources.smsFilter, ['BBK', 'NBB']);
    });
  });

  group('round trip', () {
    test('a saved registry reloads identically', () {
      final original = KaiLedgerSources([
        sms('NBB'),
        email('alerts@nbbonline.com', label: 'NBB email'),
      ]);
      final restored = KaiLedgerSources.fromJson(original.toJson());
      expect(restored.allowsSms('NBB'), isTrue);
      expect(restored.allowsEmail('NBB <alerts@nbbonline.com>'), isTrue);
      expect(restored.all.map((s) => s.key), original.all.map((s) => s.key));
    });

    test('an unknown channel fails closed rather than defaulting', () {
      // A source that cannot be classified cannot be trusted, and guessing SMS
      // would silently widen the boundary.
      final restored = KaiLedgerSources.fromJson([
        {'channel': 'carrier_pigeon', 'identifier': 'NBB', 'enabled': true},
      ]);
      expect(restored.isEmpty, isTrue);
    });

    test('a row with no identifier is dropped', () {
      final restored = KaiLedgerSources.fromJson([
        {'channel': 'sms', 'identifier': '  ', 'enabled': true},
      ]);
      expect(restored.isEmpty, isTrue);
    });
  });
}
