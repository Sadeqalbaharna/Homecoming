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

  /// Args that must be PRESENT but are allowed to be an empty string.
  ///
  /// The distinction is not pedantic. For edit_file, `new_string: ""` is not a
  /// malformed call — it is how you delete code. The validator's blanket
  /// "empty string means missing" rule made deletion structurally impossible,
  /// and it went unnoticed because nothing had asked him to delete anything.
  ///
  /// From the trace where it surfaced: he tried to cut a dead 200-line widget,
  /// was told off for an empty new_string, tried whitespace, was told off
  /// again — "It rejected whitespace too. Good, whatever" — and settled for
  /// replacing the fossil with a comment. The comment now in that file exists
  /// only because the tool wouldn't let him remove the thing cleanly. He did
  /// the right work and the gate made him leave litter.
  final Set<String> emptyOkArgs;

  final bool returnsData;
  final bool androidOnly;
  final bool needsUserApproval;

  const ToolPolicy({
    required this.name,
    required this.risk,
    required this.capabilities,
    this.requiredArgs = const {},
    this.emptyOkArgs = const {},
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
      // old_string is NOT required any more — edit_file has two modes now, and
      // range mode (start_line/end_line) exists precisely so he doesn't have to
      // paste the thing he's deleting. The executor enforces "one mode or the
      // other" and can say something useful about which; this gate can only say
      // "missing", which would send him straight back to pasting.
      //
      // Mirrors the schema's 'required' list. They must not drift: declaring an
      // arg required here that the schema calls optional invents a rejection he
      // has no way to predict.
      requiredArgs: {'path', 'new_string'},
      // new_string: "" is a deletion, not a mistake.
      emptyOkArgs: {'new_string'},
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
    // ── The work stack ───────────────────────────────────────────────────
    // These four have been running with no policy since they were added, and
    // saying so in a 4-line warning on every single boot. They're bookkeeping:
    // they move a job marker around, they don't touch the world. Declaring
    // them costs nothing and stops the warning being wallpaper — a startup
    // nag that's always there is a nag nobody reads, including the one time
    // it's about something that matters.
    'job_start': ToolPolicy(
      name: 'job_start',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.self},
      requiredArgs: {'goal'},
    ),
    // requiredArgs MUST mirror the 'required' list in the tool schema
    // (tool_executor_service.dart ~797-823). Declaring an arg required here
    // that the schema says is optional invents a rejection GPT has no way to
    // predict — it would burn an iteration being told off for a call the
    // schema told it was legal. job_progress and job_done are 'required': [].
    'job_progress': ToolPolicy(
      name: 'job_progress',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.self},
    ),
    'job_done': ToolPolicy(
      name: 'job_done',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.self},
    ),
    'run_self_improvement_loop': ToolPolicy(
      name: 'run_self_improvement_loop',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.self, ToolCapability.coding},
      returnsData: true,
    ),
    // Looking at his own graph, and cleaning it.
    //
    // NOT needsUserApproval, and that is a real decision rather than an
    // oversight. It archives the entire graph before touching anything and hard
    // aborts if the backup fails — so the destructive case is already gated by
    // something stronger than a dialog: a working restore point. And the default
    // is dry_run:true, which changes nothing at all.
    //
    // Weighed against: this tool has existed for weeks behind a button on a
    // PHONE-ONLY screen, so his graph has never once been cleaned. A safety that
    // means the repair never happens is not a safety.
    'prune_memory': ToolPolicy(
      name: 'prune_memory',
      risk: ToolRisk.destructive,
      capabilities: {ToolCapability.memory, ToolCapability.self},
      returnsData: true,
    ),
    // Asking his own memory. Read-only, no approval, no model call — the same
    // reasoning as self_check and run_tests: anything standing between him and
    // finding out will get skipped exactly when it matters. He should be able
    // to check a fact about Sadeq as cheaply as he can guess one.
    'ask_memory': ToolPolicy(
      name: 'ask_memory',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.memory},
      requiredArgs: {'about'},
      returnsData: true,
    ),
    // His own noticing. Deliberately NOT scoped to coding: the best thing he
    // ever notices might be about Sadeq, not about a file.
    'note_noticed': ToolPolicy(
      name: 'note_noticed',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.self},
      requiredArgs: {'what'},
    ),
    'make_commitment': ToolPolicy(
      name: 'make_commitment',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.self},
      requiredArgs: {'kind', 'text', 'reason'},
    ),
    'noticed_done': ToolPolicy(
      name: 'noticed_done',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.self},
      requiredArgs: {'id'},
    ),
    'set_layer_progress': ToolPolicy(
      name: 'set_layer_progress',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.self},
      requiredArgs: {'layer', 'progress', 'evidence'},
    ),
    'set_checklist_status': ToolPolicy(
      name: 'set_checklist_status',
      risk: ToolRisk.safeAction,
      capabilities: {ToolCapability.self},
      requiredArgs: {'layer', 'item', 'status', 'evidence'},
    ),
    // Proof. Read-only and no approval — the same reasoning as self_check, and
    // for the same reason: anything that stands between him and finding out
    // whether he was right will be skipped when he's tired, and being tired is
    // exactly when he rounds up.
    'run_tests': ToolPolicy(
      name: 'run_tests',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.self, ToolCapability.coding},
      returnsData: true,
    ),
    // ── Factory tools ────────────────────────────────────────────────────
    //
    // Added because the executor warned about every one of them: "has no
    // policy entry — allowing it". Allowing by default is the right failure
    // mode for a warning, and the wrong one to leave in place: an undeclared
    // tool is one whose blast radius nobody has stated.
    //
    // The risk levels are not decoration. `storefront_publish` puts Sadeq's
    // name and money behind a product, so it is destructive and needs
    // approval, exactly like write_file. Everything that only reads is read.
    'scout_score': ToolPolicy(
      name: 'scout_score',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.planning},
      returnsData: true,
    ),
    'scout_policy': ToolPolicy(
      name: 'scout_policy',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.planning},
      returnsData: true,
    ),
    'scout_record_attempt': ToolPolicy(
      name: 'scout_record_attempt',
      risk: ToolRisk.sideEffect,
      capabilities: {ToolCapability.planning, ToolCapability.memory},
    ),
    'factory_status': ToolPolicy(
      name: 'factory_status',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.planning},
      returnsData: true,
    ),
    'factory_start': ToolPolicy(
      name: 'factory_start',
      risk: ToolRisk.sideEffect,
      capabilities: {ToolCapability.planning},
    ),
    'factory_record': ToolPolicy(
      name: 'factory_record',
      risk: ToolRisk.sideEffect,
      capabilities: {ToolCapability.planning, ToolCapability.memory},
    ),
    'factory_advance': ToolPolicy(
      name: 'factory_advance',
      risk: ToolRisk.sideEffect,
      capabilities: {ToolCapability.planning},
    ),
    'factory_abandon': ToolPolicy(
      name: 'factory_abandon',
      risk: ToolRisk.sideEffect,
      capabilities: {ToolCapability.planning},
    ),
    'factory_learn': ToolPolicy(
      name: 'factory_learn',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.planning, ToolCapability.memory},
      returnsData: true,
    ),
    // Reaches the outside world and spends the operator's credibility.
    'storefront_publish': ToolPolicy(
      name: 'storefront_publish',
      risk: ToolRisk.destructive,
      capabilities: {ToolCapability.web, ToolCapability.planning},
      needsUserApproval: true,
    ),
    'storefront_sales': ToolPolicy(
      name: 'storefront_sales',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.web},
      returnsData: true,
    ),
    'usage_report': ToolPolicy(
      name: 'usage_report',
      risk: ToolRisk.read,
      capabilities: {ToolCapability.self},
      returnsData: true,
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
      // An empty string is usually a malformed call — but not always. For
      // edit_file, new_string: "" IS the delete operation. Declared per-tool
      // rather than special-cased here, so the next tool with a legitimately
      // empty argument doesn't have to rediscover this the hard way.
      if (value is String &&
          value.trim().isEmpty &&
          !policy.emptyOkArgs.contains(key)) {
        return true;
      }
      if (value is List && value.isEmpty) return true;
      return false;
    }).toList(growable: false);

    if (missing.isNotEmpty) {
      return ToolValidationResult.blocked(
        'Missing required argument(s) for "$toolName": ${missing.join(', ')}. Ask one short clarifying question before trying again.',
      );
    }

    if (toolName == 'run_tests') {
      final target = args['target'];
      if (target is List) {
        return const ToolValidationResult.blocked(
          'run_tests accepts one target path, not a list. Run the whole suite, run one file/directory, or run separate tool calls — do not report tool misuse as a test failure.',
        );
      }
      if (target is String && _looksLikeMultipleRunTestTargets(target)) {
        return const ToolValidationResult.blocked(
          'run_tests accepts one target path. Space-joined test targets become one invalid path, so this is tool misuse, not a failing test suite. Run one target at a time or run the whole suite.',
        );
      }
    }

    return const ToolValidationResult.ok();
  }

  static bool _looksLikeMultipleRunTestTargets(String target) {
    final trimmed = target.trim();
    if (trimmed.isEmpty) return false;
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1) return false;
    final pathLike = RegExp(r'(^test[\\/]|_test\.dart$|\.dart$|[\\/])');
    return parts.where((p) => pathLike.hasMatch(p)).length >= 2;
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
