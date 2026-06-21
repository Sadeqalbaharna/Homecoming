// BrainExtractionService
// After each conversation, GPT extracts meaningful nodes and relationships
// and merges them incrementally into the living knowledge graph in Firebase.
//
// Philosophy:
//   - Nodes grow heavier each time a concept is referenced (importance += 0.08)
//   - Edges strengthen each time a relationship recurs (strength += 0.08)
//   - New nodes/edges are added organically — the graph is never rebuilt from scratch
//   - Heavily-referenced concepts drift to the visual center via physics weight
//
// Firebase path: /knowledge_graph/{personaId}
//   { nodes: [...], edges: [...], lastUpdated: timestamp }

library;

import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../models/knowledge_node.dart';
import 'firebase_service.dart';
import '../ai/ai_config.dart';
import '../ai/usage_tracking_service.dart';

List<dynamic> _asList(dynamic v) {
  if (v is List) return v;
  if (v is Map) return v.values.toList();
  return [];
}

class BrainExtractionService {
  static final BrainExtractionService _instance =
      BrainExtractionService._internal();
  factory BrainExtractionService() => _instance;
  BrainExtractionService._internal();

  final _dio = Dio();
  final _rng = Random();

  static FirebaseDatabase? get _db =>
      FirebaseService.isAvailable ? FirebaseDatabase.instance : null;

  static String _path(String personaId) => 'knowledge_graph/$personaId';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Call fire-and-forget after each conversation turn.
  /// Extracts nodes/edges via GPT and merges into the live Firebase graph.
  Future<void> extractAndMerge({
    required String personaId,
    required String userMessage,
    required String aiReply,
  }) async {
    if (_db == null) return;

    try {
      // 1. Extract new nodes/edges from this conversation via GPT
      final extracted = await _extractFromGPT(
        userMessage: userMessage,
        aiReply: aiReply,
      );
      if (extracted == null) return;

      final newNodes = extracted['nodes'] as List<_RawNode>;
      final newEdges = extracted['edges'] as List<_RawEdge>;

      if (newNodes.isEmpty) return;

      // 2. Load current graph from Firebase
      final graph = await _loadGraph(personaId) ??
          KnowledgeGraph(nodes: [], edges: [], lastUpdated: DateTime.now());

      // 3. Merge
      final merged = _merge(graph, newNodes, newEdges);

      // 4. Save back
      await _saveGraph(personaId, merged);

      print(
          '🧠 [Brain] Merged ${newNodes.length} nodes, ${newEdges.length} edges '
          '→ graph now has ${merged.nodes.length} nodes, ${merged.edges.length} edges');
    } catch (e) {
      print('⚠️ [Brain] extractAndMerge failed: $e');
    }
  }

