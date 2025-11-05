/// Local NLP Service
/// Intelligent text analysis without API calls
/// Extracts entities, topics, and relationships from conversations
library;

import 'dart:math';

class LocalNLPService {
  static final LocalNLPService _instance = LocalNLPService._internal();
  factory LocalNLPService() => _instance;
  LocalNLPService._internal();

  /// Common words to ignore (stop words)
  static final Set<String> _stopWords = {
    'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
    'of', 'with', 'by', 'from', 'as', 'is', 'was', 'are', 'were', 'been',
    'be', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
    'should', 'may', 'might', 'must', 'can', 'this', 'that', 'these', 'those',
    'i', 'you', 'he', 'she', 'it', 'we', 'they', 'my', 'your', 'his', 'her',
    'its', 'our', 'their', 'me', 'him', 'us', 'them', 'what', 'which', 'who',
    'when', 'where', 'why', 'how', 'all', 'each', 'every', 'both', 'few',
    'more', 'most', 'other', 'some', 'such', 'no', 'nor', 'not', 'only',
    'own', 'same', 'so', 'than', 'too', 'very', 's', 't', 'just', 'now',
    'im', 'ive', 'dont', 'didnt', 'doesnt', 'cant', 'wont', 'wouldnt',
  };

  /// Emotion keywords and their intensities
  static final Map<String, double> _emotionKeywords = {
    // Positive emotions
    'happy': 0.8, 'joy': 0.9, 'excited': 0.9, 'love': 1.0, 'wonderful': 0.9,
    'amazing': 0.8, 'great': 0.7, 'good': 0.6, 'nice': 0.6, 'glad': 0.7,
    'pleased': 0.7, 'delighted': 0.8, 'thrilled': 0.9, 'grateful': 0.8,
    // Negative emotions
    'sad': 0.8, 'angry': 0.9, 'frustrated': 0.8, 'worried': 0.7, 'anxious': 0.8,
    'stressed': 0.8, 'upset': 0.7, 'disappointed': 0.7, 'hurt': 0.8, 'scared': 0.8,
    'afraid': 0.7, 'terrible': 0.9, 'awful': 0.9, 'bad': 0.6, 'hate': 0.9,
  };

  /// Topic keywords for categorization
  static final Map<String, List<String>> _topicKeywords = {
    'work': ['work', 'job', 'office', 'boss', 'colleague', 'meeting', 'project', 'deadline', 'career', 'business', 'client', 'salary'],
    'family': ['family', 'mom', 'dad', 'mother', 'father', 'sister', 'brother', 'parent', 'child', 'kids', 'baby', 'son', 'daughter'],
    'health': ['health', 'doctor', 'hospital', 'medicine', 'sick', 'pain', 'exercise', 'gym', 'diet', 'sleep', 'tired', 'energy'],
    'relationships': ['friend', 'boyfriend', 'girlfriend', 'partner', 'husband', 'wife', 'relationship', 'dating', 'marriage', 'love'],
    'hobbies': ['hobby', 'music', 'movie', 'book', 'game', 'sport', 'travel', 'cooking', 'art', 'reading', 'writing', 'photography'],
    'technology': ['computer', 'phone', 'app', 'software', 'website', 'internet', 'code', 'programming', 'tech', 'device', 'screen'],
    'food': ['food', 'eat', 'restaurant', 'dinner', 'lunch', 'breakfast', 'cook', 'meal', 'hungry', 'delicious', 'taste'],
    'finance': ['money', 'pay', 'buy', 'spend', 'save', 'bank', 'budget', 'cost', 'price', 'expensive', 'cheap', 'financial'],
    'education': ['school', 'college', 'university', 'study', 'learn', 'class', 'teacher', 'student', 'exam', 'homework', 'degree'],
  };

  /// Extract entities from text (people, places, concepts)
  EntityExtractionResult extractEntities(String text) {
    final words = _tokenize(text);
    final entities = <ExtractedEntity>[];
    final seen = <String>{};

    // Extract capitalized sequences (likely proper nouns)
    final capitalizedSequences = _extractCapitalizedSequences(text);
    for (final seq in capitalizedSequences) {
      final key = seq.toLowerCase();
      if (!seen.contains(key) && !_stopWords.contains(key)) {
        entities.add(ExtractedEntity(
          text: seq,
          type: EntityType.properNoun,
          importance: 0.7,
          positions: _findPositions(text, seq),
        ));
        seen.add(key);
      }
    }

    // Extract emotion-related entities
    for (final word in words) {
      final lower = word.toLowerCase();
      if (_emotionKeywords.containsKey(lower) && !seen.contains(lower)) {
        entities.add(ExtractedEntity(
          text: word,
          type: EntityType.emotion,
          importance: _emotionKeywords[lower]!,
          positions: _findPositions(text, word),
        ));
        seen.add(lower);
      }
    }

    // Extract important nouns using frequency
    final nounCandidates = _extractNounCandidates(words);
    for (final noun in nounCandidates.entries) {
      final key = noun.key.toLowerCase();
      if (!seen.contains(key) && noun.value >= 2) {
        entities.add(ExtractedEntity(
          text: noun.key,
          type: EntityType.concept,
          importance: min(1.0, noun.value * 0.3),
          positions: _findPositions(text, noun.key),
        ));
        seen.add(key);
      }
    }

    return EntityExtractionResult(entities: entities);
  }

