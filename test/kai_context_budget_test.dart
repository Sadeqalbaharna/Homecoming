import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_context_block.dart';
import 'package:homecoming_app/services/core/kai_project_service.dart';
import 'package:homecoming_app/services/core/kai_router_service.dart';

void main() {
  test('fast-chat static preamble drops capability and engineering scaffolding', () {
    final full = KaiContextBlock.staticPreamble();
    final fast = KaiContextBlock.staticPreamble(
      includeCapabilities: false,
      includeEngineerLoop: false,
    );

    expect(full, contains('What I can actually do'));
    expect(full, contains('I AM THE ONE WHO CAN COMPILE'));

    expect(fast, isNot(contains('What I can actually do')));
    expect(fast, isNot(contains('I AM THE ONE WHO CAN COMPILE')));

    // Keep the short agency spine; fast chat should be cheaper, not toothless.
    expect(fast, contains('BIAS TO ACTION'));

    // This is intentionally ratio-based so wording edits do not make the test
    // brittle, while still catching the expensive accidental re-inflation.
    expect(fast.length, lessThan(full.length * 0.35));
  });

  test('coding static preamble keeps hands but drops repeated engineer scars', () {
    final full = KaiContextBlock.staticPreamble();
    final coding = KaiContextBlock.staticPreamble(
      includeCapabilities: true,
      includeEngineerLoop: false,
    );

    expect(coding, contains('What I can actually do'));
    expect(coding, contains('BIAS TO ACTION'));
    expect(coding, isNot(contains('I AM THE ONE WHO CAN COMPILE')));
    expect(coding, isNot(contains('How I work on code')));

    final charsSaved = full.length - coding.length;
    expect(charsSaved, greaterThan(6000));
    expect(_approxTokens(charsSaved), greaterThan(1500));
    expect(coding.length, lessThan(full.length * 0.65));
  });

  test('fast-chat liveState skips rich self-maintenance payloads', () async {
    final full = await KaiContextBlock.liveState('kai_test_budget');
    final fast = await KaiContextBlock.liveState(
      'kai_test_budget',
      route: KaiRoute.fastChat,
    );

    expect(fast.length, lessThan(full.length));
    expect(fast, contains('=== Who I am right now ==='));
    expect(fast, isNot(contains('WHAT I AM IN THE MIDDLE OF')));
    expect(fast, isNot(contains('THINGS I NOTICED THAT NOBODY ASKED ME TO')));
    expect(fast, isNot(contains('MY HANDS:')));
    expect(fast, isNot(contains('MY PLAN TO BECOME SMARTER')));
    expect(fast, isNot(contains('My body, right now:')));
    expect(fast, isNot(contains('WHAT I\'VE LEARNED THE HARD WAY')));
    expect(fast, isNot(contains('Notes I left for myself')));
  });

  test('coding liveState keeps work payloads but drops self-lore payloads', () async {
    final full = await KaiContextBlock.liveState('kai_test_budget');
    final coding = await KaiContextBlock.liveState(
      'kai_test_budget',
      route: KaiRoute.coding,
    );

    expect(coding.length, lessThan(full.length));
    expect(coding, contains('=== Who I am right now ==='));
    expect(coding, contains('MY HANDS:'));

    // Coding turns are the expensive route. They need current work context, not
    // recurring autobiography blocks that are useful for identity but irrelevant
    // to reading files, editing, and verifying.
    expect(coding, isNot(contains('What my mind was actually chewing on')));
    expect(coding, isNot(contains('My body, right now:')));
    expect(coding, isNot(contains('WHAT I\'VE LEARNED THE HARD WAY')));
    expect(coding, isNot(contains('Notes I left for myself')));
  });

  test('compact project prompt keeps scoreboard but drops frozen wall text', () {
    final project = _budgetProject(
      id: KaiProjectService.smarterId,
      name: 'Kai Smarter Project',
      why: 'Make me genuinely smarter — not a dashboard that says I am.',
      layerCount: 1,
      checklistCount: 2,
      provenChecklistCount: 1,
    );

    final full = KaiProjectService.renderPromptBlockForProjects(
      smarter: project,
    );
    final compact = KaiProjectService.renderPromptBlockForProjects(
      smarter: project,
      compact: true,
    );

    expect(compact.length, lessThan(full.length));
    expect(compact, contains('MY PLAN TO BECOME SMARTER'));
    expect(compact, contains('L1 Reply Spine'));
    expect(compact, contains('40 — wired but not trusted'));
    expect(compact, contains('checklist proven: 1/2'));
    expect(compact, contains('last: recoveredReply preserves the answer'));
    expect(compact, contains('Compact board view'));

    expect(full, contains('goal: Preserve the useful answer'));
    expect(full, contains('- [tested] Frozen checklist item 1.1'));
    expect(full, contains('The "goal" lines are FROZEN'));
    expect(compact, isNot(contains('goal: Preserve the useful answer')));
    expect(compact, isNot(contains('Frozen checklist item 1.1')));
    expect(compact, isNot(contains('The "goal" lines are FROZEN')));
  });

  test('compact project prompt has a measured budget delta receipt', () {
    final smarter = _budgetProject(
      id: KaiProjectService.smarterId,
      name: 'Kai Smarter Project',
      why: 'Make me genuinely smarter — not a dashboard that says I am.',
      layerCount: 7,
      checklistCount: 5,
    );
    final sentience = _budgetProject(
      id: KaiProjectService.sentienceId,
      name: 'Sentience Ladder',
      why: 'Track the axes that make Kai more continuous and capable.',
      layerCount: 7,
      checklistCount: 5,
    );

    final full = KaiProjectService.renderPromptBlockForProjects(
      smarter: smarter,
      sentience: sentience,
    );
    final compact = KaiProjectService.renderPromptBlockForProjects(
      smarter: smarter,
      sentience: sentience,
      compact: true,
    );

    final charsSaved = full.length - compact.length;
    final approxTokensSaved = _approxTokens(charsSaved);
    final reduction = charsSaved / full.length;

    // Receipt for efficiency work. If this fails, the coding prompt budget grew
    // enough that someone needs to consciously re-approve the extra context.
    // Current synthetic two-board fixture saves thousands of chars by dropping
    // repeated goal/checklist walls while keeping the scoreboard and last proof.
    expect(charsSaved, greaterThan(4500));
    expect(approxTokensSaved, greaterThan(1100));
    expect(reduction, greaterThan(0.45));

    expect(compact, contains('MY PLAN TO BECOME SMARTER'));
    expect(compact, contains('MY SENTIENCE AXES'));
    expect(compact, contains('checklist proven: 3/5'));
    expect(compact, contains('last: evidence receipt for layer 7'));
    expect(compact, isNot(contains('goal: Preserve the useful answer')));
    expect(compact, isNot(contains('Frozen checklist item 7.5')));
  });

}

int _approxTokens(int chars) => (chars / 4).round();

KaiProject _budgetProject({
  required String id,
  required String name,
  required String why,
  required int layerCount,
  required int checklistCount,
  int provenChecklistCount = 3,
}) {
  return KaiProject(
    id: id,
    name: name,
    why: why,
    layers: List.generate(layerCount, (i) {
      final n = i + 1;
      final checklist = List.generate(
        checklistCount,
        (j) => 'Frozen checklist item $n.${j + 1}',
      );
      return KaiLayer(
        n: n,
        title: n == 1 ? 'Reply Spine' : 'Layer $n',
        intent: n == 1
            ? 'Preserve the useful answer; isolate post-processing failures.'
            : 'Frozen goal text for layer $n that repeats every turn until the budget goblin eats the wallet.',
        progress: 40,
        evidence: [
          n == 1 ? 'recoveredReply preserves the answer' : 'evidence receipt for layer $n',
        ],
        state: CapabilityState.wired,
        stamp: n == 1 ? '40 — wired but not trusted' : '40 — layer $n stamp',
        checklist: checklist,
        checklistStatus: {
          for (final item in checklist.take(provenChecklistCount))
            item: ChecklistStatus.tested,
        },
      );
    }),
  );
}
