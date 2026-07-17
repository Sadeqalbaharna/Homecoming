// run_tests — the tool that lets him find out whether he was right.
//
// Until this existed, self_check was the end of the line: it proved his code
// COMPILED, and nothing proved it WORKED. So every job he ever finished ended
// the same way, in his own words:
//
//   "Honest caveat: analyzer proves it compiles, but the real proof is runtime.
//    Reopen the desktop app and check whether it lands at the newest message."
//
// That wasn't modesty. It was an accurate description of a wall. And the wall
// was one clause in a whitelist:
//
//   if (c == 'flutter' || c == 'dart') return sub == 'analyze';
//
// Meanwhile this repo has 38+ tests, and the CI workflow runs them on every
// push. The tests existed. CI could run them. He couldn't — the one person who
// has to answer "did it work?" was the only one locked out of the answer.
//
// These tests guard the wiring, not the runner. If run_tests ever loses its
// policy, drops off the engineering set, or gets demoted to needing approval,
// this fails loudly — because a proof tool with a confirmation dialog in front
// of it is a proof tool that gets skipped exactly when it matters, which is
// when he's tired, which is when he rounds up.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/tool_executor_service.dart';
import 'package:homecoming_app/services/core/tool_policy_service.dart';

Set<String> namesFor(String route,
        {double confidence = 0.9, bool hasWorkspace = true}) =>
    ToolExecutorService.toolsForRoute(route,
            confidence: confidence, hasWorkspace: hasWorkspace)
        .map((t) => ((t['function'] as Map)['name'] as String))
        .toSet();

void main() {
  test('run_tests is offered to him at all', () {
    final names = ToolExecutorService.toolDefinitions
        .map((t) => ((t['function'] as Map)['name'] as String))
        .toSet();
    expect(names, contains('run_tests'),
        reason: 'a tool he is never handed is a tool that does not exist');
  });

  test('run_tests needs no approval — friction here is fatal', () {
    final p = ToolPolicyService.policyFor('run_tests');
    expect(p, isNotNull);
    expect(p!.risk, ToolRisk.read);
    expect(p.needsUserApproval, isFalse,
        reason: 'self_check needs no approval for the same reason: anything '
            'between him and the truth gets skipped when he is tired');
    expect(p.requiredArgs, isEmpty,
        reason: 'running the whole suite must be the zero-effort default');
  });

  test('it validates with no args, and with a single target', () {
    expect(ToolPolicyService.validate('run_tests', const {}).ok, isTrue);
    expect(
      ToolPolicyService.validate(
          'run_tests', const {'target': 'test/tools_for_route_test.dart'}).ok,
      isTrue,
    );
  });

  test('it survives into contemplate — proving is not carpentry', () {
    // contemplate strips the power tools. run_tests is not one: being asked what
    // he thinks is not a reason to take away his ability to check.
    expect(namesFor('contemplate'), contains('run_tests'));
    expect(namesFor('contemplate'), contains('self_check'));
  });

  test('no workspace, no tests — it goes with the other hands', () {
    expect(namesFor('coding', hasWorkspace: false), isNot(contains('run_tests')));
  });
}