  /// Identify topics in text
  TopicAnalysisResult analyzeTopics(String text) {
    final lower = text.toLowerCase();
    final topicScores = <String, double>{};

    for (final topic in _topicKeywords.entries) {
      double score = 0.0;
      for (final keyword in topic.value) {
        if (lower.contains(keyword)) {
          score += 1.0;
        }
      }
      if (score > 0) {
        topicScores[topic.key] = score / topic.value.length;
      }
    }

    // Sort by score
    final sortedTopics = topicScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return TopicAnalysisResult(
      topics: Map.fromEntries(sortedTopics),
      primaryTopic: sortedTopics.isNotEmpty ? sortedTopics.first.key : null,
    );
  }

  /// Analyze sentiment of text
  SentimentAnalysisResult analyzeSentiment(String text) {
    final words = _tokenize(text);
    double positiveScore = 0.0;
    double negativeScore = 0.0;
    int emotionCount = 0;

    for (final word in words) {
      final lower = word.toLowerCase();
      if (_emotionKeywords.containsKey(lower)) {
        final intensity = _emotionKeywords[lower]!;
        if (_isPositiveEmotion(lower)) {
          positiveScore += intensity;
        } else {
          negativeScore += intensity;
        }
        emotionCount++;
      }
    }

    final total = positiveScore + negativeScore;
    final sentiment = total > 0
        ? (positiveScore - negativeScore) / total
        : 0.0;

    return SentimentAnalysisResult(
      sentiment: sentiment.clamp(-1.0, 1.0),
      positiveScore: positiveScore,
      negativeScore: negativeScore,
      emotionCount: emotionCount,
    );
  }

  /// Calculate TF-IDF for a corpus of documents
  Map<String, Map<String, double>> calculateTFIDF(List<String> documents) {
    final tfidf = <String, Map<String, double>>{};
    final docCount = documents.length;

    // Calculate term frequencies for each document
    final termFreqs = <int, Map<String, int>>{};
    for (var i = 0; i < documents.length; i++) {
      final words = _tokenize(documents[i]);
      termFreqs[i] = {};
      for (final word in words) {
        final lower = word.toLowerCase();
        if (!_stopWords.contains(lower)) {
          termFreqs[i]![lower] = (termFreqs[i]![lower] ?? 0) + 1;
        }
      }
    }

    // Calculate inverse document frequency
    final idf = <String, double>{};
    final allTerms = termFreqs.values
        .expand((m) => m.keys)
        .toSet();

    for (final term in allTerms) {
      final docsWithTerm = termFreqs.values
          .where((m) => m.containsKey(term))
          .length;
      idf[term] = log(docCount / docsWithTerm);
    }

    // Calculate TF-IDF for each document
    for (var i = 0; i < documents.length; i++) {
      tfidf['doc_$i'] = {};
      final maxFreq = termFreqs[i]!.values.isEmpty
          ? 1
          : termFreqs[i]!.values.reduce(max);

      for (final entry in termFreqs[i]!.entries) {
        final tf = entry.value / maxFreq;
        final tfidfScore = tf * (idf[entry.key] ?? 0);
        tfidf['doc_$i']![entry.key] = tfidfScore;
      }
    }

    return tfidf;
  }

  /// Find co-occurring terms (words that appear together)
  Map<String, Set<String>> findCoOccurrences(
    List<String> documents, {
    int windowSize = 5,
  }) {
    final coOccur = <String, Set<String>>{};

    for (final doc in documents) {
      final words = _tokenize(doc)
          .where((w) => !_stopWords.contains(w.toLowerCase()))
          .toList();

      for (var i = 0; i < words.length; i++) {
        final word = words[i].toLowerCase();
        coOccur[word] ??= {};

        // Look at surrounding words within window
        final start = max(0, i - windowSize);
        final end = min(words.length, i + windowSize + 1);

        for (var j = start; j < end; j++) {
          if (j != i) {
            final coWord = words[j].toLowerCase();
            if (!_stopWords.contains(coWord)) {
              coOccur[word]!.add(coWord);
            }
          }
        }
      }
    }

    return coOccur;
  }

