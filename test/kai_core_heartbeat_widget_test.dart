import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_core_client.dart';
import 'package:homecoming_app/widgets/kai_core_heartbeat.dart';

void main() {
  Widget subject(KaiCoreHeartbeatPhase phase, {int bodyCount = 0}) =>
      MaterialApp(
        home: Scaffold(
          body: KaiCoreHeartbeat(
            status: KaiCoreHeartbeatStatus(phase: phase),
            bodyCount: bodyCount,
          ),
        ),
      );

  testWidgets('shows a living heart only for a healthy core', (tester) async {
    await tester.pumpWidget(
      subject(KaiCoreHeartbeatPhase.healthy, bodyCount: 2),
    );
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.text('CORE AWAKE · 2'), findsOneWidget);

    await tester.pumpWidget(subject(KaiCoreHeartbeatPhase.offline));
    expect(find.byIcon(Icons.heart_broken_rounded), findsOneWidget);
    expect(find.text('CORE ASLEEP'), findsOneWidget);
  });

  testWidgets('makes reconnection visibly distinct', (tester) async {
    await tester.pumpWidget(subject(KaiCoreHeartbeatPhase.reconnecting));
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.text('CHECKING'), findsOneWidget);
  });
}
