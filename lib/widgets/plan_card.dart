// plan_card.dart
//
// Expandable card that shows a KaiPlan's goal and each step's status in
// real-time as the planner executes them.
//
// Usage (in chat bubble area):
//   PlanCard(plan: _activePlan, isExpanded: _planExpanded,
//            onToggle: () => setState(() => _planExpanded = !_planExpanded))

library;

import 'package:flutter/material.dart';
import '../services/ai/task_planner_service.dart';

class PlanCard extends StatelessWidget {
  final KaiPlan plan;
  final bool isExpanded;
  final VoidCallback? onToggle;

  const PlanCard({
    super.key,
    required this.plan,
    this.isExpanded = true,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final done    = plan.steps.where((s) => s.status == StepStatus.done).length;
    final total   = plan.steps.length;
    final running = plan.steps.any((s) => s.status == StepStatus.running);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: running
              ? const Color(0xFF3D9BFF).withOpacity(0.6)
              : const Color(0xFF2A2A3E),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  // Animated spinner when running, checkmark when complete
                  if (running)
                    const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Color(0xFF3D9BFF)),
                      ),
                    )
                  else if (plan.isComplete)
                    const Icon(Icons.check_circle_rounded,
                        size: 16, color: Color(0xFF4ADE80))
                  else
                    const Icon(Icons.list_alt_rounded,
                        size: 16, color: Color(0xFF9CA3AF)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      plan.goal,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Progress count
                  Text(
                    '$done/$total',
                    style: TextStyle(
                      color: done == total
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFF9CA3AF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: const Color(0xFF6B7280),
                  ),
                ],
              ),
            ),
          ),

          // ── Step list (collapsible) ──────────────────────────────────────
          AnimatedCrossFade(
            firstChild: _buildStepList(),
            secondChild: const SizedBox.shrink(),
            crossFadeState: isExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildStepList() {
    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Color(0xFF2A2A3E), height: 1),
          const SizedBox(height: 8),
          ...plan.steps.asMap().entries.map((e) => _buildStep(e.key, e.value)),
        ],
      ),
    );
  }

  Widget _buildStep(int index, PlanStep step) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status icon
          SizedBox(
            width: 20,
            child: _stepIcon(step.status),
          ),
          const SizedBox(width: 8),
          // Description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.description,
                  style: TextStyle(
                    color: step.status == StepStatus.pending
                        ? const Color(0xFF6B7280)
                        : Colors.white,
                    fontSize: 12.5,
                    fontWeight: step.status == StepStatus.running
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                // Show result snippet when done
                if (step.status == StepStatus.done &&
                    step.result != null &&
                    step.result!.isNotEmpty &&
                    step.result != '[reasoning step — no tool required]')
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _truncate(step.result!, 80),
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (step.status == StepStatus.failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      step.result ?? 'Failed',
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepIcon(StepStatus status) {
    switch (status) {
      case StepStatus.pending:
        return const Icon(Icons.radio_button_unchecked,
            size: 16, color: Color(0xFF4B5563));
      case StepStatus.running:
        return const SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(Color(0xFF3D9BFF)),
          ),
        );
      case StepStatus.done:
        return const Icon(Icons.check_circle_rounded,
            size: 16, color: Color(0xFF4ADE80));
      case StepStatus.failed:
        return const Icon(Icons.cancel_rounded,
            size: 16, color: Color(0xFFEF4444));
    }
  }

  String _truncate(String s, int maxLen) =>
      s.length <= maxLen ? s : '${s.substring(0, maxLen)}…';
}
