// ChatGPTMemoryImportService
// Takes raw text pasted from ChatGPT's "Saved memories" or "Memory summary" view
// and imports it into Kai's Firebase memory system across three layers:
//
//   1. Knowledge graph  → /knowledge_graph/{personaId}
//      Rich nodes: people, projects, values, preferences, goals, insights
//
//   2. Personality context → /kai/{personaId}/personality/chatgpt_context
//      A condensed prose summary Kai can inject into its system prompt
//
//   3. Core facts → /kai/{personaId}/core_facts/
//      Structured key/value facts (name, location, occupation, projects…)
//
// Usage:
//   final result = await ChatGPTMemoryImportService().importMemories(
//     personaId: 'truekai',
//     rawText: pastedText,
//     onProgress: (msg) => setState(() => status = msg),
//   );

library;

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:firebase_database/firebase_database.dart';
import 'kai_db.dart';
import 'firebase_service.dart';
import '../ai/ai_config.dart';
import '../ai/usage_tracking_service.dart';

List<dynamic> _asList(dynamic v) {
  if (v is List) return v;
  if (v is Map) return v.values.toList();
  return [];
}

class ImportResult {
  final int nodesAdded;
  final int edgesAdded;
  final bool personalityUpdated;
  final int factsWritten;
  final String summary;

  ImportResult({
    required this.nodesAdded,
    required this.edgesAdded,
    required this.personalityUpdated,
    required this.factsWritten,
    required this.summary,
  });
}

class ChatGPTMemoryImportService {
  static final ChatGPTMemoryImportService _instance =
      ChatGPTMemoryImportService._internal();
  factory ChatGPTMemoryImportService() => _instance;
  ChatGPTMemoryImportService._internal();

  final _dio = Dio();

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<ImportResult> importMemories({
    required String personaId,
    required String rawText,
    void Function(String)? onProgress,
  }) async {
    if (!FirebaseService.isAvailable) {
      throw Exception('Firebase not available');
    }

    final key = await AIConfig.getOpenAIKey();
    if (key.isEmpty) throw Exception('No OpenAI key');

    if (rawText.trim().isEmpty) {
      throw Exception('No memory text provided');
    }

    onProgress?.call('Analysing memories with GPT…');

    // Step 1: Extract structured data from raw memory text
    final extracted = await _extractFromGPT(key, rawText);
    if (extracted == null) throw Exception('GPT extraction failed');

    final nodes = extracted['nodes'] as List<Map<String, dynamic>>;
    final edges = extracted['edges'] as List<Map<String, dynamic>>;
    final facts = extracted['facts'] as Map<String, dynamic>;
    final personalityContext = extracted['personality_context'] as String;

    onProgress?.call('Writing ${nodes.length} nodes to knowledge graph…');

    // Step 2: Merge nodes into knowledge graph
    final graphResult = await _mergeKnowledgeGraph(personaId, nodes, edges);

    onProgress?.call('Writing personality context…');

    // Step 3: Write personality context
    await _writePersonalityContext(personaId, personalityContext);

    onProgress?.call('Writing core facts…');

    // Step 4: Write core facts
    await _writeCoreFacts(personaId, facts);

    onProgress?.call('Done!');

    return ImportResult(
      nodesAdded: graphResult['added'] as int,
      edgesAdded: graphResult['edges'] as int,
      personalityUpdated: true,
      factsWritten: facts.length,
      summary: personalityContext,
    );
  }

