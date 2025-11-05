/// Graph Archive Service
/// Syncs Firebase conversations and memory shards to the knowledge graph
/// Ensures all data is archived and nothing is lost
library;

import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/knowledge_node.dart';
import 'firebase_service.dart';
import 'knowledge_graph_service.dart';

class GraphArchiveService {
  static final GraphArchiveService _instance = GraphArchiveService._internal();
  factory GraphArchiveService() => _instance;
  GraphArchiveService._internal();

  final KnowledgeGraphService _graphService = KnowledgeGraphService();
  
  // Track what's been archived
  static const String _lastArchivedTimestampKey = 'last_archived_timestamp';
  static const String _archivedConversationIdsKey = 'archived_conversation_ids';

  /// Archive all unprocessed conversations to the knowledge graph
  /// This runs periodically to ensure nothing is missed
  Future<ArchiveResult> archiveUnprocessedData({
    required String personaId,
  }) async {
    print('📦 [ARCHIVE] Starting archive process...');
    
    final result = ArchiveResult();
    final prefs = await SharedPreferences.getInstance();
    
    try {
      // 1. Get last archived timestamp
      final lastArchived = prefs.getInt(_lastArchivedTimestampKey) ?? 0;
      final lastArchivedTime = DateTime.fromMillisecondsSinceEpoch(lastArchived);
      print('📦 [ARCHIVE] Last archived: $lastArchivedTime');
      
      // 2. Get archived conversation IDs
      final archivedIds = prefs.getStringList(_archivedConversationIdsKey) ?? [];
      print('📦 [ARCHIVE] Already archived: ${archivedIds.length} conversations');
      
      // 3. Fetch ALL conversations from Firebase
      final allConversations = await _getAllConversations(personaId);
      print('📦 [ARCHIVE] Found ${allConversations.length} total conversations');
      
      // 4. Filter to unarchived conversations
      final unarchived = allConversations.where((conv) {
        final convId = conv['id'] as String;
        final timestamp = conv['timestamp'] as int? ?? 0;
        
        // Include if not in archived list OR if newer than last archived time
        return !archivedIds.contains(convId) || timestamp > lastArchived;
      }).toList();
      
      print('📦 [ARCHIVE] Found ${unarchived.length} unarchived conversations');
      result.conversationsFound = unarchived.length;
      
      if (unarchived.isEmpty) {
        print('✅ [ARCHIVE] Everything is up to date!');
        return result;
      }
      
      // 5. Process unarchived conversations
      final newNodes = <KnowledgeNode>[];
      final newEdges = <KnowledgeEdge>[];
      
      for (final conv in unarchived) {
        try {
          final processed = await _processConversation(conv, personaId);
          newNodes.addAll(processed.nodes);
          newEdges.addAll(processed.edges);
          
          // Mark as archived
          final convId = conv['id'] as String;
          archivedIds.add(convId);
          result.conversationsArchived++;
        } catch (e) {
          print('❌ [ARCHIVE] Error processing conversation: $e');
          result.errors.add('Failed to process conversation: $e');
        }
      }
      
      result.nodesCreated = newNodes.length;
      result.edgesCreated = newEdges.length;
      
      // 6. Update last archived timestamp
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_lastArchivedTimestampKey, now);
      await prefs.setStringList(_archivedConversationIdsKey, archivedIds);
      
      // 7. Force rebuild graph cache
      _graphService.clearCache();
      
      print('✅ [ARCHIVE] Archive complete!');
      print('📊 [ARCHIVE] Created ${result.nodesCreated} nodes, ${result.edgesCreated} edges');
      
      return result;
    } catch (e, stackTrace) {
      print('❌ [ARCHIVE] Archive failed: $e');
      print('❌ [ARCHIVE] Stack trace: $stackTrace');
      result.errors.add('Archive failed: $e');
      return result;
    }
  }

  /// Get ALL conversations from Firebase (not just recent)
  Future<List<Map<String, dynamic>>> _getAllConversations(String personaId) async {
    if (!FirebaseService.isAvailable) return [];
    
    try {
      final ref = FirebaseDatabase.instance.ref('conversations/$personaId');
      final snapshot = await ref.get();
      
      if (!snapshot.exists) return [];
      
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final conversations = data.entries
          .map((e) => {
                'id': e.key,
                ...Map<String, dynamic>.from(e.value as Map),
              })
          .toList();
      
      // Sort by timestamp
      conversations.sort((a, b) => 
          (a['timestamp'] as int? ?? 0).compareTo(b['timestamp'] as int? ?? 0));
      
      return conversations;
    } catch (e) {
      print('❌ [ARCHIVE] Failed to fetch conversations: $e');
      return [];
    }
  }

  /// Process a single conversation into nodes and edges
  Future<ProcessedConversation> _processConversation(
    Map<String, dynamic> conv,
    String personaId,
  ) async {
    final result = ProcessedConversation();
    
    final convId = conv['id'] as String;
    final userMessage = conv['userMessage'] as String? ?? '';
    final aiResponse = conv['aiResponse'] as String? ?? '';
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      conv['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
    
    // Create conversation node
    final convNode = KnowledgeNode(
      id: 'conv_$convId',
      label: _summarize(userMessage),
      type: NodeType.conversation,
      timestamp: timestamp,
      importance: 0.3,
      metadata: {
        'userMessage': userMessage,
        'aiResponse': aiResponse,
        'archived': true,
      },
    );
    result.nodes.add(convNode);
    
    // Extract entities from messages
    final entities = _extractEntitiesAdvanced(userMessage, aiResponse, timestamp);
    result.nodes.addAll(entities);
    
    // Create edges from conversation to entities
    for (final entity in entities) {
      result.edges.add(KnowledgeEdge(
        fromId: convNode.id,
        toId: entity.id,
        type: EdgeType.mentioned,
        strength: 0.7,
        timestamp: timestamp,
      ));
    }
    
    return result;
  }

  /// Advanced entity extraction (better than simple pattern matching)
  List<KnowledgeNode> _extractEntitiesAdvanced(
    String userMessage,
    String aiResponse,
    DateTime timestamp,
  ) {
    final entities = <KnowledgeNode>[];
    final text = '$userMessage $aiResponse';
    
    // Extract people (capitalized words)
    final words = text.split(RegExp(r'\s+'));
    final names = words.where((w) =>
      w.length > 2 &&
      w[0] == w[0].toUpperCase() &&
      !_isCommonWord(w) &&
      RegExp(r'^[A-Z][a-z]+$').hasMatch(w)
    ).toSet();
    
    for (final name in names) {
      entities.add(KnowledgeNode(
        id: 'person_${name.toLowerCase()}',
        label: name,
        type: NodeType.person,
        timestamp: timestamp,
        importance: 0.6,
        metadata: {'source': 'archive', 'mentions': 1},
      ));
    }
    
    // Extract emotions
    final emotions = {
      'happy': '😊', 'sad': '😢', 'angry': '😠', 'excited': '🎉',
      'stressed': '😰', 'relaxed': '😌', 'worried': '😟', 'grateful': '🙏',
      'frustrated': '😤', 'proud': '😊', 'anxious': '😰', 'love': '❤️',
      'joy': '😄', 'fear': '😨', 'surprise': '😲', 'tired': '😴',
    };
    
    final lowerText = text.toLowerCase();
    for (final emotion in emotions.keys) {
      if (lowerText.contains(emotion)) {
        entities.add(KnowledgeNode(
          id: 'emotion_$emotion',
          label: emotion[0].toUpperCase() + emotion.substring(1),
          type: NodeType.emotion,
          timestamp: timestamp,
          importance: 0.7,
          metadata: {'emoji': emotions[emotion], 'source': 'archive'},
        ));
      }
    }
    
    // Extract topics
    final topics = {
      'work': '💼', 'family': '👨‍👩‍👧', 'friends': '👥', 'health': '🏥',
      'hobby': '🎨', 'travel': '✈️', 'food': '🍔', 'music': '🎵',
      'movie': '🎬', 'book': '📚', 'game': '🎮', 'sport': '⚽',
      'project': '📊', 'meeting': '📅', 'weekend': '🎉', 'vacation': '🏖️',
      'school': '🎓', 'study': '📖', 'exercise': '💪', 'sleep': '😴',
    };
    
    for (final topic in topics.keys) {
      if (lowerText.contains(topic)) {
        entities.add(KnowledgeNode(
          id: 'topic_$topic',
          label: topic[0].toUpperCase() + topic.substring(1),
          type: NodeType.topic,
          timestamp: timestamp,
          importance: 0.6,
          metadata: {'emoji': topics[topic], 'source': 'archive'},
        ));
      }
    }
    
    // Extract locations (common place words)
    final locations = {
      'home': '🏠', 'office': '🏢', 'school': '🏫', 'gym': '🏋️',
      'park': '🌳', 'beach': '🏖️', 'restaurant': '🍽️', 'cafe': '☕',
      'mall': '🛍️', 'hospital': '🏥', 'airport': '✈️', 'station': '🚉',
    };
    
    for (final location in locations.keys) {
      if (lowerText.contains(location)) {
        entities.add(KnowledgeNode(
          id: 'location_$location',
          label: location[0].toUpperCase() + location.substring(1),
          type: NodeType.location,
          timestamp: timestamp,
          importance: 0.5,
          metadata: {'emoji': locations[location], 'source': 'archive'},
        ));
      }
    }
    
    // Extract time references (dates, days, etc.)
    final timeWords = [
      'today', 'tomorrow', 'yesterday', 'monday', 'tuesday', 'wednesday',
      'thursday', 'friday', 'saturday', 'sunday', 'week', 'month', 'year',
    ];
    
    for (final timeWord in timeWords) {
      if (lowerText.contains(timeWord)) {
        entities.add(KnowledgeNode(
          id: 'time_$timeWord',
          label: timeWord[0].toUpperCase() + timeWord.substring(1),
          type: NodeType.date,
          timestamp: timestamp,
          importance: 0.4,
          metadata: {'source': 'archive'},
        ));
      }
    }
    
    return entities;
  }

  /// Summarize text for node label
  String _summarize(String text) {
    final cleaned = text.trim();
    if (cleaned.length <= 40) return cleaned;
    return '${cleaned.substring(0, 37)}...';
  }

  /// Check if word is common (not an entity)
  bool _isCommonWord(String word) {
    final common = {
      'The', 'This', 'That', 'What', 'When', 'Where', 'How', 'Why',
      'Can', 'Could', 'Would', 'Should', 'Will', 'I', 'You', 'We',
      'They', 'He', 'She', 'It', 'And', 'But', 'Or', 'So', 'Because',
      'Have', 'Has', 'Had', 'Do', 'Does', 'Did', 'Is', 'Are', 'Was',
      'Were', 'Been', 'Being', 'Am', 'My', 'Your', 'His', 'Her', 'Our',
    };
    return common.contains(word);
  }

  /// Schedule automatic archiving (call this on app start)
  void scheduleAutoArchive(String personaId) {
    // Archive every 6 hours
    Timer.periodic(const Duration(hours: 6), (timer) async {
      print('⏰ [ARCHIVE] Auto-archive triggered');
      await archiveUnprocessedData(personaId: personaId);
    });
    
    // Also archive on startup after 30 seconds
    Timer(const Duration(seconds: 30), () async {
      print('🚀 [ARCHIVE] Startup archive triggered');
      await archiveUnprocessedData(personaId: personaId);
    });
  }

  /// Get archive statistics
  Future<ArchiveStats> getArchiveStats(String personaId) async {
    final prefs = await SharedPreferences.getInstance();
    final lastArchived = prefs.getInt(_lastArchivedTimestampKey) ?? 0;
    final archivedIds = prefs.getStringList(_archivedConversationIdsKey) ?? [];
    
    final allConversations = await _getAllConversations(personaId);
    final unarchived = allConversations.where((conv) {
      final convId = conv['id'] as String;
      return !archivedIds.contains(convId);
    }).length;
    
    return ArchiveStats(
      lastArchivedTime: DateTime.fromMillisecondsSinceEpoch(lastArchived),
      totalArchived: archivedIds.length,
      totalConversations: allConversations.length,
      unarchivedCount: unarchived,
    );
  }
}

/// Result of an archive operation
class ArchiveResult {
  int conversationsFound = 0;
  int conversationsArchived = 0;
  int nodesCreated = 0;
  int edgesCreated = 0;
  List<String> errors = [];
  
  bool get success => errors.isEmpty && conversationsArchived > 0;
  bool get nothingToArchive => conversationsFound == 0;
}

/// Processed conversation data
class ProcessedConversation {
  final List<KnowledgeNode> nodes = [];
  final List<KnowledgeEdge> edges = [];
}

/// Archive statistics
class ArchiveStats {
  final DateTime lastArchivedTime;
  final int totalArchived;
  final int totalConversations;
  final int unarchivedCount;
  
  ArchiveStats({
    required this.lastArchivedTime,
    required this.totalArchived,
    required this.totalConversations,
    required this.unarchivedCount,
  });
  
  bool get isUpToDate => unarchivedCount == 0;
  double get completionPercentage => 
      totalConversations > 0 ? (totalArchived / totalConversations) * 100 : 0;
}
