import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_global_presence_service.dart';

void main() {
  final now = DateTime.utc(2026, 8, 7, 20);

  test('ordinary bodies can never mutate the central coordinator lease', () {
    expect(
      resolveKaiCoordinatorLeaseAction(
        managesCoordinatorLease: false,
        requestedAwake: false,
      ),
      KaiCoordinatorLeaseAction.none,
    );
    expect(
      resolveKaiCoordinatorLeaseAction(
        managesCoordinatorLease: false,
        requestedAwake: true,
      ),
      KaiCoordinatorLeaseAction.none,
    );
  });

  test('the authorised coordinator can renew and expire its own lease', () {
    expect(
      resolveKaiCoordinatorLeaseAction(
        managesCoordinatorLease: true,
        requestedAwake: true,
      ),
      KaiCoordinatorLeaseAction.renew,
    );
    expect(
      resolveKaiCoordinatorLeaseAction(
        managesCoordinatorLease: true,
        requestedAwake: false,
      ),
      KaiCoordinatorLeaseAction.expire,
    );
  });

  test('Kai is awake when the central coordinator lease is alive', () {
    final snapshot = resolveKaiGlobalPresence(
      connected: true,
      serverNow: now,
      coordinatorValue: {
        'leaseExpiresAt':
            now.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
      },
      bodiesValue: {
        'desktop-one': {
          'surface': 'desktop',
          'leaseExpiresAt':
              now.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
        },
        'old-phone': {
          'surface': 'messenger',
          'leaseExpiresAt':
              now.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
        },
      },
    );

    expect(snapshot.isAwake, isTrue);
    expect(snapshot.bodyCount, 1);
    expect(snapshot.bodies.single.deviceId, 'desktop-one');
  });

  test('body identity and routing state survive registry parsing', () {
    final activity = now.subtract(const Duration(seconds: 8));
    final snapshot = resolveKaiGlobalPresence(
      connected: true,
      serverNow: now,
      coordinatorValue: {
        'leaseExpiresAt':
            now.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
      },
      bodiesValue: {
        'vr-body-one': {
          'deviceId': 'quest-three',
          'surface': 'vr',
          'sessionId': 'shack-session',
          'status': 'thinking',
          'foreground': true,
          'gogglesOn': true,
          'lastUserActivityAt': activity.millisecondsSinceEpoch,
          'leaseExpiresAt':
              now.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
        },
      },
    );

    final body = snapshot.bodies.single;
    expect(body.bodyId, 'vr-body-one');
    expect(body.deviceId, 'quest-three');
    expect(body.sessionId, 'shack-session');
    expect(body.status, 'thinking');
    expect(body.foreground, isTrue);
    expect(body.gogglesOn, isTrue);
    expect(body.lastUserActivityAt, activity);
  });

  test('the heart stops when the central coordinator lease has expired', () {
    final snapshot = resolveKaiGlobalPresence(
      connected: true,
      serverNow: now,
      coordinatorValue: {
        'leaseExpiresAt': now.millisecondsSinceEpoch,
      },
      bodiesValue: {
        'desktop-one': {
          'surface': 'desktop',
          'leaseExpiresAt':
              now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        },
      },
    );

    expect(snapshot.isAwake, isFalse);
    expect(snapshot.bodyCount, 1,
        reason: 'an awake body cannot impersonate the central coordinator');
  });

  test('visible heart can beat from a live body without coordinator ownership', () {
    final snapshot = resolveKaiGlobalPresence(
      connected: true,
      serverNow: now,
      coordinatorValue: null,
      bodiesValue: {
        'desktop-one': {
          'surface': 'desktop',
          'leaseExpiresAt':
              now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        },
      },
    );

    expect(snapshot.isAwake, isFalse,
        reason: 'visible desktop bodies must not impersonate the coordinator');
    expect(snapshot.hasLiveBody, isTrue,
        reason: 'the desktop badge should show the reachable core as alive');
  });

  test('loss of central verification never leaves a fake beating heart', () {
    final snapshot = resolveKaiGlobalPresence(
      connected: false,
      serverNow: now,
      coordinatorValue: {
        'leaseExpiresAt':
            now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      },
      bodiesValue: {
        'desktop-one': {
          'surface': 'desktop',
          'leaseExpiresAt':
              now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        },
      },
    );

    expect(snapshot.isAwake, isFalse);
    expect(snapshot.hasLiveBody, isFalse);
  });
}
