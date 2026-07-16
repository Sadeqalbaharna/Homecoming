// lib/services/core/tool_policy_service.dart
//
// Deterministic policy layer for Kai's tools.
//
// The LLM is allowed to decide intent; this service keeps execution boring and
// predictable: which tools exist, which platform they belong to, what risk class
// they carry, what arguments are required, and which tools are safe to run in
// parallel. Boring is good here. Boring means Kai has a spine.

library;

import 'kai_db.dart';

enum ToolRisk { read, safeAction, sideEffect, destructive }

enum ToolCapability {
  time,
  web,
  weather,
  phone,
  calendar,
  messaging,
  navigation,
  media,
  smartHome,
  planning,
  coding,
  memory,
  self,
  embodiment,
}

class ToolPolicy {
  final String name;
  final ToolRisk risk;
  final Set<ToolCapability> capabilities;
  final Set<String> requiredArgs;
  final bool returnsData;
  final bool androidOnly;
  final bool needsUserApproval;

  const ToolPolicy({
    required this.name,
    required this.risk,
    required this.capabilities,
    this.requiredArgs = const {},
    this.returnsData = false,
    this.androidOnly = false,
    this.needsUserApproval = false,
  });

  bool get isParallelSafe => !returnsData && risk != ToolRisk.destructive;
}

class ToolValidationResult {
  final bool ok;
  final String? message;

  const ToolValidationResult.ok()
      : ok = true,
        message = null;

  const ToolValidationResult.blocked(this.message) : ok = false;
}

