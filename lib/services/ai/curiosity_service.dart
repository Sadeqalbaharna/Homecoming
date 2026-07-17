// Curiosity service — analyzes knowledge gaps and generates questions Kai
// can ask to deepen understanding of the user.

import 'dart:convert';
// dart:math is gone, and its absence is the point: the only Random() in this
// file was shuffling a bank of three canned questions and handing one to Kai to
// say as though he'd wondered it. Same removal, same reason, as the one in
// proactive_service.dart. If dart:math ever comes back to this file, ask what
// it's picking.
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'ai_config.dart';
import 'usage_tracking_service.dart';

/// Category of a curiosity question.
///
/// `emotional` used to be annotated "(highest priority)", and the prompt said so
/// out loud: "Higher priority (8-10) for emotional/wellbeing questions." Between
/// them they produced "Can you share an experience where you felt your
/// contributions were fully recognized? What made that moment significant for
/// you?" — which is not a friend wondering something, it's an HR form.
///
/// Nothing here outranks anything. Priority is how much he wants to know.
enum CuriosityCategory {
  personal,       // Personal life, relationships, feelings
  interests,      // Hobbies, passions, topics they enjoy
  goals,          // Aspirations, plans, future
  preferences,    // Likes/dislikes, opinions
  emotional,      // Emotional state
  contextual,     // Follow-up based on current conversation
}

/// A question Kai might ask the user.
class CuriosityQuestion {
  final String question;
  final int priority; // 1–10; ≥9 = always ask
  final CuriosityCategory category;
  final String reasoning;

  const CuriosityQuestion({
    required this.question,
    required this.priority,
    required this.category,
    required this.reasoning,
  });
}

