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
      
      // Extract top terms from each conversation - RADICAL: Only top 3 most important
      final importantTerms = <String, Set<int>>{}; // term -> conversation indices
      for (var i = 0; i < convTexts.length; i++) {
        final docKey = 'doc_$i';
        if (tfidf.containsKey(docKey)) {
          final scores = tfidf[docKey]!.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          
          // RADICAL: Only take top 3 MOST important terms, skip if score too low
          for (var j = 0; j < min(3, scores.length); j++) {
            final term = scores[j].key;
            final score = scores[j].value;
            
            // RADICAL: Only include if TF-IDF score is substantial (> 0.15)
            if (score > 0.15) {
              importantTerms[term] ??= {};
              importantTerms[term]!.add(i);
            }
          }
        }
      }

      print('💡 [GRAPH] Found ${importantTerms.length} important terms (TF-IDF > 0.15)');

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

      // 6. Create topic nodes (high-level categories) - RADICAL: Require 3+ conversations
      final topicNodes = <String, KnowledgeNode>{};
      for (final entry in topicClusters.entries) {
        final topic = entry.key;
        final convIndices = entry.value;
        
        // RADICAL: Only create topic if it appears in 3+ conversations
        if (convIndices.length >= 3) {
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
      }

      print('📂 [GRAPH] Created ${topicNodes.length} topic nodes (3+ conversations each)');

      // 7. Create concept nodes from important terms - RADICAL: Require 3+ mentions
      final conceptNodes = <String, KnowledgeNode>{};
      for (final entry in importantTerms.entries) {
        final term = entry.key;
        final convIndices = entry.value;
        
        // RADICAL: Only create concept if mentioned in 3+ conversations with high importance
        if (convIndices.length >= 3) {
          final conceptNode = KnowledgeNode(
            id: 'concept_${term.toLowerCase().replaceAll(' ', '_')}',
            label: term,
            type: NodeType.concept,
            timestamp: DateTime.now(),
            importance: min(1.0, convIndices.length * 0.25), // Higher multiplier for rarity
            metadata: {
              'mentionCount': convIndices.length,
              'conversations': convIndices.toList(),
            },
          );
          conceptNodes[term] = conceptNode;
          nodes.add(conceptNode);
        }
      }

      print('🧠 [GRAPH] Created ${conceptNodes.length} concept nodes (3+ mentions each)');

      // 8. Extract entities and create entity nodes (ONLY for recurring entities)
      final entityCandidates = <String, Map<String, dynamic>>{}; // key -> {node, count, timestamps}
      
      for (var i = 0; i < convData.length; i++) {
        final conv = convData[i];
        final fullText = conv['fullText'] as String;
        final timestamp = DateTime.fromMillisecondsSinceEpoch(conv['timestamp'] as int);

        // Use NLP to extract entities
        final entityResult = nlp.extractEntities(fullText);
        
        // Track entity candidates (we'll only keep recurring ones)
        for (final entity in entityResult.byImportance.take(5)) {
          final key = entity.text.toLowerCase();
          
          if (!entityCandidates.containsKey(key)) {
            final nodeType = entity.type == EntityType.emotion
                ? NodeType.emotion
                : entity.type == EntityType.properNoun
                    ? NodeType.person
                    : NodeType.fact;

            entityCandidates[key] = {
              'text': entity.text,
              'type': nodeType,
              'importance': entity.importance,
              'timestamps': <DateTime>[timestamp],
              'count': 1,
            };
          } else {
            // Increase count and track timestamp
            final existing = entityCandidates[key]!;
            existing['count'] = (existing['count'] as int) + 1;
            (existing['timestamps'] as List<DateTime>).add(timestamp);
            // Update importance based on recurrence
            existing['importance'] = min(1.0, 
              (entity.importance + (existing['importance'] as double)) / 2 + 
              (existing['count'] as int) * 0.1
            );
          }
        }
      }

      // Only create entity nodes for entities mentioned in 2+ conversations OR with very high importance
      final entityNodes = <String, KnowledgeNode>{};
      for (final entry in entityCandidates.entries) {
        final key = entry.key;
        final data = entry.value;
        final count = data['count'] as int;
        final importance = data['importance'] as double;
        
        // RADICAL INTELLIGENCE: Ultra-stringent filtering
        // Filter 1: Must appear 3+ times OR have exceptional importance (> 0.9)
        if (count < 3 && importance <= 0.9) continue;
        
        // Filter 2: If 3 mentions, must have importance > 0.5
        if (count == 3 && importance <= 0.5) continue;
        
        // Filter 3: Single character entities are almost never valid
        if (key.length <= 1) continue;
        
        // Filter 4: Two character entities need very high importance
        if (key.length == 2 && importance < 0.8) continue;
        
        // Filter 5: Three character entities need high importance (likely abbreviations)
        if (key.length == 3 && importance < 0.7) continue;
        
        final timestamps = data['timestamps'] as List<DateTime>;
        final entityNode = KnowledgeNode(
          id: '${data['type'].toString().split('.').last}_${key.replaceAll(' ', '_')}',
          label: data['text'] as String,
          type: data['type'] as NodeType,
          timestamp: timestamps.first,
          importance: importance,
          metadata: {
            'mentionCount': count,
            'firstSeen': timestamps.first.toIso8601String(),
            'lastSeen': timestamps.last.toIso8601String(),
          },
        );
        entityNodes[key] = entityNode;
        nodes.add(entityNode);
      }

      print('👥 [GRAPH] Extracted ${entityNodes.length} high-quality entities (from ${entityCandidates.length} candidates, requiring 3+ mentions)');

      // 8.5. ADVANCED: Semantic deduplication - merge similar entities
      final deduplicated = _deduplicateEntities(entityNodes);
      print('🔗 [GRAPH] Deduplicated to ${deduplicated.length} unique entities');

      // 9. Create relationship edges between concepts based on co-occurrence
      for (final entry in coOccurrences.entries) {
        final term1 = entry.key;
        final relatedTerms = entry.value;
        
        if (conceptNodes.containsKey(term1)) {
          for (final term2 in relatedTerms) {
            if (conceptNodes.containsKey(term2) && term1 != term2) {
              // RADICAL: Calculate relationship strength, only keep strong relationships
              final strength = min(1.0, relatedTerms.length * 0.20);
              
              // RADICAL: Only create edge if relationship is meaningful (strength > 0.3)
              if (strength > 0.3) {
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

      // 11. Link entities to concepts they're mentioned with (use deduplicated entities)
      for (var i = 0; i < convData.length; i++) {
        final conv = convData[i];
        final fullText = conv['fullText'] as String;
        final lowerText = fullText.toLowerCase();
        
        // Find which entities and concepts appear in this conversation
        final convEntities = deduplicated.keys.where((k) => lowerText.contains(k)).toList();
        final convConcepts = conceptNodes.keys.where((k) => lowerText.contains(k.toLowerCase())).toList();
        
        // Link entities to concepts
        for (final entityKey in convEntities) {
          for (final conceptKey in convConcepts) {
            if (deduplicated.containsKey(entityKey) && conceptNodes.containsKey(conceptKey)) {
              edges.add(KnowledgeEdge(
                fromId: deduplicated[entityKey]!.id,
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
      print('   👤 Entities: ${deduplicated.length} (deduplicated from ${entityNodes.length})');
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

  /// ADVANCED: Semantic deduplication - merge similar entities
  /// Uses string similarity to identify and merge related entities
  Map<String, KnowledgeNode> _deduplicateEntities(Map<String, KnowledgeNode> entities) {
    final deduplicated = <String, KnowledgeNode>{};
    final processed = <String>{};
    
    for (final entry in entities.entries) {
      final key = entry.key;
      final node = entry.value;
      
      if (processed.contains(key)) continue;
      
      // Find similar entities
      final similar = <String>[];
      for (final otherKey in entities.keys) {
        if (otherKey == key || processed.contains(otherKey)) continue;
        
        // Check string similarity
        if (_areSimilarStrings(key, otherKey)) {
          similar.add(otherKey);
        }
      }
      
      if (similar.isEmpty) {
        // No duplicates, keep as is
        deduplicated[key] = node;
        processed.add(key);
      } else {
        // Merge similar entities - use longest/most complete name
        var bestKey = key;
        var bestNode = node;
        var maxLength = key.length;
        
        for (final simKey in similar) {
          if (simKey.length > maxLength) {
            bestKey = simKey;
            bestNode = entities[simKey]!;
            maxLength = simKey.length;
          }
          processed.add(simKey);
        }
        
        // Merge metadata
        var totalMentions = bestNode.metadata['mentionCount'] as int? ?? 1;
        for (final simKey in similar) {
          final simNode = entities[simKey]!;
          totalMentions += simNode.metadata['mentionCount'] as int? ?? 1;
        }
        
        bestNode.metadata['mentionCount'] = totalMentions;
        bestNode.metadata['importance'] = min(1.0, totalMentions * 0.15);
        bestNode.metadata['mergedFrom'] = similar;
        
        deduplicated[bestKey] = bestNode;
        processed.add(bestKey);
        processed.add(key);
      }
    }
    
    return deduplicated;
  }

  /// Check if two strings are similar (fuzzy match)
  bool _areSimilarStrings(String a, String b) {
    final lowerA = a.toLowerCase();
    final lowerB = b.toLowerCase();
    
    // Exact match
    if (lowerA == lowerB) return true;
    
    // One contains the other (e.g., "John" and "John Smith")
    if (lowerA.contains(lowerB) || lowerB.contains(lowerA)) return true;
    
    // Similar with minor differences (plurals, possessives, verb forms)
    if ((lowerA == '${lowerB}s') || (lowerB == '${lowerA}s')) return true;
    if ((lowerA == '${lowerB}es') || (lowerB == '${lowerA}es')) return true;
    if ((lowerA == '${lowerB}ing') || (lowerB == '${lowerA}ing')) return true;
    if ((lowerA == '${lowerB}ed') || (lowerB == '${lowerA}ed')) return true;
    if ((lowerA == "${lowerB}'s") || (lowerB == "${lowerA}'s")) return true;
    
    // Remove common articles and check again
    final cleanA = lowerA.replaceAll(RegExp(r'\b(the|a|an)\s+'), '');
    final cleanB = lowerB.replaceAll(RegExp(r'\b(the|a|an)\s+'), '');
    if (cleanA == cleanB) return true;
    
    // Acronym matching (e.g., "AI" matches "Artificial Intelligence")
    if (_isAcronymMatch(lowerA, lowerB)) return true;
    
    // Levenshtein distance for typos/variations
    final distance = _levenshteinDistance(lowerA, lowerB);
    final maxLen = max(lowerA.length, lowerB.length);
    final similarity = 1.0 - (distance / maxLen);
    
    return similarity > 0.85; // 85% similar
  }
  
  /// Check if one string is an acronym of another
  bool _isAcronymMatch(String short, String long) {
    if (short.length >= long.length) return false;
    if (short.length < 2) return false;
    
    final words = long.split(' ');
    if (words.length < 2) return false;
    
    final acronym = words.map((w) => w.isNotEmpty ? w[0] : '').join('');
    return acronym.toLowerCase() == short.toLowerCase();
  }

  /// Calculate Levenshtein distance (edit distance)
  int _levenshteinDistance(String s1, String s2) {
    final len1 = s1.length;
    final len2 = s2.length;
    
    if (len1 == 0) return len2;
    if (len2 == 0) return len1;
    
    final matrix = List.generate(len1 + 1, (_) => List.filled(len2 + 1, 0));
    
    for (var i = 0; i <= len1; i++) matrix[i][0] = i;
    for (var j = 0; j <= len2; j++) matrix[0][j] = j;
    
    for (var i = 1; i <= len1; i++) {
      for (var j = 1; j <= len2; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = min(
          min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
          matrix[i - 1][j - 1] + cost,
        );
      }
    }
    
    return matrix[len1][len2];
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

  /// Cull low-quality, non-sensical nodes from the mind map
  /// Removes nodes with low importance, single mentions, and poor connections
  Future<CullResult> cullLowQualityNodes({
    required String personaId,
    double minImportance = 0.3,
    int minMentions = 1,
    int minConnections = 0,
  }) async {
    print('🗑️ [GRAPH] Starting mind map cull...');
    print('   Filters: importance>=$minImportance, mentions>=$minMentions, connections>=$minConnections');
    
    try {
      // Load current graph
      final graph = await buildGraph(personaId: personaId);
      if (graph.nodes.isEmpty) {
        return CullResult(
          success: true,
          nodesRemoved: 0,
          edgesRemoved: 0,
          message: 'No nodes to cull',
        );
      }

      final originalNodeCount = graph.nodes.length;
      final originalEdgeCount = graph.edges.length;

      // Identify nodes to remove
      final nodesToRemove = <String>{};
      
      for (final node in graph.nodes) {
        var shouldRemove = false;
        final reasons = <String>[];

        // FILTER 1: Importance too low
        if (node.importance < minImportance) {
          shouldRemove = true;
          reasons.add('low importance (${node.importance.toStringAsFixed(2)})');
        }

        // FILTER 2: Mention count too low
        final mentionCount = node.metadata['mentionCount'] as int? ?? 1;
        if (mentionCount < minMentions) {
          shouldRemove = true;
          reasons.add('insufficient mentions ($mentionCount)');
        }

        // FILTER 3: No connections (orphaned node)
        final connections = graph.getNodeEdges(node.id).length;
        if (connections < minConnections) {
          shouldRemove = true;
          reasons.add('no connections');
        }

        // FILTER 4: Node type exceptions (always keep topics)
        if (node.type == NodeType.topic) {
          shouldRemove = false; // Never remove topic nodes
        }

        if (shouldRemove) {
          nodesToRemove.add(node.id);
          print('   ❌ Removing "${node.label}": ${reasons.join(", ")}');
        }
      }

      // Filter nodes and edges
      final culledNodes = graph.nodes.where((n) => !nodesToRemove.contains(n.id)).toList();
      final culledEdges = graph.edges.where((e) => 
        !nodesToRemove.contains(e.fromId) && !nodesToRemove.contains(e.toId)
      ).toList();

      final nodesRemoved = originalNodeCount - culledNodes.length;
      final edgesRemoved = originalEdgeCount - culledEdges.length;

      print('🗑️ [GRAPH] Cull complete: removed $nodesRemoved nodes, $edgesRemoved edges');

      // Save culled graph back to Firebase
      final culledGraph = KnowledgeGraph(
        nodes: culledNodes,
        edges: culledEdges,
        lastUpdated: DateTime.now(),
      );
      
      await _saveGraphToFirebase(personaId, culledGraph);
      
      // Clear cache to force reload
      clearCache();

      return CullResult(
        success: true,
        nodesRemoved: nodesRemoved,
        edgesRemoved: edgesRemoved,
        message: 'Removed $nodesRemoved low-quality nodes',
      );
    } catch (e, stackTrace) {
      print('❌ [GRAPH] Cull error: $e');
      print('❌ [GRAPH] Stack trace: $stackTrace');
      return CullResult(
        success: false,
        nodesRemoved: 0,
        edgesRemoved: 0,
        message: 'Error: $e',
      );
    }
  }
}

/// Result of culling operation
class CullResult {
  final bool success;
  final int nodesRemoved;
  final int edgesRemoved;
  final String message;

  CullResult({
    required this.success,
    required this.nodesRemoved,
    required this.edgesRemoved,
    required this.message,
  });
}
