// ClaudeCodeAgent
//
// Phase 1 of engineer mode: a small Anthropic tool-use loop that gives the
// Claude hemisphere READ-ONLY access to a code workspace, so it can actually
// investigate the repo (read / list / grep / glob) before answering — instead
// of guessing. It plans, calls tools, reads the results, and iterates until it
// produces a grounded answer.
//
// Read-only by construction: the only tools exposed are the four inspection
// tools from CodeWorkspaceService. Nothing here can write, delete, or run.
// Returns null on any failure (no key, no workspace, API error) so the caller
// can fall back to a plain single-shot Claude reply.

import 'package:dio/dio.dart';
import 'ai_config.dart';
import 'usage_tracking_service.dart';
import '../core/cortex_activity_bus.dart';
import '../core/code_workspace_service.dart';
import '../core/edit_gate.dart';
import '../core/engineer_status_bus.dart';

class ClaudeCodeAgent {
  final _dio = Dio();

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _version = '2023-06-01';
  static const _model = 'claude-sonnet-5';
  static const _maxIterations = 8;

  static const _system =
      "You are Kai's coding brain, powered by Claude, working inside the user's "
      "chosen code workspace. Investigate before you act: use search_code / "
      "find_files to locate things and read_file to confirm exact contents. "
      "You MAY change files with edit_file (targeted string replacement — "
      "strongly preferred for existing files) and write_file (create or fully "
      "overwrite). EVERY write is shown to the user as a diff and applied only if "
      "they approve; a rejection comes back as a tool result — if rejected, stop "
      "and ask rather than retrying. Make minimal, surgical edits, one file at a "
      "time, and read a file immediately before editing it so old_string matches "
      "exactly. On desktop you can run_command (e.g. 'flutter analyze', 'dart "
      "test', 'git diff') to check your work — after editing, run analyze/tests "
      "and fix what breaks. Read-only commands run automatically; others ask the "
      "user. Explain what you changed and why, citing file paths and line numbers.";

