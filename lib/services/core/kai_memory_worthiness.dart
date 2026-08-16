/// Whether an unclassifiable turn was actually about Sadeq's life.
///
/// ── Why this exists at all ──────────────────────────────────────────────────
///
/// [scopeForTurn] used to answer "the router could not place this turn" with
/// `sharedLife`, which is Messenger-visible. That was the one optimistic
/// control in a file of conservative ones, and it ran on every ordinary desktop
/// turn. It is now inverted: an unplaced turn is `privateCore`.
///
/// Inverting it alone would be correct and would make Kai worse. The turns that
/// branch covered are not only mis-routed technical questions — they are also
/// "my sister is coming to stay", "I could not sleep again", "we should go back
/// to that place by the water". Those are exactly what a friend should carry
/// onto Messenger, and a keyword router will never recognise them, because
/// recognising them is a judgement and not a match.
///
/// So the deterministic rule keeps the boundary and this asks the narrow
/// question the rule cannot: *was that about his life?*
///
/// ── The rules that make a model safe here ───────────────────────────────────
///
/// 1. It runs ONLY on [KaiMemoryScopeDecision.marginal] turns. Anything decided
///    by a positive rule — emotional, guest, VR, technical, work intent — never
///    reaches it. A model cannot reopen a decision made on evidence.
/// 2. It can only ever WIDEN, and only to [KaiMemoryScopeDecision.promotion],
///    which is always `sharedLife`. It cannot narrow, cannot reach `identity`
///    or `relationship`, and cannot invent a scope.
/// 3. Every failure is closed. No response, empty response, unparseable JSON,
///    wrong shape, low confidence, timeout, exception, no provider — all of
///    them keep the private answer.
/// 4. It is MECHANICAL work in the sense the hardware roadmap means: it
///    classifies, it never speaks, and nothing it writes is ever read back as
///    something Kai said. It is the correct kind of job for a local model.
///
/// The asymmetry is deliberate. A turn that should have travelled and did not
/// is a thinner Messenger; a turn that should not have travelled and did is
/// unrecoverable. Every branch here is written to be wrong in the first
/// direction.
library;

import 'dart:async';
import 'dart:convert';

import 'kai_memory_scope.dart';

/// What the classifier concluded. `unknown` is not a failure state that callers
/// must handle specially — it simply does not promote.
enum KaiMemoryWorthiness { personal, notPersonal, unknown }

class KaiMemoryWorthinessVerdict {
  const KaiMemoryWorthinessVerdict(
    this.worthiness, {
    this.confidence = 0,
    this.reasonCode = 'unknown',
  });

  final KaiMemoryWorthiness worthiness;

  /// 0..1. Below [KaiMemoryWorthinessClassifier.minimumConfidence] never
  /// promotes, so an unsure model behaves exactly like an absent one.
  final double confidence;

  /// For the audit line. Never contains message content.
  final String reasonCode;

  static const closed =
      KaiMemoryWorthinessVerdict(KaiMemoryWorthiness.unknown, reasonCode: 'closed');
}

/// Reads a model response into a verdict. Pure, so the whole decision table is
/// testable without a model, a network, or a clock.
///
/// Anything it does not positively understand is [KaiMemoryWorthiness.unknown].
/// There is no lenient parse path on purpose — "the model probably meant yes"
/// is how a boundary becomes a suggestion.
KaiMemoryWorthinessVerdict parseMemoryWorthiness(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return KaiMemoryWorthinessVerdict.closed;

  // Small local models like to wrap JSON in prose or a fence. Take the first
  // balanced-looking object and refuse everything else.
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return const KaiMemoryWorthinessVerdict(KaiMemoryWorthiness.unknown,
        reasonCode: 'no_json');
  }

  Object? decoded;
  try {
    decoded = jsonDecode(text.substring(start, end + 1));
  } catch (_) {
    return const KaiMemoryWorthinessVerdict(KaiMemoryWorthiness.unknown,
        reasonCode: 'bad_json');
  }
  if (decoded is! Map) {
    return const KaiMemoryWorthinessVerdict(KaiMemoryWorthiness.unknown,
        reasonCode: 'not_an_object');
  }

  final personal = decoded['personal'];
  if (personal is! bool) {
    // A string "true" is not a boolean. A model that cannot follow the schema
    // is not a model whose judgement should widen a privacy scope.
    return const KaiMemoryWorthinessVerdict(KaiMemoryWorthiness.unknown,
        reasonCode: 'missing_verdict');
  }

  final rawConfidence = decoded['confidence'];
  final confidence = rawConfidence is num ? rawConfidence.toDouble() : 0.0;
  if (confidence.isNaN || confidence < 0 || confidence > 1) {
    return const KaiMemoryWorthinessVerdict(KaiMemoryWorthiness.unknown,
        reasonCode: 'bad_confidence');
  }

  return KaiMemoryWorthinessVerdict(
    personal ? KaiMemoryWorthiness.personal : KaiMemoryWorthiness.notPersonal,
    confidence: confidence,
    reasonCode: personal ? 'personal' : 'not_personal',
  );
}

