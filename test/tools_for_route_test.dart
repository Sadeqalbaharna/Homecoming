// toolsForRoute — what he's holding when you ask him something.
//
// This test exists because of one line in one trace:
//
//   🧰 [Agentic] route=contemplate (78%) → 36/39 tools
//
// Sadeq asked "so, what do you think we should do next?". The router read it
// correctly — contemplate, 78% — and he was handed 36 of 39 tools anyway,
// edit_file and run_command among them. The routing decision was being
// computed, logged, and then almost entirely ignored: on desktop the device
// and home sets are already gone via androidOnlyTools, so "drop device+home"
// dropped three tools and changed nothing.
//
// The correct thing existing, disconnected from the thing that runs. Again.
//
// The function is pure and static. There was nothing stopping this test being
// written except nobody writing it.

import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/tool_executor_service.dart';

Set<String> namesFor(String route, {double confidence = 0.9, bool hasWorkspace = true}) =>
    ToolExecutorService.toolsForRoute(route,
            confidence: confidence, hasWorkspace: hasWorkspace)
        .map((t) => ((t['function'] as Map)['name'] as String))
        .toSet();

void main() {
  group('contemplate — he keeps his eyes, not his power tools', () {
    test('the mutating toolchain is gone', () {
      final tools = namesFor('contemplate');
      for (final t in [
        'edit_file',
        'write_file',
        'run_command',
        'open_terminal',
        'code_task',
        'set_code_workspace',
      ]) {
        expect(tools, isNot(contains(t)),
            reason: 'asked what he thinks, handed a $t');
      }
    });

    test('reading survives — taking his eyes would make him guess', () {
      final tools = namesFor('contemplate');
      // The whole point. A contemplating Kai who cannot look at the code
      // answers from memory and sounds certain, which is the failure this
      // codebase keeps paying for.
      expect(tools, contains('read_file'));
      expect(tools, contains('search_code'));
      expect(tools, contains('self_check'));
    });

    test('the job stack survives — a long think is still a job', () {
      final tools = namesFor('contemplate');
      expect(tools, contains('job_start'));
      expect(tools, contains('job_progress'));
      expect(tools, contains('job_done'));
    });

    test('it actually strips something now', () {
      // The regression that started this. If contemplate ever again returns
      // everything, this fails loudly instead of being a log line nobody
      // reads.
      final all = ToolExecutorService.toolDefinitions.length;
      expect(namesFor('contemplate').length, lessThan(all - 3),
          reason: 'contemplate used to drop exactly 3 tools and call it routing');
    });
  });

  group('confidence is the guard', () {
    test('a guess costs him nothing — below 0.75 strips nothing', () {
      final all = ToolExecutorService.toolDefinitions.length;
      expect(namesFor('contemplate', confidence: 0.5).length, all);
      expect(namesFor('emotional', confidence: 0.74).length, all);
    });

    test('0.75 is the floor, and it is inclusive', () {
      final all = ToolExecutorService.toolDefinitions.length;
      expect(namesFor('contemplate', confidence: 0.75).length, lessThan(all));
    });
  });

  group('the other routes still mean what they said', () {
    test('coding keeps the hands', () {
      final tools = namesFor('coding');
      expect(tools, contains('edit_file'));
      expect(tools, contains('run_command'));
      expect(tools, contains('read_file'));
    });

    test('emotional drops engineering and the house', () {
      final tools = namesFor('emotional');
      expect(tools, isNot(contains('edit_file')));
      expect(tools, isNot(contains('read_file')));
      expect(tools, isNot(contains('control_tv')));
      // The device set deliberately survives this route — "call my brother"
      // mid-rough-day is reasonable and being unable would cost more than any
      // token saving. It can't be asserted here: these tests run on desktop,
      // where androidOnlyTools has already removed the phone entirely.
    });

    test('fastChat and tool keep everything', () {
      final all = ToolExecutorService.toolDefinitions.length;
      expect(namesFor('fastChat').length, all);
      expect(namesFor('tool').length, all);
    });

    test('an unknown route strips nothing rather than guessing', () {
      final all = ToolExecutorService.toolDefinitions.length;
      expect(namesFor('something_new_someone_added').length, all);
    });
  });

  test('no workspace means no hands, whatever the route', () {
    // His own engineerDirective says the engineering tools need a workspace.
    // Carrying schemas for tools that cannot work is pure tax.
    for (final route in ['coding', 'fastChat', 'contemplate']) {
      final tools = namesFor(route, hasWorkspace: false);
      expect(tools, isNot(contains('edit_file')), reason: 'route=$route');
      expect(tools, isNot(contains('read_file')), reason: 'route=$route');
      expect(tools, isNot(contains('self_check')), reason: 'route=$route');
    }
  });
}
