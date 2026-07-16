/// Knowledge Graph Node - Represents entities in Kai's memory
library;

import 'dart:math' show exp;
import 'package:flutter/material.dart';

enum NodeType {
  // === EXISTING: Basic extraction ===
  person,       // Generic people mentioned
  topic,        // Topics discussed (blue)
  event,        // Specific events/plans (green)
  emotion,      // Emotional moments (pink)
  location,     // Places mentioned (yellow)
  date,         // Important dates (purple)
  fact,         // Extracted facts (cyan)
  conversation, // Conversation sessions (white)
  concept,      // Important concepts/terms (orange)
  
  // === NEW: Kai's Consciousness ===
  // People - Enhanced categorization
  you,          // The user (central node - most important)
  realPerson,   // Real people in user's life
  fictional,    // Fictional characters discussed
  historical,   // Historical figures mentioned
  
  // Kai's Mind
  value,        // What Kai learns to care about
  goal,         // Kai's aspirations and objectives
  belief,       // Kai's understanding of truth
  principle,    // Guiding principles Kai develops
  
  // Dynamics & Learning
  pattern,      // Recurring behaviors Kai notices
  insight,      // Realizations and epiphanies
  question,     // Things Kai wants to learn
  memory,       // Important moments worth remembering
  skill,        // Capabilities Kai is developing
  
  // Relationships
  preference,   // User's likes/dislikes
  habit,        // User's regular behaviors
  aspiration,   // User's goals and dreams
}

class KnowledgeNode {
  final String id;
  final String label;
  final NodeType type;
  final DateTime timestamp;
  final List<String> tags;
  final double importance; // 0-1, affects node size
  final Map<String, dynamic> metadata;
  
  // Neuromorphic fields (Phase 1 enhancement)
  double emotionalIntensity;  // 0-1, how emotionally charged
  int accessCount;             // How many times recalled
  double retention;            // 0-1, forgetting curve value
  DateTime? lastAccessed;      // When last recalled
  double activationLevel;      // 0-1, current activation (spreading)
  
  // Visual properties (will be computed)
  double x = 0.0;
  double y = 0.0;
  double vx = 0.0; // Velocity for force simulation
  double vy = 0.0;
  
  KnowledgeNode({
    required this.id,
    required this.label,
    required this.type,
    required this.timestamp,
    this.tags = const [],
    this.importance = 0.5,
    this.metadata = const {},
    this.emotionalIntensity = 0.0,
    this.accessCount = 0,
    this.retention = 1.0,
    this.lastAccessed,
    this.activationLevel = 0.0,
  });
  
  /// Get color based on node type
  Color get color {
    switch (type) {
      // Basic types
      case NodeType.person:
        return Colors.red.shade400;
      case NodeType.topic:
        return Colors.blue.shade400;
      case NodeType.event:
        return Colors.green.shade400;
      case NodeType.emotion:
        return Colors.pink.shade400;
      case NodeType.location:
        return Colors.amber.shade400;
      case NodeType.date:
        return Colors.purple.shade400;
      case NodeType.fact:
        return Colors.cyan.shade400;
      case NodeType.conversation:
        return Colors.white70;
      case NodeType.concept:
        return Colors.orange.shade400;
      
      // People - Enhanced
      case NodeType.you:
        return Colors.deepPurple.shade300; // Special! The user
      case NodeType.realPerson:
        return Colors.red.shade400;
      case NodeType.fictional:
        return Colors.indigo.shade300;
      case NodeType.historical:
        return Colors.brown.shade300;
      
      // Kai's Mind
      case NodeType.value:
        return Colors.teal.shade400;
      case NodeType.goal:
        return Colors.lightGreen.shade400;
      case NodeType.belief:
        return Colors.deepOrange.shade300;
      case NodeType.principle:
        return Colors.blueGrey.shade400;
      
      // Dynamics & Learning
      case NodeType.pattern:
        return Colors.lime.shade400;
      case NodeType.insight:
        return Colors.yellow.shade400;
      case NodeType.question:
        return Colors.pink.shade300;
      case NodeType.memory:
        return Colors.purple.shade300;
      case NodeType.skill:
        return Colors.cyan.shade300;
      
      // Relationships
      case NodeType.preference:
        return Colors.pinkAccent.shade200;
      case NodeType.habit:
        return Colors.grey.shade400;
      case NodeType.aspiration:
        return Colors.lightBlue.shade300;
    }
  }
  
