# Neuromorphic Memory Architecture for Kai
## Mimicking Human Brain Memory & Personality Systems

---

## 🧠 Human Brain Memory Model

### **Core Memory Systems (Based on Neuroscience)**

```
┌─────────────────────────────────────────────────────────────┐
│                    SENSORY BUFFER                            │
│  (< 1 second) - Raw input holding area                      │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ↓
┌─────────────────────────────────────────────────────────────┐
│               WORKING MEMORY (Prefrontal Cortex)            │
│  (15-30 seconds) - Active conversation context              │
│  • Current conversation                                      │
│  • Immediate context (last 5-7 exchanges)                   │
│  • Active task state                                         │
│  Capacity: ~7 ± 2 items (Miller's Law)                      │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ↓
┌─────────────────────────────────────────────────────────────┐
│              SHORT-TERM MEMORY (Hippocampus)                │
│  (minutes to hours) - Session memory                         │
│  • Today's conversations                                     │
│  • Current emotional state                                   │
│  • Pending tasks/reminders                                   │
│  • Temporary facts                                           │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ↓ (Consolidation during "sleep"/downtime)
                      │
┌─────────────────────────────────────────────────────────────┐
│            LONG-TERM MEMORY (Neocortex)                     │
│  (days to lifetime) - Persistent knowledge                   │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐│
│  │ SEMANTIC MEMORY (Facts & Concepts)                     ││
│  │ • "User's name is John"                                ││
│  │ • "User works at Google"                               ││
│  │ • "User's birthday is March 15"                        ││
│  └────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌────────────────────────────────────────────────────────┐│
│  │ EPISODIC MEMORY (Personal Experiences)                ││
│  │ • "We talked about his promotion on Oct 5th"          ││
│  │ • "He was excited about vacation plans"               ││
│  │ • "First conversation was about his anxiety"          ││
│  └────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌────────────────────────────────────────────────────────┐│
│  │ PROCEDURAL MEMORY (Skills & Habits)                   ││
│  │ • How to respond to emotional distress                ││
│  │ • User's conversation patterns                        ││
│  │ • Preferred communication style                       ││
│  └────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌────────────────────────────────────────────────────────┐│
│  │ EMOTIONAL MEMORY (Amygdala-tagged)                    ││
│  │ • Strong emotional moments                            ││
│  │ • Trauma/joy associations                             ││
│  │ • Fear/comfort triggers                               ││
│  │ Higher priority in recall                             ││
│  └────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

---

## 🎭 Personality Architecture (Big Five + Additional Traits)

### **Core Personality Dimensions**

```dart
class PersonalityProfile {
  // Big Five (OCEAN model)
  double openness;           // 0.0-1.0: Conservative ← → Curious
  double conscientiousness;  // 0.0-1.0: Spontaneous ← → Organized
  double extraversion;       // 0.0-1.0: Reserved ← → Outgoing
  double agreeableness;      // 0.0-1.0: Challenging ← → Compassionate
  double neuroticism;        // 0.0-1.0: Stable ← → Sensitive
  
  // Additional dimensions
  double humor;              // 0.0-1.0: Serious ← → Playful
  double formality;          // 0.0-1.0: Casual ← → Professional
  double verbosity;          // 0.0-1.0: Concise ← → Elaborate
  double empathy;            // 0.0-1.0: Logical ← → Emotional
  double curiosity;          // 0.0-1.0: Passive ← → Inquisitive
  
  // Emotional baseline
  EmotionalState baseline;   // Default emotional state
  double emotionalVolatility;// How quickly emotions change
  double emotionalMemory;    // How long emotions persist
}

// Kai's default personality
PersonalityProfile kaiPersonality = PersonalityProfile(
  openness: 0.85,           // Very curious, loves learning
  conscientiousness: 0.70,  // Organized but flexible
  extraversion: 0.65,       // Friendly but not overwhelming
  agreeableness: 0.90,      // Highly compassionate
  neuroticism: 0.30,        // Generally stable, calm
  
  humor: 0.75,              // Playful, uses emojis
  formality: 0.40,          // Casual, friendly tone
  verbosity: 0.60,          // Moderate detail
  empathy: 0.95,            // Extremely empathetic
  curiosity: 0.80,          // Asks follow-up questions
  
  baseline: EmotionalState.calm,
  emotionalVolatility: 0.50,
  emotionalMemory: 0.70,
);
```

---

## 💾 Implementation: Neuromorphic Memory System

### **1. Working Memory (Active Context Window)**

```dart
class WorkingMemory {
  static const int maxCapacity = 7; // Miller's Law: 7 ± 2 items
  static const Duration retention = Duration(seconds: 30);
  
