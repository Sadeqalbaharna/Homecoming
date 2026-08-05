import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_noticed_service.dart';
import 'package:homecoming_app/services/core/kai_project_service.dart';
import 'package:homecoming_app/services/core/kai_self_improvement_runner.dart';

void main() {
  test('prioritises live tool bridge blockers over ordinary polish noticings', () {
    final runner = KaiSelfImprovementRunner.instance;
    final plan = runner.plan(
      noticings: const [
        Noticed(
          id: 'polish',
          text: 'Dashboard spacing could be prettier someday.',
          context: 'ui',
          notedAt: 1,
        ),
        Noticed(
          id: 'bridge',
          text: 'Newly-added tools are blocked by the outer API schema bridge, preventing live proof.',
          context: 'tool manifest',
          notedAt: 2,
          carried: 4,
        ),
      ],
      projects: const [],
    );

    expect(plan.hasWork, isTrue);
    expect(plan.selected!.id, 'noticed:bridge');
    expect(plan.selected!.priority, greaterThan(plan.candidates.last.priority));
    expect(
      plan.selected!.proofGates,
      contains('Run self_check last, after the final edit.'),
    );
  });

  test('turns non-trusted checklist items into bounded self-improvement candidates', () {
    final project = KaiProject(
      id: KaiProjectService.sentienceId,
      name: 'Sentience Ladder',
      why: 'Track real becoming.',
      layers: const [
        KaiLayer(
          n: 6,
          title: 'Becoming / Self-Iteration',
          intent: 'Scars become rules; rules fire from observable traces; behaviour changes later.',
          state: CapabilityState.tested,
          progress: 86,
          checklist: [
            'Live-use proof exists for new checklist status updates.',
            'Trusted regression prevents fake progress.',
          ],
          checklistStatus: {
            'Live-use proof exists for new checklist status updates.': ChecklistStatus.pending,
            'Trusted regression prevents fake progress.': ChecklistStatus.trusted,
          },
        ),
      ],
    );

    final plan = KaiSelfImprovementRunner.instance.plan(
      noticings: const [],
      projects: [project],
    );

    expect(plan.hasWork, isTrue);
    expect(plan.candidates, hasLength(1));
    expect(plan.selected!.id, startsWith('checklist:sentience_ladder:L6:'));
    expect(plan.selected!.source, 'checklist:pending');
    expect(
      plan.selected!.firstStep,
      contains('move this checklist item from pending with evidence'),
    );
  });

  test('returns no work when there are no noticings or checklist gaps', () {
    final project = KaiProject(
      id: 'done_project',
      name: 'Done Project',
      why: 'Nothing queued.',
      layers: const [
        KaiLayer(
          n: 1,
          title: 'Trusted Layer',
          intent: 'Already done.',
          state: CapabilityState.trusted,
          progress: 100,
          checklist: ['Proof exists.'],
          checklistStatus: {'Proof exists.': ChecklistStatus.trusted},
        ),
      ],
    );

    final plan = KaiSelfImprovementRunner.instance.plan(
      noticings: const [],
      projects: [project],
    );

    expect(plan.hasWork, isFalse);
    expect(plan.selected, isNull);
    expect(plan.candidates, isEmpty);
  });

  test('run chooses one wound, starts one proof-gated job, then stops', () async {
    final startedJobs = <({String personaId, String goal, String next})>[];

    final result = await KaiSelfImprovementRunner.instance.run(
      personaId: 'testkai',
      loadNoticings: (_) async => const [
        Noticed(
          id: 'bridge',
          text: 'Outer API schema bridge blocks newly-added tools from live proof.',
          context: 'tool manifest',
          notedAt: 1,
          carried: 4,
        ),
      ],
      loadProjects: (_) async => const [],
      startJob: (personaId, goal, {next = ''}) async {
        startedJobs.add((personaId: personaId, goal: goal, next: next));
      },
    );

    expect(startedJobs, hasLength(1));
    expect(startedJobs.single.personaId, 'testkai');
    expect(
      startedJobs.single.goal,
      'Self-improvement loop: Outer API schema bridge blocks newly-added tools from live proof.',
    );
    expect(
      startedJobs.single.next,
      'Inspect the code/state behind this noticing and confirm the wound is still real.',
    );

    expect(result, contains('Self-improvement loop started 1 bounded job.'));
    expect(result, contains('Selected: Outer API schema bridge blocks newly-added tools from live proof.'));
    expect(result, contains('Source: noticed:tool manifest'));
    expect(result, contains('First step: ${startedJobs.single.next}'));
    expect(result, contains('Proof gates:'));
    expect(result, contains('- Run self_check last, after the final edit.'));
    expect(result, isNot(contains('started 2')));
  });
}
