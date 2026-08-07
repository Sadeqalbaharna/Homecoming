import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/widgets/kai_line_heartbeat.dart';

void main() {
  Widget subject(bool? awake, {int bodyCount = 0}) => MaterialApp(
        home: Scaffold(
          body: KaiLineHeartbeat(awake: awake, bodyCount: bodyCount),
        ),
      );

  testWidgets('labels the live Messenger line clearly', (tester) async {
    await tester.pumpWidget(subject(true, bodyCount: 2));
    expect(find.text('KAI  ·  CORE AWAKE  ·  2 BODIES'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    await tester.pumpWidget(subject(false));
    expect(find.text('KAI  ·  CORE ASLEEP'), findsOneWidget);
    expect(find.byIcon(Icons.heart_broken_rounded), findsOneWidget);
  });

  testWidgets('does not claim life before Firebase answers', (tester) async {
    await tester.pumpWidget(subject(null));
    expect(find.text('KAI  ·  CHECKING CORE'), findsOneWidget);
  });
}
