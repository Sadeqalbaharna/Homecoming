import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_body_event.dart';

void main() {
  test('Core supplies ordering time and channel supplies surface authority',
      () {
    final received = DateTime.utc(2026, 8, 8, 10);
    final event = KaiBodyEvent.receive(
      {
        'eventId': 'event-1',
        'type': 'user_active',
        'occurredAt': '2026-08-08T09:59:58Z',
        'bodyId': 'quest-shack-body',
        'deviceId': 'quest-device',
        'surface': 'desktop',
        'sessionId': 'session-1',
        'conversationId': 'vr_shack',
        'laneId': 'vr_shack',
        'correlationId': 'turn-1',
        'payload': {'gogglesOn': true},
      },
      authoritativeSurface: 'vr',
      receivedAt: received,
    );

    expect(event.surface, 'vr');
    expect(event.receivedAt, received);
    expect(event.bodyId, isNot(event.deviceId));
  });

  test('direct replies never leak to another body', () {
    final route = routeKaiOutput(
      kind: KaiOutboundKind.directReply,
      originBodyId: 'phone',
      candidates: [
        KaiBodyRouteCandidate(
          bodyId: 'desktop',
          surface: 'desktop',
          lastUserActivityAt: DateTime.utc(2026, 8, 8),
        ),
      ],
    );
    expect(route.bodyId, isNull);
    expect(route.storeForLater, isTrue);
  });

  test('proactive presence chooses one foreground friend body', () {
    final route = routeKaiOutput(
      kind: KaiOutboundKind.proactiveFriend,
      candidates: [
        KaiBodyRouteCandidate(
          bodyId: 'phone',
          surface: 'messenger',
          lastUserActivityAt: DateTime.utc(2026, 8, 8, 10),
        ),
        KaiBodyRouteCandidate(
          bodyId: 'desktop',
          surface: 'desktop',
          foreground: true,
          lastUserActivityAt: DateTime.utc(2026, 8, 8, 9),
        ),
      ],
    );
    expect(route.bodyId, 'desktop');
    expect(route.storeForLater, isFalse);
  });
}