class ToolPolicyService {
  static const Map<String, ToolPolicy> policies = {
    'get_current_time': ToolPolicy(
      name: 'get_current_time',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.time},
      returnsData: true,
    ),
    'web_search': ToolPolicy(
      name: 'web_search',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.web},
      requiredArgs: {'query'},
      returnsData: true,
    ),
    'get_weather': ToolPolicy(
      name: 'get_weather',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.weather},
      returnsData: true,
    ),

    // Phone body tools.
    'set_alarm': ToolPolicy(
      name: 'set_alarm',
      risk: ToolRisk.sideEffect,
      capabilities: {ToolCapability.phone},
      requiredArgs: {'hour', 'minute'},
      androidOnly: true,
    ),
    'set_timer': ToolPolicy(
      name: 'set_timer',
      risk: ToolRisk.sideEffect,
      capabilities: {ToolCapability.phone},
      requiredArgs: {'seconds'},
      androidOnly: true,
    ),
    'set_reminder': ToolPolicy(
      name: 'set_reminder',
      risk: ToolRisk.sideEffect,
      capabilities: {ToolCapability.phone},
      requiredArgs: {'message', 'year', 'month', 'day', 'hour', 'minute'},
      androidOnly: true,
    ),
    'read_calendar': ToolPolicy(
      name: 'read_calendar',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.calendar},
      returnsData: true,
      androidOnly: true,
    ),
    'create_calendar_event': ToolPolicy(
      name: 'create_calendar_event',
      risk: ToolRisk.sideEffect,
      capabilities: {ToolCapability.calendar},
      requiredArgs: {'title', 'date', 'start_time'},
      returnsData: true,
      androidOnly: true,
    ),
    'open_app': ToolPolicy(
      name: 'open_app',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.phone},
      requiredArgs: {'app_name'},
      androidOnly: true,
    ),
    'send_whatsapp': ToolPolicy(
      name: 'send_whatsapp',
      risk: ToolRisk.sideEffect,
      capabilities: {ToolCapability.messaging},
      requiredArgs: {'contact', 'message'},
      androidOnly: true,
    ),
    'send_sms': ToolPolicy(
      name: 'send_sms',
      risk: ToolRisk.sideEffect,
      capabilities: {ToolCapability.messaging},
      requiredArgs: {'contact', 'message'},
      androidOnly: true,
    ),
    'call_contact': ToolPolicy(
      name: 'call_contact',
      risk: ToolRisk.sideEffect,
      capabilities: {ToolCapability.phone},
      requiredArgs: {'contact'},
      androidOnly: true,
    ),
    'navigate_to': ToolPolicy(
      name: 'navigate_to',
      risk: ToolRisk.sideEffect,
      capabilities: {ToolCapability.navigation},
      requiredArgs: {'destination'},
      androidOnly: true,
    ),
    'play_music': ToolPolicy(
      name: 'play_music',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.media},
      requiredArgs: {'query'},
      androidOnly: true,
    ),
    'read_notifications': ToolPolicy(
      name: 'read_notifications',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.phone},
      returnsData: true,
      androidOnly: true,
    ),
    'read_screen': ToolPolicy(
      name: 'read_screen',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.phone},
      returnsData: true,
      androidOnly: true,
    ),

    // Home / station.
    'discover_tvs': ToolPolicy(
      name: 'discover_tvs',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.smartHome},
      returnsData: true,
    ),
    'control_tv': ToolPolicy(
      name: 'control_tv',
      risk: ToolRisk.sideEffect,
      capabilities: {ToolCapability.smartHome},
      requiredArgs: {'action'},
    ),
    'control_device': ToolPolicy(
      name: 'control_device',
      risk: ToolRisk.sideEffect,
      capabilities: {ToolCapability.smartHome},
      requiredArgs: {'device', 'action'},
    ),

    // Agentic / engineering / memory.
    'create_plan': ToolPolicy(
      name: 'create_plan',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.planning},
      requiredArgs: {'goal', 'steps'},
      returnsData: true,
    ),
    'code_task': ToolPolicy(
      name: 'code_task',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.coding},
      requiredArgs: {'task'},
      returnsData: true,
    ),
    'contemplate': ToolPolicy(
      name: 'contemplate',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.self},
      requiredArgs: {'topic'},
      returnsData: true,
    ),
    'set_code_workspace': ToolPolicy(
      name: 'set_code_workspace',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.coding},
      requiredArgs: {'path'},
    ),
    'read_file': ToolPolicy(
      name: 'read_file',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.coding},
      requiredArgs: {'path'},
      returnsData: true,
    ),
    'list_dir': ToolPolicy(
      name: 'list_dir',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.coding},
      requiredArgs: {'path'},
      returnsData: true,
    ),
    'search_code': ToolPolicy(
      name: 'search_code',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.coding},
      requiredArgs: {'pattern'},
      returnsData: true,
    ),
    'find_files': ToolPolicy(
      name: 'find_files',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.coding},
      requiredArgs: {'glob'},
      returnsData: true,
    ),
    'write_file': ToolPolicy(
      name: 'write_file',
      risk: ToolRisk.destructive,
      capabilities: {ToolCapability.coding},
      requiredArgs: {'path', 'content'},
      needsUserApproval: true,
    ),
    'edit_file': ToolPolicy(
      name: 'edit_file',
      risk: ToolRisk.destructive,
      capabilities: {ToolCapability.coding},
      requiredArgs: {'path', 'old_string', 'new_string'},
      needsUserApproval: true,
    ),
    'run_command': ToolPolicy(
      name: 'run_command',
      risk: ToolRisk.destructive,
      capabilities: {ToolCapability.coding},
      requiredArgs: {'command'},
      returnsData: true,
      needsUserApproval: true,
    ),
    'open_terminal': ToolPolicy(
      name: 'open_terminal',
      risk: ToolRisk.sideEffect,
      capabilities: {ToolCapability.coding},
    ),
    'fetch_url': ToolPolicy(
      name: 'fetch_url',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.web},
      requiredArgs: {'url'},
      returnsData: true,
    ),
    'add_goal': ToolPolicy(
      name: 'add_goal',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.self},
      requiredArgs: {'text'},
    ),
    'list_goals': ToolPolicy(
      name: 'list_goals',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.self},
      returnsData: true,
    ),
    'complete_goal': ToolPolicy(
      name: 'complete_goal',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.self},
      requiredArgs: {'id'},
    ),
    'remember_about_user': ToolPolicy(
      name: 'remember_about_user',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.memory},
      requiredArgs: {'key', 'value'},
    ),
    'forget_about_user': ToolPolicy(
      name: 'forget_about_user',
      risk: ToolRisk.destructive,
      capabilities: {ToolCapability.memory},
      requiredArgs: {'key'},
      needsUserApproval: true,
    ),
    'envision_dream': ToolPolicy(
      name: 'envision_dream',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.self},
      requiredArgs: {'dream'},
    ),
    'refine_purpose': ToolPolicy(
      name: 'refine_purpose',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.self},
      requiredArgs: {'purpose'},
    ),
    'recall_my_growth': ToolPolicy(
      name: 'recall_my_growth',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.self},
      returnsData: true,
    ),
    'set_focus': ToolPolicy(
      name: 'set_focus',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.self},
      requiredArgs: {'focus'},
    ),
    'note_to_self': ToolPolicy(
      name: 'note_to_self',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.self},
      requiredArgs: {'text'},
    ),
    'read_notes': ToolPolicy(
      name: 'read_notes',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.self},
      returnsData: true,
    ),
    'remember_bit': ToolPolicy(
      name: 'remember_bit',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.memory},
      requiredArgs: {'text'},
    ),
    'list_bits': ToolPolicy(
      name: 'list_bits',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.memory},
      returnsData: true,
    ),
    'forget_bit': ToolPolicy(
      name: 'forget_bit',
      risk: ToolRisk.destructive,
      capabilities: {ToolCapability.memory},
      requiredArgs: {'id'},
      needsUserApproval: true,
    ),
    'self_check': ToolPolicy(
      name: 'self_check',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.self, ToolCapability.coding},
      returnsData: true,
    ),
    'log_body_progress': ToolPolicy(
      name: 'log_body_progress',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.embodiment},
      requiredArgs: {'body', 'note'},
    ),
  };

  static ToolPolicy? policyFor(String toolName) => policies[toolName];

  static bool isParallelSafe(String? toolName) {
    if (toolName == null || toolName.isEmpty) return false;
    return policies[toolName]?.isParallelSafe ?? false;
  }

  /// Tools Kai is OFFERED that have no declared policy.
  ///
  /// The severed-nerve check. Two hand-maintained registries — the schemas he's
  /// given and the policies that judge them — will always drift apart, and the
  /// failure is silent and cruel: he reaches for a capability he can see listed,
  /// and something invisible slaps his hand down. Now the gap is a warning at
  /// boot, not a mystery mid-conversation.
  ///
  /// Pass `ToolExecutorService.toolDefinitions` in (this service can't import it
  /// without a cycle).
  static List<String> undeclared(List<Map<String, dynamic>> schemas) {
    final out = <String>[];
    for (final s in schemas) {
      final fn = s['function'];
      final name = (fn is Map) ? fn['name'] as String? : null;
      if (name == null) continue;
      if (!policies.containsKey(name)) out.add(name);
    }
    return out;
  }

  /// Shout once at boot if the nerve is severed anywhere.
  static void auditAgainstSchemas(List<Map<String, dynamic>> schemas) {
    final gaps = undeclared(schemas);
    if (gaps.isEmpty) return;
    // ignore: avoid_print
    print('⚠️ [ToolPolicy] ${gaps.length} tool(s) offered to Kai with no policy '
        'declared: ${gaps.join(', ')} — they will run (EditGate still guards '
        'destructive ones), but their risk/parallelism is undeclared.');
  }

  static ToolValidationResult validate(String toolName, Map<String, dynamic> args) {
    final policy = policies[toolName];
    if (policy == null) {
      // FAIL OPEN, LOUDLY — and here's why that's the safe choice, not the lazy
      // one.
      //
      // This used to `blocked('Unknown tool')`, which meant EVERY new capability
      // arrived dead: the schema was in Kai's spec (so he'd confidently reach
      // for it) and this registry rejected it (so it did nothing). A severed
      // nerve — he could see the hand but not move it. It cost us job_start,
      // job_progress, job_done and set_layer_progress, so he sat there watching
      // his own project tracker refuse his honest progress reports.
      //
      // Two hand-synced registries WILL drift. That's not a bug you fix once,
      // it's a bug you keep re-fixing forever — so delete the class of bug.
      //
      // And this was never the real lock anyway: anything genuinely dangerous
      // (write_file, edit_file, run_command) goes through EditGate, which shows
      // Sadeq a diff and defaults to REJECT with no UI. This registry is RISK
      // CLASSIFICATION — advice about confirmation and parallelism. Advice that
      // silently amputates unlisted capabilities is worse than no advice.
      //
      // So: an unregistered tool runs, and shouts about it in the log so the
      // omission gets fixed instead of quietly maiming him.
      // ignore: avoid_print
      print('⚠️ [ToolPolicy] "$toolName" has no policy entry — allowing it '
          '(EditGate still guards anything destructive). Add a ToolPolicy for '
          'it so its risk/parallelism is declared rather than assumed.');
      return const ToolValidationResult.ok();
    }

    if (policy.androidOnly && kaiDbUsesRest) {
      return ToolValidationResult.blocked(
        '"$toolName" is only available in Kai\'s phone body. This desktop body should answer plainly instead of pretending it can do phone actions.',
      );
    }

    final missing = policy.requiredArgs.where((key) {
      final value = args[key];
      if (value == null) return true;
      if (value is String && value.trim().isEmpty) return true;
      if (value is List && value.isEmpty) return true;
      return false;
    }).toList(growable: false);

    if (missing.isNotEmpty) {
      return ToolValidationResult.blocked(
        'Missing required argument(s) for "$toolName": ${missing.join(', ')}. Ask one short clarifying question before trying again.',
      );
    }

    return const ToolValidationResult.ok();
  }

  static String promptBrief() {
    final currentBody = kaiDbUsesRest ? 'desktop' : 'phone';
    final unavailable = policies.values
        .where((p) => p.androidOnly && kaiDbUsesRest)
        .map((p) => p.name)
        .join(', ');

    return '''
🔧 TOOL EXECUTION POLICY:
- Current body: $currentBody.
- Before using a tool, satisfy its required arguments. If any required detail is missing, ask ONE short clarifying question instead of calling it with blanks.
- Destructive or approval-gated tools are allowed only through their existing approval flows. Never imply a file write/command landed until the tool result says it did.
- Data-returning tools are not parallel-safe when later steps depend on their results; gather data first, then act.
${unavailable.isEmpty ? '' : '- Unavailable in this body: $unavailable. Do not offer or call these here; say plainly that they are phone-body actions.'}
'''.trim();
  }
}
