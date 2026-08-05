import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/tools/replay.dart';

void main() {
  Map<String, dynamic> row(List<Map<String, dynamic>> steps) => {
        'userInput': 'why does it keep happening?',
        'startTime': '2026-07-18T12:00:00.000Z',
        'steps': steps,
      };

  test('graph consultation is measured from explicit trace step, not memory hits', () {
    final trace = row([
      {
        'description': 'Memory retrieval complete',
        'data': {'results': 2, 'used': 0},
      },
      {
        'description': 'Graph consulted directly (not via transcript match)',
        'data': {'seedTerms': ['mojibake', 'happening']},
      },
    ]);

    expect(retrievalAttempted(trace), isTrue);
    expect(retrievalUsable(trace), isFalse);
    expect(graphConsulted(trace), isTrue);

    final card = score([trace]);
    expect(card.retrievalsAttempted, 1);
    expect(card.retrievalsWithSomethingUsable, 0);
    expect(card.graphConsulted, 1);
  });

  test('retrieval hit alone does not count as graph consultation', () {
    final trace = row([
      {
        'description': 'Memory retrieval complete',
        'data': {'results': 3, 'used': 2},
      },
    ]);

    expect(retrievalUsable(trace), isTrue);
    expect(graphConsulted(trace), isFalse);

    final card = score([trace]);
    expect(card.retrievalsWithSomethingUsable, 1);
    expect(card.graphConsulted, 0);
  });

  test('scorecard counts recovered replies and post-process errors', () {
    final recovered = {
      ...row([
        {
          'description': 'Post-process recovered reply after tag extraction failed',
          'data': {'recoveredReply': true, 'error': 'tag parser exploded'},
        },
      ]),
      'finalResponse': 'Useful answer survived.',
    };
    final fallback = {
      ...row([
        {
          'description': 'Fallback response returned',
          'data': {'fallback': true},
        },
      ]),
      'finalResponse': '{"status":"error_occurred"}',
    };
    final clean = row([
      {'description': 'Tags extracted cleanly'},
    ]);

    expect(recoveredReply(recovered), isTrue);
    expect(recoveredReply(fallback), isTrue);
    expect(recoveredReply(clean), isFalse);
    expect(postProcessErrors(recovered), 1);

    final card = score([recovered, fallback, clean]);
    expect(card.recoveredReplies, 2);
    expect(card.postProcessErrors, 2);
  });

  test('scorecard counts structured route confidence and tool outcomes', () {
    final highConfidence = {
      ...row(const []),
      'route': 'coding',
      'routeConfidence': 0.91,
      'toolCalls': [
        {'name': 'self_check', 'outcome': 'passed'},
        {'name': 'edit_file', 'outcome': 'failed'},
      ],
    };
    final lowConfidence = {
      ...row(const []),
      'route': 'fastChat',
      'routeConfidence': 0.42,
      'toolCalls': [
        {'name': 'get_weather', 'outcome': 'success'},
      ],
    };

    final card = score([highConfidence, lowConfidence]);

    expect(card.routedTurns, 2);
    expect(card.highConfidenceRoutes, 1);
    expect(card.totalToolCalls, 3);
    expect(card.toolCallsRecorded, 3);
    expect(card.successfulToolCalls, 2);
    expect(card.failedToolCalls, 1);
  });

  test('scorecard sums prompt cost and token telemetry', () {
    final first = {
      ...row(const []),
      'promptInputTokens': 1000,
      'promptOutputTokens': 250,
      'promptCostUsd': 0.0015,
    };
    final second = {
      ...row(const []),
      'promptInputTokens': '500',
      'promptOutputTokens': '100',
      'promptCostUsd': '0.0007',
    };
    final missing = row(const []);

    expect(costTracked(first), isTrue);
    expect(costTracked(missing), isFalse);

    final card = score([first, second, missing]);

    expect(card.turnsWithCost, 2);
    expect(card.totalInputTokens, 1500);
    expect(card.totalOutputTokens, 350);
    expect(card.totalTokens, 1850);
    expect(card.totalCostUsd, closeTo(0.0022, 0.0000001));
    expect(card.averageCostUsd, closeTo(0.0011, 0.0000001));
    expect(card.averageTokens, 925);
    expect(card.report(), contains('cost tracked               2 of 3'));
  });

  test('scorecard counts mood telemetry averages, dips, and spikes', () {
    final steady = {
      ...row(const []),
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
    };
    final wobbleGoblin = {
      ...row(const []),
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
    };
    final missing = row(const []);

    expect(moodTracked(steady), isTrue);
    expect(moodTracked(missing), isFalse);
    expect(confidenceDipped(wobbleGoblin), isTrue);
    expect(playfulnessSpiked(wobbleGoblin), isTrue);

    final card = score([steady, wobbleGoblin, missing]);

    expect(card.turnsWithMood, 2);
    expect(card.averageMoodEnergy, 40);
    expect(card.averageMoodFocus, 50);
    expect(card.confidenceDips, 1);
    expect(card.playfulnessSpikes, 1);
    expect(card.report(), contains('mood tracked               2 of 3'));
  });
  test('efficiency summary reports prompt component slabs from traced turns', () {
    final summary = efficiencySummary([
      {
        ...row(const []),
        'route': 'coding',
        'promptInputTokens': 12000,
        'promptOutputTokens': 500,
        'promptCostUsd': 0.01,
        'promptComponentChars': {
          'kaiLiveState': 16000,
          'staticPreamble': 8000,
          'routePromptBlock': 4000,
        },
        'nonSystemInputChars': {
          'tool.content': 60000,
          'assistant.toolCalls': 12000,
          'user.content': 800,
          'messageCount': 5,
        },
      },
      {
        ...row(const []),
        'route': 'coding',
        'promptInputTokens': 10000,
        'promptOutputTokens': 500,
        'promptCostUsd': 0.01,
        'promptComponentChars': {
          'kaiLiveState': 12000,
          'staticPreamble': 4000,
          'routePromptBlock': 4000,
        },
        'nonSystemInputChars': {
          'tool.content': 40000,
          'assistant.toolCalls': 8000,
          'user.content': 800,
          'messageCount': 4,
        },
      },
    ], window: 2);

    expect(summary.recent.promptComponentTurns, 2);
    expect(summary.recent.averagePromptComponentChars('kaiLiveState'), 14000);
    expect(summary.recent.topPromptComponents.first.key, 'kaiLiveState');
    expect(summary.recent.nonSystemInputTurns, 2);
    expect(summary.recent.averageNonSystemInputChars('tool.content'), 50000);
    expect(summary.recent.topNonSystemInputs.first.key, 'tool.content');

    final report = summary.report();
    expect(report, contains('prompt slabs'));
    expect(report, contains('kaiLiveState: 14000 chars (~3500 tok)'));
    expect(report, contains('staticPreamble: 6000 chars (~1500 tok)'));
    expect(report, contains('non-system input'));
    expect(report, contains('tool.content: 50000 chars (~12500 tok)'));
  });

  test('input breakdown reports newest matching route rows first', () {
    Map<String, dynamic> trace(String id, String route, int input) => {
          ...row(const []),
          'id': id,
          'route': route,
          'promptInputTokens': input,
          'manifestApproxTokens': 100,
          'promptComponentChars': {'systemPromptTotal': 400},
          'nonSystemInputChars': {'tool.content': input * 4},
        };

    final report = inputBreakdownReport([
      trace('old-coding', 'coding', 1000),
      trace('middle-fast', 'fastChat', 2000),
      trace('new-coding', 'coding', 3000),
    ], route: 'coding', limit: 1);

    expect(report, contains('new-coding'));
    expect(report, contains('unattributed≈0 (clamped overcount)'));
    expect(report, contains('iterations='));
    expect(report, isNot(contains('old-coding')));
  });

  test('input breakdown groups metered api sends and final pass buckets', () {
    final report = inputBreakdownReport([
      {
        ...row(const []),
        'id': 'grouped-coding',
        'route': 'coding',
        'promptInputTokens': 10000,
        'manifestApproxTokens': 100,
        'promptComponentChars': {'systemPromptTotal': 400},
        'nonSystemInputChars': {
          'apiSend.tool.content': 20000,
          'apiSend.assistant.toolCallArgs': 8000,
          'finalPass.tool.content': 4000,
        },
        'assistantToolCallArgApproxTokensSaved': 1234,
      },
    ], route: 'coding', limit: 1);

    expect(report, contains('apiSend.*'));
    expect(report, contains('finalPass.*'));
    expect(report, contains('apiSend.tool.content'));
  });

  test('efficiency summary compares latest window to previous window by route', () {
    Map<String, dynamic> trace({
      required String route,
      required int input,
      required int output,
      required int schema,
      required int firstTokenMs,
      required int second,
      required double cost,
      int toolTrimTokensSaved = 0,
      int toolTrimCompactedResults = 0,
      int toolTrimHardCappedResults = 0,
    }) {
      final sentAt = DateTime.utc(2026, 7, 18, 12, 0, second);
      final startedAt = sentAt.subtract(Duration(milliseconds: firstTokenMs));
      return {
        ...row([
          {
            'description': 'Sending to GPT',
            'timestamp': sentAt.toIso8601String(),
          },
        ]),
        'route': route,
        'promptInputTokens': input,
        'promptOutputTokens': output,
        'promptCostUsd': cost,
        'manifestApproxTokens': schema,
        'manifestSchemaChars': schema * 4,
        'toolTrimApproxTokensSaved': toolTrimTokensSaved,
        'toolTrimCompactedResults': toolTrimCompactedResults,
        'toolTrimHardCappedResults': toolTrimHardCappedResults,
        'startTime': startedAt.toIso8601String(),
      };
    }

    final rows = [
      trace(
        route: 'fastChat',
        input: 9000,
        output: 1000,
        schema: 7000,
        firstTokenMs: 4000,
        second: 10,
        cost: 0.010,
      ),
      trace(
        route: 'coding',
        input: 15000,
        output: 1000,
        schema: 9000,
        firstTokenMs: 6000,
        second: 20,
        cost: 0.018,
        toolTrimTokensSaved: 6000,
        toolTrimCompactedResults: 3,
      ),
      trace(
        route: 'fastChat',
        input: 3000,
        output: 700,
        schema: 1000,
        firstTokenMs: 2500,
        second: 30,
        cost: 0.004,
      ),
      trace(
        route: 'coding',
        input: 12000,
        output: 800,
        schema: 8500,
        firstTokenMs: 5000,
        second: 40,
        cost: 0.014,
        toolTrimTokensSaved: 10000,
        toolTrimCompactedResults: 4,
        toolTrimHardCappedResults: 1,
      ),
    ];

    final summary = efficiencySummary(rows, window: 2);

    expect(summary.previous.averageTokens, 13000);
    expect(summary.recent.averageTokens, 8250);
    expect(summary.tokenReduction, closeTo(36.538, 0.001));
    expect(summary.previous.averageSchemaTokens, 8000);
    expect(summary.recent.averageSchemaTokens, 4750);
    expect(summary.schemaReduction, closeTo(40.625, 0.001));
    expect(summary.previous.averageTimeToFirstTokenMs, 5000);
    expect(summary.recent.averageTimeToFirstTokenMs, 3750);
    expect(summary.latencyReduction, 25);
    expect(summary.recent.averageInputTokens, 7500);
    expect(summary.recent.averageOutputTokens, 750);
    expect(summary.recent.inputTokenSharePercent, 91);
    expect(summary.recent.outputTokenSharePercent, 9);
    expect(summary.recent.schemaShareOfInputPercent, 63);
    expect(summary.recent.averageToolTrimTokensSaved, 10000);
    expect(summary.recent.totalToolTrimCompactedResults, 4);
    expect(summary.recent.totalToolTrimHardCappedResults, 1);
    expect(summary.recentByRoute['fastChat']!.averageSchemaTokens, 1000);
    expect(summary.recentByRoute['coding']!.averageSchemaTokens, 8500);
    expect(summary.recentByRoute['coding']!.averageToolTrimTokensSaved, 10000);
    expect(summary.report(), contains('schema tokens      ↓ 41%'));
    expect(summary.report(), contains('recent token mix   7500 in / 750 out; schema 63% of input'));
    expect(summary.report(), contains('tool-loop saved    10000 tok/trimmed turn  (4 compacted, 1 capped)'));
    expect(summary.report(), contains('fastChat: 1 turns'));
  });
}
