/// Knowledge Graph Service
/// Builds and manages the knowledge graph from Kai's memories
library;

import 'dart:async';
import 'dart:math';
import '../models/knowledge_node.dart';
import 'firebase_service.dart';

class KnowledgeGraphService {
  static final KnowledgeGraphService _instance = KnowledgeGraphService._internal();
  factory KnowledgeGraphService() => _instance;
  KnowledgeGraphService._internal();

  KnowledgeGraph? _cachedGraph;
  DateTime? _lastBuildTime;
  static const Duration _cacheValidDuration = Duration(minutes: 5);

  /// Build knowledge graph from memories and conversations
  Future<KnowledgeGraph> buildGraph({
    required String personaId,
    bool forceRebuild = false,
  }) async {
    // Return cached graph if still valid
    if (!forceRebuild &&
        _cachedGraph != null &&
        _lastBuildTime != null &&
        DateTime.now().difference(_lastBuildTime!) < _cacheValidDuration) {
      print('📊 [GRAPH] Returning cached graph');
      return _cachedGraph!;
    }

    print('🔨 [GRAPH] Building knowledge graph...');

    final nodes = <KnowledgeNode>[];
    final edges = <KnowledgeEdge>[];

    try {
      // 1. Get recent conversations from Firebase
      final conversations = await FirebaseService.getRecentConversations(
        personaId,
        limit: 50, // Last 50 conversations
      );

      print('📚 [GRAPH] Processing ${conversations.length} conversations');

      // 2. Extract entities from conversations
      final entityMap = <String, KnowledgeNode>{};
      final conversationNodes = <KnowledgeNode>[];

      for (final conv in conversations) {
        final timestamp = DateTime.fromMillisecondsSinceEpoch(
          conv['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        );
        final userMessage = conv['userMessage'] as String? ?? '';
        final aiResponse = conv['aiResponse'] as String? ?? '';
        final convId = conv['id'] as String;

        // Create conversation node
        final convNode = KnowledgeNode(
          id: 'conv_$convId',
          label: _summarizeConversation(userMessage, aiResponse),
          type: NodeType.conversation,
          timestamp: timestamp,
          importance: 0.3,
          metadata: {
            'userMessage': userMessage,
            'aiResponse': aiResponse,
          },
        );
        conversationNodes.add(convNode);

        // Extract entities from both messages
        final entities = _extractEntitiesSimple(userMessage + ' ' + aiResponse, timestamp);

        for (final entity in entities) {
          // Deduplicate entities
          final existingEntity = entityMap[entity.label.toLowerCase()];
          if (existingEntity != null) {
            // Increase importance if mentioned multiple times
            existingEntity.metadata['mentionCount'] = 
              (existingEntity.metadata['mentionCount'] as int? ?? 1) + 1;
            existingEntity.metadata['importance'] = 
              min(1.0, (existingEntity.metadata['mentionCount'] as int) * 0.1);
            
            // Create edge from conversation to entity
            edges.add(KnowledgeEdge(
              fromId: convNode.id,
              toId: existingEntity.id,
              type: EdgeType.mentioned,
              strength: 0.6,
              timestamp: timestamp,
            ));
          } else {
            entityMap[entity.label.toLowerCase()] = entity;
            
            // Create edge from conversation to entity
            edges.add(KnowledgeEdge(
              fromId: convNode.id,
              toId: entity.id,
              type: EdgeType.mentioned,
              strength: 0.6,
              timestamp: timestamp,
            ));
          }
        }
      }

      nodes.addAll(conversationNodes);
      nodes.addAll(entityMap.values);

      // 3. Create similarity-based edges between entities
      _createSimilarityEdges(nodes, edges);

      // 4. Create temporal edges between conversations
      _createTemporalEdges(conversationNodes, edges);

      print('✅ [GRAPH] Built graph: ${nodes.length} nodes, ${edges.length} edges');

      final graph = KnowledgeGraph(
        nodes: nodes,
        edges: edges,
        lastUpdated: DateTime.now(),
      );

      _cachedGraph = graph;
      _lastBuildTime = DateTime.now();

      return graph;
    } catch (e, stackTrace) {
      print('❌ [GRAPH] Build error: $e');
      print('❌ [GRAPH] Stack trace: $stackTrace');

      // Return empty graph on error
      return KnowledgeGraph(
        nodes: [],
        edges: [],
        lastUpdated: DateTime.now(),
      );
    }
  }

  /// Simple entity extraction using pattern matching
  /// TODO: Replace with GPT-based extraction for better accuracy
  List<KnowledgeNode> _extractEntitiesSimple(String text, DateTime timestamp) {
    final entities = <KnowledgeNode>[];
    final words = text.split(RegExp(r'\s+'));

    // Extract capitalized words as potential person/place names
    final capitalized = words.where((w) =>
      w.length > 2 &&
      w[0] == w[0].toUpperCase() &&
      !_isCommonWord(w)
    ).toSet();

    for (final name in capitalized) {
      entities.add(KnowledgeNode(
        id: 'person_${name.toLowerCase()}',
        label: name,
        type: NodeType.person,
        timestamp: timestamp,
        importance: 0.5,
        metadata: {'mentionCount': 1},
      ));
    }

    // Extract emotion keywords
    final emotions = {
      'happy': '😊', 'sad': '😢', 'angry': '😠', 'excited': '🎉',
      'stressed': '😰', 'relaxed': '😌', 'worried': '😟', 'grateful': '🙏',
      'frustrated': '😤', 'proud': '😊', 'anxious': '😰', 'love': '❤️',
    };

    for (final emotion in emotions.keys) {
      if (text.toLowerCase().contains(emotion)) {
        entities.add(KnowledgeNode(
          id: 'emotion_$emotion',
          label: emotion[0].toUpperCase() + emotion.substring(1),
          type: NodeType.emotion,
          timestamp: timestamp,
          importance: 0.6,
          metadata: {'emoji': emotions[emotion]},
        ));
      }
    }

    // Extract common topics
    final topics = {
      'work': '💼', 'family': '👨‍👩‍👧', 'friends': '👥', 'health': '🏥',
      'hobby': '🎨', 'travel': '✈️', 'food': '🍔', 'music': '🎵',
      'movie': '🎬', 'book': '📚', 'game': '🎮', 'sport': '⚽',
      'project': '📊', 'meeting': '📅', 'weekend': '🎉', 'vacation': '🏖️',
    };

    for (final topic in topics.keys) {
      if (text.toLowerCase().contains(topic)) {
        entities.add(KnowledgeNode(
          id: 'topic_$topic',
          label: topic[0].toUpperCase() + topic.substring(1),
          type: NodeType.topic,
          timestamp: timestamp,
          importance: 0.5,
          metadata: {'emoji': topics[topic]},
        ));
      }
    }

    return entities;
  }

  /// Create edges between similar entities
  void _createSimilarityEdges(List<KnowledgeNode> nodes, List<KnowledgeEdge> edges) {
    // Create edges between entities mentioned in close time proximity
    final entityNodes = nodes.where((n) => n.type != NodeType.conversation).toList();
    
    for (var i = 0; i < entityNodes.length; i++) {
      for (var j = i + 1; j < entityNodes.length; j++) {
        final node1 = entityNodes[i];
        final node2 = entityNodes[j];
        
        // If mentioned within 1 hour, they're likely related
        final timeDiff = node1.timestamp.difference(node2.timestamp).abs();
        if (timeDiff.inHours <= 1) {
          edges.add(KnowledgeEdge(
            fromId: node1.id,
            toId: node2.id,
            type: EdgeType.related,
            strength: max(0.3, 1.0 - (timeDiff.inMinutes / 60.0)),
            timestamp: node1.timestamp,
          ));
        }
      }
    }
  }

  /// Create temporal edges between consecutive conversations
  void _createTemporalEdges(List<KnowledgeNode> conversations, List<KnowledgeEdge> edges) {
    // Sort by timestamp
    conversations.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    
    for (var i = 0; i < conversations.length - 1; i++) {
      edges.add(KnowledgeEdge(
        fromId: conversations[i].id,
        toId: conversations[i + 1].id,
        type: EdgeType.temporal,
        strength: 0.2,
        timestamp: conversations[i + 1].timestamp,
        label: 'then',
      ));
    }
  }

  /// Summarize conversation for node label
  String _summarizeConversation(String userMsg, String aiResponse) {
    final msg = userMsg.trim();
    if (msg.length <= 30) return msg;
    return '${msg.substring(0, 27)}...';
  }

  /// Check if word is a common word (not an entity)
  bool _isCommonWord(String word) {
    final common = {
      'The', 'This', 'That', 'What', 'When', 'Where', 'How', 'Why',
      'Can', 'Could', 'Would', 'Should', 'Will', 'I', 'You', 'We',
      'They', 'He', 'She', 'It', 'And', 'But', 'Or', 'So', 'Because',
    };
    return common.contains(word);
  }

  /// Clear cache
  void clearCache() {
    _cachedGraph = null;
    _lastBuildTime = null;
    print('🗑️ [GRAPH] Cache cleared');
  }
}
