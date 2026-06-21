// Curiosity service — analyzes knowledge gaps and generates questions Kai
// can ask to deepen understanding of the user.

import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'ai_config.dart';
import 'usage_tracking_service.dart';

/// Category of a curiosity question.
enum CuriosityCategory {
  personal,       // Personal life, relationships, feelings
  interests,      // Hobbies, passions, topics they enjoy
  goals,          // Aspirations, plans, future
  preferences,    // Likes/dislikes, opinions
  emotional,      // Emotional state, wellbeing (highest priority)
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
You are analyzing what Kai (an AI companion) knows about the user to find genuine knowledge gaps.

Recent memories about the user:
${memoryContext.isEmpty ? '(none yet)' : memoryContext}

Current conversation context:
"$currentContext"

Already asked recently (don't repeat):
${alreadyAsked.take(10).join('\n')}

Generate 3 questions Kai could ask to genuinely understand the user better.
Return ONLY JSON array:
[
  {
    "question": "...",
    "priority": 7,
    "category": "personal|interests|goals|preferences|emotional|contextual",
    "reasoning": "why this fills a gap"
  }
]
Higher priority (8-10) for emotional/wellbeing questions.''';

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

  List<CuriosityQuestion> _getFallbackQuestions(String context) {
    final rng = Random();
    final fallbacks = [
      CuriosityQuestion(
        question: 'How are you feeling today?',
        priority: 8,
        category: CuriosityCategory.emotional,
        reasoning: 'Check in on emotional wellbeing',
      ),
      CuriosityQuestion(
        question: 'What\'s been on your mind lately?',
        priority: 6,
        category: CuriosityCategory.personal,
        reasoning: 'Open-ended connection',
      ),
      CuriosityQuestion(
        question: 'Is there something you\'ve been looking forward to?',
        priority: 5,
        category: CuriosityCategory.goals,
        reasoning: 'Explore positive anticipation',
      ),
    ];
    fallbacks.shuffle(rng);
    return fallbacks;
  }

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