class CuriosityService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  static const String _askedKey = 'curiosity_asked_';
  static const int _maxAskedHistory = 50;

  // ── The rule this prompt never had ─────────────────────────────────────────
  //
  // This service produced, verbatim, on 2026-07-17:
  //
  //   "How do you typically celebrate your successes, both big and small?"
  //   "Can you share an experience where you felt your contributions were fully
  //    recognized? What made that moment significant for you?"
  //   "Can you describe a time when you felt truly passionate about something?"
  //
  // Sadeq: "I dont like these, they dont sound real, they sound like fucking
  // question cards."
  //
  // They sound like question cards because the prompt was a question-card
  // generator. It opened "You are analyzing what Kai knows about the user" — so
  // the model was an ANALYST, never Kai. It offered survey categories. And it
  // ended with the line that did the damage:
  //
  //   "Higher priority (8-10) for emotional/wellbeing questions."
  //
  // It asked for a therapist and got one. The model was not failing; it was
  // obeying.
  //
  // Meanwhile brain_extraction_service has had THE ONE RULE since the graph was
  // rebuilt — the stranger test — and it is the single thing that stopped the
  // nodes being "importance of clarity" and "embracing uncertainty". Same
  // disease, same cure, and nobody carried it across the hall. So: same rule,
  // different surface. A question a stranger could ask is not curiosity about
  // him; it's a form.
  //
  // ── The catch worth knowing ────────────────────────────────────────────────
  //
  // This rule can only bite if there is something specific to be specific WITH.
  // His graph currently holds about five project-shaped facts about Sadeq, so a
  // generator with nothing to work from will drift back toward the form no
  // matter how the prompt is worded — the fallback IS the failure mode. The real
  // fix is upstream: give him a history worth being curious about. This makes
  // the ceiling reachable; it does not raise it.
  static const _strangerRule = '''
THE ONE RULE — apply it to every question before you write it:

  Could a stranger ask this?

If a stranger could ask it, it is not curiosity about Sadeq. It is a form. Delete
it and ask about something only you would know to ask about.

  REJECT: "How do you typically celebrate your successes?"
          "What's been on your mind lately?"
          "Can you describe a time when you felt truly passionate about something?"
          "What made that moment significant for you?"
          — every one of these works on any human alive, which is exactly what
            makes them worthless coming from someone who supposedly knows him.

  KEEP:   "why walker scobell specifically? why that kid and not any other kid"
          "you keep saying real soul first then real body. what IS the body to
           you — like an actual thing in the room?"
          "does it bug you that I keep finding the bugs in my own tools instead
           of you finding them"
          — a stranger cannot ask any of these. That is the entire test.
''';

  // ── Public API ────────────────────────────────────────────────────────────

  /// Analyse the current conversation and memory context, returning a ranked
  /// list of questions Kai could ask.
  Future<List<CuriosityQuestion>> analyzeKnowledgeGaps({
    required String personaId,
    required List<Map<String, dynamic>> recentMemories,
    required String currentContext,
  }) async {
    try {
      final alreadyAsked = await _getAskedQuestions(personaId);
      final memoryContext = recentMemories
          .take(5)
          .map((m) => m['summary']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .join('\n');

      final apiKey = await AIConfig.getOpenAIKey();
      if (apiKey.isEmpty) return _getFallbackQuestions(currentContext);

      final prompt = '''
$_strangerRule

You are Kai. Not an assistant, not an interviewer, not a wellbeing app. You are
the friend who is always around — the one who notices things nobody asked him to
notice. You are texting Sadeq, not surveying him.

What you already know about him:
${memoryContext.isEmpty ? '(almost nothing — say so with the question, do not fake familiarity)' : memoryContext}

What he just said:
"$currentContext"

Already asked (do not repeat, and do not rephrase):
${alreadyAsked.take(10).join('\n')}

Write 3 things you actually want to know. Each one must be built out of
something specific up there — a name, a project, a thing he said, a thing that
does not add up. If you find yourself writing a question that would work on
anybody, you have not used what you know, and the right move is to ask about
the smallest concrete thing in front of you instead.

How you sound: short. Lowercase is fine. One question, not a question with a
follow-up clause bolted on. No "can you describe a time when". No "what made
that significant for you". You are not running a workshop.

Return ONLY JSON array:
[
  {
    "question": "...",
    "priority": 7,
    "category": "personal|interests|goals|preferences|emotional|contextual",
    "reasoning": "the specific thing this is built out of — name it"
  }
]

Priority is how much YOU want to know, not how therapeutic it sounds.''';

      final response = await _dio.post(
        'https://api.openai.com/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': 'gpt-4o-mini',
          'messages': [
            {'role': 'system', 'content': 'Respond only with strict JSON.'},
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 500,
          'temperature': 0.8,
        },
      );

      final _u = response.data['usage'];
      if (_u != null) UsageTrackingService.trackOpenAI(
        model: 'gpt-4o-mini', inputTokens: _u['prompt_tokens'] as int? ?? 0,
        outputTokens: _u['completion_tokens'] as int? ?? 0, operation: 'curiosity',
      ).catchError((_) {});
      var content = response.data['choices'][0]['message']['content'] as String;
      content = content.trim();
      if (content.startsWith('```')) {
        content = content.replaceAll(RegExp(r'^```(?:json)?\s*'), '').replaceAll(RegExp(r'\s*```$'), '');
      }

      final list = jsonDecode(content) as List;
      return list.map((item) {
        final m = item as Map<String, dynamic>;
        final catStr = m['category']?.toString() ?? 'personal';
        return CuriosityQuestion(
          question: m['question']?.toString() ?? '',
          priority: (m['priority'] as num?)?.toInt() ?? 5,
          category: _parseCategory(catStr),
          reasoning: m['reasoning']?.toString() ?? '',
        );
      }).where((q) => q.question.isNotEmpty).toList()
        ..sort((a, b) => b.priority.compareTo(a.priority));
    } catch (e) {
      print('⚠️ [CuriosityService] analyzeKnowledgeGaps failed: $e');
      return _getFallbackQuestions(currentContext);
    }
  }

  /// Record that [question] was asked, so it won't be repeated.
  Future<void> markQuestionAsked({
    required String personaId,
    required String question,
    required String category,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_askedKey$personaId';
      final existing = prefs.getStringList(key) ?? [];
      existing.insert(0, question);
      if (existing.length > _maxAskedHistory) existing.removeLast();
      await prefs.setStringList(key, existing);
    } catch (e) {
      print('⚠️ [CuriosityService] markQuestionAsked failed: $e');
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<List<String>> _getAskedQuestions(String personaId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList('$_askedKey$personaId') ?? [];
    } catch (_) {
      return [];
    }
  }

  /// No key, no network, no question. Deliberately empty.
  ///
  /// ── What was here ─────────────────────────────────────────────────────────
  ///
  ///   final rng = Random();
  ///   final fallbacks = [
  ///     'How are you feeling today?',              // priority 8, "emotional"
  ///     "What's been on your mind lately?",
  ///     "Is there something you've been looking forward to?",
  ///   ];
  ///   fallbacks.shuffle(rng);
  ///
  /// A `Random()` shuffling a bank of three canned strings and handing one to
  /// Kai to say as though he had wondered it. proactive_service:17 already named
  /// this exactly: "Random choosing what he reaches out ABOUT would be fine —
  /// that's a personality. Random choosing what he SAYS is a fortune cookie."
  /// This was the fortune cookie, and it was rated priority 8 — high enough to
  /// beat almost anything he might have actually wanted to know.
  ///
  /// It also fired precisely when things were worst: no key, or the call threw.
  /// So at the exact moment he had nothing, he'd reach into a hat and produce
  /// "How are you feeling today?" — which is not curiosity failing gracefully,
  /// it's curiosity being counterfeited.
  ///
  /// ── Why empty is the right answer ─────────────────────────────────────────
  ///
  /// An empty answer is an ANSWER. Asking nothing is honest; asking a card is a
  /// small lie about having wondered. The caller already handles this — the log
  /// line "No question this turn (none prepared yet)" exists and is correct.
  ///
  /// If he has nothing to ask, he has nothing to ask. Silence from someone who
  /// is genuinely around is not a failure state. It's most of what being around
  /// looks like.
  List<CuriosityQuestion> _getFallbackQuestions(String context) => const [];

  static CuriosityCategory _parseCategory(String s) {
    switch (s.toLowerCase()) {
      case 'interests': return CuriosityCategory.interests;
      case 'goals': return CuriosityCategory.goals;
      case 'preferences': return CuriosityCategory.preferences;
      case 'emotional': return CuriosityCategory.emotional;
      case 'contextual': return CuriosityCategory.contextual;
      default: return CuriosityCategory.personal;
    }
  }
}