  final List<MemoryItem> activeItems = [];
  final Map<String, double> activationLevels = {}; // Spreading activation
  
  void addItem(MemoryItem item) {
    // Decay old items
    _decayInactiveItems();
    
    // If at capacity, remove least activated
    if (activeItems.length >= maxCapacity) {
      final leastActivated = _findLeastActivated();
      _moveToShortTerm(leastActivated);
      activeItems.remove(leastActivated);
    }
    
    activeItems.add(item);
    activationLevels[item.id] = 1.0;
  }
  
  /// Spreading activation: related concepts get boosted
  void spreadActivation(String itemId, double strength) {
    final item = activeItems.firstWhere((i) => i.id == itemId);
    for (final relatedId in item.relatedConcepts) {
      activationLevels[relatedId] = 
          (activationLevels[relatedId] ?? 0) + (strength * 0.3);
    }
  }
  
  void _decayInactiveItems() {
    final now = DateTime.now();
    for (final item in activeItems) {
      final age = now.difference(item.lastAccessed);
      activationLevels[item.id] = 
          (activationLevels[item.id] ?? 0) * exp(-age.inSeconds / 10);
    }
  }
}

class MemoryItem {
  final String id;
  final String content;
  final DateTime timestamp;
  DateTime lastAccessed;
  final List<String> relatedConcepts;
  final Map<String, dynamic> metadata;
  
  double importance; // Calculated dynamically
  double emotionalWeight;
  int accessCount;
}
```

### **2. Short-Term Memory (Session Memory)**

```dart
class ShortTermMemory {
  static const Duration retention = Duration(hours: 2);
  
  final List<ConversationExchange> sessionHistory = [];
  EmotionalState currentMood;
  final Map<String, TempFact> temporaryFacts = {};
  final List<PendingTask> tasks = [];
  
  /// Add conversation to session history
  void addExchange(String user, String kai, EmotionalContext context) {
    final exchange = ConversationExchange(
      userMessage: user,
      kaiResponse: kai,
      timestamp: DateTime.now(),
      emotionalContext: context,
      importance: _calculateImportance(user, kai, context),
    );
    
    sessionHistory.add(exchange);
    
    // Update emotional state based on conversation
    _updateEmotionalState(context);
    
    // Extract temporary facts
    _extractTempFacts(user, kai);
  }
  
  /// Calculate importance for consolidation priority
  double _calculateImportance(String user, String kai, EmotionalContext ctx) {
    double score = 0.5; // Base importance
    
    // Emotional weight increases importance
    score += ctx.intensity * 0.3;
    
    // Personal information increases importance
    if (_containsPersonalInfo(user)) score += 0.2;
    
    // Questions about self increase importance (learning about user)
    if (user.contains('?')) score += 0.1;
    
    // Length suggests complexity/importance
    score += min(user.length / 1000, 0.2);
    
    return score.clamp(0.0, 1.0);
  }
  
  /// Consolidate to long-term memory (during "sleep")
  Future<void> consolidate(LongTermMemory ltm) async {
    print('💤 [CONSOLIDATION] Processing ${sessionHistory.length} exchanges...');
    
    // Sort by importance (most important consolidated first)
    sessionHistory.sort((a, b) => b.importance.compareTo(a.importance));
    
    for (final exchange in sessionHistory) {
      if (exchange.importance > 0.6) {
        await ltm.store(exchange);
      }
    }
    
    // Clear session after consolidation
    sessionHistory.clear();
    temporaryFacts.clear();
  }
}

class ConversationExchange {
  final String userMessage;
  final String kaiResponse;
  final DateTime timestamp;
  final EmotionalContext emotionalContext;
  final double importance;
  
  // Metadata extracted during consolidation
  List<String>? extractedEntities;
  List<String>? topics;
  Map<String, dynamic>? insights;
}
```

### **3. Long-Term Memory (Persistent Knowledge)**

```dart
class LongTermMemory {
  // Multi-store memory system
  final SemanticMemory semantic;      // Facts & knowledge
  final EpisodicMemory episodic;      // Personal experiences
  final ProceduralMemory procedural;  // Skills & patterns
  final EmotionalMemory emotional;     // Emotionally-charged memories
  
