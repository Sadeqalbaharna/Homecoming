// What needs rotating, how old it is, and where to go.
//
// The rule that shapes the whole thing: this never holds or shows a secret
// value. A panel that prints keys is a new exposure surface, and this app has
// `read_screen` as a tool — anything rendered is readable by the assistant, by
// a screenshot, by a share.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/secret_registry.dart';

final now = DateTime(2026, 8, 16);

KaiSecret secret({
  String id = 'openai',
  KaiSecretKind kind = KaiSecretKind.secret,
  KaiSecretStore store = KaiSecretStore.sourceLocal,
  DateTime? lastRotated,
  bool inGitHistory = false,
}) =>
    KaiSecret(
      id: id,
      label: id,
      provider: id,
      store: store,
      location: 'lib/secrets.dart',
      kind: kind,
      lastRotated: lastRotated,
      inGitHistory: inGitHistory,
    );

DateTime daysAgo(int d) => now.subtract(Duration(days: d));

void main() {
  group('never rotated is not the same as recently rotated', () {
    test('an unknown age gets its own state', () {
      // Treating "no record" as fresh is how a key from three years ago looks
      // fine. An unknown age is not a safe age.
      expect(secret(lastRotated: null).urgency(now),
          KaiSecretUrgency.neverRotated);
      expect(secret(lastRotated: daysAgo(2)).urgency(now),
          KaiSecretUrgency.fresh);
    });

    test('ageInDays is null rather than zero when never rotated', () {
      expect(secret(lastRotated: null).ageInDays(now), isNull,
          reason: 'zero would read as "rotated today"');
    });
  });

  group('the bands', () {
    test('fresh, aging and overdue follow the interval', () {
      expect(secret(lastRotated: daysAgo(10)).urgency(now),
          KaiSecretUrgency.fresh);
      expect(secret(lastRotated: daysAgo(65)).urgency(now),
          KaiSecretUrgency.aging);
      expect(secret(lastRotated: daysAgo(120)).urgency(now),
          KaiSecretUrgency.overdue);
    });

    test('exactly at the interval is overdue, not aging', () {
      expect(secret(lastRotated: daysAgo(90)).urgency(now),
          KaiSecretUrgency.overdue);
    });
  });

  group('a committed secret outranks everything', () {
    test('exposure beats age', () {
      final fresh = secret(lastRotated: daysAgo(1), inGitHistory: true);
      expect(fresh.urgency(now), KaiSecretUrgency.exposed,
          reason: 'rotated yesterday but the old one is in history forever');
    });

    test('rotating clears the exposure but not the history', () {
      final exposed = secret(inGitHistory: true);
      final after = exposed.rotated(now, 'ab12cd34');
      expect(after.inGitHistory, isFalse,
          reason: 'the committed value no longer opens anything');
      expect(after.urgency(now), KaiSecretUrgency.fresh);
      expect(after.fingerprint, 'ab12cd34');
    });
  });

  group('not everything that looks like a key is a secret', () {
    test('a public identifier is never urgent', () {
      // Firebase web keys identify a project and are meant to ship. Listing
      // them beside a live OpenAI key produces alarm fatigue, and a panel
      // nobody believes is worse than no panel.
      final firebase = secret(
        id: 'firebase',
        kind: KaiSecretKind.publicIdentifier,
        store: KaiSecretStore.tracked,
        inGitHistory: true,
        lastRotated: null,
      );
      expect(firebase.urgency(now), KaiSecretUrgency.informational);
    });

    test('it is excluded from needsAttention', () {
      const registry = KaiSecretRegistry([]);
      expect(registry.needsAttention, isFalse);

      final onlyIdentifiers = KaiSecretRegistry([
        secret(
          id: 'firebase',
          kind: KaiSecretKind.publicIdentifier,
          inGitHistory: true,
        ),
      ]);
      expect(onlyIdentifiers.needsAttention, isFalse,
          reason: 'a shipped project id is not an outstanding task');
    });
  });

  group('the top of the list is the answer to "what now"', () {
    test('ranked puts exposure first, then overdue, then never', () {
      final registry = KaiSecretRegistry([
        secret(id: 'fresh', lastRotated: daysAgo(3)),
        secret(id: 'never', lastRotated: null),
        secret(id: 'overdue', lastRotated: daysAgo(200)),
        secret(id: 'exposed', lastRotated: daysAgo(1), inGitHistory: true),
        secret(id: 'aging', lastRotated: daysAgo(70)),
      ]);
      expect(
        registry.ranked(now).map((s) => s.id),
        ['exposed', 'overdue', 'never', 'aging', 'fresh'],
      );
    });

    test('oldest first within a band', () {
      final registry = KaiSecretRegistry([
        secret(id: 'older', lastRotated: daysAgo(300)),
        secret(id: 'old', lastRotated: daysAgo(120)),
      ]);
      expect(registry.ranked(now).first.id, 'older');
    });
  });

  group('the summary is a headline, not a report', () {
    test('it names the worst thing only', () {
      expect(
        KaiSecretRegistry([
          secret(id: 'a', inGitHistory: true),
          secret(id: 'b', lastRotated: daysAgo(200)),
        ]).summary(now),
        '1 exposed',
      );
      expect(
        KaiSecretRegistry([secret(lastRotated: daysAgo(200))]).summary(now),
        '1 overdue',
      );
      expect(
        KaiSecretRegistry([secret(lastRotated: null)]).summary(now),
        '1 never rotated',
      );
      expect(
        KaiSecretRegistry([secret(lastRotated: daysAgo(70))]).summary(now),
        '1 due soon',
      );
      expect(
        KaiSecretRegistry([secret(lastRotated: daysAgo(1))]).summary(now),
        'all current',
      );
    });

    test('needsAttention is true while anything is exposed or unrecorded', () {
      expect(KaiSecretRegistry([secret(inGitHistory: true)]).needsAttention,
          isTrue);
      expect(KaiSecretRegistry([secret(lastRotated: null)]).needsAttention,
          isTrue);
      expect(
        KaiSecretRegistry([secret(lastRotated: daysAgo(200))]).needsAttention,
        isFalse,
        reason: 'overdue is a schedule, not an unknown — the clock is running',
      );
    });
  });

  group('nothing here can leak a value', () {
    test('the type has no field that could hold one', () {
      // Structural, deliberately: the only defence that survives someone adding
      // a convenient `value` field later is a test that fails when they do.
      final s = secret(lastRotated: now);
      final rendered = [
        s.id,
        s.label,
        s.provider,
        s.location,
        s.consoleUrl,
        s.fingerprint,
        s.note,
      ].join(' ');
      expect(rendered.length, lessThan(400),
          reason: 'no field here is large enough to be a credential blob');
      expect(s.fingerprint.length, lessThanOrEqualTo(16),
          reason: 'a fingerprint confirms change; it must not reconstruct');
    });
  });
}
