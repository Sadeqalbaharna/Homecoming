import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/widgets/kai_efficiency_delta_meter.dart';

Map<String, dynamic> trace({
  required int tokens,
  required int firstTokenMs,
  required int second,
  int? schemaTokens,
}) {
  final start = DateTime.utc(2026, 7, 18, 12, 0, second);
  return {
    'startTime': start.toIso8601String(),
    'promptInputTokens': tokens,
    'promptOutputTokens': 0,
    if (schemaTokens != null) 'manifestApproxTokens': schemaTokens,
    'steps': [
      {
        'description': 'Sending to GPT',
        'timestamp': start.add(Duration(milliseconds: firstTokenMs)).toIso8601String(),
      },
    ],
  };
}

void main() {
  test('computes recent-vs-previous token, schema and latency reduction from oldest-first traces', () {
    final stats = EfficiencyDelta.fromRows([
      trace(tokens: 1000, schemaTokens: 800, firstTokenMs: 1000, second: 0),
      trace(tokens: 1000, schemaTokens: 800, firstTokenMs: 1000, second: 1),
      trace(tokens: 500, schemaTokens: 200, firstTokenMs: 500, second: 2),
      trace(tokens: 500, schemaTokens: 200, firstTokenMs: 500, second: 3),
    ], window: 2);

    expect(stats.tokenReduction, 50);
    expect(stats.schemaReduction, 75);
    expect(stats.latencyReduction, 50);
  });

  testWidgets('renders compact header deltas from injected traces', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KaiEfficiencyDeltaMeter(
            window: 2,
            traceLoader: () async => [
              trace(tokens: 1000, schemaTokens: 800, firstTokenMs: 1000, second: 0),
              trace(tokens: 1000, schemaTokens: 800, firstTokenMs: 1000, second: 1),
              trace(tokens: 500, schemaTokens: 400, firstTokenMs: 500, second: 2),
              trace(tokens: 500, schemaTokens: 400, firstTokenMs: 500, second: 3),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('tok'), findsOneWidget);
    expect(find.text('sch'), findsOneWidget);
    expect(find.text('lat'), findsOneWidget);
    expect(find.text('↓ 50%'), findsNWidgets(3));
  });

  testWidgets('header meter expands the full scorecard on demand',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final rows = [
      trace(tokens: 1000, schemaTokens: 800, firstTokenMs: 1000, second: 0),
      trace(tokens: 1000, schemaTokens: 800, firstTokenMs: 1000, second: 1),
      trace(tokens: 500, schemaTokens: 400, firstTokenMs: 500, second: 2),
      trace(tokens: 500, schemaTokens: 400, firstTokenMs: 500, second: 3),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: KaiEfficiencyDeltaMeter(
            window: 2,
            traceLoader: () async => rows,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('KAI STATE SCORECARD'), findsNothing);
    await tester.tap(find.byKey(const Key('kai-efficiency-scorecard-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kai-efficiency-scorecard-panel')),
        findsOneWidget);
    expect(find.text('KAI STATE SCORECARD'), findsOneWidget);
    expect(find.text('efficiency window'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders no-data dashes until there is enough baseline', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KaiEfficiencyDeltaMeter(
            window: 2,
            traceLoader: () async => [trace(tokens: 500, firstTokenMs: 500, second: 0)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('—'), findsNWidgets(3));
  });
}
