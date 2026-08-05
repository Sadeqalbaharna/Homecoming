// lib/services/core/kai_router_service.dart
//
// Deterministic routing brain for Kai.
//
// This does NOT replace the LLM. It gives the LLM a boring, inspectable first
// pass over the user's intent so Kai can choose the right posture before he
// starts speaking: quick chat, tool/action, coding, emotional support, or deeper
// contemplation. Style comes after route. Otherwise we get shiny if-else soup.

library;

enum KaiRoute {
  fastChat,
  tool,
  coding,
  emotional,
  contemplate,
}

class KaiRouteDecision {
  const KaiRouteDecision({
    required this.route,
    required this.confidence,
    required this.reasons,
  });

  final KaiRoute route;
  final double confidence;
  final List<String> reasons;

  String get label => route.name;

  String promptBlock() {
    final pct = (confidence * 100).round();
    final why = reasons.isEmpty ? 'no strong deterministic signal' : reasons.join('; ');
    return '''
\n=== Kai Routing Brain ===
Route: $label ($pct% confidence)
Why: $why
Use this as a posture hint, not a cage:
  • fastChat — answer directly; no fake ceremony.
  • tool — if a matching tool is available, call it instead of explaining manually.
  • coding — inspect real code first, make the smallest verified change, then self-check.
  • emotional — slow down, ground Sadeq, be warm before being clever.
  • contemplate — deepen the idea with structure; don't rush to a shallow answer.''';
  }
}

class KaiRouterService {
  const KaiRouterService();

  KaiRouteDecision decide(
    String message, {
    bool hasImage = false,
    bool hasActiveJob = false,
  }) {
    final text = message.trim();
    final lower = text.toLowerCase();
    final reasons = <String>[];

    var route = KaiRoute.fastChat;
    var confidence = 0.35;

    void pick(KaiRoute candidate, double score, String reason) {
      if (score > confidence) {
        route = candidate;
        confidence = score;
        reasons
          ..clear()
          ..add(reason);
      } else if (candidate == route && reason.isNotEmpty) {
        reasons.add(reason);
        if (confidence < score) confidence = score;
      }
    }

    if (hasImage) {
      pick(KaiRoute.fastChat, 0.55, 'message includes an image; answer in visual context unless another route is stronger');
    }

    if (_containsAny(lower, _codingSignals) || _looksLikeFilePath(lower)) {
      pick(KaiRoute.coding, 0.86, 'coding/build/debugging signal detected');
    }

    if (_containsAny(lower, _toolSignals)) {
      pick(KaiRoute.tool, 0.84, 'explicit action/tool request detected');
    }

    if (_containsAny(lower, _emotionalSignals)) {
      pick(KaiRoute.emotional, 0.82, 'emotional support / vulnerable-state signal detected');
    }

    if (_containsAny(lower, _contemplateSignals)) {
      pick(KaiRoute.contemplate, 0.78, 'deep design/strategy/thinking signal detected');
    }

    // Trust mode / "go ahead" during an already-open job should keep momentum in
    // coding instead of collapsing into generic chatter. The important signal is
    // the persisted job, not whether Sadeq happened to repeat "project".
    if (hasActiveJob && _containsAny(lower, _continuationSignals)) {
      pick(KaiRoute.coding, 0.80, 'continuation of an active persisted job');
    }

    if (text.length <= 24 && route == KaiRoute.fastChat) {
      confidence = 0.45;
      reasons.add('short conversational turn');
    }

    return KaiRouteDecision(
      route: route,
      confidence: confidence.clamp(0.0, 1.0),
      reasons: reasons.take(4).toList(growable: false),
    );
  }

  static bool _containsAny(String lower, List<String> needles) =>
      needles.any(lower.contains);

  static bool _looksLikeFilePath(String lower) =>
      lower.contains('.dart') ||
      lower.contains('.yaml') ||
      lower.contains('.json') ||
      lower.contains('lib/') ||
      lower.contains('test/') ||
      lower.contains('c:\\') ||
      lower.contains('stack trace');

  static const _codingSignals = <String>[
    'code',
    'bug',
    'fix',
    'compile',
    'analyzer',
    'self-check',
    'self check',
    'test',
    'flutter',
    'dart',
    'firebase',
    'repo',
    'file',
    'function',
    'class ',
    'service',
    'widget',
    'exception',
    'error',
    'crash',
    'implement',
    'refactor',
    'dashboard',
    'layer ',
  ];

  static const _toolSignals = <String>[
    'set an alarm',
    'set a timer',
    'remind me',
    'message ',
    'whatsapp',
    'sms',
    'call ',
    'open ',
    'navigate',
    'directions',
    'weather',
    'search ',
    'look up',
    'scan for',
    'turn on',
    'turn off',
    'volume',
    'tv',
    'lights',
  ];

  static const _emotionalSignals = <String>[
    'i feel',
    "i'm sad",
    'im sad',
    "i'm scared",
    'im scared',
    'anxious',
    'overwhelmed',
    'lonely',
    'tired',
    'burned out',
    'depressed',
    'panic',
    'hurt',
    'rough day',
    'comfort me',
  ];

  static const _contemplateSignals = <String>[
    'think deeply',
    'contemplate',
    'brainstorm',
    'strategy',
    'design',
    'architecture',
    'what do you think',
    'pros and cons',
    'tradeoff',
    'roadmap',
    'plan',
  ];

  static const _continuationSignals = <String>[
    'go ahead',
    'keep going',
    'continue',
    'and now',
    'what now',
    'what next',
    'and?',
    'do it',
    'trust',
    'no pitstops',
  ];

  static const _projectSignals = <String>[
    'kai',
    'homecoming',
    'project',
    'layer',
    'smarter',
  ];
}