  // ── GPT extraction ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _extractFromGPT({
    required String userMessage,
    required String aiReply,
  }) async {
    final key = await AIConfig.getOpenAIKey();
    if (key.isEmpty) return null;

    const prompt = '''You are building a living knowledge graph for an AI companion named Kai.
Analyze this conversation exchange and extract meaningful nodes and relationships.

MANDATORY RULES — always apply these first:
1. Any named person (real name like "Mikey", "Sarah", "dad") → ALWAYS extract as type "person", importance 0.7+
2. Any named place, school, city, company → extract as type "topic", importance 0.6+
3. These are NON-NEGOTIABLE even if the exchange seems casual

Then also extract things that reveal:
- What the user cares about, feels, wants, or worries about
- What Kai is learning or noticing about the user's life
- Abstract ideas and recurring themes worth remembering

Node types (use exact string):
concept, emotion, belief, memory, question, goal, preference, insight, person, topic, value, pattern

Edge relation examples (short verb phrases):
"knows", "cares about", "worries about", "is studying at", "wonders about", "feels",
"believes in", "connects to", "leads to", "shapes", "reveals", "fears", "desires"

Rules:
- Extract 2–6 nodes. Named people/places always count toward this.
- Labels: 1–4 words, lowercase. Names keep their capitalisation ("mikey", "sarah").
- Return ONLY valid JSON, no commentary.

JSON format:
{
  "nodes": [
    {"label": "string", "type": "string", "importance": 0.1–1.0}
  ],
  "edges": [
    {"from": "label", "to": "label", "relation": "short verb phrase", "strength": 0.1–1.0}
  ]
}

If truly trivial (no names, no feelings, no facts), return: {"nodes": [], "edges": []}''';

    final userContent =
        'User: "$userMessage"\nKai: "$aiReply"';

    try {
      final response = await _dio.post(
        'https://api.openai.com/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': 'gpt-4o-mini',
          'messages': [
            {'role': 'system', 'content': prompt},
            {'role': 'user', 'content': userContent},
          ],
          'max_tokens': 400,
          'temperature': 0.4,
          'response_format': {'type': 'json_object'},
        },
      );

      final raw = (response.data['choices'] as List)[0]['message']['content']
          as String? ?? '{}';
      final _u = response.data['usage'];
      if (_u != null) UsageTrackingService.trackOpenAI(
        model: 'gpt-4o-mini', inputTokens: _u['prompt_tokens'] as int? ?? 0,
        outputTokens: _u['completion_tokens'] as int? ?? 0, operation: 'brain_extraction',
      ).catchError((_) {});
      final json = jsonDecode(raw) as Map<String, dynamic>;

      final nodes = (json['nodes'] as List? ?? []).map((n) {
        final m = n as Map<String, dynamic>;
        return _RawNode(
          label: (m['label'] as String? ?? '').toLowerCase().trim(),
          type: _parseNodeType(m['type'] as String? ?? ''),
          importance: (m['importance'] as num?)?.toDouble() ?? 0.5,
        );
      }).where((n) => n.label.isNotEmpty).toList();

      final edges = (json['edges'] as List? ?? []).map((e) {
        final m = e as Map<String, dynamic>;
        return _RawEdge(
          fromLabel: (m['from'] as String? ?? '').toLowerCase().trim(),
          toLabel: (m['to'] as String? ?? '').toLowerCase().trim(),
          relation: m['relation'] as String? ?? 'relates to',
          strength: (m['strength'] as num?)?.toDouble() ?? 0.5,
        );
      }).where((e) => e.fromLabel.isNotEmpty && e.toLabel.isNotEmpty).toList();

      return {'nodes': nodes, 'edges': edges};
    } catch (e) {
      print('⚠️ [Brain] GPT extraction failed: $e');
      return null;
    }
  }

  // ── Merge ──────────────────────────────────────────────────────────────────

  KnowledgeGraph _merge(
    KnowledgeGraph existing,
    List<_RawNode> newNodes,
    List<_RawEdge> newEdges,
  ) {
    final nodes = List<KnowledgeNode>.from(existing.nodes);
    final edges = List<KnowledgeEdge>.from(existing.edges);

    // Index existing nodes by label → list index (KnowledgeNode has final fields,
    // so we replace the item at the index rather than mutating in place)
    final labelToIndex = <String, int>{};
    for (var i = 0; i < nodes.length; i++) {
      labelToIndex[nodes[i].label.toLowerCase()] = i;
    }

    // Upsert nodes
    final resolvedIds = <String, String>{}; // rawLabel → nodeId

    for (final raw in newNodes) {
      final idx = labelToIndex[raw.label];
      if (idx != null) {
        // Node exists — replace with strengthened copy
        final old = nodes[idx];
        final updatedMeta = Map<String, dynamic>.from(old.metadata)
          ..['lastSeen'] = DateTime.now().millisecondsSinceEpoch
          ..['mentions'] = ((old.metadata['mentions'] as int? ?? 1) + 1);
        final updated = KnowledgeNode(
          id: old.id,
          label: old.label,
          type: old.type,
          timestamp: old.timestamp,
          tags: old.tags,
          importance: (old.importance + 0.08).clamp(0.1, 1.0),
          metadata: updatedMeta,
          emotionalIntensity: old.emotionalIntensity,
          accessCount: old.accessCount,
          retention: old.retention,
          lastAccessed: old.lastAccessed,
          activationLevel: old.activationLevel,
        )
          ..x = old.x
          ..y = old.y
          ..vx = old.vx
          ..vy = old.vy;
        nodes[idx] = updated;
        resolvedIds[raw.label] = old.id;
      } else {
        // New node
        final newNode = KnowledgeNode(
          id: _genId(),
          label: raw.label,
          type: raw.type,
          timestamp: DateTime.now(),
          importance: raw.importance,
          metadata: {
            'lastSeen': DateTime.now().millisecondsSinceEpoch,
            'mentions': 1,
          },
        );
        nodes.add(newNode);
        labelToIndex[raw.label] = nodes.length - 1;
        resolvedIds[raw.label] = newNode.id;
      }
    }

    // Upsert edges
    for (final raw in newEdges) {
      final fromId = resolvedIds[raw.fromLabel] ??
          (labelToIndex[raw.fromLabel] != null
              ? nodes[labelToIndex[raw.fromLabel]!].id
              : null);
      final toId = resolvedIds[raw.toLabel] ??
          (labelToIndex[raw.toLabel] != null
              ? nodes[labelToIndex[raw.toLabel]!].id
              : null);

      if (fromId == null || toId == null) continue;

      final edgeIdx =
          edges.indexWhere((e) => e.fromId == fromId && e.toId == toId);

      if (edgeIdx >= 0) {
        // Replace with strengthened copy (KnowledgeEdge.strength is final)
        final old = edges[edgeIdx];
        edges[edgeIdx] = KnowledgeEdge(
          fromId: old.fromId,
          toId: old.toId,
          type: old.type,
          strength: (old.strength + 0.08).clamp(0.1, 1.0),
          timestamp: old.timestamp,
          label: old.label,
        );
      } else {
        // New edge
        edges.add(KnowledgeEdge(
          fromId: fromId,
          toId: toId,
          type: EdgeType.related,
          strength: raw.strength,
          timestamp: DateTime.now(),
          label: raw.relation,
        ));
      }
    }

    return KnowledgeGraph(
      nodes: nodes,
      edges: edges,
      lastUpdated: DateTime.now(),
    );
  }

  // ── Firebase I/O ───────────────────────────────────────────────────────────

  Future<KnowledgeGraph?> _loadGraph(String personaId) async {
    try {
      final snap = await _db!.ref(_path(personaId)).get();
      if (!snap.exists || snap.value == null) return null;

      final data = Map<String, dynamic>.from(snap.value as Map);

      final nodes = <KnowledgeNode>[];
      for (final n in _asList(data['nodes'])) {
        final m = Map<String, dynamic>.from(n as Map);
        final type = NodeType.values.firstWhere(
          (t) => t.toString().split('.').last == m['type'],
          orElse: () => NodeType.concept,
        );
        nodes.add(KnowledgeNode(
          id: m['id'] as String,
          label: m['label'] as String,
          type: type,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              (m['timestamp'] as num).toInt()),
          importance: (m['importance'] as num?)?.toDouble() ?? 0.5,
          metadata: Map<String, dynamic>.from(m['metadata'] as Map? ?? {}),
        )
          ..x = (m['x'] as num?)?.toDouble() ?? 0
          ..y = (m['y'] as num?)?.toDouble() ?? 0);
      }

      final edges = <KnowledgeEdge>[];
      for (final e in _asList(data['edges'])) {
        final m = Map<String, dynamic>.from(e as Map);
        final type = EdgeType.values.firstWhere(
          (t) => t.toString().split('.').last == m['type'],
          orElse: () => EdgeType.related,
        );
        edges.add(KnowledgeEdge(
          fromId: m['fromId'] as String,
          toId: m['toId'] as String,
          type: type,
          strength: (m['strength'] as num?)?.toDouble() ?? 0.5,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              (m['timestamp'] as num).toInt()),
          label: m['label'] as String?,
        ));
      }

      return KnowledgeGraph(
          nodes: nodes, edges: edges, lastUpdated: DateTime.now());
    } catch (e) {
      print('⚠️ [Brain] _loadGraph failed: $e');
      return null;
    }
  }

  Future<void> _saveGraph(String personaId, KnowledgeGraph graph) async {
    await _db!.ref(_path(personaId)).set({
      'nodes': graph.nodes
          .map((n) => {
                'id': n.id,
                'label': n.label,
                'type': n.type.toString().split('.').last,
                'timestamp': n.timestamp.millisecondsSinceEpoch,
                'importance': n.importance,
                'metadata': n.metadata,
                'x': n.x,
                'y': n.y,
              })
          .toList(),
      'edges': graph.edges
          .map((e) => {
                'fromId': e.fromId,
                'toId': e.toId,
                'type': e.type.toString().split('.').last,
                'strength': e.strength,
                'timestamp': e.timestamp.millisecondsSinceEpoch,
                if (e.label != null) 'label': e.label,
              })
          .toList(),
      'lastUpdated': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _genId() => List.generate(16,
      (_) => _rng.nextInt(16).toRadixString(16)).join();

  NodeType _parseNodeType(String s) {
    return NodeType.values.firstWhere(
      (t) => t.toString().split('.').last == s.toLowerCase().trim(),
      orElse: () => NodeType.concept,
    );
  }
}

// ── Internal DTOs ─────────────────────────────────────────────────────────────

class _RawNode {
  final String label;
  final NodeType type;
  final double importance;
  _RawNode({required this.label, required this.type, required this.importance});
}

class _RawEdge {
  final String fromLabel;
  final String toLabel;
  final String relation;
  final double strength;
  _RawEdge({
    required this.fromLabel,
    required this.toLabel,
    required this.relation,
    required this.strength,
  });
}
