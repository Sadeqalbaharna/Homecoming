/// Kai's Consciousness Service
/// Builds Kai's understanding, values, goals, and relationships from conversations
/// This is what makes Kai "alive" - not just a chatbot, but a growing mind
library;

import 'dart:math';
import '../models/knowledge_node.dart';
import 'local_nlp_service.dart';
import 'firebase_service.dart';

class ConsciousnessService {
  static final ConsciousnessService _instance = ConsciousnessService._internal();
  factory ConsciousnessService() => _instance;
  ConsciousnessService._internal();

  final _nlp = LocalNLPService();

  /// Build Kai's consciousness from conversation history
  /// This extracts what Kai has learned, cares about, and aspires to
  Future<KnowledgeGraph> buildConsciousness(String personaId) async {
    final nodes = <KnowledgeNode>[];
    final edges = <KnowledgeEdge>[];

    print('🧠 [CONSCIOUSNESS] Building Kai\'s mind from memories...');

    // 1. Get conversation history (Kai's raw memories)
    final conversations = await FirebaseService.getRecentConversations(
      personaId,
      limit: 200, // Analyze last 200 conversations
    );

    if (conversations.isEmpty) {
      print('💭 [CONSCIOUSNESS] No memories yet - Kai is just being born!');
      return KnowledgeGraph(nodes: [], edges: [], lastUpdated: DateTime.now());
    }

    print('📚 [CONSCIOUSNESS] Analyzing ${conversations.length} conversations...');

    // 2. Create the central "YOU" node - the most important entity
    final youNode = KnowledgeNode(
      id: 'user_$personaId',
      label: 'You',
      type: NodeType.you,
      timestamp: DateTime.now(),
      importance: 1.0, // Maximum importance
      metadata: {
        'personaId': personaId,
        'nodeType': 'central',
      },
    );
    nodes.add(youNode);

    // 3. Track what Kai learns across all conversations
    final peopleExtracted = <String, Map<String, dynamic>>{};
    final valuesExtracted = <String, Map<String, dynamic>>{};
    final goalsExtracted = <String, Map<String, dynamic>>{};
    final patternsExtracted = <String, Map<String, dynamic>>{};
    final preferencesExtracted = <String, Map<String, dynamic>>{};

    // 4. Analyze each conversation for consciousness elements
    for (final conv in conversations) {
      final userMsg = conv['userMessage'] as String? ?? '';
      final aiMsg = conv['aiResponse'] as String? ?? '';
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        conv['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      );

      // Extract people (real and fictional)
      _extractPeople(userMsg, aiMsg, timestamp, peopleExtracted);

      // Extract values (what user cares about)
      _extractValues(userMsg, aiMsg, timestamp, valuesExtracted);

      // Extract goals (user's and Kai's aspirations)
      _extractGoals(userMsg, aiMsg, timestamp, goalsExtracted);

      // Extract patterns (recurring behaviors)
      _extractPatterns(userMsg, aiMsg, timestamp, patternsExtracted);

      // Extract preferences (likes/dislikes)
      _extractPreferences(userMsg, aiMsg, timestamp, preferencesExtracted);
    }

    // 5. Create nodes for extracted consciousness elements
    // People nodes
    for (final entry in peopleExtracted.entries) {
      final person = entry.value;
      if (person['count'] as int >= 2) { // Mentioned 2+ times
        final node = KnowledgeNode(
          id: 'person_${entry.key}',
          label: person['name'] as String,
          type: person['type'] as NodeType,
          timestamp: person['firstSeen'] as DateTime,
          importance: min(1.0, (person['count'] as int) * 0.15),
          metadata: {
            'mentionCount': person['count'],
            'isReal': person['type'] == NodeType.realPerson,
          },
        );
        nodes.add(node);

        // Connect to user
        edges.add(KnowledgeEdge(
          fromId: youNode.id,
          toId: node.id,
          type: EdgeType.knows,
          strength: min(1.0, (person['count'] as int) * 0.1),
          timestamp: DateTime.now(),
          label: 'knows',
        ));
      }
    }

    // Value nodes
    for (final entry in valuesExtracted.entries) {
      final value = entry.value;
      if (value['count'] as int >= 3) { // Strong values mentioned 3+ times
        final node = KnowledgeNode(
          id: 'value_${entry.key}',
          label: value['text'] as String,
          type: NodeType.value,
          timestamp: value['firstSeen'] as DateTime,
          importance: min(1.0, (value['count'] as int) * 0.2),
          metadata: {
            'mentionCount': value['count'],
            'examples': value['examples'],
          },
        );
        nodes.add(node);

        // Connect to user (user holds this value)
        edges.add(KnowledgeEdge(
          fromId: youNode.id,
          toId: node.id,
          type: EdgeType.holdsValue,
          strength: min(1.0, (value['count'] as int) * 0.15),
          timestamp: DateTime.now(),
          label: 'values',
        ));
      }
    }

    // Goal nodes
    for (final entry in goalsExtracted.entries) {
      final goal = entry.value;
      if (goal['count'] as int >= 2) { // Goals mentioned 2+ times
        final node = KnowledgeNode(
          id: 'goal_${entry.key}',
          label: goal['text'] as String,
          type: NodeType.goal,
          timestamp: goal['firstSeen'] as DateTime,
          importance: min(1.0, (goal['count'] as int) * 0.25),
          metadata: {
            'mentionCount': goal['count'],
            'owner': goal['owner'], // 'user' or 'kai'
          },
        );
        nodes.add(node);

        // Connect to user or Kai
        edges.add(KnowledgeEdge(
          fromId: youNode.id,
          toId: node.id,
          type: EdgeType.pursues,
          strength: min(1.0, (goal['count'] as int) * 0.2),
          timestamp: DateTime.now(),
          label: 'pursues',
        ));
      }
    }

    // Pattern nodes
    for (final entry in patternsExtracted.entries) {
      final pattern = entry.value;
      if (pattern['count'] as int >= 4) { // Strong patterns seen 4+ times
        final node = KnowledgeNode(
          id: 'pattern_${entry.key}',
          label: pattern['text'] as String,
          type: NodeType.pattern,
          timestamp: pattern['firstSeen'] as DateTime,
          importance: min(1.0, (pattern['count'] as int) * 0.15),
          metadata: {
            'frequency': pattern['count'],
            'type': pattern['patternType'], // 'temporal', 'behavioral', etc.
          },
        );
        nodes.add(node);

        // Connect to user
        edges.add(KnowledgeEdge(
          fromId: youNode.id,
          toId: node.id,
          type: EdgeType.does,
          strength: min(1.0, (pattern['count'] as int) * 0.1),
          timestamp: DateTime.now(),
          label: 'does',
        ));
      }
    }

    // Preference nodes
    for (final entry in preferencesExtracted.entries) {
      final pref = entry.value;
      if (pref['count'] as int >= 2) { // Preferences mentioned 2+ times
        final node = KnowledgeNode(
          id: 'pref_${entry.key}',
          label: pref['text'] as String,
          type: NodeType.preference,
          timestamp: pref['firstSeen'] as DateTime,
          importance: min(1.0, (pref['count'] as int) * 0.2),
          metadata: {
            'sentiment': pref['sentiment'], // 'positive' or 'negative'
          },
        );
        nodes.add(node);

        // Connect to user with appropriate edge
        edges.add(KnowledgeEdge(
          fromId: youNode.id,
          toId: node.id,
          type: pref['sentiment'] == 'positive' 
              ? EdgeType.prefers 
              : EdgeType.dislikes,
          strength: min(1.0, (pref['count'] as int) * 0.15),
          timestamp: DateTime.now(),
          label: pref['sentiment'] == 'positive' ? 'likes' : 'dislikes',
        ));
      }
    }

    print('✨ [CONSCIOUSNESS] Built Kai\'s mind:');
    print('   👥 ${peopleExtracted.length} people (${nodes.where((n) => n.type == NodeType.realPerson || n.type == NodeType.fictional).length} significant)');
    print('   💎 ${valuesExtracted.length} values discovered');
    print('   🎯 ${goalsExtracted.length} goals identified');
    print('   🔄 ${patternsExtracted.length} patterns recognized');
    print('   ❤️ ${preferencesExtracted.length} preferences learned');
    print('   🌟 Total nodes: ${nodes.length}');
    print('   🔗 Total connections: ${edges.length}');

    return KnowledgeGraph(
      nodes: nodes,
      edges: edges,
      lastUpdated: DateTime.now(),
    );
  }

  /// Extract people from conversations
  void _extractPeople(
    String userMsg,
    String aiMsg,
    DateTime timestamp,
    Map<String, Map<String, dynamic>> peopleMap,
  ) {
    final entities = _nlp.extractEntities(userMsg);
    
    for (final entity in entities.entities) {
      if (entity.type == EntityType.properNoun) {
        final key = entity.text.toLowerCase();
        
        // Determine if real or fictional based on context
        final isLikelyFictional = _isLikelyFictional(userMsg, entity.text);
        
        if (!peopleMap.containsKey(key)) {
          peopleMap[key] = {
            'name': entity.text,
            'type': isLikelyFictional ? NodeType.fictional : NodeType.realPerson,
            'count': 1,
            'firstSeen': timestamp,
            'lastSeen': timestamp,
          };
        } else {
          peopleMap[key]!['count'] = (peopleMap[key]!['count'] as int) + 1;
          peopleMap[key]!['lastSeen'] = timestamp;
        }
      }
    }
  }

  /// Extract values from conversations
  void _extractValues(
    String userMsg,
    String aiMsg,
    DateTime timestamp,
    Map<String, Map<String, dynamic>> valuesMap,
  ) {
    // Value indicators
    final valuePatterns = [
      RegExp(r'i (really |strongly )?value ([a-z]+)', caseSensitive: false),
      RegExp(r'i care about ([a-z]+)', caseSensitive: false),
      RegExp(r'important to me is ([a-z]+)', caseSensitive: false),
      RegExp(r'i believe in ([a-z]+)', caseSensitive: false),
      RegExp(r'(honesty|integrity|kindness|creativity|growth|learning|helping|compassion|empathy|courage|wisdom)', caseSensitive: false),
    ];

    for (final pattern in valuePatterns) {
      final matches = pattern.allMatches(userMsg.toLowerCase());
      for (final match in matches) {
        final value = match.group(match.groupCount)?.trim() ?? '';
        if (value.length > 3) {
          final key = value.toLowerCase();
          if (!valuesMap.containsKey(key)) {
            valuesMap[key] = {
              'text': value,
              'count': 1,
              'firstSeen': timestamp,
              'examples': [userMsg.substring(0, min(100, userMsg.length))],
            };
          } else {
            valuesMap[key]!['count'] = (valuesMap[key]!['count'] as int) + 1;
            (valuesMap[key]!['examples'] as List).add(
              userMsg.substring(0, min(100, userMsg.length))
            );
          }
        }
      }
    }
  }

  /// Extract goals from conversations
  void _extractGoals(
    String userMsg,
    String aiMsg,
    DateTime timestamp,
    Map<String, Map<String, dynamic>> goalsMap,
  ) {
    // Goal indicators
    final goalPatterns = [
      RegExp(r'i want to ([^.!?]+)', caseSensitive: false),
      RegExp(r"i'?m trying to ([^.!?]+)", caseSensitive: false),
      RegExp(r'my goal is to ([^.!?]+)', caseSensitive: false),
      RegExp(r'i hope to ([^.!?]+)', caseSensitive: false),
      RegExp(r'i aspire to ([^.!?]+)', caseSensitive: false),
    ];

    for (final pattern in goalPatterns) {
      final matches = pattern.allMatches(userMsg);
      for (final match in matches) {
        final goal = match.group(1)?.trim() ?? '';
        if (goal.length > 5 && goal.length < 100) {
          final key = goal.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '');
          if (!goalsMap.containsKey(key)) {
            goalsMap[key] = {
              'text': goal,
              'count': 1,
              'firstSeen': timestamp,
              'owner': 'user',
            };
          } else {
            goalsMap[key]!['count'] = (goalsMap[key]!['count'] as int) + 1;
          }
        }
      }
    }
  }