  List<Map<String, dynamic>> get _tools {
    final tools = <Map<String, dynamic>>[
        {
          'name': 'read_file',
          'description':
              'Read a UTF-8 text file (returned line-numbered) at a workspace-relative path.',
          'input_schema': {
            'type': 'object',
            'properties': {'path': {'type': 'string'}},
            'required': ['path'],
          },
        },
        {
          'name': 'list_dir',
          'description':
              'List entries of a workspace-relative directory. Use "" for the workspace root.',
          'input_schema': {
            'type': 'object',
            'properties': {'path': {'type': 'string'}},
            'required': ['path'],
          },
        },
        {
          'name': 'search_code',
          'description':
              'Regex-search file contents across the workspace. Optional glob to scope (e.g. "**/*.dart"). Returns path:line: match.',
          'input_schema': {
            'type': 'object',
            'properties': {
              'pattern': {'type': 'string'},
              'glob': {'type': 'string'},
            },
            'required': ['pattern'],
          },
        },
        {
          'name': 'find_files',
          'description': 'List files matching a glob, e.g. "lib/**/*.dart".',
          'input_schema': {
            'type': 'object',
            'properties': {'glob': {'type': 'string'}},
            'required': ['glob'],
          },
        },
        {
          'name': 'edit_file',
          'description':
              'Replace an exact substring in a file (preferred for existing files). '
              'old_string must appear EXACTLY once — include surrounding lines to make '
              'it unique. Shown to the user as a diff; applied only on approval.',
          'input_schema': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'old_string': {'type': 'string'},
              'new_string': {'type': 'string'},
            },
            'required': ['path', 'old_string', 'new_string'],
          },
        },
        {
          'name': 'write_file',
          'description':
              'Create a new file, or fully overwrite an existing one, with the given '
              'content. Use for new files; prefer edit_file for changes. Shown to the '
              'user as a diff; applied only on approval.',
          'input_schema': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'content': {'type': 'string'},
            },
            'required': ['path', 'content'],
          },
        },
    ];
    // Shell tool only exists on desktop — never offered to the mobile build.
    if (CodeWorkspaceService.shellSupported) {
      tools.add({
        'name': 'run_command',
        'description':
            'Run a command in the workspace (e.g. flutter analyze, dart test, '
            'git diff). Pass the executable and its args separately — no shell is '
            'used. Read-only commands run automatically; others need approval.',
        'input_schema': {
          'type': 'object',
          'properties': {
            'command': {
              'type': 'string',
              'description': 'Executable, e.g. flutter, dart, git.',
            },
            'args': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'Arguments, e.g. ["analyze"].',
            },
          },
          'required': ['command'],
        },
      });
    }
    return tools;
  }

  /// Run the agent for [task]. Returns the final answer, or null to fall back.
  Future<String?> run({required String task, String? extraContext}) async {
    final key = await AIConfig.getAnthropicKey();
    if (key.isEmpty) return null;
    final ws = CodeWorkspaceService.instance;
    await ws.load();
    if (!ws.hasWorkspace) return null;

    CortexActivityBus.instance.brain(CortexBrain.claude, ms: 6000);
    EngineerStatusBus.instance.emit('investigating', project: ws.root);

    final firstMsg = (extraContext != null && extraContext.trim().isNotEmpty)
        ? 'Workspace root: ${ws.root}\n\nTASK:\n$task\n\nCONTEXT:\n$extraContext'
        : 'Workspace root: ${ws.root}\n\nTASK:\n$task';
    final messages = <Map<String, dynamic>>[
      {'role': 'user', 'content': firstMsg}
    ];

    try {
      for (int iter = 0; iter < _maxIterations; iter++) {
        final res = await _dio.post(
          _endpoint,
          options: Options(headers: {
            'x-api-key': key,
            'anthropic-version': _version,
            'content-type': 'application/json',
          }),
          data: {
            'model': _model,
            'max_tokens': 4096,
            'system': _system,
            'tools': _tools,
            'messages': messages,
          },
        );

        final data = res.data as Map<String, dynamic>;
        final usage = data['usage'] as Map?;
        UsageTrackingService.trackAnthropic(
          model: _model,
          inputTokens: (usage?['input_tokens'] as num?)?.toInt() ?? 0,
          outputTokens: (usage?['output_tokens'] as num?)?.toInt() ?? 0,
          operation: 'code_agent',
        ).catchError((_) {});

        final blocks = (data['content'] as List?) ?? const [];
        // Feed the assistant's turn (incl. tool_use blocks) back verbatim.
        messages.add({'role': 'assistant', 'content': blocks});

        final toolUses = blocks
            .whereType<Map>()
            .where((b) => b['type'] == 'tool_use')
            .toList();

        if (toolUses.isEmpty) {
          final text = blocks
              .whereType<Map>()
              .where((b) => b['type'] == 'text')
              .map((b) => (b['text'] as String?) ?? '')
              .join('\n')
              .trim();
          return text.isEmpty ? null : text;
        }

        // Execute each requested tool (read-only) and return the results.
        final results = <Map<String, dynamic>>[];
        for (final tu in toolUses) {
          final out = await _exec(
            ws,
            (tu['name'] as String?) ?? '',
            (tu['input'] as Map?)?.cast<String, dynamic>() ?? const {},
          );
          results.add({
            'type': 'tool_result',
            'tool_use_id': tu['id'],
            'content': out,
          });
        }
        messages.add({'role': 'user', 'content': results});
        CortexActivityBus.instance.brain(CortexBrain.claude, ms: 4000);
      }
      return 'I explored the code but ran out of investigation steps before '
          'finishing. Try narrowing the question.';
    } catch (_) {
      return null; // fall back to a single-shot reply
    } finally {
      EngineerStatusBus.instance.idle();
    }
  }

  Future<String> _exec(
      CodeWorkspaceService ws, String name, Map<String, dynamic> input) async {
    const editing = {'edit_file', 'write_file'};
    const running = {'run_command'};
    EngineerStatusBus.instance.emit(
      editing.contains(name)
          ? 'editing'
          : running.contains(name)
              ? 'running'
              : 'investigating',
      project: ws.root,
    );
    switch (name) {
      case 'read_file':
        return ws.readFile((input['path'] as String?) ?? '');
      case 'list_dir':
        return ws.listDir((input['path'] as String?) ?? '');
      case 'search_code':
        return ws.searchCode((input['pattern'] as String?) ?? '',
            glob: input['glob'] as String?);
      case 'find_files':
        return ws.findFiles((input['glob'] as String?) ?? '');
      case 'edit_file':
        return EditGate.instance.proposeEdit(
          (input['path'] as String?) ?? '',
          (input['old_string'] as String?) ?? '',
          (input['new_string'] as String?) ?? '',
        );
      case 'write_file':
        return EditGate.instance.proposeWrite(
          (input['path'] as String?) ?? '',
          (input['content'] as String?) ?? '',
        );
      case 'run_command':
        return EditGate.instance.proposeCommand(
          (input['command'] as String?) ?? '',
          (input['args'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[],
        );
      default:
        return 'Unknown tool: $name';
    }
  }
}
