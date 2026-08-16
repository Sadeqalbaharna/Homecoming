// Telling "you did not spend" apart from "the pipe is dead".
//
// A notification listener stops without saying so — OEM battery managers
// unbind it, and "remove permissions if app unused" revokes the grant after a
// few days of not opening the app. Neither produces an error, and an empty
// ledger looks exactly like a quiet week.
//
// Three separate faults were caught today whose only symptom was silence: a
// wrong sender guess, an enrolment that forgot itself, and a case-sensitive
// comparison. This is the instrument for the fourth.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/capture_health.dart';

const monitor = KaiCaptureMonitor();
final now = DateTime(2026, 8, 16, 14, 0);

KaiCaptureHealth check({
  bool accessGranted = true,
  bool listenerConnected = true,
  Duration? lastSeenAgo = const Duration(minutes: 5),
  int queued = 0,
}) =>
    monitor.evaluate(
      accessGranted: accessGranted,
      listenerConnected: listenerConnected,
      lastAnyNotification:
          lastSeenAgo == null ? null : now.subtract(lastSeenAgo),
      now: now,
      queued: queued,
    );

void main() {
  group('the heartbeat is every notification, not every bank alert', () {
    test('recent traffic means the pipe is alive', () {
      final h = check(lastSeenAgo: const Duration(minutes: 5));
      expect(h.state, KaiCaptureState.healthy);
      expect(h.ok, isTrue);
      expect(h.worthRaising, isFalse);
    });

    test('silence past the threshold means the listener is gone', () {
      final h = check(lastSeenAgo: const Duration(hours: 9));
      expect(h.state, KaiCaptureState.listenerSilent);
      expect(h.worthRaising, isTrue);
      expect(h.silentFor, const Duration(hours: 9));
    });

    test('a night with Do Not Disturb is not a fault', () {
      // The obvious false positive, and the reason the threshold is six hours
      // rather than one. An alert nobody believes is worse than no alert.
      expect(check(lastSeenAgo: const Duration(hours: 5, minutes: 30)).ok,
          isTrue);
    });
  });

  group('the OS saying so beats inferring it', () {
    test('a disconnect is reported even with recent traffic', () {
      final h = check(
        listenerConnected: false,
        lastSeenAgo: const Duration(minutes: 2),
      );
      expect(h.state, KaiCaptureState.listenerDisconnected);
      expect(h.worthRaising, isTrue);
    });

    test('revoked access outranks everything else', () {
      final h = check(accessGranted: false, listenerConnected: false);
      expect(h.state, KaiCaptureState.accessMissing);
      expect(h.worthRaising, isTrue);
    });
  });

  group('a new install is not a fault', () {
    test('nothing ever seen is neverStarted, and stays quiet', () {
      final h = check(lastSeenAgo: null);
      expect(h.state, KaiCaptureState.neverStarted);
      expect(h.silentFor, isNull);
      expect(h.worthRaising, isFalse,
          reason: 'nagging a fresh install teaches people to ignore this');
    });
  });

  group('a growing queue is a different fault', () {
    test('capture working and drain broken is visible', () {
      // Alerts arriving and piling up means the listener is fine and the drain
      // is not — a different fix from a dead listener, so it must not look the
      // same.
      final h = check(queued: 47);
      expect(h.state, KaiCaptureState.healthy);
      expect(h.queued, 47);
    });
  });

  group('quiet spending is only meaningful once the pipe is known good', () {
    test('no bank alerts with a healthy pipe is a quiet week', () {
      final h = check();
      expect(
        monitor.spendingQuiet(
          health: h,
          lastBankAlert: now.subtract(const Duration(days: 5)),
          now: now,
        ),
        isTrue,
      );
    });

    test('a dead pipe is never reported as frugal', () {
      // Conflating these is exactly how a broken listener gets celebrated as a
      // good spending week.
      final dead = check(lastSeenAgo: const Duration(hours: 20));
      expect(
        monitor.spendingQuiet(
          health: dead,
          lastBankAlert: now.subtract(const Duration(days: 5)),
          now: now,
        ),
        isFalse,
      );
    });

    test('recent spending is not quiet', () {
      expect(
        monitor.spendingQuiet(
          health: check(),
          lastBankAlert: now.subtract(const Duration(hours: 2)),
          now: now,
        ),
        isFalse,
      );
    });
  });

  // ── Detection without a remedy just moves the problem ──────────────────────
  //
  // Knowing the listener died still leaves Sadeq guessing which of five Samsung
  // settings it was. Android reports three facts that separate the cases, and
  // each has exactly one fix.
  group('the remedy is specific, not "something is wrong"', () {
    test('a dropped binding is the one Kai can repair himself', () {
      expect(
        kaiCaptureRepairs(
          accessGranted: true,
          rebindRequested: true,
          batteryExempt: true,
          autoRevokeExempt: true,
        ),
        [KaiCaptureRepair.rebindRequested],
      );
    });

    test('a revoked permission asks for one thing, not four', () {
      // Everything else is moot without the grant, and listing four steps when
      // one is required is how instructions get ignored.
      expect(
        kaiCaptureRepairs(
          accessGranted: false,
          rebindRequested: false,
          batteryExempt: false,
          autoRevokeExempt: false,
        ),
        [KaiCaptureRepair.grantAccess],
      );
    });

    test('causes are named before the symptom', () {
      // A rebind on a phone still allowed to sleep the app works now and fails
      // again next week, so the standing causes come first.
      final repairs = kaiCaptureRepairs(
        accessGranted: true,
        rebindRequested: true,
        batteryExempt: false,
        autoRevokeExempt: false,
      );
      expect(repairs, [
        KaiCaptureRepair.exemptFromBatteryOptimisation,
        KaiCaptureRepair.disableAutoRevoke,
        KaiCaptureRepair.rebindRequested,
      ]);
    });

    test('a healthy phone is told to do nothing', () {
      expect(
        kaiCaptureRepairs(
          accessGranted: true,
          rebindRequested: false,
          batteryExempt: true,
          autoRevokeExempt: true,
        ),
        isEmpty,
      );
    });

    test('an unknown fact is not treated as a fault', () {
      // isIgnoringBatteryOptimizations and isAutoRevokeWhitelisted can both
      // fail or be unavailable on older Android. Null means "not observed", and
      // reporting a fix for something we never measured is inventing a
      // diagnosis — the thing this file exists to avoid.
      expect(
        kaiCaptureRepairs(
          accessGranted: true,
          rebindRequested: false,
          batteryExempt: null,
          autoRevokeExempt: null,
        ),
        isEmpty,
      );
    });
  });

  group('the verdict carries a reason code and no content', () {
    test('reasonCode names the state', () {
      expect(check().reasonCode, 'healthy');
      expect(check(lastSeenAgo: const Duration(days: 2)).reasonCode,
          'listenerSilent');
      expect(check(accessGranted: false).reasonCode, 'accessMissing');
    });
  });
}
