import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/widgets/kai_state_scorecard_card.dart';

void main() {
  Map<String, dynamic> efficiencyRow({
    required int input,
    required int output,
    required int schema,
    required double cost,
    required int setupMs,
    int toolTrimTokensSaved = 0,
    int toolTrimCompactedResults = 0,
    int toolTrimHardCappedResults = 0,
  }) => {
        'userInput': 'measure it',
        'startTime': '2026-07-18T12:00:00.000Z',
        'route': 'fastChat',
        'promptInputTokens': input,
        'promptOutputTokens': output,
        'promptCostUsd': cost,
        'manifestApproxTokens': schema,
        'toolTrimApproxTokensSaved': toolTrimTokensSaved,
        'toolTrimCompactedResults': toolTrimCompactedResults,
        'toolTrimHardCappedResults': toolTrimHardCappedResults,
        'steps': [
          {
            'description': 'Sending to GPT',
            'timestamp': DateTime.utc(2026, 7, 18, 12, 0, 0, setupMs).toIso8601String(),
          },
        ],
      };

  testWidgets('renders replay scorecard metrics from injected trace rows', (tester) async {
    final rows = <Map<String, dynamic>>[
      {
        'userInput': 'fix the thing',
        'startTime': '2026-07-18T12:00:00.000Z',
        'finalResponse': 'Done and verified.',
        'route': 'coding',
        'routeConfidence': 0.86,
        'promptInputTokens': 1000,
        'promptOutputTokens': 250,
        'promptCostUsd': 0.0015,
        'moodCurrent': {
          'energy': 50,
          'focus': 60,
          'confidence': 55,
          'playfulness': 45,
        },
        'moodDelta': {
          'confidence': 2,
          'playfulness': 0,
        },
        'toolCalls': [
          {'name': 'run_tests', 'outcome': 'passed'},
        ],
        'steps': [
          {'description': 'Keeping (durable project memory)'},
          {
            'description': 'Memory retrieval complete',
            'data': {'used': 1},
          },
          {'description': 'Graph consulted directly (not via transcript match)'},
          {'description': 'calling tool run_tests'},
          {'description': 'job_done with run_tests proof'},
          {
            'description': 'Post-process recovered reply after TTS failed',
            'data': {'recoveredReply': true, 'error': 'tts timeout'},
          },
          {'description': 'Sending to GPT', 'timestamp': '2026-07-18T12:00:01.200Z'},
        ],
      },
      {
        'userInput': 'try again',
        'startTime': '2026-07-18T12:00:00.000Z',
        'route': 'fastChat',
        'routeConfidence': 0.44,
        'moodCurrent': {
          'energy': 30,
          'focus': 40,
          'confidence': 35,
          'playfulness': 80,
        },
        'moodDelta': {
          'confidence': -3,
          'playfulness': 5,
        },
        'toolCalls': [
          {'name': 'edit_file', 'outcome': 'failed'},
        ],
        'steps': [
          {
            'description': 'Memory retrieval complete',
            'data': {'used': 0},
          },
          {'description': 'calling tool edit_file'},
          {'description': 'old_string not found in file'},
          {'description': 'Sending to GPT', 'timestamp': '2026-07-18T12:00:01.800Z'},
        ],
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KaiStateScorecardCard(traceLoader: () async => rows),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KAI STATE SCORECARD'), findsOneWidget);
    expect(find.text('2 turns'), findsOneWidget);
    expect(find.text('memory formed'), findsOneWidget);
    expect(find.text('1 of 2'), findsWidgets);
    expect(find.text('retrieval usable'), findsOneWidget);
    expect(find.text('graph consulted'), findsOneWidget);
    expect(find.text('route selected'), findsOneWidget);
    expect(find.text('route confident'), findsOneWidget);
    expect(find.text('tool outcomes'), findsOneWidget);
    expect(find.text('tool failed'), findsOneWidget);
    expect(find.text('recovered replies'), findsOneWidget);
    expect(find.text('post errors'), findsOneWidget);
    expect(find.text('jobs proved'), findsOneWidget);
    expect(find.text('cost tracked'), findsOneWidget);
    expect(find.text('total cost'), findsOneWidget);
    expect(find.text('avg cost'), findsOneWidget);
    expect(find.text('avg tokens'), findsOneWidget);
    expect(find.text('efficiency window'), findsOneWidget);
    expect(find.text('latest 2 vs previous 0'), findsOneWidget);
    expect(find.text('token trend'), findsOneWidget);
    expect(find.text('schema trend'), findsOneWidget);
    expect(find.text('cost trend'), findsOneWidget);
    expect(find.text('recent token mix'), findsOneWidget);
    expect(find.text('tool trim saved'), findsOneWidget);
    expect(find.text('setup trend'), findsOneWidget);
    expect(find.text('— (no trimmed loops)'), findsOneWidget);
    expect(find.textContaining('— (no baseline) · 0 → 1250 tok/turn'), findsOneWidget);
    expect(find.text('1000 in / 250 out · schema 0% of input'), findsOneWidget);
    expect(find.textContaining('— (no baseline) · 0 → 0 schema/turn'), findsOneWidget);
    expect(find.textContaining('— (no baseline) · \$0.000000 → \$0.001500 / turn'), findsOneWidget);
    expect(find.textContaining('— (no baseline) · 0ms → 1500ms to GPT'), findsOneWidget);
    expect(find.text('mood tracked'), findsOneWidget);
    expect(find.text('avg energy'), findsOneWidget);
    expect(find.text('avg focus'), findsOneWidget);
    expect(find.text('confidence dips'), findsOneWidget);
    expect(find.text('play spikes'), findsOneWidget);
    expect(find.text('2 of 2'), findsWidgets);
    expect(find.text('1 of 2'), findsWidgets);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('\$0.001500'), findsOneWidget);
    expect(find.text('\$0.001500 / turn'), findsOneWidget);
    expect(find.text('1250 / turn'), findsOneWidget);
    expect(find.text('1800ms median'), findsOneWidget);
  });

  testWidgets('shows absolute before-after efficiency numbers', (tester) async {
    final rows = <Map<String, dynamic>>[
      for (var i = 0; i < 8; i++)
        efficiencyRow(input: 900, output: 100, schema: 800, cost: 0.004, setupMs: 2000),
      for (var i = 0; i < 8; i++)
        efficiencyRow(
          input: 450,
          output: 50,
          schema: 200,
          cost: 0.002,
          setupMs: 1000,
          toolTrimTokensSaved: 8000,
          toolTrimCompactedResults: 3,
          toolTrimHardCappedResults: 1,
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KaiStateScorecardCard(
            traceLoader: () async => rows,
            limit: 4,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('efficiency window'), findsOneWidget);
    expect(find.text('latest 4 vs previous 0'), findsNothing);
    expect(find.textContaining('↓ 50% · 1000 → 500 tok/turn'), findsOneWidget);
    expect(find.textContaining('↓ 75% · 800 → 200 schema/turn'), findsOneWidget);
    expect(find.text('450 in / 50 out · schema 44% of input'), findsOneWidget);
    expect(find.textContaining('↓ 50% · \$0.004000 → \$0.002000 / turn'), findsOneWidget);
    expect(find.text('8000 tok/trimmed turn (24 compacted, 8 capped)'), findsOneWidget);
    expect(find.textContaining('↓ 50% · 2000ms → 1000ms to GPT'), findsOneWidget);
  });

  testWidgets('shows honest empty state when no traces exist', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KaiStateScorecardCard(traceLoader: () async => const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KAI STATE SCORECARD'), findsOneWidget);
    expect(find.text('no trace rows yet'), findsOneWidget);
  });
}
