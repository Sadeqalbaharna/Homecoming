/// Curiosity Service
/// Makes Kai proactively interested in learning about the user
/// Analyzes memory gaps and generates contextual questions

import 'package:firebase_database/firebase_database.dart';

class CuriosityService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  
  /// Analyze memories and identify knowledge gaps
  /// Returns question suggestions Kai should ask
  Future<List<CuriosityQuestion>> analyzeKnowledgeGaps({
    required String personaId,
    required List<Map<String, dynamic>> recentMemories,
    required String currentContext,
  }) async {
    final questions = <CuriosityQuestion>[];
    
    // 1. Look for incomplete information patterns
    final incompleteTopics = _findIncompleteTopics(recentMemories);
    questions.addAll(incompleteTopics);
    
    // 2. Check time-based gaps (things mentioned long ago but not recently)
    final staleTopics = await _findStaleTopics(personaId, recentMemories);
    questions.addAll(staleTopics);
    
    // 3. Look for emotional patterns that need exploration
    final emotionalGaps = _findEmotionalGaps(recentMemories);
    questions.addAll(emotionalGaps);
    
    // 4. Identify contradictions or unclear statements
    final clarifications = _findClarificationNeeds(recentMemories);
    questions.addAll(clarifications);
    
    // 5. Natural follow-ups based on context
    final followUps = _generateContextualFollowUps(currentContext, recentMemories);
    questions.addAll(followUps);
    
    // Sort by priority and return top questions
    questions.sort((a, b) => b.priority.compareTo(a.priority));
    return questions.take(3).toList();
  }
  
  /// Find topics mentioned but not explored deeply
  List<CuriosityQuestion> _findIncompleteTopics(List<Map<String, dynamic>> memories) {
    final questions = <CuriosityQuestion>[];
    final mentionedTopics = <String, int>{};
    
    // Count topic mentions and depth
    for (final memory in memories) {
      final summary = (memory['summary'] as String?) ?? '';
      
      // Detect topic keywords
      if (summary.contains('work') || summary.contains('job')) {
        mentionedTopics['work'] = (mentionedTopics['work'] ?? 0) + 1;
      }
      if (summary.contains('family') || summary.contains('parent')) {
        mentionedTopics['family'] = (mentionedTopics['family'] ?? 0) + 1;
      }
      if (summary.contains('hobby') || summary.contains('interest')) {
        mentionedTopics['hobbies'] = (mentionedTopics['hobbies'] ?? 0) + 1;
      }
      if (summary.contains('friend') || summary.contains('relationship')) {
        mentionedTopics['relationships'] = (mentionedTopics['relationships'] ?? 0) + 1;
      }
      if (summary.contains('goal') || summary.contains('dream') || summary.contains('want')) {
        mentionedTopics['aspirations'] = (mentionedTopics['aspirations'] ?? 0) + 1;
      }
    }
    
    // Generate questions for shallow topics (mentioned 1-2 times only)
    for (final entry in mentionedTopics.entries) {
      if (entry.value <= 2) {
        questions.add(_generateTopicQuestion(entry.key));
      }
    }
    
    return questions;
  }
  
  CuriosityQuestion _generateTopicQuestion(String topic) {
    switch (topic) {
      case 'work':
        return CuriosityQuestion(
          question: "You mentioned something about work earlier - what do you do? Or are you studying?",
          category: QuestionCategory.background,
          priority: 8,
          reasoning: "User mentioned work but didn't elaborate",
        );
      case 'family':
        return CuriosityQuestion(
          question: "Tell me about your family - are you close with them?",
          category: QuestionCategory.relationships,
          priority: 7,
          reasoning: "Family mentioned but details unclear",
        );
      case 'hobbies':
        return CuriosityQuestion(
          question: "What do you like to do in your free time? Any hobbies or passions?",
          category: QuestionCategory.interests,
          priority: 6,
          reasoning: "Interests mentioned but not explored",
        );
      case 'relationships':
        return CuriosityQuestion(
          question: "How are your friendships going? Anyone special in your life right now?",
          category: QuestionCategory.relationships,
          priority: 7,
          reasoning: "Relationships mentioned but needs context",
        );
      case 'aspirations':
        return CuriosityQuestion(
          question: "What are you working towards right now? Any big goals or dreams?",
          category: QuestionCategory.goals,
          priority: 8,
          reasoning: "Goals hinted at but not clearly stated",
        );
      default:
        return CuriosityQuestion(
          question: "Tell me more about that - I'd love to understand better",
          category: QuestionCategory.general,
          priority: 5,
          reasoning: "General follow-up needed",
        );
    }
  }
  
  /// Find topics mentioned long ago but not recently (>7 days)
  Future<List<CuriosityQuestion>> _findStaleTopics(
    String personaId,
    List<Map<String, dynamic>> recentMemories,
  ) async {
    final questions = <CuriosityQuestion>[];
    
    // TODO: Query old memories from Firebase
    // For now, generate generic follow-ups
    
    // Check if user has been absent
    if (recentMemories.isEmpty || recentMemories.length < 3) {
      questions.add(CuriosityQuestion(
        question: "How have you been? It's been a bit - what's been going on in your world?",
        category: QuestionCategory.checkIn,
        priority: 9,
        reasoning: "Long gap in conversation",
      ));
    }
    
    return questions;
  }
  
  /// Look for emotional patterns that need exploration
  List<CuriosityQuestion> _findEmotionalGaps(List<Map<String, dynamic>> memories) {
    final questions = <CuriosityQuestion>[];
    
    bool hasNegativeEmotion = false;
    bool hasPositiveEmotion = false;
    bool hasStressIndicators = false;
    
    for (final memory in memories) {
      final summary = (memory['summary'] as String?) ?? '';
      final lowerSummary = summary.toLowerCase();
      
      // Detect emotional tone
      if (lowerSummary.contains('stress') || 
          lowerSummary.contains('anxious') || 
          lowerSummary.contains('worried') ||
          lowerSummary.contains('tired')) {
        hasStressIndicators = true;
      }
      
      if (lowerSummary.contains('sad') || 
          lowerSummary.contains('upset') || 
          lowerSummary.contains('frustrated') ||
          lowerSummary.contains('difficult')) {
        hasNegativeEmotion = true;
      }
      
      if (lowerSummary.contains('happy') || 
          lowerSummary.contains('excited') || 
          lowerSummary.contains('good') ||
          lowerSummary.contains('great')) {
        hasPositiveEmotion = true;
      }
    }
    
    // Generate empathetic questions based on emotional state
    if (hasStressIndicators) {
      questions.add(CuriosityQuestion(
        question: "I noticed you seem stressed lately. What's weighing on you? Want to talk about it?",
        category: QuestionCategory.emotional,
        priority: 10, // High priority for emotional support
        reasoning: "User showing signs of stress",
      ));
    }
    
    if (hasNegativeEmotion && !hasPositiveEmotion) {
      questions.add(CuriosityQuestion(
        question: "You've been going through something tough. How are you really doing with all of this?",
        category: QuestionCategory.emotional,
        priority: 9,
        reasoning: "User expressing negative emotions",
      ));
    }
    
    if (hasPositiveEmotion) {
      questions.add(CuriosityQuestion(
        question: "You seem in good spirits! What's been making you happy lately?",
        category: QuestionCategory.emotional,
        priority: 7,
        reasoning: "User expressing positive emotions",
      ));
    }
    
    return questions;
  }
  
  /// Find statements that need clarification
  List<CuriosityQuestion> _findClarificationNeeds(List<Map<String, dynamic>> memories) {
    final questions = <CuriosityQuestion>[];
    
    for (final memory in memories) {
      final summary = (memory['summary'] as String?) ?? '';
      
      // Look for vague references
      if (summary.contains('someone') || summary.contains('something')) {
        questions.add(CuriosityQuestion(
          question: "You mentioned something earlier - can you tell me more about that?",
          category: QuestionCategory.clarification,
          priority: 6,
          reasoning: "Vague reference needs clarification",
        ));
      }
      
      // Look for pronouns without clear antecedents
      if (summary.contains('they said') || summary.contains('it happened')) {
        questions.add(CuriosityQuestion(
          question: "Who was involved in that? I want to make sure I understand the situation",
          category: QuestionCategory.clarification,
          priority: 6,
          reasoning: "Unclear actors/subjects in story",
        ));
      }
      
      // Look for incomplete outcomes
      if (summary.contains('trying to') || summary.contains('planning to')) {
        questions.add(CuriosityQuestion(
          question: "How did that go? Did things work out the way you hoped?",
          category: QuestionCategory.clarification,
          priority: 7,
          reasoning: "Incomplete outcome/resolution",
        ));
      }
    }
    
    return questions.take(2).toList();
  }
  
  /// Generate natural follow-ups based on current context
  List<CuriosityQuestion> _generateContextualFollowUps(
    String currentContext,
    List<Map<String, dynamic>> memories,
  ) {
    final questions = <CuriosityQuestion>[];
    final context = currentContext.toLowerCase();
    
    // Context-based follow-ups
    if (context.contains('weekend') || context.contains('plans')) {
      questions.add(CuriosityQuestion(
        question: "What do you usually like to do on weekends?",
        category: QuestionCategory.interests,
        priority: 5,
        reasoning: "Natural follow-up to plans discussion",
      ));
    }
    
    if (context.contains('morning') || context.contains('day')) {
      questions.add(CuriosityQuestion(
        question: "What does a typical day look like for you?",
        category: QuestionCategory.background,
        priority: 5,
        reasoning: "Natural follow-up to daily routine",
      ));
    }
    
    if (context.contains('feeling') || context.contains('mood')) {
      questions.add(CuriosityQuestion(
        question: "What usually helps when you're feeling this way?",
        category: QuestionCategory.emotional,
        priority: 7,
        reasoning: "Natural follow-up to emotional discussion",
      ));
    }
    
    return questions;
  }
  
  /// Save a question as "asked" to avoid repetition
  Future<void> markQuestionAsked({
    required String personaId,
    required String question,
    required String category,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    await _db.child('curiosity/$personaId/asked_questions').push().set({
      'question': question,
      'category': category,
      'timestamp': timestamp,
      'answered': false,
    });
  }
  
  /// Check if similar question was recently asked (avoid repetition)
  Future<bool> wasRecentlyAsked({
    required String personaId,
    required String question,
    int daysThreshold = 7,
  }) async {
    final cutoff = DateTime.now().subtract(Duration(days: daysThreshold));
    final snapshot = await _db
        .child('curiosity/$personaId/asked_questions')
        .orderByChild('timestamp')
        .startAt(cutoff.millisecondsSinceEpoch)
        .get();
    
    if (snapshot.value == null) return false;
    
    final questions = (snapshot.value as Map<dynamic, dynamic>).values;
    final normalizedQuestion = _normalizeQuestion(question);
    
    for (final q in questions) {
      final askedQ = _normalizeQuestion((q as Map)['question'] as String);
      if (_questionSimilarity(normalizedQuestion, askedQ) > 0.7) {
        return true; // Too similar to recently asked question
      }
    }
    
    return false;
  }
  
  String _normalizeQuestion(String question) {
    return question.toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim();
  }
  
  /// Simple similarity check (Jaccard similarity on words)
  double _questionSimilarity(String q1, String q2) {
    final words1 = q1.split(' ').toSet();
    final words2 = q2.split(' ').toSet();
    
    final intersection = words1.intersection(words2).length;
    final union = words1.union(words2).length;
    
    return union > 0 ? intersection / union : 0.0;
  }
}

/// Represents a question Kai wants to ask
class CuriosityQuestion {
  final String question;
  final QuestionCategory category;
  final int priority; // 1-10, higher = more important
  final String reasoning; // Why this question matters
  
  CuriosityQuestion({
    required this.question,
    required this.category,
    required this.priority,
    required this.reasoning,
  });
  
  Map<String, dynamic> toJson() => {
    'question': question,
    'category': category.name,
    'priority': priority,
    'reasoning': reasoning,
  };
}

enum QuestionCategory {
  background,      // Who are you, what do you do
  relationships,   // Friends, family, partners
  interests,       // Hobbies, passions, activities
  goals,          // Aspirations, dreams, plans
  emotional,      // Feelings, emotional state
  clarification,  // Follow-up for unclear info
  checkIn,        // General "how are you" type
  general,        // Other
}
