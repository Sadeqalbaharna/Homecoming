/// Knowledge Graph Service
/// Builds and manages the knowledge graph from Kai's memories
library;

import 'dart:async';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import '../models/knowledge_node.dart';
import 'firebase_service.dart';
import 'graph_archive_service.dart';
import 'local_nlp_service.dart';

class KnowledgeGraphService {
  static final KnowledgeGraphService _instance = KnowledgeGraphService._internal();
  factory KnowledgeGraphService() => _instance;
  KnowledgeGraphService._internal();

  KnowledgeGraph? _cachedGraph;
  DateTime? _lastBuildTime;
  static const Duration _cacheValidDuration = Duration(minutes: 5);
  
  // Use lazy getter to avoid circular dependency
  GraphArchiveService get _archiveService => GraphArchiveService();

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
  
  /// Build graph from conversations using intelligent local NLP (ZERO API CALLS!)
  Future<KnowledgeGraph> _buildGraphFromConversations(String personaId) async {
    final nlp = LocalNLPService();
    final nodes = <KnowledgeNode>[];
    final edges = <KnowledgeEdge>[];

    try {
      // 1. Get recent conversations from Firebase
      final conversations = await FirebaseService.getRecentConversations(
        personaId,
        limit: 100, // Increased for better analysis
      );

      print('📚 [GRAPH] Processing ${conversations.length} conversations with intelligent NLP');

      if (conversations.isEmpty) {
        return KnowledgeGraph(nodes: [], edges: [], lastUpdated: DateTime.now());
      }

      // 2. Prepare conversation texts for batch NLP analysis
      final convTexts = <String>[];
      final convData = <Map<String, dynamic>>[];
      
      for (final conv in conversations) {
        final userMsg = conv['userMessage'] as String? ?? '';
        final aiMsg = conv['aiResponse'] as String? ?? '';
        final fullText = '$userMsg $aiMsg';
        convTexts.add(fullText);
        convData.add({
          'id': conv['id'] as String,
          'timestamp': conv['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
          'userMessage': userMsg,
          'aiResponse': aiMsg,
          'fullText': fullText,
        });
      }

      // 3. Calculate TF-IDF to find important terms across ALL conversations
      print('🔍 [GRAPH] Running TF-IDF analysis...');
      final tfidf = nlp.calculateTFIDF(convTexts);
      
      // Extract top terms from each conversation
      final importantTerms = <String, Set<int>>{}; // term -> conversation indices
      for (var i = 0; i < convTexts.length; i++) {
        final docKey = 'doc_$i';
        if (tfidf.containsKey(docKey)) {
          final scores = tfidf[docKey]!.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          
          // Take top 5 most important terms from each conversation
          for (var j = 0; j < min(5, scores.length); j++) {
            final term = scores[j].key;
            importantTerms[term] ??= {};
            importantTerms[term]!.add(i);
          }
        }
      }

      print('💡 [GRAPH] Found ${importantTerms.length} important terms');

      // 4. Find co-occurring terms to establish relationships
      print('🔗 [GRAPH] Analyzing term relationships...');
      final coOccurrences = nlp.findCoOccurrences(convTexts, windowSize: 10);

      // 5. Create topic clusters by analyzing all conversations
      final topicClusters = <String, List<int>>{}; // topic -> conversation indices
      for (var i = 0; i < convTexts.length; i++) {
        final topicAnalysis = nlp.analyzeTopics(convTexts[i]);
        if (topicAnalysis.primaryTopic != null) {
          final topic = topicAnalysis.primaryTopic!;
          topicClusters[topic] ??= [];
          topicClusters[topic]!.add(i);
        }
      }

      print('📂 [GRAPH] Identified ${topicClusters.length} topic clusters');

      // 6. Create topic nodes (high-level categories)
      final topicNodes = <String, KnowledgeNode>{};
      for (final entry in topicClusters.entries) {
        final topic = entry.key;
        final convIndices = entry.value;
        
        final topicNode = KnowledgeNode(
          id: 'topic_$topic',
          label: topic[0].toUpperCase() + topic.substring(1),
          type: NodeType.topic,
          timestamp: DateTime.now(),
          importance: min(1.0, convIndices.length * 0.15),
          metadata: {
            'conversationCount': convIndices.length,
            'emoji': _getTopicEmoji(topic),
          },
        );
        topicNodes[topic] = topicNode;
        nodes.add(topicNode);
      }

      // 7. Create concept nodes from important terms (mentioned multiple times)
      final conceptNodes = <String, KnowledgeNode>{};
      for (final entry in importantTerms.entries) {
        final term = entry.key;
        final convIndices = entry.value;
        
        // Only create concept nodes for terms mentioned in 2+ conversations
        if (convIndices.length >= 2) {
          final conceptNode = KnowledgeNode(
            id: 'concept_${term.toLowerCase().replaceAll(' ', '_')}',
            label: term,
            type: NodeType.concept,
            timestamp: DateTime.now(),
            importance: min(1.0, convIndices.length * 0.2),
            metadata: {
              'mentionCount': convIndices.length,
              'conversations': convIndices.toList(),
            },
          );
          conceptNodes[term] = conceptNode;
          nodes.add(conceptNode);
        }
      }

      print('🧠 [GRAPH] Created ${conceptNodes.length} concept nodes');

      // 8. Extract entities and create entity nodes
      final entityNodes = <String, KnowledgeNode>{};
      
      for (var i = 0; i < convData.length; i++) {
        final conv = convData[i];
        final fullText = conv['fullText'] as String;
        final timestamp = DateTime.fromMillisecondsSinceEpoch(conv['timestamp'] as int);

        // Use NLP to extract entities
        final entityResult = nlp.extractEntities(fullText);
        
        // Create entity nodes from top entities
        for (final entity in entityResult.byImportance.take(3)) {
          final key = entity.text.toLowerCase();
          
          if (!entityNodes.containsKey(key)) {
            final nodeType = entity.type == EntityType.emotion
                ? NodeType.emotion
                : entity.type == EntityType.properNoun
                    ? NodeType.person
                    : NodeType.fact;

            final entityNode = KnowledgeNode(
              id: '${nodeType.toString().split('.').last}_${key.replaceAll(' ', '_')}',
              label: entity.text,
              type: nodeType,
              timestamp: timestamp,
              importance: entity.importance,
              metadata: {'mentionCount': 1, 'firstSeen': timestamp.toIso8601String()},
            );
            entityNodes[key] = entityNode;
            nodes.add(entityNode);
          } else {
            // Increase mention count for existing entity
            final existing = entityNodes[key]!;
            existing.metadata['mentionCount'] = 
              (existing.metadata['mentionCount'] as int? ?? 1) + 1;
            existing.metadata['importance'] = 
              min(1.0, (existing.metadata['mentionCount'] as int) * 0.15);
          }
        }
      }

      print('👥 [GRAPH] Extracted ${entityNodes.length} entities');

      // 9. Create relationship edges between concepts based on co-occurrence
      for (final entry in coOccurrences.entries) {
        final term1 = entry.key;
        final relatedTerms = entry.value;
        
        if (conceptNodes.containsKey(term1)) {
          for (final term2 in relatedTerms) {
            if (conceptNodes.containsKey(term2) && term1 != term2) {
              // Calculate relationship strength based on frequency
              final strength = min(1.0, relatedTerms.length * 0.15);
              
              edges.add(KnowledgeEdge(
                fromId: conceptNodes[term1]!.id,
                toId: conceptNodes[term2]!.id,
                type: EdgeType.related,
                strength: strength,
                timestamp: DateTime.now(),
              ));
            }
          }
        }
      }

      // 10. Link concepts to their topics
      for (final conceptEntry in conceptNodes.entries) {
        final conceptTerm = conceptEntry.key;
        final conceptNode = conceptEntry.value;
        final convIndices = importantTerms[conceptTerm]!;
        
        // Find which topics this concept belongs to
        final conceptTopics = <String>{};
        for (final idx in convIndices) {
          for (final topicEntry in topicClusters.entries) {
            if (topicEntry.value.contains(idx)) {
              conceptTopics.add(topicEntry.key);
            }
          }
        }
        
        // Create edges to all related topics
        for (final topic in conceptTopics) {
          if (topicNodes.containsKey(topic)) {
            edges.add(KnowledgeEdge(
              fromId: conceptNode.id,
              toId: topicNodes[topic]!.id,
              type: EdgeType.categorized,
              strength: 0.7,
              timestamp: DateTime.now(),
            ));
          }
        }
      }

      // 11. Link entities to concepts they're mentioned with
      for (var i = 0; i < convData.length; i++) {
        final conv = convData[i];
        final fullText = conv['fullText'] as String;
        final lowerText = fullText.toLowerCase();
        
        // Find which entities and concepts appear in this conversation
        final convEntities = entityNodes.keys.where((k) => lowerText.contains(k)).toList();
        final convConcepts = conceptNodes.keys.where((k) => lowerText.contains(k.toLowerCase())).toList();
        
        // Link entities to concepts
        for (final entityKey in convEntities) {
          for (final conceptKey in convConcepts) {
            if (entityNodes.containsKey(entityKey) && conceptNodes.containsKey(conceptKey)) {
              edges.add(KnowledgeEdge(
                fromId: entityNodes[entityKey]!.id,
                toId: conceptNodes[conceptKey]!.id,
                type: EdgeType.mentioned,
                strength: 0.5,
                timestamp: DateTime.now(),
              ));
            }
          }
        }
      }

      print('✅ [GRAPH] Built intelligent graph: ${nodes.length} nodes, ${edges.length} edges');
      print('   📊 Topics: ${topicNodes.length}');
      print('   💡 Concepts: ${conceptNodes.length}');
      print('   👤 Entities: ${entityNodes.length}');
      print('   🔗 Relationships: ${edges.length}');

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

  String _getTopicEmoji(String topic) {
    const emojis = {
      'work': '💼',
      'family': '👨‍👩‍👧',
      'health': '🏥',
      'relationships': '❤️',
      'hobbies': '🎨',
      'technology': '💻',
      'food': '🍔',
      'finance': '💰',
      'education': '📚',
    };
    return emojis[topic] ?? '📌';
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