  /// Get emoji for node type
  String get emoji {
    switch (type) {
      // Basic types
      case NodeType.person:
        return '👤';
      case NodeType.topic:
        return '💭';
      case NodeType.event:
        return '📅';
      case NodeType.emotion:
        return '😊';
      case NodeType.location:
        return '📍';
      case NodeType.date:
        return '🗓️';
      case NodeType.fact:
        return '💡';
      case NodeType.conversation:
        return '💬';
      case NodeType.concept:
        return '🧠';
      
      // People - Enhanced
      case NodeType.you:
        return '⭐'; // The user is special!
      case NodeType.realPerson:
        return '👥';
      case NodeType.fictional:
        return '📖';
      case NodeType.historical:
        return '🏛️';
      
      // Kai's Mind
      case NodeType.value:
        return '💎';
      case NodeType.goal:
        return '🎯';
      case NodeType.belief:
        return '🔮';
      case NodeType.principle:
        return '⚖️';
      
      // Dynamics & Learning
      case NodeType.pattern:
        return '🔄';
      case NodeType.insight:
        return '💫';
      case NodeType.question:
        return '❓';
      case NodeType.memory:
        return '🌟';
      case NodeType.skill:
        return '🛠️';
      
      // Relationships
      case NodeType.preference:
        return '❤️';
      case NodeType.habit:
        return '🔁';
      case NodeType.aspiration:
        return '🌠';
    }
  }
  
  /// Calculate visual size based on importance
  double get size {
    return 8.0 + (importance * 12.0); // 8-20px radius
  }
  
  /// Create from JSON
  factory KnowledgeNode.fromJson(Map<String, dynamic> json) {
    return KnowledgeNode(
      id: json['id'] as String,
      label: json['label'] as String,
      type: NodeType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => NodeType.fact,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      tags: (json['tags'] as List?)?.cast<String>() ?? [],
      importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      emotionalIntensity: (json['emotionalIntensity'] as num?)?.toDouble() ?? 0.0,
      accessCount: json['accessCount'] as int? ?? 0,
      retention: (json['retention'] as num?)?.toDouble() ?? 1.0,
      lastAccessed: json['lastAccessed'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['lastAccessed'] as int)
          : null,
      activationLevel: (json['activationLevel'] as num?)?.toDouble() ?? 0.0,
    );
  }
  
  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'type': type.name,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'tags': tags,
    'importance': importance,
    'metadata': metadata,
    'emotionalIntensity': emotionalIntensity,
    'accessCount': accessCount,
    'retention': retention,
    'lastAccessed': lastAccessed?.millisecondsSinceEpoch,
    'activationLevel': activationLevel,
  };
  
  /// Record access (strengthens memory)
  void recall() {
    accessCount++;
    lastAccessed = DateTime.now();
    retention = (retention + 0.1).clamp(0.0, 1.0); // Recall strengthens memory
    print('🔄 [NODE] Recalled "$label" (count: $accessCount, retention: ${retention.toStringAsFixed(2)})');
  }
  
  /// Apply forgetting curve (Ebbinghaus)
  void applyForgetting() {
    final now = DateTime.now();
    final age = now.difference(timestamp).inDays;
    
    // Strength depends on importance and reinforcement
    final S = 30 * importance * (1 + accessCount);
    
    // Retention probability: R = e^(-t/S)
    retention = exp(-age / S);
    
    // Important memories decay slower
    if (importance > 0.8) {
      retention = retention.clamp(0.5, 1.0);
    }
    
    // Emotional memories decay slower (flashbulb effect)
    if (emotionalIntensity > 0.8) {
      retention = retention.clamp(0.7, 1.0);
    }
    
    print('⏳ [NODE] Applied forgetting to "$label": retention=${retention.toStringAsFixed(2)} (age=${age}d, S=$S)');
  }
}

