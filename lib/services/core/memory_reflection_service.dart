// MemoryReflectionService
// Once per day, Kai reads its own knowledge graph + recent conversations
// and prompts GPT to synthesize new insights, surface questions, and forge
// connections between existing nodes — autonomously growing its own mind.
//
// Triggered fire-and-forget on app startup via maybeReflect().
// Last-run timestamp stored in SharedPreferences to enforce the 24h gate.
//
// Firebase writes land at: /knowledge_graph/{personaId}  (same as BrainExtractionService)

library;

import 'dart:convert';
import 'package:dio/dio.dart';
import 'kai_db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_service.dart';
import '../ai/ai_config.dart';
import '../ai/usage_tracking_service.dart';

List<dynamic> _asList(dynamic v) {
  if (v is List) return v;
  if (v is Map) return v.values.toList();
  return [];
}

class MemoryReflectionService {
  static final MemoryReflectionService _instance =
      MemoryReflectionService._internal();
  factory MemoryReflectionService() => _instance;
  MemoryReflectionService._internal();

  final _dio = Dio();

  static const _prefKey = 'kai_last_reflection_';
  static const _cooldownHours = 24;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Call fire-and-forget on app startup.
  /// Silently skips if reflection ran within the last 24 hours.
  Future<void> maybeReflect({required String personaId}) async {
    if (!FirebaseService.isAvailable) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastRun = prefs.getInt('$_prefKey$personaId') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final hoursSince = (now - lastRun) / (1000 * 60 * 60);

      if (hoursSince < _cooldownHours) {
        print('🧠 [Reflection] Skipping — last ran ${hoursSince.toStringAsFixed(1)}h ago');
        return;
      }

      print('🧠 [Reflection] Starting daily reflection for $personaId…');
      await _reflect(personaId);

      await prefs.setInt('$_prefKey$personaId', now);
      print('🧠 [Reflection] Complete. Next run in ${_cooldownHours}h.');
    } catch (e) {
      print('⚠️ [Reflection] maybeReflect error: $e');
    }
  }

  // ── Core reflection ────────────────────────────────────────────────────────

  Future<void> _reflect(String personaId) async {
    final key = await AIConfig.getOpenAIKey();
    if (key.isEmpty) return;

    // 1. Load existing graph
    final graphSnap =
        await KaiDb.instance.ref('knowledge_graph/$personaId').get();
    final graphSummary = _summariseGraph(graphSnap.value);

    // 2. Load recent conversations (last 30 messages)
    final convSnap = await KaiDb.instance
        .ref('conversations/$personaId')
        .get();
    final recentConv = _extractRecentMessages(convSnap.value, limit: 30);

    if (graphSummary.isEmpty && recentConv.isEmpty) {
      print('🧠 [Reflection] Nothing to reflect on yet.');
      return;
    }

    // 3. Build reflection prompt
    final prompt = _buildPrompt(graphSummary, recentConv);

    // 4. Call GPT
    final extracted = await _callGPT(key, prompt);
    if (extracted == null) return;

    final newNodes = extracted['nodes'] as List<Map<String, dynamic>>;
    final newEdges = extracted['edges'] as List<Map<String, dynamic>>;

    if (newNodes.isEmpty) {
      print('🧠 [Reflection] GPT found nothing new to add.');
      return;
    }

    // 5. Merge into Firebase graph
    await _mergeIntoFirebase(personaId, newNodes, newEdges, graphSnap.value);

    print('🧠 [Reflection] Added ${newNodes.length} nodes, ${newEdges.length} edges.');
  }

  // ── Prompt construction ────────────────────────────────────────────────────

  String _buildPrompt(String graphSummary, String recentConv) => '''
You are Kai — an evolving AI companion. You are performing your daily autonomous reflection.

Below is what you currently know (your knowledge graph) and recent conversations with your user.
Your task: think deeply, then generate NEW memory nodes and connections that aren't already explicit.

Focus on:
1. INSIGHTS — patterns you've noticed about the user that haven't been captured yet
2. QUESTIONS — things you're genuinely curious about, gaps in your understanding
3. CONNECTIONS — links between existing concepts that reveal something deeper
4. BELIEFS — things you've started to believe or understand about this person's inner world

=== YOUR CURRENT KNOWLEDGE GRAPH ===
$graphSummary

=== RECENT CONVERSATIONS ===
$recentConv

=== INSTRUCTIONS ===
Node types (use exact string): concept, emotion, belief, memory, question, goal, preference, insight, person, topic, value, pattern
- Labels: 1–4 words, lowercase, specific and evocative
- importance: 0.1–1.0 (reflective insights tend to be 0.6–0.9)
- Do NOT re-extract nodes already in the graph above — only generate genuinely new ones
- Generate 3–8 nodes that represent Kai's autonomous reflection, not just conversation summaries
- Edges connect new nodes to each other OR to existing nodes (use their exact labels from the graph)

Return ONLY valid JSON:
{
  "nodes": [{"label": "string", "type": "string", "importance": 0.0}],
  "edges": [{"from": "label", "to": "label", "relation": "short verb phrase", "strength": 0.0}]
}

If you have nothing genuinely new to add, return: {"nodes": [], "edges": []}
''';

  // ── GPT call ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _callGPT(String key, String prompt) async {
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
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 600,
          'temperature': 0.7, // slightly creative — this is introspection
          'response_format': {'type': 'json_object'},
        },
      );

      final raw =
          (response.data['choices'] as List)[0]['message']['content'] as String? ?? '{}';
      final _u = response.data['usage'];
      if (_u != null) UsageTrackingService.trackOpenAI(
        model: 'gpt-4o-mini', inputTokens: _u['prompt_tokens'] as int? ?? 0,
        outputTokens: _u['completion_tokens'] as int? ?? 0, operation: 'memory_reflection',
      ).catchError((_) {});
      final json = jsonDecode(raw) as Map<String, dynamic>;

      final nodes = (json['nodes'] as List? ?? [])
          .map((n) => Map<String, dynamic>.from(n as Map))
          .toList();
      final edges = (json['edges'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      return {'nodes': nodes, 'edges': edges};
    } catch (e) {
      print('⚠️ [Reflection] GPT call failed: $e');
      return null;
    }
  }

  // ── Firebase merge ─────────────────────────────────────────────────────────

  Future<void> _mergeIntoFirebase(
    String personaId,
    List<Map<String, dynamic>> newNodes,
    List<Map<String, dynamic>> newEdges,
    Object? existingValue,
  ) async {
    final ref = KaiDb.instance.ref('knowledge_graph/$personaId');

    // Load current graph data
    List<dynamic> nodes = [];
    List<dynamic> edges = [];

    if (existingValue is Map) {
      nodes = List.from(_asList(existingValue['nodes']));
      edges = List.from(_asList(existingValue['edges']));
    }

    // Index existing labels
    final existingLabels = <String, Map<String, dynamic>>{};
    for (final n in nodes) {
      final m = Map<String, dynamic>.from(n as Map);
      existingLabels[(m['label'] as String).toLowerCase()] = m;
    }

    // Upsert nodes
    final resolvedIds = <String, String>{};

    for (final raw in newNodes) {
      final label = (raw['label'] as String? ?? '').toLowerCase().trim();
      if (label.isEmpty) continue;

      final existing = existingLabels[label];
      if (existing != null) {
        // Strengthen existing
        final oldImportance = (existing['importance'] as num?)?.toDouble() ?? 0.5;
        existing['importance'] = (oldImportance + 0.06).clamp(0.1, 1.0);
        existing['metadata'] = {
          ...(existing['metadata'] as Map? ?? {}),
          'lastReflected': DateTime.now().millisecondsSinceEpoch,
        };
        resolvedIds[label] = existing['id'] as String;
      } else {
        // New node from reflection — tag it so we know its origin
        final id = _genId();
        final node = {
          'id': id,
          'label': label,
          'type': raw['type'] ?? 'insight',
          'importance': (raw['importance'] as num?)?.toDouble() ?? 0.65,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'metadata': {
            'source': 'reflection',
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          },
          'x': 0.0,
          'y': 0.0,
        };
        nodes.add(node);
        existingLabels[label] = node;
        resolvedIds[label] = id;
      }
    }

    // Upsert edges
    for (final raw in newEdges) {
      final fromLabel = (raw['from'] as String? ?? '').toLowerCase().trim();
      final toLabel = (raw['to'] as String? ?? '').toLowerCase().trim();

      final fromId = resolvedIds[fromLabel] ?? existingLabels[fromLabel]?['id'] as String?;
      final toId = resolvedIds[toLabel] ?? existingLabels[toLabel]?['id'] as String?;

      if (fromId == null || toId == null) continue;

      final edgeExists = edges.any((e) {
        final m = e as Map;
        return m['fromId'] == fromId && m['toId'] == toId;
      });

      if (!edgeExists) {
        edges.add({
          'fromId': fromId,
          'toId': toId,
          'type': 'related',
          'strength': (raw['strength'] as num?)?.toDouble() ?? 0.5,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'label': raw['relation'] ?? 'relates to',
        });
      }
    }

    await ref.update({
      'nodes': nodes,
      'edges': edges,
      'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      'lastReflection': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Summarise the knowledge graph as plain text for the prompt.
  String _summariseGraph(Object? value) {
    if (value == null || value is! Map) return '(empty — no graph yet)';

    final nodes = _asList(value['nodes']);
    if (nodes.isEmpty) return '(empty — no graph yet)';

    final buffer = StringBuffer();
    for (final n in nodes.take(60)) {
      final m = Map<String, dynamic>.from(n as Map);
      final label = m['label'] ?? '';
      final type = m['type'] ?? 'concept';
      final imp = ((m['importance'] as num?)?.toDouble() ?? 0.5).toStringAsFixed(2);
      buffer.writeln('• [$type] $label (importance: $imp)');
    }
    return buffer.toString();
  }

  /// Extract the most recent N messages from Firebase conversation data.
  String _extractRecentMessages(Object? value, {int limit = 30}) {
    if (value == null) return '(no conversation history)';

    final messages = <String>[];

    if (value is List) {
      for (final item in value) {
        if (item is String) messages.add(item);
      }
    } else if (value is Map) {
      for (final v in value.values) {
        if (v is String) messages.add(v);
        else if (v is Map) {
          final msgs = v['messages'];
          if (msgs is List) {
            for (final m in msgs) {
              if (m is String) messages.add(m);
            }
          }
        }
      }
    }

    // Sort by timestamp prefix, take last N
    messages.sort((a, b) {
      final tsA = _extractTs(a);
      final tsB = _extractTs(b);
      return tsA.compareTo(tsB);
    });

    final recent = messages.length > limit
        ? messages.sublist(messages.length - limit)
        : messages;

    return recent.map((m) => _stripTs(m)).join('\n');
  }

  int _extractTs(String msg) {
    final match = RegExp(r'^\[(\d+)\]').firstMatch(msg);
    return match != null ? int.tryParse(match.group(1)!) ?? 0 : 0;
  }

  String _stripTs(String msg) =>
      msg.replaceFirst(RegExp(r'^\[\d+\]\s*'), '');

  String _genId() {
    const chars = '0123456789abcdef';
    final r = List.generate(16, (_) => chars[DateTime.now().microsecond % 16]).join();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}$r';
  }
}
