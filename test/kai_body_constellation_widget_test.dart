import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_global_presence_service.dart';
import 'package:homecoming_app/widgets/kai_body_constellation.dart';

void main() {
  testWidgets('shows only leased bodies around the verified central heart',
      (tester) async {
    final now = DateTime.utc(2026, 8, 8);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KaiBodyConstellation(
          awake: true,
          bodies: [
            KaiGlobalBody(
              bodyId: 'phone-one',
              deviceId: 'phone-device',
              surface: 'messenger',
              status: 'listening',
              foreground: true,
              leaseExpiresAt: now.add(const Duration(minutes: 1)),
            ),
            KaiGlobalBody(
              bodyId: 'quest-one',
              deviceId: 'quest-device',
              surface: 'vr',
              gogglesOn: true,
              leaseExpiresAt: now.add(const Duration(minutes: 1)),
            ),
          ],
        ),
      ),
    ));

    expect(find.byKey(const ValueKey('kai-central-heart')), findsOneWidget);
    expect(find.byKey(const ValueKey('kai-body-phone-one')), findsOneWidget);
    expect(find.byKey(const ValueKey('kai-body-quest-one')), findsOneWidget);
    expect(find.textContaining('MESSENGER'), findsOneWidget);
    expect(find.textContaining('VR'), findsOneWidget);
  });
}
