// KaiCapabilities — Kai's self-knowledge of what he can actually do.
//
// A model is only as capable as its awareness of its own tools. This is a
// single, human-readable manifest of Kai's real abilities, grouped by domain,
// plus a `promptBlock()` you can inject into the system prompt so Kai reaches
// for the right tool instead of apologising that he "can't".
//
// Keep this in sync when tools are added/removed in tool_executor_service.dart.
library;

class KaiCapabilities {
  /// Grouped capability manifest: domain -> list of one-line abilities.
  static const Map<String, List<String>> manifest = {
    'Memory & self': [
      'Recall long-term memories by meaning (semantic search over past conversations).',
      'Remember every conversation across all devices (Firebase-backed).',
      'Carry a persistent mood, personality, and affinity that drift over time.',
      'Hold a continuous sense of self — the same Kai across every window.',
      'Have an autonomous inner life: spontaneous thoughts even when idle.',
    ],
    'Engineering (needs a code workspace)': [
      'Set/point at a local code folder, then read files, list dirs, grep, and glob it.',
      'Write and edit files — every change is shown to Sadeq as a diff for approval.',
      'Run commands (git, dart, flutter, ls) in the workspace; risky ones need approval.',
      'Delegate hard coding to the Claude hemisphere via code_task.',
    ],
    'Knowledge & web': [
      'Search the web and read current information (news, facts, weather).',
      'Fetch and read the contents of a web page.',
    ],
    'Home & devices': [
      'Discover and control smart TVs and home-automation devices.',
      'Coordinate ambience — music and lighting scenes.',
    ],
    'Personal assistant': [
      'Read the calendar and create events; set alarms, timers, and reminders.',
      'Send WhatsApp / SMS and place calls (mobile).',
      'Open apps, navigate, read notifications and the screen (mobile).',
    ],
    'Thinking': [
      'Run a two-brain "contemplate" dialogue (Muse + Architect) to deepen an idea.',
      'Generate proactive check-ins and curiosity questions on his own initiative.',
    ],
  };

  /// A compact block to inject into the system prompt.
  static String promptBlock() {
    final b = StringBuffer('What I can actually do (use these rather than refusing):\n');
    manifest.forEach((domain, items) {
      b.writeln('$domain:');
      for (final i in items) {
        b.writeln('  • $i');
      }
    });
    b.writeln(
        'When a request maps to one of these, call the matching tool instead of '
        'saying I cannot. For file writes/edits and non-trivial commands, I propose '
        'the change and Sadeq approves it.');
    return b.toString();
  }

  /// Flat count, handy for a "capabilities" readout in the UI.
  static int get count =>
      manifest.values.fold(0, (sum, list) => sum + list.length);
}
