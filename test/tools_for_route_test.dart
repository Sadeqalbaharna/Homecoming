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

Set<String> namesFor(String route,
        {double confidence = 0.9, bool hasWorkspace = true}) =>
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
          reason:
              'contemplate used to drop exactly 3 tools and call it routing');
    });
  });

  group('confidence is the guard', () {
    test('non-fastChat guesses still strip nothing below 0.75', () {
      final all = ToolExecutorService.toolDefinitions.length;
      expect(namesFor('contemplate', confidence: 0.5).length, all);
      expect(namesFor('emotional', confidence: 0.74).length, all);
    });

    test('low-confidence fastChat preserves desktop hands', () {
      final tools = namesFor('fastChat', confidence: 0.35);
      expect(
        tools,
        containsAll(ToolExecutorService.desktopCodingToolNames),
        reason: 'router uncertainty must not make Kai deny real capabilities',
      );
      expect(tools, contains('web_search'));
      expect(tools, contains('ask_memory'));
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
      expect(tools, contains('set_checklist_status'));
      expect(tools, contains('run_self_improvement_loop'));
    });

    test(
        'catch-all desktop manifest exposes every required tool by exact API name',
        () {
      final definitions = ToolExecutorService.toolsForRoute(
        'fastChat',
        confidence: 0.35,
        hasWorkspace: true,
      );
      final names = ToolExecutorService.toolNames(definitions).toSet();

      expect(
        names,
        containsAll(ToolExecutorService.desktopCodingToolNames),
      );
      expect(names, contains('write_file'));
      expect(names, contains('edit_file'));
      expect(names, isNot(contains('write_file/edit_file')));
    });

    test('tool-name extractor reads the same nested field sent to OpenAI', () {
      expect(
        ToolExecutorService.toolName({
          'type': 'function',
          'function': {'name': 'read_file'},
        }),
        'read_file',
      );
      expect(ToolExecutorService.toolName({'name': 'read_file'}), isNull);
    });

    test('exact manifest becomes explicit awareness of Kai\'s current hands', () {
      final definitions = ToolExecutorService.toolsForRoute(
        'fastChat',
        confidence: 0.35,
        hasWorkspace: true,
      );
      final block = ToolExecutorService.toolAwarenessBlock(
        ToolExecutorService.toolNames(definitions),
      );

      expect(block, contains('THESE ARE REAL AND ATTACHED TO THIS REQUEST'));
      for (final name in ToolExecutorService.desktopCodingToolNames) {
        expect(block, contains('- $name'));
      }
      expect(block, contains('use it instead of merely'));
      expect(block, contains('Never claim a tool that is absent'));
    });

    test('empty manifest explicitly tells Kai he has no tools this turn', () {
      final block = ToolExecutorService.toolAwarenessBlock(const []);
      expect(block, contains('none are attached'));
      expect(block, contains('Do not claim'));
    });

    test(
        'new self-iteration tools are present in the emitted schema, not just source-grep wired',
        () {
      final all = ToolExecutorService.toolDefinitions
          .map((t) => ((t['function'] as Map)['name'] as String))
          .toSet();

      expect(all, contains('set_checklist_status'));
      expect(all, contains('run_self_improvement_loop'));
    });

    test('factory run ledger survives cheap routes and no-workspace mode', () {
      // Product scouting is not the same as code editing. The factory state
      // machine must be reachable even when the engineering toolbox is stripped,
      // otherwise Kai can scout but cannot formally start or record the run.
      for (final tools in [
        namesFor('fastChat', confidence: 0.35),
        namesFor('emotional'),
        namesFor('contemplate'),
        namesFor('fastChat', confidence: 0.35, hasWorkspace: false),
      ]) {
        expect(tools, contains('factory_start'));
        expect(tools, contains('factory_status'));
        expect(tools, contains('factory_record'));
        expect(tools, contains('factory_advance'));
        expect(tools, contains('scout_score'));
      }
    });

    test(
        'list_dir schema really defaults to root instead of requiring an empty path',
        () {
      final listDir = ToolExecutorService.toolDefinitions.firstWhere(
        (t) => ((t['function'] as Map)['name'] as String) == 'list_dir',
      );
      final function = listDir['function'] as Map;
      final parameters = function['parameters'] as Map;

      expect(parameters['required'], isNull,
          reason: 'empty means root is useless if the schema rejects omission');
      expect(function['description'] as String, contains('omitted'));
      expect(function['description'] as String, contains('"."'));
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

    test('tool and catch-all fastChat keep everything when workspace exists', () {
      final all = ToolExecutorService.toolDefinitions.length;
      expect(namesFor('fastChat', confidence: 0.35).length, all);
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
      expect(tools, isNot(contains('run_self_improvement_loop')),
          reason: 'route=$route');
    }
  });

  test('manifest gains code hands immediately after workspace becomes available', () {
    final before = namesFor(
      'fastChat',
      confidence: 0.35,
      hasWorkspace: false,
    );
    final after = namesFor(
      'fastChat',
      confidence: 0.35,
      hasWorkspace: true,
    );

    expect(before, contains('set_code_workspace'));
    expect(before, isNot(contains('read_file')));
    expect(after, containsAll(ToolExecutorService.desktopCodingToolNames));
  });

  test('no-workspace awareness tells Kai to acquire code hands automatically', () {
    final names = namesFor(
      'fastChat',
      confidence: 0.35,
      hasWorkspace: false,
    );
    final block = ToolExecutorService.toolAwarenessBlock(names);

    expect(block, contains('WORKSPACE RECOVERY'));
    expect(block, contains('set_code_workspace immediately'));
    expect(block, contains('automatically refresh this'));
    expect(block, contains("I'm activating my hands"));
  });

  test('hands light state follows the actual manifest', () {
    final acquiring = namesFor('fastChat', hasWorkspace: false);
    final ready = namesFor('fastChat', hasWorkspace: true);

    expect(
      ToolExecutorService.handsStateForTools(acquiring),
      KaiHandsState.activating,
    );
    expect(
      ToolExecutorService.handsStateForTools(ready),
      KaiHandsState.on,
    );
    expect(
      ToolExecutorService.handsStateForTools(const []),
      KaiHandsState.off,
    );
  });
}
