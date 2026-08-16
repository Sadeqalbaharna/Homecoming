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
    this.unmatched = false,
  });

  final KaiRoute route;
  final double confidence;
  final List<String> reasons;

  /// No rule fired. [route] is the fallback, not a finding.
  ///
  /// Defaults to false so a hand-built decision behaves as a deliberate choice,
  /// which is what every existing caller and test means by one.
  final bool unmatched;

  /// Whether this turn was positively identified as small talk.
  ///
  /// The distinction that matters downstream: `route == fastChat` answers "what
  /// shape of prompt", and this answers "do we actually know". Only the second
  /// one is allowed to take capability away.
  bool get confidentlyTrivial => route == KaiRoute.fastChat && !unmatched;

  String get label => route.name;

  String promptBlock() {
    final pct = (confidence * 100).round();
    final why =
        reasons.isEmpty ? 'no strong deterministic signal' : reasons.join('; ');
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
      pick(KaiRoute.fastChat, 0.55,
          'message includes an image; answer in visual context unless another route is stronger');
    }

    if (_containsAny(lower, _codingSignals) || _looksLikeFilePath(lower)) {
      pick(KaiRoute.coding, 0.86, 'coding/build/debugging signal detected');
    }

    if (_containsAny(lower, _toolSignals) ||
        _looksLikePhoneCallRequest(lower)) {
      pick(KaiRoute.tool, 0.84, 'explicit action/tool request detected');
    }

    if (_containsAny(lower, _emotionalSignals)) {
      pick(KaiRoute.emotional, 0.82,
          'emotional support / vulnerable-state signal detected');
    }

    if (_containsAny(lower, _contemplateSignals)) {
      pick(KaiRoute.contemplate, 0.78,
          'deep design/strategy/thinking signal detected');
    }

    // Trust mode / "go ahead" during an already-open job should keep momentum in
    // coding instead of collapsing into generic chatter. The important signal is
    // the persisted job, not whether Sadeq happened to repeat "project".
    if (hasActiveJob && _containsAny(lower, _continuationSignals)) {
      pick(KaiRoute.coding, 0.80, 'continuation of an active persisted job');
    }

    // A short turn is evidence of small talk only if it is not ASKING
    // something. "ok thanks" is nine characters and genuinely trivial; "why did
    // that break" is nineteen and is a debugging question that needs his whole
    // context. Length alone cannot tell them apart, and treating it as though
    // it could is what sent the motivating example down the thin path.
    //
    // So the short-turn rule still picks the cheap prompt SHAPE, but it only
    // claims to have recognised the turn when nothing is being asked.
    var matched = reasons.isNotEmpty;
    if (text.length <= 24 && route == KaiRoute.fastChat) {
      confidence = 0.45;
      if (_looksLikeQuestion(lower)) {
        reasons.add('short, but asking something — not treated as small talk');
      } else {
        reasons.add('short conversational turn');
        matched = true;
      }
    }

    return KaiRouteDecision(
      route: route,
      confidence: confidence.clamp(0.0, 1.0),
      reasons: reasons.take(4).toList(growable: false),
      // ── The shrug, finally named ────────────────────────────────────────────
      //
      // `route` starts as fastChat and only moves if some rule fires. So when
      // nothing matched, this method returned fastChat — and downstream that is
      // indistinguishable from "I am confident this is small talk".
      //
      // It is not the same claim. fastChat drops ten of the fifteen live
      // context blocks and takes a reply ceiling, so a question the keyword
      // list simply does not cover — "why did that break" matches nothing at
      // all — was getting the THINNEST possible Kai precisely because it was
      // the hardest to classify.
      //
      // This router is a latency optimisation that picks a prompt shape. It was
      // never built as a security boundary, and it was never built as a
      // capability boundary either; it became one by accident, and it fails in
      // the wrong direction.
      //
      // Note the asymmetry with the memory write classifier, which was fixed
      // the same day in the OPPOSITE direction. For privacy, an unclassified
      // turn must fail CLOSED — absence of evidence is not evidence of
      // intimacy. For capability, an unclassified turn must fail OPEN — absence
      // of evidence is not evidence of triviality. Same shrug, opposite safe
      // defaults, because the cost of being wrong points the other way.
      unmatched: !matched,
    );
  }

  static bool _containsAny(String lower, List<String> needles) =>
      needles.any(lower.contains);

  /// Is this turn asking for something, rather than acknowledging?
  ///
  /// Deliberately generous: a false positive costs a few cached context tokens,
  /// a false negative costs a stripped-down answer to a real question. Matches
  /// a question mark, or an interrogative opener — the second one matters
  /// because Sadeq rarely punctuates.
  static bool _looksLikeQuestion(String lower) {
    if (lower.contains('?')) return true;
    const openers = [
      'why', 'what', 'how', 'when', 'where', 'who', 'which',
      'did', 'does', 'do ', 'is ', 'are ', 'was ', 'were ',
      'can ', 'could ', 'should ', 'would ', 'will ',
    ];
    final trimmed = lower.trimLeft();
    return openers.any(trimmed.startsWith);
  }

  static bool _looksLikeFilePath(String lower) =>
      lower.contains('.dart') ||
      lower.contains('.yaml') ||
      lower.contains('.json') ||
      lower.contains('lib/') ||
      lower.contains('test/') ||
      lower.contains('c:\\') ||
      lower.contains('stack trace');

  /// A phone call is an action only when the sentence actually asks for one.
  ///
  /// The old tool list contained the raw substring `call `. That classified
  /// "let's call this corner the Wobble Nook" as a device action and stranded
  /// a relationship moment inside VR-only creative memory. Naming something is
  /// not telephony. Keep this deliberately narrow; uncertain language should
  /// remain conversation rather than gaining a tool posture.
  static bool _looksLikePhoneCallRequest(String lower) =>
      RegExp(r'^(?:please\s+)?call\s+(?!this\b|that\b|it\b|the\b)')
          .hasMatch(lower) ||
      RegExp(r'\b(?:can|could|would|will) you call\s+').hasMatch(lower) ||
      RegExp(r'^phone\s+').hasMatch(lower);

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
    'makes me happy',
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