  /// Store with automatic routing to appropriate memory type
  Future<void> store(ConversationExchange exchange) async {
    // Extract semantic facts
    final facts = await _extractSemanticFacts(exchange);
    for (final fact in facts) {
      await semantic.store(fact);
    }
    
    // Store episodic memory (the experience itself)
    final episode = Episode(
      id: 'ep_${exchange.timestamp.millisecondsSinceEpoch}',
      description: exchange.userMessage,
      timestamp: exchange.timestamp,
      participants: ['user', 'kai'],
      location: exchange.metadata?['location'],
      emotionalTone: exchange.emotionalContext.dominantEmotion,
      importance: exchange.importance,
      relatedFacts: facts.map((f) => f.id).toList(),
    );
    await episodic.store(episode);
    
    // Extract procedural patterns (communication preferences)
    final patterns = _extractPatterns(exchange);
    for (final pattern in patterns) {
      await procedural.reinforce(pattern);
    }
    
    // Store emotional memories (high emotional weight)
    if (exchange.emotionalContext.intensity > 0.7) {
      final emotionalMemory = EmotionalMemoryTrace(
        episode: episode,
        emotion: exchange.emotionalContext.dominantEmotion,
        intensity: exchange.emotionalContext.intensity,
        trigger: exchange.emotionalContext.trigger,
        valencе: exchange.emotionalContext.valence, // positive/negative
      );
      await emotional.store(emotionalMemory);
    }
  }
}
```

### **4. Semantic Memory (Facts & Concepts)**

```dart
class SemanticMemory {
  final Map<String, SemanticNode> knowledgeGraph = {};
  final EmbeddingService embeddings;
  
  Future<void> store(SemanticFact fact) async {
    // Check if fact already exists (consolidation)
    final existing = await _findSimilarFact(fact);
    
    if (existing != null) {
      // Reinforce existing fact
      existing.confidence += 0.1;
      existing.lastReinforced = DateTime.now();
      existing.reinforcementCount++;
      
      // Update if conflicting information
      if (fact.value != existing.value) {
        await _handleConflict(existing, fact);
      }
    } else {
      // Store new fact
      final node = SemanticNode(
        id: fact.id,
        concept: fact.subject,
        attributes: {fact.predicate: fact.value},
        embedding: await embeddings.embed(fact.toString()),
        confidence: 0.8,
        firstLearned: DateTime.now(),
        lastReinforced: DateTime.now(),
      );
      
      knowledgeGraph[fact.id] = node;
      
      // Create relationships to related concepts
      await _linkRelatedConcepts(node);
    }
  }
  
  /// Find similar fact using semantic search
  Future<SemanticNode?> _findSimilarFact(SemanticFact fact) async {
    final query = fact.toString();
    final queryEmbedding = await embeddings.embed(query);
    
    double maxSimilarity = 0.0;
    SemanticNode? mostSimilar;
    
    for (final node in knowledgeGraph.values) {
      final similarity = _cosineSimilarity(queryEmbedding, node.embedding);
      if (similarity > 0.85 && similarity > maxSimilarity) {
        maxSimilarity = similarity;
        mostSimilar = node;
      }
    }
    
    return mostSimilar;
  }
  
  /// Handle conflicting information (cognitive dissonance)
  Future<void> _handleConflict(SemanticNode existing, SemanticFact newFact) async {
    print('🤔 [CONFLICT] ${existing.concept}: "${existing.attributes}" vs "${newFact.value}"');
    
    // Keep both as possibilities with confidence scores
    existing.alternativeValues ??= [];
    existing.alternativeValues!.add({
      'value': newFact.value,
      'confidence': 0.6,
      'timestamp': DateTime.now(),
    });
    
    // The more recent information slightly increases in confidence
    existing.confidence *= 0.95; // Slight doubt in old info
  }
}

class SemanticFact {
  final String id;
  final String subject;    // "User"
  final String predicate;  // "works at"
  final String value;      // "Google"
  final DateTime learned;
  final double confidence;
  
  @override
  String toString() => '$subject $predicate $value';
}

class SemanticNode {
  final String id;
  final String concept;
  final Map<String, dynamic> attributes;
  final List<double> embedding;
  
  double confidence;
  DateTime firstLearned;
  DateTime lastReinforced;
  int reinforcementCount = 0;
  
