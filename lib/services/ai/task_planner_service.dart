// lib/services/ai/task_planner_service.dart
//
// Multi-step plan model + sequential executor.
//
// Flow:
//   1. GPT calls create_plan({goal, steps}) via the agentic loop
//   2. _callOpenAIWithTools intercepts it and calls TaskPlannerService.executePlan()
//   3. Each step runs via ToolExecutorService (or pure-reasoning if no tool)
//   4. Progress fires onStepUpdate so the UI can update the plan card in real-time
//   5. All step results are bundled into a context string and returned to GPT
//   6. GPT writes a synthesised final reply

library;

import '../core/tool_executor_service.dart';
import '../core/tool_policy_service.dart';

// ── Data model ────────────────────────────────────────────────────────────────

enum StepStatus { pending, running, done, failed }

class PlanStep {
  final String description;
  final String? tool; // optional: exact tool name to invoke
  final Map<String, dynamic> args;

  StepStatus status;
  String? result; // filled after execution

  PlanStep({
    required this.description,
    this.tool,
    this.args = const {},
    this.status = StepStatus.pending,
    this.result,
  });

  factory PlanStep.fromMap(Map<String, dynamic> m) => PlanStep(
        description: m['description'] as String? ?? '',
        tool: m['tool'] as String?,
        args: Map<String, dynamic>.from(
          (m['args'] as Map?)?.cast<String, dynamic>() ?? {},
        ),
      );
}

class KaiPlan {
  final String goal;
  final List<PlanStep> steps;

  KaiPlan({required this.goal, required this.steps});

  factory KaiPlan.fromMap(Map<String, dynamic> m) => KaiPlan(
        goal: m['goal'] as String? ?? '',
        steps: (m['steps'] as List? ?? [])
            .map((s) => PlanStep.fromMap(Map<String, dynamic>.from(s as Map)))
            .toList(),
      );

  bool get isComplete => steps.every(
      (s) => s.status == StepStatus.done || s.status == StepStatus.failed);
}

// ── Executor ──────────────────────────────────────────────────────────────────

typedef StepUpdateCallback = void Function(KaiPlan plan, int stepIndex);

class TaskPlannerService {
  static final TaskPlannerService _i = TaskPlannerService._();
  factory TaskPlannerService() => _i;
  TaskPlannerService._();

  /// Execute every step in [plan] in order.
  ///
  /// [onStepUpdate] fires:
  ///   • when a step transitions to [StepStatus.running]
  ///   • when a step transitions to [StepStatus.done] or [StepStatus.failed]
  ///
  /// Returns a formatted context string with all results — this goes back
  /// into the GPT message history so GPT can write the final synthesised reply.
  Future<String> executePlan(
    KaiPlan plan,
    ToolExecutorService executor, {
    StepUpdateCallback? onStepUpdate,
  }) async {
    final buf = StringBuffer();
    buf.writeln('PLAN RESULTS — Goal: "${plan.goal}"');
    buf.writeln('─' * 48);

    // Detect independent steps using the deterministic tool policy registry.
    // The old version carried a duplicate hand-written list of data tools here,
    // which is how planners rot. One source of truth, tiny goblin discipline.
    bool isParallelSafe(PlanStep s) => ToolPolicyService.isParallelSafe(s.tool);

    // Split into groups: data-gathering / reasoning steps run sequentially first,
    // then pure side-effect action steps can run in parallel.
    final dataSteps = <int>[];
    final actionSteps = <int>[];
    for (int i = 0; i < plan.steps.length; i++) {
      if (isParallelSafe(plan.steps[i])) {
        actionSteps.add(i);
      } else {
        dataSteps.add(i);
      }
    }

    // ── Phase 1: sequential data/reasoning steps ─────────────────────────────
    for (final i in dataSteps) {
      await _runStep(plan, i, executor, onStepUpdate);
    }

    // ── Phase 2: parallel action steps ──────────────────────────────────────
    if (actionSteps.isNotEmpty) {
      // Mark all as running first so the UI shows them simultaneously.
      for (final i in actionSteps) {
        plan.steps[i].status = StepStatus.running;
        onStepUpdate?.call(plan, i);
      }
      await Future.wait(
        actionSteps.map((i) => _runStep(
              plan,
              i,
              executor,
              onStepUpdate,
              alreadyMarkedRunning: true,
            )),
      );
    }

    for (int i = 0; i < plan.steps.length; i++) {
      final s = plan.steps[i];
      buf.writeln('\nStep ${i + 1}: ${s.description}');
      buf.writeln('Status: ${s.status.name}');
      buf.writeln('Result: ${s.result ?? "(none)"}');
    }

    buf.writeln('\n─' * 48);
    buf.writeln('All ${plan.steps.length} step(s) executed. '
        'Now write a natural, concise summary for the user.');

    return buf.toString();
  }

  Future<void> _runStep(
    KaiPlan plan,
    int i,
    ToolExecutorService executor,
    StepUpdateCallback? onStepUpdate, {
    bool alreadyMarkedRunning = false,
  }) async {
    final step = plan.steps[i];

    if (!alreadyMarkedRunning) {
      step.status = StepStatus.running;
      onStepUpdate?.call(plan, i);
    }

    try {
      String result;
      if (step.tool != null && step.tool!.isNotEmpty) {
        print('📋 [Planner] Step ${i + 1}: calling tool "${step.tool}"');
        result = await executor.execute(step.tool!, step.args);
      } else {
        result = '[reasoning step — no tool required]';
      }
      step.result = result;
      step.status = result.startsWith('Tool call blocked:')
          ? StepStatus.failed
          : StepStatus.done;
      print('✅ [Planner] Step ${i + 1} ${step.status.name}: '
          '${result.length > 80 ? result.substring(0, 80) : result}');
    } catch (e) {
      step.result = 'Error: $e';
      step.status = StepStatus.failed;
      print('❌ [Planner] Step ${i + 1} failed: $e');
    }

    onStepUpdate?.call(plan, i);
  }
}