class KnowledgeEdge {
  final String fromId;
  final String toId;
  final EdgeType type;
  final double strength; // 0-1, affects edge thickness/opacity
  final DateTime timestamp;
  final String? label;

  /// Memory shard ids this claim came from — `memory/embeddings/{persona}/{id}`,
  /// which holds the actual words that were said.
  ///
  /// Without this the graph is a rumour with good styling: it asserts things
  /// about Sadeq and cannot say why. With it, Kai can answer "because you told
  /// me, on the 3rd" — and a wrong belief can be corrected at its source
  /// instead of merely deleted.
  ///
  /// It is also the nerve between his two memory systems. `MemoryService`
  /// (episodics, vectors) and this graph (entities, claims) are built from the
  /// SAME exchange and, until now, had never once referenced each other.
  final List<String> sources;

  /// When this claim stopped being true. Null = still believed.
  ///
  /// Facts change — he moves, he changes his mind, the Tavern opens. Nothing
  /// used to retire a claim; it just decayed, so his graph could only ever be a
  /// snapshot of now with no memory of having been wrong. Superseded edges are
  /// never deleted: they are what makes this a mind that changed rather than a
  /// mind that was always right.
  final DateTime? supersededAt;

  KnowledgeEdge({
    required this.fromId,
    required this.toId,
    required this.type,
    required this.strength,
    required this.timestamp,
    this.label,
    this.sources = const [],
    this.supersededAt,
  });

  /// A claim he currently holds.
  bool get isActive => supersededAt == null;

  KnowledgeEdge copyWith({
    EdgeType? type,
    double? strength,
    String? label,
    List<String>? sources,
    DateTime? supersededAt,
  }) =>
      KnowledgeEdge(
        fromId: fromId,
        toId: toId,
        type: type ?? this.type,
        strength: strength ?? this.strength,
        timestamp: timestamp,
        label: label ?? this.label,
        sources: sources ?? this.sources,
        supersededAt: supersededAt ?? this.supersededAt,
      );
  
  /// Get color based on edge type
  Color get color {
    switch (type) {
      // Basic relationships
      case EdgeType.mentioned:
        return Colors.white.withOpacity(0.3);
      case EdgeType.related:
        return Colors.blue.withOpacity(0.4);
      case EdgeType.caused:
        return Colors.red.withOpacity(0.5);
      case EdgeType.contains:
        return Colors.green.withOpacity(0.3);
      case EdgeType.temporal:
        return Colors.purple.withOpacity(0.2);
      case EdgeType.categorized:
        return Colors.cyan.withOpacity(0.4);
      
      // Consciousness relationships
      case EdgeType.holdsValue:
        return Colors.teal.withOpacity(0.6);
      case EdgeType.pursues:
        return Colors.lightGreen.withOpacity(0.6);
      case EdgeType.believes:
        return Colors.deepOrange.withOpacity(0.5);
      case EdgeType.learned:
        return Colors.yellow.withOpacity(0.5);
      case EdgeType.knows:
        return Colors.pink.withOpacity(0.5);
      case EdgeType.caresAbout:
        return Colors.purple.withOpacity(0.6);
      
      // Pattern relationships
      case EdgeType.influences:
        return Colors.orange.withOpacity(0.5);
      case EdgeType.exemplifies:
        return Colors.amber.withOpacity(0.5);
      case EdgeType.contradicts:
        return Colors.red.withOpacity(0.6);
      case EdgeType.reinforces:
        return Colors.green.withOpacity(0.5);
      
      // User relationships
      case EdgeType.prefers:
        return Colors.pinkAccent.withOpacity(0.5);
      case EdgeType.dislikes:
        return Colors.grey.withOpacity(0.4);
      case EdgeType.does:
        return Colors.blueGrey.withOpacity(0.4);
      case EdgeType.wants:
        return Colors.lightBlue.withOpacity(0.6);
    }
  }
  