  /// Calculate similarity between two texts using cosine similarity
  double calculateSimilarity(String text1, String text2) {
    final words1 = _tokenize(text1)
        .where((w) => !_stopWords.contains(w.toLowerCase()))
        .map((w) => w.toLowerCase())
        .toList();
    final words2 = _tokenize(text2)
        .where((w) => !_stopWords.contains(w.toLowerCase()))
        .map((w) => w.toLowerCase())
        .toList();

    if (words1.isEmpty || words2.isEmpty) return 0.0;

    // Create frequency vectors
    final allWords = {...words1, ...words2}.toList();
    final vector1 = allWords.map((w) => words1.where((x) => x == w).length).toList();
    final vector2 = allWords.map((w) => words2.where((x) => x == w).length).toList();

    // Cosine similarity
    double dotProduct = 0.0;
    double mag1 = 0.0;
    double mag2 = 0.0;

    for (var i = 0; i < allWords.length; i++) {
      dotProduct += vector1[i] * vector2[i];
      mag1 += vector1[i] * vector1[i];
      mag2 += vector2[i] * vector2[i];
    }

    if (mag1 == 0 || mag2 == 0) return 0.0;

    return dotProduct / (sqrt(mag1) * sqrt(mag2));
  }

  // === Private Helper Methods ===

  List<String> _tokenize(String text) {
    // Split on whitespace and common punctuation
    final pattern = RegExp(r'[\s,.;:!?()\[\]{}\-]+');
    return text
        .replaceAll('"', ' ')
        .replaceAll("'", ' ')
        .split(pattern)
        .where((w) => w.isNotEmpty)
        .toList();
  }

  List<String> _extractCapitalizedSequences(String text) {
    final sequences = <String>[];
    final words = text.split(RegExp(r'\s+'));
    
    String? currentSequence;
    for (final word in words) {
      final cleaned = word.replaceAll(RegExp(r'[^\w]'), '');
      if (cleaned.isEmpty) continue;

      if (cleaned[0] == cleaned[0].toUpperCase() &&
          cleaned.length > 1 &&
          !_stopWords.contains(cleaned.toLowerCase())) {
        if (currentSequence != null) {
          currentSequence += ' $cleaned';
        } else {
          currentSequence = cleaned;
        }
      } else {
        if (currentSequence != null) {
          sequences.add(currentSequence);
          currentSequence = null;
        }
      }
    }
    if (currentSequence != null) {
      sequences.add(currentSequence);
    }

    return sequences;
  }

  Map<String, int> _extractNounCandidates(List<String> words) {
    final nouns = <String, int>{};
    for (final word in words) {
      final lower = word.toLowerCase();
      // Simple heuristic: words that are not stop words and not emotions
      if (!_stopWords.contains(lower) &&
          !_emotionKeywords.containsKey(lower) &&
          word.length > 3) {
        nouns[word] = (nouns[word] ?? 0) + 1;
      }
    }
    return nouns;
  }

  List<int> _findPositions(String text, String word) {
    final positions = <int>[];
    var index = 0;
    while (index < text.length) {
      index = text.toLowerCase().indexOf(word.toLowerCase(), index);
      if (index == -1) break;
      positions.add(index);
      index += word.length;
    }
    return positions;
  }

  bool _isPositiveEmotion(String emotion) {
    const positive = {
      'happy', 'joy', 'excited', 'love', 'wonderful', 'amazing',
      'great', 'good', 'nice', 'glad', 'pleased', 'delighted',
      'thrilled', 'grateful',
    };
    return positive.contains(emotion);
  }
}

// === Data Classes ===

enum EntityType {
  properNoun,
  concept,
  emotion,
  unknown,
}

class ExtractedEntity {
  final String text;
  final EntityType type;
  final double importance;
  final List<int> positions;

  ExtractedEntity({
    required this.text,
    required this.type,
    required this.importance,
    required this.positions,
  });
}

class EntityExtractionResult {
  final List<ExtractedEntity> entities;

  EntityExtractionResult({required this.entities});

  List<ExtractedEntity> get byImportance {
    final sorted = List<ExtractedEntity>.from(entities);
    sorted.sort((a, b) => b.importance.compareTo(a.importance));
    return sorted;
  }
}

class TopicAnalysisResult {
  final Map<String, double> topics;
  final String? primaryTopic;

  TopicAnalysisResult({
    required this.topics,
    this.primaryTopic,
  });
}

class SentimentAnalysisResult {
  final double sentiment; // -1.0 (negative) to 1.0 (positive)
  final double positiveScore;
  final double negativeScore;
  final int emotionCount;

  SentimentAnalysisResult({
    required this.sentiment,
    required this.positiveScore,
    required this.negativeScore,
    required this.emotionCount,
  });

  bool get isPositive => sentiment > 0.2;
  bool get isNegative => sentiment < -0.2;
  bool get isNeutral => sentiment.abs() <= 0.2;
}