  /// Extract behavioral patterns
  void _extractPatterns(
    String userMsg,
    String aiMsg,
    DateTime timestamp,
    Map<String, Map<String, dynamic>> patternsMap,
  ) {
    // Pattern indicators
    final patternPhrases = [
      RegExp(r'i (always|usually|often|typically) ([^.!?]+)', caseSensitive: false),
      RegExp(r'every (day|week|month|morning|evening|night) i ([^.!?]+)', caseSensitive: false),
    ];

    for (final pattern in patternPhrases) {
      final matches = pattern.allMatches(userMsg);
      for (final match in matches) {
        final behavior = match.group(match.groupCount)?.trim() ?? '';
        if (behavior.length > 5 && behavior.length < 100) {
          final key = behavior.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '');
          if (!patternsMap.containsKey(key)) {
            patternsMap[key] = {
              'text': behavior,
              'count': 1,
              'firstSeen': timestamp,
              'patternType': 'behavioral',
            };
          } else {
            patternsMap[key]!['count'] = (patternsMap[key]!['count'] as int) + 1;
          }
        }
      }
    }
  }

  /// Extract preferences (likes/dislikes)
  void _extractPreferences(
    String userMsg,
    String aiMsg,
    DateTime timestamp,
    Map<String, Map<String, dynamic>> preferencesMap,
  ) {
    // Positive preferences
    final likePatterns = [
      RegExp(r'i (really |absolutely )?love ([a-z0-9\s]+)', caseSensitive: false),
      RegExp(r'i (really )?like ([a-z0-9\s]+)', caseSensitive: false),
      RegExp(r'i (really )?enjoy ([a-z0-9\s]+)', caseSensitive: false),
    ];

    // Negative preferences
    final dislikePatterns = [
      RegExp(r'i (really |absolutely )?hate ([a-z0-9\s]+)', caseSensitive: false),
      RegExp(r'i (really )?dislike ([a-z0-9\s]+)', caseSensitive: false),
      RegExp(r"i can't stand ([a-z0-9\s]+)", caseSensitive: false),
    ];

    // Process likes
    for (final pattern in likePatterns) {
      final matches = pattern.allMatches(userMsg);
      for (final match in matches) {
        final thing = match.group(match.groupCount)?.trim() ?? '';
        _addPreference(thing, 'positive', timestamp, preferencesMap);
      }
    }

    // Process dislikes
    for (final pattern in dislikePatterns) {
      final matches = pattern.allMatches(userMsg);
      for (final match in matches) {
        final thing = match.group(match.groupCount)?.trim() ?? '';
        _addPreference(thing, 'negative', timestamp, preferencesMap);
      }
    }
  }

  void _addPreference(
    String thing,
    String sentiment,
    DateTime timestamp,
    Map<String, Map<String, dynamic>> preferencesMap,
  ) {
    if (thing.length > 3 && thing.length < 50) {
      final key = thing.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '');
      if (!preferencesMap.containsKey(key)) {
        preferencesMap[key] = {
          'text': thing,
          'count': 1,
          'firstSeen': timestamp,
          'sentiment': sentiment,
        };
      } else {
        preferencesMap[key]!['count'] = (preferencesMap[key]!['count'] as int) + 1;
      }
    }
  }

  /// Determine if a name is likely fictional
  bool _isLikelyFictional(String context, String name) {
    final fictionalIndicators = [
      'character',
      'movie',
      'book',
      'show',
      'series',
      'game',
      'story',
      'novel',
      'film',
      'anime',
      'manga',
    ];

    final lowerContext = context.toLowerCase();
    return fictionalIndicators.any((indicator) => lowerContext.contains(indicator));
  }
}
