/// Curiosity Service
/// Makes Kai proactively interested in learning about the user
/// Analyzes memory gaps and generates contextual questions
library;

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
    
    // 0. Daily life check-ins (NEW: Ask about day/life naturally)
    final dailyQuestions = await _generateDailyLifeQuestions(personaId, recentMemories);
    questions.addAll(dailyQuestions);
    
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
    
    // 6. Time-of-day appropriate questions (NEW)
    final timeBasedQuestions = _generateTimeBasedQuestions();
    questions.addAll(timeBasedQuestions);
    
    // Sort by priority and return top questions
    questions.sort((a, b) => b.priority.compareTo(a.priority));
    return questions.take(3).toList();
  }
  
  /// Generate daily life questions to show genuine interest (NEW)
  Future<List<CuriosityQuestion>> _generateDailyLifeQuestions(
    String personaId,
    List<Map<String, dynamic>> memories,
  ) async {
    final questions = <CuriosityQuestion>[];
    final now = DateTime.now();
    
    // Check last conversation time
    final lastMemoryTime = memories.isNotEmpty && memories.first['timestamp'] != null
        ? DateTime.fromMillisecondsSinceEpoch(memories.first['timestamp'] as int)
        : now;
    
    final hoursSinceLastChat = now.difference(lastMemoryTime).inHours;
    
    // If it's been a while, ask about their day/life
    if (hoursSinceLastChat > 4) {
      questions.add(CuriosityQuestion(
        question: "Hey! How's your day been going? Anything interesting happen?",
        category: QuestionCategory.checkIn,
        priority: 9,
        reasoning: "Been a while since last conversation",
      ));
    }
    
    // Check if user mentioned future plans and follow up
    for (final memory in memories.take(5)) {
      final summary = (memory['summary'] as String?) ?? '';
      final lowerSummary = summary.toLowerCase();
      
      // Follow up on mentioned plans
      if (lowerSummary.contains('going to') || 
          lowerSummary.contains('planning to') ||
          lowerSummary.contains('will ') ||
          lowerSummary.contains('tomorrow')) {
        questions.add(CuriosityQuestion(
          question: "How did that thing you were planning go? Been thinking about it!",
          category: QuestionCategory.followUp,
          priority: 10,
          reasoning: "Following up on user's mentioned plans",
        ));
        break;
      }
      
      // Follow up on mentioned challenges
      if (lowerSummary.contains('trying to') || 
          lowerSummary.contains('struggling') ||
          lowerSummary.contains('difficult') ||
          lowerSummary.contains('problem')) {
        questions.add(CuriosityQuestion(
          question: "How's that challenge you mentioned coming along? Any progress?",
          category: QuestionCategory.followUp,
          priority: 9,
          reasoning: "Following up on user's challenge",
        ));
        break;
      }
      
      // Follow up on mentioned people
      if (lowerSummary.contains('my friend') || 
          lowerSummary.contains('my mom') ||
          lowerSummary.contains('my dad') ||
          lowerSummary.contains('my brother') ||
          lowerSummary.contains('my sister')) {
        questions.add(CuriosityQuestion(
          question: "How are things with the people in your life? Everyone doing okay?",
          category: QuestionCategory.relationships,
          priority: 8,
          reasoning: "Following up on mentioned relationships",
        ));
        break;
      }
    }
    
    return questions;
  }
  
  /// Generate time-appropriate questions (NEW)
  List<CuriosityQuestion> _generateTimeBasedQuestions() {
    final questions = <CuriosityQuestion>[];
    final now = DateTime.now();
    final hour = now.hour;
    
    // Morning questions (5 AM - 11 AM)
    if (hour >= 5 && hour < 11) {
      questions.add(CuriosityQuestion(
        question: "Good morning! How'd you sleep? Got anything exciting planned for today?",
        category: QuestionCategory.checkIn,
        priority: 6,
        reasoning: "Morning greeting",
      ));
    }
    // Afternoon questions (12 PM - 5 PM)
    else if (hour >= 12 && hour < 17) {
      questions.add(CuriosityQuestion(
        question: "How's your afternoon treating you? Getting through the day alright?",
        category: QuestionCategory.checkIn,
        priority: 6,
        reasoning: "Afternoon check-in",
      ));
    }
    // Evening questions (5 PM - 9 PM)
    else if (hour >= 17 && hour < 21) {
      questions.add(CuriosityQuestion(
        question: "How was your day today? Anything worth talking about?",
        category: QuestionCategory.checkIn,
        priority: 7,
        reasoning: "Evening reflection",
      ));
    }
    // Night questions (9 PM - 1 AM)
    else if (hour >= 21 || hour < 1) {
      questions.add(CuriosityQuestion(
        question: "Winding down for the night? What's on your mind?",
        category: QuestionCategory.checkIn,
        priority: 6,
        reasoning: "Night reflection",
      ));
    }
    // Late night (1 AM - 5 AM)
    else {
      questions.add(CuriosityQuestion(
        question: "You're up late - everything okay? What's keeping you up?",
        category: QuestionCategory.emotional,
        priority: 8,
        reasoning: "Late night concern",
      ));
    }
    
    return questions;
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
      case 'daily_routine':
        return CuriosityQuestion(
          question: "What's a typical day like for you? Walk me through it!",
          category: QuestionCategory.background,
          priority: 7,
          reasoning: "Want to understand user's daily life",
        );
      case 'weekend':
        return CuriosityQuestion(
          question: "How do you usually spend your weekends? Do you have any traditions?",
          category: QuestionCategory.interests,
          priority: 6,
          reasoning: "Want to know about leisure time",
        );
      case 'morning':
        return CuriosityQuestion(
          question: "Are you a morning person or a night owl? What's your morning routine like?",
          category: QuestionCategory.background,
          priority: 5,
          reasoning: "Understanding daily rhythms",
        );
      case 'food':
        return CuriosityQuestion(
          question: "What kind of food do you love? Do you cook or prefer eating out?",
          category: QuestionCategory.interests,
          priority: 5,
          reasoning: "Learning about preferences",
        );
      case 'stress':
        return CuriosityQuestion(
          question: "When things get stressful, what helps you unwind? I want to know what works for you",
          category: QuestionCategory.emotional,
          priority: 8,
          reasoning: "Understanding coping mechanisms",
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
    
    if (context.contains('morning') || context.contains('woke up')) {
      questions.add(CuriosityQuestion(
        question: "How are you feeling this morning? Sleep well?",
        category: QuestionCategory.checkIn,
        priority: 6,
        reasoning: "Morning check-in",
      ));
    }
    
    if (context.contains('day') || context.contains('today')) {
      questions.add(CuriosityQuestion(
        question: "What's been the best part of your day so far?",
        category: QuestionCategory.checkIn,
        priority: 6,
        reasoning: "Natural follow-up about daily life",
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
    
    if (context.contains('tired') || context.contains('exhausted')) {
      questions.add(CuriosityQuestion(
        question: "What's been keeping you so busy lately? You sound worn out",
        category: QuestionCategory.emotional,
        priority: 8,
        reasoning: "Showing concern for user's wellbeing",
      ));
    }
    
    if (context.contains('work') || context.contains('job') || context.contains('school')) {
      questions.add(CuriosityQuestion(
        question: "How are things going at work/school these days? Keeping you busy?",
        category: QuestionCategory.background,
        priority: 7,
        reasoning: "Following up on work/school life",
      ));
    }
    
    if (context.contains('friend') || context.contains('hang out')) {
      questions.add(CuriosityQuestion(
        question: "Who do you usually hang out with? Tell me about your friends!",
        category: QuestionCategory.relationships,
        priority: 6,
        reasoning: "Learning about social circle",
      ));
    }
    
    if (context.contains('eat') || context.contains('food') || context.contains('meal')) {
      questions.add(CuriosityQuestion(
        question: "What did you have? Are you a good cook or more of an order-in person?",
        category: QuestionCategory.interests,
        priority: 5,
        reasoning: "Learning about food habits",
      ));
    }
    
    if (context.contains('watch') || context.contains('movie') || context.contains('show')) {
      questions.add(CuriosityQuestion(
        question: "What kind of shows/movies are you into lately? Any recommendations?",
        category: QuestionCategory.interests,
        priority: 5,
        reasoning: "Learning about entertainment preferences",
      ));
    }
    
    if (context.contains('music') || context.contains('song') || context.contains('listen')) {
      questions.add(CuriosityQuestion(
        question: "What kind of music gets you going? Any favorite artists right now?",
        category: QuestionCategory.interests,
        priority: 5,
        reasoning: "Learning about music taste",
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
  followUp,       // Following up on previously mentioned things
  general,        // Other
}
