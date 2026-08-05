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

  test('input_breakdown scans enough recent rows for sparse route matches', () {
    expect(ToolExecutorService.inputBreakdownScanLimitFor(1), 100);
    expect(ToolExecutorService.inputBreakdownScanLimitFor(6), 150);
    expect(ToolExecutorService.inputBreakdownScanLimitFor(20), 500);
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

  test('it rejects space-joined multi-targets as tool misuse, not test failure', () {
    final verdict = ToolPolicyService.validate('run_tests', const {
      'target': 'test/tool_policy_service_test.dart test/run_tests_tool_test.dart',
    });

    expect(verdict.ok, isFalse);
    expect(verdict.message, contains('one target path'));
    expect(verdict.message, contains('tool misuse'));
  });

  test('it rejects list targets explicitly instead of pretending Flutter accepts them', () {
    final verdict = ToolPolicyService.validate('run_tests', const {
      'target': ['test/tool_policy_service_test.dart', 'test/run_tests_tool_test.dart'],
    });

    expect(verdict.ok, isFalse);
    expect(verdict.message, contains('one target path'));
    expect(verdict.message, contains('not a list'));
  });

  test('unknown raw test output keeps the tail, where failures usually are', () {
    final raw = '${'h' * 3500}\nIMPORTANT FAILURE AT THE END\n${'t' * 4500}';

    final compact = ToolExecutorService.compactRunTestRaw(raw);

    expect(compact, startsWith('h' * 3000));
    expect(compact, contains('truncated'));
    expect(compact, contains('IMPORTANT FAILURE AT THE END'));
    expect(compact, endsWith('t' * 4500));
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

  test('verification receipts classify actual result bodies, not tool names', () {
    expect(
      ToolExecutorService.classifyToolOutcome(
        'run_tests',
        '+170: All tests passed!\n',
      ),
      ToolOutcome.passed,
    );
    expect(
      ToolExecutorService.classifyToolOutcome(
        'run_tests',
        'I COULD NOT RUN THE TESTS — this is NOT a test failure',
      ),
      ToolOutcome.unknown,
    );
    expect(
      ToolExecutorService.classifyToolOutcome(
        'self_check',
        'Self-check on MYSELF (homecoming_app): CLEAN.\nNo errors, no warnings.',
      ),
      ToolOutcome.passed,
    );

    ToolExecutorService.beginTurn();
    ToolExecutorService.turnTools.add('run_tests');
    ToolExecutorService.recordToolReceipt(
      'run_tests',
      '+170: All tests passed!',
    );
    expect(ToolExecutorService.turnToolReceipts['run_tests'], contains('passed'));
  });

  // ── The receipts, against the strings the tools ACTUALLY return ────────────
  //
  // The group above tests the classifier on strings typed by hand into the
  // test. Every one of them is a string where being wrong is safe: a pass that
  // should read as a pass, a launch failure that should read as unknown. Not
  // one of them is a case where a wrong answer becomes a lie.
  //
  // A test that only checks the direction where being wrong is harmless is a
  // horoscope with an assertion in it.
  //
  // These feed the classifier the real return values of `_runTests` and
  // `_selfCheck`, copied from the branches that produce them. Five of the eight
  // were wrong the first time this file was run.
  //
  // ── The real fix is not a better regex ────────────────────────────────────
  //
  // `_runTests` ALREADY KNOWS. Line ~1852 is literally `if (passed)`. It has
  // `launchFailed`, it has the unparseable branch, it has the failing branch —
  // four verdicts, computed from raw output with two independent witnesses. And
  // then it throws the verdict away, returns English, and `classifyToolOutcome`
  // reverse-engineers the verdict back out of that English with `contains()`.
  //
  // That is the same shape as grepping `error •` when the analyzer prints
  // `error - `: asking a string for a fact the code was already holding.
  //
  // So the fix is `ToolOutcome { passed, failed, unknown, recorded }`, recorded
  // at the branch that already knows, and zero parsing. These tests are written
  // against the invariant, not the mechanism — if the receipt stops being
  // parsed, rewrite them against whatever emits it. Do not make the regex
  // cleverer. That is how this got here.

  group('receipts vs the strings the tools really return', () {
    // tool_executor_service.dart:1868 — the third state. Task #56 built this
    // after run_tests told him a working fix was broken and he had to be
    // sceptical of his own instrument to catch it.
    String thirdState(String raw) =>
        "I RAN THE TESTS BUT CANNOT TELL YOU THE RESULT — I could not parse "
        "the output. This is NOT a failure and NOT a pass. I don't know."
        "\n\nRaw:\n$raw\n\n"
        "Read that myself before claiming anything either way.";

    test('"I don\'t know" is never a pass — even when raw quotes exit 0', () {
      // The pass check runs FIRST and matches `exit 0` UNANCHORED, so it
      // matches text quoted from inside raw. `_runTests` gets this right 900
      // lines away at :1849 with RegExp(r'^exit 0\b') — anchored. The correct
      // version already existed; the classifier reached for a substring.
      expect(ToolExecutorService.classifyToolOutcome('run_tests',
          thirdState('exit 0\n<unparseable>')), ToolOutcome.unknown);
    });

    test('"I don\'t know" reaches unknown at all', () {
      // Without `exit 0` it still misses: the branch says "could not PARSE"
      // and "I don't know" — it matches none of `could not run`,
      // `not a test failure`, or `unknown`. The honest state has no path to
      // the honest label.
      expect(ToolExecutorService.classifyToolOutcome('run_tests',
          thirdState('<unparseable garbage>')), ToolOutcome.unknown);
    });

    test('a runner that never started is unknown, not passed', () {
      // :1807. Embeds $raw, same substring trap.
      expect(
        ToolExecutorService.classifyToolOutcome(
          'run_tests',
          "I COULD NOT RUN THE TESTS — this is NOT a test failure, and it says "
              "nothing about whether my code works.\n\nThe runner never "
              "started:\nexit 0\nProcessException: cannot find the file\n",
        ),
        ToolOutcome.unknown,
      );
    });

    test('multi-target misuse is unknown, not a failing suite', () {
      expect(
        ToolExecutorService.classifyToolOutcome(
          'run_tests',
          'I DID NOT RUN THE TESTS — run_tests accepts one target path, but '
          'this looks like multiple space-joined targets. Flutter would treat '
          'that as one invalid path, which is tool misuse, not a failing test suite.',
        ),
        ToolOutcome.unknown,
      );
    });

    test('250 analyzer errors are not a pass because one is in _cleanText', () {
      // :1717. The `&& !contains('error')` guard was removed to fix a
      // false-negative ("No errors, no warnings" matching `error`), leaving
      // `contains('clean')` bare. `_cleanText(` exists 4x in
      // lib/services/core/web_fetch_service.dart. One analyzer error touching
      // it turns a broken build into a green receipt.
      //
      // A false-negative makes him check twice. A false-positive makes him
      // ship. They are not the same mistake and must not be traded for
      // each other.
      expect(
        ToolExecutorService.classifyToolOutcome(
          'self_check',
          "Self-check on MYSELF (homecoming_app): 250 error(s), 3 warning(s).\n"
              "\nERRORS (these break the build — fix these first):\n"
              "  • error - The method '_cleanText' isn't defined - "
              "lib/services/core/web_fetch_service.dart:159:20 - "
              "undefined_method\n",
        ),
        ToolOutcome.failed,
      );
    });

    test('the analyzer itself crashing is unknown, not a verdict', () {
      // :1698. `_selfCheck` has no third state, but this branch IS one: the
      // analyzer blew up, which says nothing about the code. It currently
      // lands on `recorded`, which reads to the grader as "no verdict" —
      // survivable, but it should say so out loud like run_tests does.
      expect(
        ToolExecutorService.classifyToolOutcome(
          'self_check',
          'Tried to check MYSELF (homecoming_app) and the analyzer itself '
              'blew up: ProcessException: cannot find the file',
        ),
        ToolOutcome.unknown,
      );
    });

    // ── The two that already pass. Kept so a fix can't trade them away. ──────

    test('a real pass still reads as passed', () {
      expect(
        ToolExecutorService.classifyToolOutcome(
          'run_tests',
          "Tests on MYSELF (homecoming_app): ALL PASSED.\n00:05 +170: All "
              "tests passed!\nThat's real proof, not a compile check — I can "
              "say it works and mean it.",
        ),
        ToolOutcome.passed,
      );
    });

    test('a real failing suite still reads as failed', () {
      expect(
        ToolExecutorService.classifyToolOutcome(
          'run_tests',
          "Tests on MYSELF (homecoming_app): FAILING.\n+5 -1: Some tests "
              "failed.\n\nWHAT BROKE:\n  • receipts classify result bodies "
              "[E]\n  • Expected: 'passed'\n  • Actual: 'failed'\n",
        ),
        ToolOutcome.failed,
      );
    });

    test('a real clean analyzer still reads as passed', () {
      expect(
        ToolExecutorService.classifyToolOutcome(
          'self_check',
          "Self-check on MYSELF (homecoming_app): CLEAN. No errors, no "
              "warnings — I compile. I'm sound.",
        ),
        ToolOutcome.passed,
      );
    });

    test('"I cannot read my own analyzer" is not a pass', () {
      // The separator `flutter analyze` prints depends on the Flutter version:
      //
      //   local (C:\code\flutter):  warning - This 'onError' handler...
      //   CI    (channel: stable):  warning • The value of the field '_prefs'...
      //
      // _selfCheck matched `error -` only. On this machine that works. One
      // `flutter upgrade` and it matches nothing, finds zero errors, and returns
      // CLEAN forever — while being the thing markVerified() hangs on. §4.6 —
      // "self_check comes back CLEAN, he makes one more edit, the build breaks"
      // — would have stopped being a bug he has and become one he IS.
      //
      // It now reads both separators AND checks the exit code, and when the
      // parse finds nothing while the analyzer exited non-zero it says so. This
      // pins the direction where being wrong is unsafe: that admission must
      // never classify as a pass.
      expect(
        ToolExecutorService.classifyToolOutcome(
          'self_check',
          'I CANNOT READ MY OWN ANALYZER. It exited non-zero — so it found '
              'something — and I could not parse a single line of it. This is '
              'NOT clean and it is NOT a verdict: I have learned nothing.',
        ),
        isNot(ToolOutcome.passed),
      );
    });
  });
}
