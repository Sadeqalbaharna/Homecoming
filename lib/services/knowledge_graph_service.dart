/// Knowledge Graph Service
/// Builds and manages the knowledge graph from Kai's memories
library;

import 'dart:async';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import '../models/knowledge_node.dart';
import 'firebase_service.dart';
import 'graph_archive_service.dart';

class KnowledgeGraphService {
  static final KnowledgeGraphService _instance = KnowledgeGraphService._internal();
  factory KnowledgeGraphService() => _instance;
  KnowledgeGraphService._internal();

  KnowledgeGraph? _cachedGraph;
  DateTime? _lastBuildTime;
  static const Duration _cacheValidDuration = Duration(minutes: 5);
  
  final GraphArchiveService _archiveService = GraphArchiveService();

  /// Build knowledge graph from memories and conversations
  /// First tries to load from Firebase, then builds from conversations if needed
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

    // Try to load from Firebase first
    if (!forceRebuild && FirebaseService.isAvailable) {
      final savedGraph = await _loadGraphFromFirebase(personaId);
      if (savedGraph != null && savedGraph.nodes.isNotEmpty) {
        print('✅ [GRAPH] Loaded ${savedGraph.nodes.length} nodes from Firebase');
        _cachedGraph = savedGraph;
        _lastBuildTime = DateTime.now();
        return savedGraph;
      }
    }

    // Build from conversations if no saved graph
    final graph = await _buildGraphFromConversations(personaId);
    
    // Save to Firebase for next time
    if (FirebaseService.isAvailable) {
      await _saveGraphToFirebase(personaId, graph);
    }
    
    _cachedGraph = graph;
    _lastBuildTime = DateTime.now();
    
    return graph;
  }
  
  /// Build graph from conversations (used when no saved graph exists)
  Future<KnowledgeGraph> _buildGraphFromConversations(String personaId) async {

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
  
  /// Save knowledge graph to Firebase
  Future<void> _saveGraphToFirebase(String personaId, KnowledgeGraph graph) async {
    if (!FirebaseService.isAvailable) return;
    
    try {
      print('💾 [GRAPH] Saving graph to Firebase...');
      
      final ref = FirebaseDatabase.instance.ref('knowledge_graph/$personaId');
      
      // Serialize graph
      final data = {
        'nodes': graph.nodes.map((n) => {
          'id': n.id,
          'label': n.label,
          'type': n.type.toString().split('.').last,
          'timestamp': n.timestamp.millisecondsSinceEpoch,
          'importance': n.importance,
          'metadata': n.metadata,
          'x': n.x,
          'y': n.y,
        }).toList(),
        'edges': graph.edges.map((e) => {
          'fromId': e.fromId,
          'toId': e.toId,
          'type': e.type.toString().split('.').last,
          'strength': e.strength,
          'timestamp': e.timestamp.millisecondsSinceEpoch,
          if (e.label != null) 'label': e.label,
        }).toList(),
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      };
      
      await ref.set(data);
      print('✅ [GRAPH] Saved ${graph.nodes.length} nodes, ${graph.edges.length} edges to Firebase');
    } catch (e) {
      print('❌ [GRAPH] Failed to save to Firebase: $e');
    }
  }
  
  /// Load knowledge graph from Firebase
  Future<KnowledgeGraph?> _loadGraphFromFirebase(String personaId) async {
    if (!FirebaseService.isAvailable) return null;
    
    try {
      print('📥 [GRAPH] Loading graph from Firebase...');
      
      final ref = FirebaseDatabase.instance.ref('knowledge_graph/$personaId');
      final snapshot = await ref.get();
      
      if (!snapshot.exists) {
        print('ℹ️ [GRAPH] No saved graph found in Firebase');
        return null;
      }
      
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      
      // Deserialize nodes
      final nodes = <KnowledgeNode>[];
      final nodesData = data['nodes'] as List? ?? [];
      
      for (final nodeData in nodesData) {
        final n = Map<String, dynamic>.from(nodeData as Map);
        
        // Parse node type
        NodeType type;
        try {
          type = NodeType.values.firstWhere(
            (t) => t.toString().split('.').last == n['type'],
            orElse: () => NodeType.fact,
          );
        } catch (e) {
          type = NodeType.fact;
        }
        
        nodes.add(KnowledgeNode(
          id: n['id'] as String,
          label: n['label'] as String,
          type: type,
          timestamp: DateTime.fromMillisecondsSinceEpoch(n['timestamp'] as int),
          importance: (n['importance'] as num?)?.toDouble() ?? 0.5,
          metadata: Map<String, dynamic>.from(n['metadata'] as Map? ?? {}),
        )
          ..x = (n['x'] as num?)?.toDouble() ?? 0
          ..y = (n['y'] as num?)?.toDouble() ?? 0);
      }
      
      // Deserialize edges
      final edges = <KnowledgeEdge>[];
      final edgesData = data['edges'] as List? ?? [];
      
      for (final edgeData in edgesData) {
        final e = Map<String, dynamic>.from(edgeData as Map);
        
        // Parse edge type
        EdgeType type;
        try {
          type = EdgeType.values.firstWhere(
            (t) => t.toString().split('.').last == e['type'],
            orElse: () => EdgeType.related,
          );
        } catch (ex) {
          type = EdgeType.related;
        }
        
        edges.add(KnowledgeEdge(
          fromId: e['fromId'] as String,
          toId: e['toId'] as String,
          type: type,
          strength: (e['strength'] as num?)?.toDouble() ?? 0.5,
          timestamp: DateTime.fromMillisecondsSinceEpoch(e['timestamp'] as int),
          label: e['label'] as String?,
        ));
      }
      
      print('✅ [GRAPH] Loaded ${nodes.length} nodes, ${edges.length} edges from Firebase');
      
      final lastUpdated = data['lastUpdated'] as int?;
      return KnowledgeGraph(
        nodes: nodes,
        edges: edges,
        lastUpdated: lastUpdated != null 
          ? DateTime.fromMillisecondsSinceEpoch(lastUpdated)
          : DateTime.now(),
      );
    } catch (e) {
      print('❌ [GRAPH] Failed to load from Firebase: $e');
      return null;
    }
  }
  
  /// Archive unprocessed conversations to the graph
  /// This ensures all Firebase data is visualized
  Future<ArchiveResult> archiveUnprocessedData({
    required String personaId,
  }) async {
    print('🔄 [GRAPH] Triggering archive process...');
    final result = await _archiveService.archiveUnprocessedData(
      personaId: personaId,
    );
    
    if (result.success) {
      // Clear cache to force rebuild with new data
      clearCache();
      print('✅ [GRAPH] Archived ${result.conversationsArchived} conversations');
      print('📊 [GRAPH] Created ${result.nodesCreated} nodes, ${result.edgesCreated} edges');
    }
    
    return result;
  }
  
  /// Get archive statistics
  Future<ArchiveStats> getArchiveStats(String personaId) async {
    return await _archiveService.getArchiveStats(personaId);
  }
  
  /// Schedule automatic archiving (call on app start)
  void scheduleAutoArchive(String personaId) {
    _archiveService.scheduleAutoArchive(personaId);
    print('⏰ [GRAPH] Auto-archive scheduled (every 6 hours)');
  }
}