  // ── GPT extraction ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _extractFromGPT(
      String key, String rawText) async {
    const systemPrompt = '''You are helping build a rich memory system for an AI companion named Kai.
The user has provided their saved memories from ChatGPT.
Your job is to extract every meaningful piece of information and structure it for Kai.

Extract into these four sections:

1. NODES (knowledge graph nodes):
   - Every named person mentioned (type: "person")
   - Every project, business, or initiative (type: "topic")
   - Goals and aspirations (type: "goal")
   - Values the user holds (type: "value")
   - Preferences, likes, dislikes (type: "preference")
   - Beliefs and worldview elements (type: "belief")
   - Patterns in their behaviour or thinking (type: "pattern")
   - Key memories or experiences (type: "memory")
   - Insights about who this person is (type: "insight")
   - Important concepts in their life (type: "concept")
   Node labels: 1–4 words, lowercase, specific. Importance 0.1–1.0 (higher = more central to their life).

2. EDGES (connections between nodes):
   Use short verb phrases. Connect people to projects, values to goals, etc.

3. FACTS (structured key/value facts):
   Name, location, occupation, age, key projects, family members, health goals, etc.
   Use simple string values. E.g. {"name": "Sadeq", "location": "Bahrain", "business": "The Tavern"}

4. PERSONALITY_CONTEXT (a 3–5 sentence prose summary):
   Write as if briefing Kai on who this person is — their essence, what drives them,
   what kind of conversations they want, and what Kai should always keep in mind.
   Write in second person: "The user is..." or "Sadeq is..."

Return ONLY valid JSON:
{
  "nodes": [{"label": "string", "type": "string", "importance": 0.0}],
  "edges": [{"from": "label", "to": "label", "relation": "string", "strength": 0.0}],
  "facts": {"key": "value"},
  "personality_context": "string"
}''';

    try {
      final response = await _dio.post(
        'https://api.openai.com/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': 'gpt-4o',       // use 4o for richer extraction on dense text
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {
              'role': 'user',
              'content':
                  'Here are my ChatGPT memories. Extract everything:\n\n$rawText'
            },
          ],
          'max_tokens': 3000,
          'temperature': 0.3,
          'response_format': {'type': 'json_object'},
        },
      );

      final raw =
          (response.data['choices'] as List)[0]['message']['content'] as String? ??
              '{}';
      final _u = response.data['usage'];
      if (_u != null) UsageTrackingService.trackOpenAI(
        model: 'gpt-4o', inputTokens: _u['prompt_tokens'] as int? ?? 0,
        outputTokens: _u['completion_tokens'] as int? ?? 0, operation: 'memory_import',
      ).catchError((_) {});
      final json = jsonDecode(raw) as Map<String, dynamic>;

      return {
        'nodes': (json['nodes'] as List? ?? [])
            .map((n) => Map<String, dynamic>.from(n as Map))
            .toList(),
        'edges': (json['edges'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        'facts': Map<String, dynamic>.from(json['facts'] as Map? ?? {}),
        'personality_context':
            json['personality_context'] as String? ?? '',
      };
    } catch (e) {
      print('⚠️ [Import] GPT extraction failed: $e');
      return null;
    }
  }

  // ── Knowledge graph merge ──────────────────────────────────────────────────

  Future<Map<String, int>> _mergeKnowledgeGraph(
    String personaId,
    List<Map<String, dynamic>> newNodes,
    List<Map<String, dynamic>> newEdges,
  ) async {
    final ref =
        KaiDb.instance.ref('knowledge_graph/$personaId');
    final snap = await ref.get();

    List<dynamic> nodes = [];
    List<dynamic> edges = [];

    final snapValue = snap.value;
    if (snap.exists && snapValue is Map) {
      nodes = List.from(_asList(snapValue['nodes']));
      edges = List.from(_asList(snapValue['edges']));
    }

    // Index existing by label
    final labelToNode = <String, Map<String, dynamic>>{};
    for (final n in nodes) {
      final m = Map<String, dynamic>.from(n as Map);
      labelToNode[(m['label'] as String).toLowerCase()] = m;
    }

    int added = 0;
    final resolvedIds = <String, String>{};

    for (final raw in newNodes) {
      final label = (raw['label'] as String? ?? '').toLowerCase().trim();
      if (label.isEmpty) continue;

      final existing = labelToNode[label];
      if (existing != null) {
        // Boost importance on re-confirmation from external source
        final old = (existing['importance'] as num?)?.toDouble() ?? 0.5;
        existing['importance'] = (old + 0.1).clamp(0.1, 1.0);
        existing['metadata'] = {
          ...(existing['metadata'] as Map? ?? {}),
          'chatgptConfirmed': true,
          'lastImport': DateTime.now().millisecondsSinceEpoch,
        };
        resolvedIds[label] = existing['id'] as String;
      } else {
        final id = _genId();
        final node = {
          'id': id,
          'label': label,
          'type': raw['type'] ?? 'concept',
          'importance': (raw['importance'] as num?)?.toDouble() ?? 0.6,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'metadata': {
            'source': 'chatgpt_import',
            'importedAt': DateTime.now().millisecondsSinceEpoch,
          },
          'x': 0.0,
          'y': 0.0,
        };
        nodes.add(node);
        labelToNode[label] = node;
        resolvedIds[label] = id;
        added++;
      }
    }

    int edgesAdded = 0;
    for (final raw in newEdges) {
      final fromLabel = (raw['from'] as String? ?? '').toLowerCase().trim();
      final toLabel = (raw['to'] as String? ?? '').toLowerCase().trim();
      final fromId =
          resolvedIds[fromLabel] ?? labelToNode[fromLabel]?['id'] as String?;
      final toId =
          resolvedIds[toLabel] ?? labelToNode[toLabel]?['id'] as String?;

      if (fromId == null || toId == null) continue;

      final exists = edges.any((e) {
        final m = e as Map;
        return m['fromId'] == fromId && m['toId'] == toId;
      });

      if (!exists) {
        edges.add({
          'fromId': fromId,
          'toId': toId,
          'type': 'related',
          'strength': (raw['strength'] as num?)?.toDouble() ?? 0.6,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'label': raw['relation'] ?? 'relates to',
        });
        edgesAdded++;
      }
    }

    await ref.update({
      'nodes': nodes,
      'edges': edges,
      'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      'lastChatGPTImport': DateTime.now().millisecondsSinceEpoch,
    });

    return {'added': added, 'edges': edgesAdded};
  }

  // ── Personality context ────────────────────────────────────────────────────

  Future<void> _writePersonalityContext(
      String personaId, String context) async {
    await KaiDb.instance
        .ref('kai/$personaId/personality/chatgpt_context')
        .set({
      'text': context,
      'importedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── Core facts ─────────────────────────────────────────────────────────────

  Future<void> _writeCoreFacts(
      String personaId, Map<String, dynamic> facts) async {
    if (facts.isEmpty) return;
    await KaiDb.instance
        .ref('kai/$personaId/core_facts')
        .update({
      ...facts,
      'lastImport': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _genId() {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final rand = List.generate(8, (i) => (DateTime.now().microsecond * (i + 1)) % 16)
        .map((n) => n.toRadixString(16))
        .join();
    return '$ts$rand';
  }
}
