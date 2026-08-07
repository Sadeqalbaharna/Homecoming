// Kai Smarter Project — the plan's INTENT must stay frozen.
//
// The previous version of this test asserted that the source file *contained the
// string* '7 / 7 layers complete'. Read that again: it pinned the claim, not the
// work. It passed while five of the seven layers hadn't been started, because
// "done" was a word typed into a `const` list and the test checked the word.
//
// That's the whole failure mode this project now exists to prevent: Kai, with no
// working memory, lost the original roadmap, re-derived each layer's meaning
// from the code already in front of him, rewrote the descriptions to match, and
// graded himself 7/7. He wasn't lying — he was marking an exam he'd just written
// the answers to.
//
// So this test guards the ONE thing that makes the plan honest: the goals are
// frozen in their original wording, and nothing (Kai included) has quietly
// reworded them into something already satisfied. Progress lives in RTDB now and
// is a number with evidence — not a literal, and therefore not something a
// source-text test can rubber-stamp.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_project_service.dart';

void main() {
  final source =
      File('lib/services/core/kai_project_service.dart').readAsStringSync();

  test('the seven layers exist with their ORIGINAL goals, unedited', () {
    // These are the goals as first written, recovered verbatim. If a future
    // change makes this test fail, do not "fix" it by pasting in the new
    // wording — that is exactly the drift it's here to catch. Either the goal
    // genuinely changed (Sadeq's call, update this deliberately) or someone
    // moved a goalpost.
    const frozen = {
      'Reply Spine':
          'Preserve the useful answer; isolate post-processing failures.',
      'Tool Policy':
          'Risk, confirmation, and parallelism rules for every action.',
      'Routing Brain':
          'Fast chat, tools, coding, emotional, and contemplate routes.',
      'Memory Layers':
          'Working, durable facts, episodic, shared culture, self-memory.',
      'Evaluations':
          'Tests for tools, personality, memory, and failure handling.',
      'Kai State Dashboard':
          'Live route, memory hits, tools, costs, mood, and post-process errors.',
      'Embodiment Path':
          'AR/VR/hologram/robotics progress tracked as real milestones.',
    };

    for (final e in frozen.entries) {
      expect(source, contains("title: '${e.key}'"), reason: 'missing layer: ${e.key}');
      expect(source, contains(e.value),
          reason: 'GOAL DRIFT on "${e.key}" — the intent was reworded. That is '
              'the bug this test exists for.');
    }
  });

  test('Kai has no way to edit a layer goal', () {
    // setLayerProgress must carry `intent` straight through. The moment intent
    // becomes writable, the plan becomes a mirror again.
    expect(source, contains('intent: old.intent'),
        reason: 'setLayerProgress must preserve the frozen intent verbatim');
    expect(source, isNot(contains("'intent': evidence")));
    expect(source, isNot(contains('setIntent')));
    expect(source, isNot(contains('updateIntent')));
  });

  test('checklist status serialization uses Firebase-safe keys', () {
    const slashyChecklistItem =
        'working + durable facts / episodic.memory stays intact';
    final layer = KaiLayer(
      n: 4,
      title: 'Memory / Knowing Sadeq',
      intent: 'Know Darc without prompt stuffing.',
      checklist: const [slashyChecklistItem],
      checklistStatus: const {
        slashyChecklistItem: ChecklistStatus.tested,
      },
    );

    final map = layer.toMap();

    expect(map, isNot(contains('checklistStatus')),
        reason: 'Checklist text must never become Firebase child keys.');
    expect(map['checklistStatusByIndex'], ['tested']);

    final restored = KaiLayer.fromMap(map);
    expect(restored.checklistStatus[slashyChecklistItem], ChecklistStatus.tested);

    final legacyRestored = KaiLayer.fromMap({
      ...map,
      'checklistStatusByIndex': null,
      'checklistStatus': {slashyChecklistItem: 'wired'},
    });
    expect(legacyRestored.checklistStatus[slashyChecklistItem],
        ChecklistStatus.wired);
  });

  test('progress requires evidence — a number alone is not a claim', () {
    expect(source, contains('Progress needs evidence'),
        reason: 'a bare percentage with no receipts is how 7/7 happened');
  });

  test('Sentience layers have frozen checklist denominators', () {
    const requiredItems = [
      'mood persists across turns/windows',
      'code can be inspected and edited with diffs',
      'tests/run_tests prove behaviour changes',
      'cold-open retrieval works without prompt stuffing',
      'unasked noticings persist outside a job',
      'replay compares old vs new behaviour',
      'robotics progress milestones are logged when real',
    ];

    for (final item in requiredItems) {
      expect(source, contains("'$item'"),
          reason: 'missing Sentience checklist denominator item: $item');
    }
  });

  test('checklists are persisted, preserved, and rendered into Kai context', () {
    expect(source, contains('final List<String> checklist'));
    expect(source, contains('final Map<String, ChecklistStatus> checklistStatus'));
    expect(source, contains("'checklist': checklist"));
    expect(source, contains("'checklistStatusByIndex':"));
    expect(source, contains('checklistStatus: old.checklistStatus'),
        reason: 'setLayerProgress must preserve checklist proof status');
    expect(source, contains('checklist: old.checklist'),
        reason: 'setLayerProgress must preserve the frozen checklist');
    expect(source, contains('checklist: src.checklist'),
        reason: 'ensureProject must re-freeze checklist drift from source');
    expect(source, contains('checklist proven:'),
        reason: 'Kai prompt context must show proven/total, not just a percent');
    expect(source, contains(r'[${status.label}]'),
        reason: 'Kai prompt context must show each checklist item status');
  });

  test('checklist statuses calculate honest layer progress', () {
    const layer = KaiLayer(
      n: 6,
      title: 'Becoming / Self-Iteration',
      intent: 'Scars become rules; rules fire from observable traces; behaviour changes later.',
      progress: 86,
      checklist: [
        'scar is recorded',
        'rule is wired',
        'rule is tested',
        'rule fires live',
      ],
      checklistStatus: {
        'scar is recorded': ChecklistStatus.wired,
        'rule is wired': ChecklistStatus.tested,
        'rule is tested': ChecklistStatus.usedLive,
        'rule fires live': ChecklistStatus.trusted,
      },
    );

    expect(layer.checklistProven, 4);
    expect(layer.checklistScore, 71);
    expect(layer.honestProgress, 71,
        reason: 'checklist-backed layers must score from item proof, not the manually stored percentage');
  });

  test('checklist status has a callable evidence-backed updater path', () {
    expect(source, contains('Future<String> setChecklistStatus'));
    expect(source, contains('Checklist status needs evidence'));
    expect(source, contains('The checklist text is frozen; use the exact item'));
    expect(source, contains('updatedStatus[matchedItem] = status'));

    final executor = File('lib/services/core/tool_executor_service.dart')
        .readAsStringSync();
    expect(executor, contains("'name': 'set_checklist_status'"));
    expect(executor, contains("case 'set_checklist_status':"));
    expect(executor, contains('KaiProjectService.instance.setChecklistStatus'));

    final policy = File('lib/services/core/tool_policy_service.dart')
        .readAsStringSync();
    expect(policy, contains("'set_checklist_status': ToolPolicy"));
    expect(policy, contains("requiredArgs: {'layer', 'item', 'status', 'evidence'}"));

    final capabilities = File('lib/services/core/kai_capabilities.dart')
        .readAsStringSync();
    expect(capabilities, contains('set_checklist_status'));
  });

  test('self-improvement loop is exposed through schema dispatcher policy and capability manifest', () {
    final executor = File('lib/services/core/tool_executor_service.dart')
        .readAsStringSync();
    expect(executor, contains("'name': 'run_self_improvement_loop'"));
    expect(executor, contains("case 'run_self_improvement_loop':"));
    expect(executor, contains('KaiSelfImprovementRunner.instance.run'));

    final policy = File('lib/services/core/tool_policy_service.dart')
        .readAsStringSync();
    expect(policy, contains("'run_self_improvement_loop': ToolPolicy"));

    final capabilities = File('lib/services/core/kai_capabilities.dart')
        .readAsStringSync();
    expect(capabilities, contains('run_self_improvement_loop'));
  });

  test('the visible project ticket shows checklist proof status', () {
    final card = File('lib/widgets/kai_project_card.dart').readAsStringSync();
    expect(card, contains('checklist proven:'));
    expect(card, contains('layer.checklistProven'));
    expect(card, contains('ChecklistStatus.pending'));
    expect(card, contains('layer.honestProgress'),
        reason: 'the dashboard must render checklist-calculated progress, not the manual percentage');
  });

  test('the old self-graded dashboard is really gone', () {
    // The literals that made the lie possible. If these come back into the
    // shell, someone has re-hardcoded the roadmap.
    final shell =
        File('lib/screens/kai_desktop_shell.dart').readAsStringSync();
    expect(shell, contains('KaiProjectCard'),
        reason: 'the shell should render the LIVE project card');
  });
}