  /// Calculate visual thickness based on strength
  double get thickness {
    return 0.5 + (strength * 2.5); // 0.5-3px
  }
  
  /// Create from JSON
  factory KnowledgeEdge.fromJson(Map<String, dynamic> json) {
    return KnowledgeEdge(
      fromId: json['fromId'] as String,
      toId: json['toId'] as String,
      type: EdgeType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => EdgeType.related,
      ),
      strength: (json['strength'] as num?)?.toDouble() ?? 0.5,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      label: json['label'] as String?,
      // Legacy edges have neither — they predate provenance and supersession.
      // Absent sources means "we don't know where this came from", which is the
      // honest reading of every edge written before today.
      sources: (json['sources'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      supersededAt: json['supersededAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['supersededAt'] as int)
          : null,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'fromId': fromId,
    'toId': toId,
    'type': type.name,
    'strength': strength,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'label': label,
    if (sources.isNotEmpty) 'sources': sources,
    if (supersededAt != null) 'supersededAt': supersededAt!.millisecondsSinceEpoch,
  };
}

enum EdgeType {
  // Basic relationships
  mentioned,   // A was mentioned in B
  related,     // A is related to B (via similarity)
  caused,      // A caused B (e.g., event → emotion)
  contains,    // A contains B (conversation → facts)
  temporal,    // A happened before/after B
  categorized, // A belongs to category B
  
  // Consciousness relationships
  holdsValue,  // Kai values X (Kai → value)
  pursues,     // Kai pursues goal X (Kai → goal)
  believes,    // Kai believes X (Kai → belief)
  learned,     // Kai learned X (Kai → knowledge)
  knows,       // Kai knows person X (Kai → person)
  caresAbout,  // Kai cares about X (Kai → anything)
  
  // Pattern relationships
  influences,  // X influences Y
  exemplifies, // X exemplifies value Y
  contradicts, // X contradicts belief Y
  reinforces,  // X reinforces pattern Y
  
  // User relationships
  prefers,     // User prefers X
  dislikes,    // User dislikes X
  does,        // User does X (habit)
  wants,       // User wants X (aspiration)
}

/// Complete knowledge graph
class KnowledgeGraph {
  final List<KnowledgeNode> nodes;
  final List<KnowledgeEdge> edges;
  final DateTime lastUpdated;
  
  KnowledgeGraph({
    required this.nodes,
    required this.edges,
    required this.lastUpdated,
  });
  
  /// Get node by ID
  KnowledgeNode? getNode(String id) {
    try {
      return nodes.firstWhere((n) => n.id == id);
    } catch (e) {
      return null;
    }
  }
  
  /// Get edges for a specific node
  List<KnowledgeEdge> getNodeEdges(String nodeId) {
    return edges.where((e) => e.fromId == nodeId || e.toId == nodeId).toList();
  }
  
  /// Get connected nodes for a specific node
  List<KnowledgeNode> getConnectedNodes(String nodeId) {
    final connectedIds = <String>{};
    for (final edge in edges) {
      if (edge.fromId == nodeId) {
        connectedIds.add(edge.toId);
      } else if (edge.toId == nodeId) {
        connectedIds.add(edge.fromId);
      }
    }
    return nodes.where((n) => connectedIds.contains(n.id)).toList();
  }
  
  /// Filter nodes by type
  List<KnowledgeNode> filterByType(NodeType type) {
    return nodes.where((n) => n.type == type).toList();
  }
  
  /// Search nodes by label
  List<KnowledgeNode> search(String query) {
    final lowerQuery = query.toLowerCase();
    return nodes.where((n) => 
      n.label.toLowerCase().contains(lowerQuery) ||
      n.tags.any((tag) => tag.toLowerCase().contains(lowerQuery))
    ).toList();
  }
}
