// capture_health — telling "you did not spend" apart from "the pipe is dead".
//
// ── The failure this exists for ─────────────────────────────────────────────
//
// A notification listener can stop without saying so. Samsung and other OEMs
// unbind listeners for apps they judge unused, battery optimisation kills
// background work, and "remove permissions if app unused" revokes the grant
// after a few days. None of those produce an error. The ledger simply stops
// filling.
//
// And an empty ledger is ambiguous by nature: no rows today is exactly what a
// quiet Tuesday looks like. Three separate things were caught today whose only
// symptom was silence — a wrong sender guess, an enrolment that forgot itself,
// a case-sensitive comparison — so the pattern is worth instrumenting rather
// than hoping about.
//
// ── The signal that disambiguates it ────────────────────────────────────────
//
// The listener sees EVERY notification, not only bank alerts. WhatsApp, email,
// the weather, a delivery. Dozens a day, and completely independent of whether
// Sadeq spent money.
//
// So two timestamps answer the question:
//
//   lastAnyNotification   is the pipe alive?
//   lastBankAlert         has money moved?
//
// Old bank alert + recent anything  → quiet spending week. Healthy.
// Old bank alert + old anything     → the listener is dead. Say so.
//
// This is deliberately not a guess about WHY. It reports a state and leaves
// the diagnosis to a human, because "battery optimisation" and "permission
// revoked" look identical from in here and inventing a cause would be worse
// than naming the symptom.
//
// Pure and deterministic.

enum KaiCaptureState {
  /// Notifications are arriving. The pipe works.
  healthy,

  /// Nothing at all for long enough that the listener is probably unbound.
  /// This is the one worth interrupting someone about.
  listenerSilent,

  /// The OS told us the listener disconnected. Better than inference.
  listenerDisconnected,

  /// Access was never granted, or has been revoked.
  accessMissing,

  /// Nothing has ever been captured, so there is no baseline to judge against.
  /// Not a fault — a new install looks exactly like this.
  neverStarted,
}

class KaiCaptureHealth {
  const KaiCaptureHealth({
    required this.state,
    required this.silentFor,
    this.queued = 0,
  });

  final KaiCaptureState state;

  /// How long since ANY notification was seen. Null when nothing ever was.
  final Duration? silentFor;

  /// Alerts sitting in the durable queue, undrained. A number that only ever
  /// grows means capture works and the DRAIN is broken, which is a different
  /// fault with a different fix.
  final int queued;

  bool get ok => state == KaiCaptureState.healthy;

  /// Worth telling Sadeq about unprompted. A new install is not.
  bool get worthRaising =>
      state == KaiCaptureState.listenerSilent ||
      state == KaiCaptureState.listenerDisconnected ||
      state == KaiCaptureState.accessMissing;

  String get reasonCode => state.name;
}

/// What to actually do about a dead listener.
///
/// Detection without a remedy just moves the problem: Sadeq still has to
/// remember which of five Samsung settings it was. Android reports three facts
/// that separate the cases cleanly, and each has exactly one fix.
enum KaiCaptureRepair {
  /// Nothing to do.
  none,

  /// The binding was dropped while the permission is still granted — the
  /// common OEM case. `requestRebind` fixes this from inside the app, so it is
  /// the one failure Kai can repair himself.
  rebindRequested,

  /// The permission is gone. Nothing in the app can restore it: granting
  /// notification access is deliberately a human act in Settings, and an app
  /// that could grant itself that would be the actual security hole.
  grantAccess,

  /// The OS is allowed to sleep the app, so the listener will keep dying.
  /// Rebinding treats the symptom; this is the cause.
  exemptFromBatteryOptimisation,

  /// Android will revoke permissions for disuse. A listener that works today
  /// and stops after a quiet fortnight is this.
  disableAutoRevoke,
}

/// The remedy, in the order that actually fixes things.
///
/// Ordered by cause before symptom: a rebind on a phone that is still allowed
/// to sleep the app will work and then fail again next week, so the standing
/// causes are named first even though the rebind is what restores service now.
List<KaiCaptureRepair> kaiCaptureRepairs({
  required bool accessGranted,
  required bool rebindRequested,
  bool? batteryExempt,
  bool? autoRevokeExempt,
}) {
  if (!accessGranted) {
    // Everything else is moot without the grant, and listing four steps when
    // one is required is how instructions get ignored.
    return const [KaiCaptureRepair.grantAccess];
  }
  return [
    if (batteryExempt == false) KaiCaptureRepair.exemptFromBatteryOptimisation,
    if (autoRevokeExempt == false) KaiCaptureRepair.disableAutoRevoke,
    if (rebindRequested) KaiCaptureRepair.rebindRequested,
  ];
}

class KaiCaptureMonitor {
  const KaiCaptureMonitor({this.silenceThreshold = const Duration(hours: 6)});

  /// How long without a single notification before the listener is presumed
  /// dead.
  ///
  /// Six hours is chosen to survive a night's sleep with Do Not Disturb on,
  /// which is the obvious false positive. Shorter would cry wolf every morning,
  /// and an alert nobody believes is worse than no alert.
  final Duration silenceThreshold;

  KaiCaptureHealth evaluate({
    required bool accessGranted,
    required bool listenerConnected,
    required DateTime? lastAnyNotification,
    required DateTime now,
    int queued = 0,
  }) {
    if (!accessGranted) {
      return KaiCaptureHealth(
        state: KaiCaptureState.accessMissing,
        silentFor: lastAnyNotification == null
            ? null
            : now.difference(lastAnyNotification),
        queued: queued,
      );
    }
    // The OS saying so beats inferring it from a gap.
    if (!listenerConnected) {
      return KaiCaptureHealth(
        state: KaiCaptureState.listenerDisconnected,
        silentFor: lastAnyNotification == null
            ? null
            : now.difference(lastAnyNotification),
        queued: queued,
      );
    }
    if (lastAnyNotification == null) {
      return KaiCaptureHealth(
        state: KaiCaptureState.neverStarted,
        silentFor: null,
        queued: queued,
      );
    }

    final silent = now.difference(lastAnyNotification);
    return KaiCaptureHealth(
      state: silent >= silenceThreshold
          ? KaiCaptureState.listenerSilent
          : KaiCaptureState.healthy,
      silentFor: silent,
      queued: queued,
    );
  }

  /// Has money been quiet, given the pipe is fine?
  ///
  /// Separate from [evaluate] on purpose. "No transactions" is only meaningful
  /// once the pipe is known good, and conflating them is how a dead listener
  /// gets reported as a frugal week.
  bool spendingQuiet({
    required KaiCaptureHealth health,
    required DateTime? lastBankAlert,
    required DateTime now,
    Duration threshold = const Duration(days: 3),
  }) {
    if (!health.ok) return false;
    if (lastBankAlert == null) return true;
    return now.difference(lastBankAlert) >= threshold;
  }
}