/// Asks the narrow question, on the margin only.
class KaiMemoryWorthinessClassifier {
  KaiMemoryWorthinessClassifier({
    required this.providers,
    this.timeout = const Duration(seconds: 4),
    this.minimumConfidence = 0.7,
  });

  /// Tried in order until one returns something parseable. Ordered cheapest
  /// first by convention; an empty list means the feature is simply off, and
  /// off means private.
  final List<Future<String?> Function(String system, String user)> providers;

  /// A classification that has not returned by now is not worth a slower turn.
  /// Timing out keeps the private answer, so the cost of being slow is a
  /// thinner Messenger and never a leak.
  final Duration timeout;

  /// Below this, an answer counts as no answer.
  final double minimumConfidence;

  static const String systemPrompt = '''
You classify one exchange for memory scope. You are not a chat model here.

Answer ONE question: was this exchange about the user's personal life, feelings,
relationships, plans, or a shared experience with Kai?

personal = true for: family, friends, health, sleep, mood, plans, travel, food,
things they did or want to do, memories, anything they would tell a friend.

personal = false for: software, business operations, configuration, debugging,
tooling, admin, logistics with no personal content, and small talk that reveals
nothing about their life ("ok", "thanks", "go on").

If you are unsure, say false. A wrong true is worse than a wrong false.

Reply with ONLY this JSON object and nothing else:
{"personal": true|false, "confidence": 0.0-1.0}
''';

  Future<KaiMemoryWorthinessVerdict> classify({
    String? userText,
    String? kaiReply,
  }) async {
    final user = _payload(userText, kaiReply);
    if (user.isEmpty) return KaiMemoryWorthinessVerdict.closed;

    for (final provider in providers) {
      try {
        final raw = await provider(systemPrompt, user).timeout(timeout);
        final verdict = parseMemoryWorthiness(raw);
        if (verdict.worthiness == KaiMemoryWorthiness.unknown) continue;
        return verdict;
      } on TimeoutException {
        continue;
      } catch (_) {
        // A classifier that throws must never break a turn. The reply has
        // already been generated and shown; this only decides where the record
        // of it goes.
        continue;
      }
    }
    return KaiMemoryWorthinessVerdict.closed;
  }

  static String _payload(String? userText, String? kaiReply) {
    final u = userText?.trim() ?? '';
    final k = kaiReply?.trim() ?? '';
    if (u.isEmpty && k.isEmpty) return '';
    // Bounded. A long exchange does not classify better, and a classifier is
    // not a place to spend a context window.
    String clip(String s) => s.length <= 600 ? s : '${s.substring(0, 600)}…';
    return 'USER: ${clip(u)}\nKAI: ${clip(k)}';
  }
}

/// The whole decision, deterministic part and model part together.
///
/// This is what callers should use. Passing a null [classifier] gives exactly
/// the strict inversion, which is why every caller is correct before it is
/// configured.
Future<KaiMemoryScope> resolveMemoryScope({
  required KaiMemoryScopeDecision decision,
  KaiMemoryWorthinessClassifier? classifier,
  String? userText,
  String? kaiReply,
  void Function(String reasonCode, double confidence)? onDecision,
}) async {
  final promotion = decision.promotion;
  if (!decision.marginal || promotion == null || classifier == null) {
    onDecision?.call(decision.reasonCode, 0);
    return decision.scope;
  }

  final verdict = await classifier.classify(userText: userText, kaiReply: kaiReply);
  final promote = verdict.worthiness == KaiMemoryWorthiness.personal &&
      verdict.confidence >= classifier.minimumConfidence;

  onDecision?.call(
    promote ? 'promoted_${promotion.name}' : 'held_${verdict.reasonCode}',
    verdict.confidence,
  );
  return promote ? promotion : decision.scope;
}