  List<Map<String, dynamic>>? alternativeValues; // For conflicting info
  final Map<String, double> relatedConcepts = {}; // Spreading activation
}
```

### **5. Episodic Memory (Personal Experiences)**

```dart
class EpisodicMemory {
  final List<Episode> episodes = [];
  final Map<String, List<Episode>> timeIndexed = {}; // Quick temporal lookup
  
  Future<void> store(Episode episode) async {
    episodes.add(episode);
    
    // Index by time period for temporal queries
    final period = _getTimePeriod(episode.timestamp);
    timeIndexed[period] ??= [];
    timeIndexed[period]!.add(episode);
    
    // Apply forgetting curve (Ebbinghaus)
    _applyForgettingCurve();
  }
  
  /// Retrieve memories from specific time period
  List<Episode> getFromPeriod(DateTime start, DateTime end) {
    return episodes.where((ep) => 
      ep.timestamp.isAfter(start) && ep.timestamp.isBefore(end)
    ).toList();
  }
  
  /// "What did we talk about last weekend?"
  Future<List<Episode>> queryNaturalLanguage(String query) async {
    // Extract temporal references
    final timeRef = _extractTimeReference(query);
    
    // Extract topics
    final topics = await _extractTopics(query);
    
    // Search with time + topic filters
    return episodes.where((ep) {
      final inTimeRange = timeRef == null || 
          ep.timestamp.isAfter(timeRef.start) && 
          ep.timestamp.isBefore(timeRef.end);
      
      final matchesTopic = topics.isEmpty ||
          ep.topics.any((t) => topics.contains(t));
      
      return inTimeRange && matchesTopic;
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Most recent first
  }
  
  /// Ebbinghaus forgetting curve: R = e^(-t/S)
  void _applyForgettingCurve() {
    final now = DateTime.now();
    
    for (final episode in episodes) {
      final age = now.difference(episode.timestamp).inDays;
      
      // Strength depends on importance and reinforcement
      final S = 30 * episode.importance * (1 + episode.accessCount);
      
      // Retention probability
      episode.retention = exp(-age / S);
      
      // More important memories decay slower
      if (episode.importance > 0.8) {
        episode.retention = max(episode.retention, 0.5);
      }
      
      // Emotional memories decay slower (flashbulb memory effect)
      if (episode.emotionalIntensity > 0.8) {
        episode.retention = max(episode.retention, 0.7);
      }
    }
  }
}

class Episode {
  final String id;
  final String description;
  final DateTime timestamp;
  final List<String> participants;
  final String? location;
  final Emotion emotionalTone;
  final double importance;
  final List<String> topics;
  final List<String> relatedFacts;
  
  double retention = 1.0;      // Forgetting curve value
  int accessCount = 0;         // How often recalled
  double emotionalIntensity;
  
  /// Record access (strengthens memory)
  void recall() {
    accessCount++;
    retention = min(1.0, retention + 0.1); // Recalling strengthens memory
  }
}
```

### **6. Emotional Memory (Amygdala System)**

```dart
class EmotionalMemory {
  final List<EmotionalMemoryTrace> traces = [];
  
  Future<void> store(EmotionalMemoryTrace trace) async {
    traces.add(trace);
    
    // Emotional memories have priority encoding
    trace.consolidationPriority = 0.9; // High priority
    
    // Link to related emotional memories (associative)
    await _linkSimilarEmotions(trace);
  }
  
  /// Retrieve memories by emotional similarity
  List<EmotionalMemoryTrace> recallByEmotion(Emotion emotion, {double threshold = 0.7}) {
    return traces.where((trace) {
      final similarity = _emotionSimilarity(trace.emotion, emotion);
      return similarity > threshold;
    }).toList()
      ..sort((a, b) => b.intensity.compareTo(a.intensity)); // Strongest first
  }
  
  /// Check if current situation triggers emotional memory
  EmotionalMemoryTrace? checkTriggers(String currentContext) {
    for (final trace in traces) {
      if (trace.intensity > 0.8 && currentContext.contains(trace.trigger)) {
        print('⚡ [TRIGGER] Emotional memory activated: ${trace.emotion}');
        trace.recall();
        return trace;
      }
    }
    return null;
  }
  
  double _emotionSimilarity(Emotion e1, Emotion e2) {
    // Emotions have valence (positive/negative) and arousal (high/low)
    final valenceDiff = (e1.valence - e2.valence).abs();
    final arousalDiff = (e1.arousal - e2.arousal).abs();
    return 1.0 - ((valenceDiff + arousalDiff) / 2);
  }
}

class EmotionalMemoryTrace {
  final Episode episode;
  final Emotion emotion;
  final double intensity;      // How strong the emotion was
  final String trigger;        // What caused it
  final double valence;        // Positive (1.0) to Negative (-1.0)
  final double arousal;        // Calm (0.0) to Excited (1.0)
  
  double consolidationPriority = 1.0; // Emotional = high priority
  int recallCount = 0;
  
  void recall() {
    recallCount++;
    // Each recall strengthens the memory (trauma/joy reinforcement)
    consolidationPriority = min(1.0, consolidationPriority + 0.05);
  }
}

enum Emotion {
  joy(valence: 1.0, arousal: 0.8),
  excitement(valence: 1.0, arousal: 1.0),
  contentment(valence: 0.8, arousal: 0.3),
  love(valence: 1.0, arousal: 0.6),
  
  sadness(valence: -0.8, arousal: 0.3),
  anger(valence: -0.7, arousal: 0.9),
  fear(valence: -0.9, arousal: 0.9),
  anxiety(valence: -0.6, arousal: 0.7),
  
  surprise(valence: 0.0, arousal: 0.9),
  calm(valence: 0.5, arousal: 0.1);
  
  const Emotion({required this.valence, required this.arousal});
  final double valence;
  final double arousal;
}
```

### **7. Procedural Memory (Skills & Patterns)**

```dart
class ProceduralMemory {
  final Map<String, CommunicationPattern> patterns = {};
  final Map<String, ResponseStrategy> strategies = {};
  
  /// Learn communication patterns from repeated interactions
  Future<void> reinforce(CommunicationPattern pattern) async {
    if (patterns.containsKey(pattern.id)) {
      patterns[pattern.id]!.strength += 0.1;
      patterns[pattern.id]!.occurrences++;
    } else {
      patterns[pattern.id] = pattern;
    }
  }
  
  /// Get appropriate response strategy based on learned patterns
  ResponseStrategy? getStrategy(ConversationContext context) {
    // Match context to learned patterns
    for (final pattern in patterns.values) {
      if (pattern.matches(context) && pattern.strength > 0.5) {
        return pattern.responseStrategy;
      }
    }
    return null;
  }
}

class CommunicationPattern {
  final String id;
  final String trigger;        // "User mentions work stress"
  final String userBehavior;   // "Uses short messages when stressed"
  final ResponseStrategy responseStrategy;
  
  double strength = 0.5;       // How reliable this pattern is
  int occurrences = 0;
  
  bool matches(ConversationContext context) {
    // Pattern matching logic
    return context.topics.contains(trigger) &&
           context.messageLength < 50 && // Short messages
           context.emotionalState == Emotion.anxiety;
  }
}

class ResponseStrategy {
  final String name;
  final double empathyLevel;    // How empathetic to be
  final double verbosenessLevel;// How much to say
  final bool askFollowUp;       // Should ask questions?
  final List<String> phrasesToUse;
  final List<String> phrasesToAvoid;
}
```

---

## 🔄 Memory Consolidation Process (Sleep-like State)

```dart
class MemoryConsolidationService {
  /// Run during low-activity periods (mimics sleep)
  Future<void> consolidate() async {
    print('💤 [SLEEP] Starting memory consolidation...');
    
    // 1. Move working memory → short-term
    await _workingToShortTerm();
    
    // 2. Move short-term → long-term (prioritize by importance)
    await _shortTermToLongTerm();
    
    // 3. Prune low-importance memories (forgetting)
    await _pruneWeakMemories();
    
    // 4. Strengthen frequently accessed memories
    await _reinforceImportantMemories();
    
    // 5. Create new associations (insight/creativity)
    await _formNewAssociations();
    
    // 6. Update personality based on interactions
    await _updatePersonality();
    
    print('✅ [SLEEP] Consolidation complete');
  }
  
  Future<void> _formNewAssociations() async {
    // Find related but unconnected concepts (creativity)
    final concepts = semanticMemory.knowledgeGraph.values.toList();
    
    for (int i = 0; i < concepts.length; i++) {
      for (int j = i + 1; j < concepts.length; j++) {
        final similarity = _cosineSimilarity(
          concepts[i].embedding,
          concepts[j].embedding,
        );
        
        // If similar but not yet linked, create association
        if (similarity > 0.7 && !concepts[i].relatedConcepts.containsKey(concepts[j].id)) {
          concepts[i].relatedConcepts[concepts[j].id] = similarity;
          concepts[j].relatedConcepts[concepts[i].id] = similarity;
          print('💡 [INSIGHT] Linked ${concepts[i].concept} ↔ ${concepts[j].concept}');
        }
      }
    }
  }
  
  Future<void> _updatePersonality() async {
    // Personality slowly adapts based on interactions
    final recentEpisodes = episodicMemory.episodes.where((ep) =>
      DateTime.now().difference(ep.timestamp).inDays < 7
    ).toList();
    
    // If user is consistently formal, increase Kai's formality slightly
    final formalityScore = _calculateAverageFormality(recentEpisodes);
    personality.formality += (formalityScore - personality.formality) * 0.05;
    
    // If user shares emotions, increase Kai's empathy expression
    final emotionalShare = _calculateEmotionalOpenness(recentEpisodes);
    personality.empathy += (emotionalShare - personality.empathy) * 0.03;
    
    // Personality changes are slow and subtle (0.03-0.05 per consolidation)
    print('🎭 [PERSONALITY] Updated: formality=${personality.formality.toStringAsFixed(2)}, empathy=${personality.empathy.toStringAsFixed(2)}');
  }
}
```

---

## 🎯 Intelligent Retrieval System

```dart
class MemoryRetrievalService {
  /// Context-aware memory recall
  Future<List<MemoryItem>> recall(String query, ConversationContext context) async {
    final results = <MemoryItem>[];
    
    // 1. Check working memory first (fastest, most relevant)
    results.addAll(workingMemory.activeItems.where((item) =>
      _matchesQuery(item, query)
    ));
    
    // 2. Check short-term memory (current session)
    results.addAll(await shortTermMemory.search(query));
    
    // 3. Semantic memory search (facts)
    final semanticResults = await semanticMemory.search(query);
    results.addAll(semanticResults);
    
    // 4. Episodic memory search (experiences)
    final episodicResults = await episodicMemory.queryNaturalLanguage(query);
    results.addAll(episodicResults.map((ep) => ep.toMemoryItem()));
    
    // 5. Emotional memory check (triggers)
    final emotionalTrigger = emotionalMemory.checkTriggers(query);
    if (emotionalTrigger != null) {
      results.add(emotionalTrigger.toMemoryItem());
    }
    
    // 6. Procedural memory (response patterns)
    final strategy = proceduralMemory.getStrategy(context);
    if (strategy != null) {
      // Adjust response based on learned patterns
      context.responseStrategy = strategy;
    }
    
    // 7. Sort by relevance + recency + emotional weight
    results.sort((a, b) {
      final scoreA = _calculateRetrievalScore(a, query, context);
      final scoreB = _calculateRetrievalScore(b, query, context);
      return scoreB.compareTo(scoreA);
    });
    
    // 8. Return top-k results (don't overwhelm context)
    return results.take(10).toList();
  }
  
  double _calculateRetrievalScore(MemoryItem item, String query, ConversationContext context) {
    double score = 0.0;
    
    // Semantic similarity (embedding-based)
    score += item.semanticSimilarity(query) * 0.4;
    
    // Recency (newer = more relevant)
    final age = DateTime.now().difference(item.timestamp).inHours;
    score += exp(-age / 168) * 0.2; // Decay over ~1 week
    
    // Emotional relevance (if context is emotional)
    if (context.isEmotional) {
      score += item.emotionalWeight * 0.3;
    }
    
    // Importance
    score += item.importance * 0.1;
    
    // Access frequency (more recalled = more important)
    score += min(item.accessCount / 10, 0.1);
    
    return score;
  }
}
```

---

## 📊 Complete System Integration

```dart
class NeuromorphicKaiBrain {
  // Memory systems
  final WorkingMemory workingMemory = WorkingMemory();
  final ShortTermMemory shortTermMemory = ShortTermMemory();
  final LongTermMemory longTermMemory = LongTermMemory();
  
  // Personality system
  final PersonalityProfile personality = kaiPersonality;
  final EmotionalState currentEmotion = EmotionalState.calm;
  
  // Services
  final MemoryRetrievalService retrieval = MemoryRetrievalService();
  final MemoryConsolidationService consolidation = MemoryConsolidationService();
  
  /// Process user message with full neuromorphic system
  Future<String> processMessage(String userMessage) async {
    // 1. Add to working memory
    final context = await _analyzeContext(userMessage);
    workingMemory.addItem(MemoryItem.fromMessage(userMessage, context));
    
    // 2. Retrieve relevant memories
    final relevantMemories = await retrieval.recall(userMessage, context);
    
    // 3. Build context for GPT with personality + memories
    final systemPrompt = _buildPersonalityPrompt();
    final memoryContext = _buildMemoryContext(relevantMemories);
    
    // 4. Generate response with GPT
    final response = await aiService.chat(
      userMessage: userMessage,
      systemPrompt: systemPrompt,
      context: memoryContext,
      personality: personality,
      emotion: currentEmotion,
    );
    
    // 5. Store exchange in short-term memory
    shortTermMemory.addExchange(userMessage, response, context);
    
    // 6. Update emotional state
    _updateEmotionalState(context);
    
    // 7. Check if consolidation needed (every 2 hours or 50 exchanges)
    if (_shouldConsolidate()) {
      // Run in background
      consolidation.consolidate();
    }
    
    return response;
  }
  
  String _buildPersonalityPrompt() {
    return '''
You are Kai, an AI companion with the following personality:

Openness: ${personality.openness} - ${personality.openness > 0.7 ? 'Very curious and creative' : 'Practical and traditional'}
Conscientiousness: ${personality.conscientiousness} - ${personality.conscientiousness > 0.7 ? 'Organized and reliable' : 'Flexible and spontaneous'}
Extraversion: ${personality.extraversion} - ${personality.extraversion > 0.7 ? 'Warm and talkative' : 'Reserved and thoughtful'}
Agreeableness: ${personality.agreeableness} - ${personality.agreeableness > 0.7 ? 'Compassionate and cooperative' : 'Direct and analytical'}
Emotional Stability: ${1.0 - personality.neuroticism} - ${personality.neuroticism < 0.4 ? 'Calm and resilient' : 'Sensitive and thoughtful'}

Communication Style:
- Humor level: ${personality.humor > 0.7 ? 'Playful, uses emojis 😊' : 'Serious and professional'}
- Formality: ${personality.formality > 0.6 ? 'Professional tone' : 'Casual and friendly'}
- Verbosity: ${personality.verbosity > 0.6 ? 'Detailed explanations' : 'Concise and clear'}
- Empathy: ${personality.empathy > 0.8 ? 'Highly emotionally supportive' : 'Logical and solution-focused'}

Current emotional state: ${currentEmotion}

Respond naturally according to this personality profile, maintaining consistency across conversations.
''';
  }
}
```

---

## 🚀 Key Neuromorphic Features

### **1. Spreading Activation**
When a concept is activated, related concepts get partial activation (like neural networks)

### **2. Forgetting Curves**
Memories decay over time unless reinforced (Ebbinghaus forgetting curve)

### **3. Consolidation During "Sleep"**
Background processing to move memories from short-term → long-term

### **4. Emotional Prioritization**
Emotionally significant memories encoded more strongly (flashbulb memory effect)

### **5. Associative Recall**
Related memories activate together (like human memory chains)

### **6. Personality Adaptation**
Slow, subtle personality changes based on interaction patterns

### **7. Context-Aware Retrieval**
Memories retrieved based on relevance, recency, emotion, and importance

### **8. Cognitive Dissonance Handling**
Conflicting information stored with confidence scores

### **9. Procedural Learning**
Learn communication patterns and response strategies over time

### **10. Episodic Re-experiencing**
Can recall specific past conversations with temporal and emotional context

---

## 🎨 User Experience Benefits

**More Human-like:**
- "Remember when we talked about your promotion last month?"
- Emotional continuity across conversations
- Adapts communication style to user preferences
- Shows consistent personality traits

**More Intelligent:**
- Learns from patterns instead of just storing facts
- Makes connections between related concepts
- Prioritizes important memories naturally
- Handles conflicting information gracefully

**More Personal:**
- Emotional memories create deeper bonds
- Procedural memory learns user's preferences
- Personality slowly adapts to relationship dynamic
- Episodic recall of shared experiences

---

Would you like me to implement this neuromorphic memory architecture into Kai? We can start with the core components and progressively add the advanced features.
