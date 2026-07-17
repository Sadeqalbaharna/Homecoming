import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/ai/task_planner_service.dart';
import 'package:homecoming_app/services/brain_debug_service.dart';
import 'package:homecoming_app/services/core/tool_executor_service.dart';

void main() {
  test('trace JSON carries route, iterations, and tool call outcomes', () {
    final trace = BrainDebugTrace(
      id: 'trace-1',
      userInput: 'fix the goblin',
      startTime: DateTime.utc(2026, 7, 17),
    );

    trace.recordRoute(name: 'coding', confidence: 0.86);
    trace.iterationCount = 3;
    trace.recordToolCall(
      name: 'self_check',
      args: {'target': 'myself'},
      result: 'Self-check on MYSELF: CLEAN. No errors, no warnings.',
      outcome: 'passed',
      iteration: 2,
    );

    final json = trace.toJson();

    expect(json['route'], 'coding');
    expect(json['routeConfidence'], 0.86);
    expect(json['iterationCount'], 3);

    final toolCalls = json['toolCalls'] as List<dynamic>;
    expect(toolCalls, hasLength(1));
    expect(toolCalls.single, containsPair('name', 'self_check'));
    expect(toolCalls.single, containsPair('outcome', 'passed'));
    expect(toolCalls.single, containsPair('iteration', 2));
    expect(toolCalls.single, containsPair('args', {'target': 'myself'}));
  });

  test('brain debug service records route and tool calls on current trace', () {
    final service = BrainDebugService();
    service.enable();
    final trace = service.startTrace('run your tests');

    service.recordRoute('coding', 0.91);
    service.recordIterationCount(4);
    service.recordToolCall(
      'run_tests',
      {'target': 'test/example_test.dart'},
      result: 'Tests on MYSELF: ALL PASSED.',
      outcome: 'passed',
      iteration: 3,
    );

    final json = trace.toJson();
    expect(json['route'], 'coding');
    expect(json['routeConfidence'], 0.91);
    expect(json['iterationCount'], 4);
    expect(json['toolCalls'], isNotEmpty);
  });

  test('planner-fired tools are recorded as structured trace tool calls', () async {
    final service = BrainDebugService();
    service.enable();
    final trace = service.startTrace('plan two cheap tools');

    final planArgs = {
      'goal': 'collect two timestamps',
      'steps': [
        {
          'description': 'read time once',
          'tool': 'get_current_time',
          'args': <String, dynamic>{},
        },
        {
          'description': 'read time twice',
          'tool': 'get_current_time',
          'args': <String, dynamic>{},
        },
      ],
    };

    final plan = KaiPlan.fromMap(planArgs);
    final result = await TaskPlannerService().executePlan(
      plan,
      ToolExecutorService(),
    );

    // create_plan itself is intercepted by AIService before executor.execute().
    // Planner steps, however, must be recorded by ToolExecutorService.execute(),
    // not hidden as prose inside this result string.
    service.recordToolCall(
      'create_plan',
      planArgs,
      result: result,
      outcome: ToolExecutorService.classifyToolOutcome('create_plan', result).label,
      iteration: 1,
    );

    final toolCalls = trace.toJson()['toolCalls'] as List<dynamic>;
    expect(toolCalls, hasLength(3));
    expect(toolCalls.map((c) => c['name']), [
      'get_current_time',
      'get_current_time',
      'create_plan',
    ]);
    expect(toolCalls.where((c) => c['name'] == 'get_current_time'), hasLength(2));
    expect(
      toolCalls.where((c) => c['name'] == 'get_current_time'),
      everyElement(containsPair('outcome', isNotEmpty)),
    );
  });
}

