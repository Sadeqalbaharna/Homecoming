/// Knowledge Graph Node - Represents entities in Kai's memory
library;

import 'package:flutter/material.dart';

enum NodeType {
  person,       // People mentioned (red)
  topic,        // Topics discussed (blue)
  event,        // Specific events/plans (green)
  emotion,      // Emotional moments (pink)
  location,     // Places mentioned (yellow)
  date,         // Important dates (purple)
  fact,         // Extracted facts (cyan)
  conversation, // Conversation sessions (white)
}

class KnowledgeNode {
  final String id;
  final String label;
  final NodeType type;
  final DateTime timestamp;
  final List<String> tags;
  final double importance; // 0-1, affects node size
  final Map<String, dynamic> metadata;
  
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
  });
  
  /// Get color based on node type
  Color get color {
    switch (type) {
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
    }
  }
  
  /// Get emoji for node type
  String get emoji {
    switch (type) {
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
  };
}

class KnowledgeEdge {
  final String fromId;
  final String toId;
  final EdgeType type;
  final double strength; // 0-1, affects edge thickness/opacity
  final DateTime timestamp;
  final String? label;
  
  KnowledgeEdge({
    required this.fromId,
    required this.toId,
    required this.type,
    required this.strength,
    required this.timestamp,
    this.label,
  });
  
  /// Get color based on edge type
  Color get color {
    switch (type) {
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
  };
}

enum EdgeType {
  mentioned,  // A was mentioned in B
  related,    // A is related to B (via similarity)
  caused,     // A caused B (e.g., event → emotion)
  contains,   // A contains B (conversation → facts)
  temporal,   // A happened before/after B
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
