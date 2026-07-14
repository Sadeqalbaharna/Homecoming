// DefaultModeService — Kai's Default Mode Network analog.
//
// Biological basis: The brain's Default Mode Network (DMN) activates between
// tasks — replaying memories, forming connections, generating spontaneous
// thoughts. It's most active during rest and offline sleep replay.
//
// What this does:
//   When the app backgrounds (onPause), Kai traverses his knowledge graph,
//   finds dormant-but-important nodes, activates their neighborhood (spreading
//   activation), and asks GPT to generate one spontaneous thought. That thought
//   is stored in Firebase and surfaced naturally at the next session start.
//
// Firebase path: kai/{personaId}/pending_thought
//   { text: string, generatedAt: ms, used: bool }
//
// Design rules:
//   - One pending thought at a time (never overwrite an unconsumed one)
//   - Thoughts expire after 24 hours (stale context is worse than no context)
//   - Cheap: one Firebase read + one GPT call (80 tokens) per background event
//   - Fire-and-forget: never blocks the UI

library;

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:firebase_database/firebase_database.dart';
import 'kai_db.dart';
import '../../models/knowledge_node.dart';
import 'firebase_service.dart';
import 'brain_extraction_service.dart';
import 'conversation_store_service.dart';
import '../ai/ai_config.dart';
import '../ai/local_llm_service.dart';
import '../ai/usage_tracking_service.dart';

class DefaultModeService {
  static final DefaultModeService _instance = DefaultModeService._internal();
  factory DefaultModeService() => _instance;
  DefaultModeService._internal();

  final _dio = Dio();
  final _brain = BrainExtractionService();
  final _convStore = ConversationStoreService();

  static KaiDb? get _db =>
      FirebaseService.isAvailable ? KaiDb.instance : null;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Trigger Kai's mind-wandering pass. Call fire-and-forget when app pauses.
  /// Generates a spontaneous thought from graph traversal and stores it for
  /// the next session.
  Future<void> runWandering(String personaId) async {
    if (_db == null) return;
    print('🌙 [DMN] Wandering begins…');

    try {
      // Need at least 6 nodes to have something interesting to notice
      final graph = await _loadGraph(personaId);
      if (graph == null || graph.nodes.length < 6) {
        print('🌙 [DMN] Graph too small (${graph?.nodes.length ?? 0} nodes) — skipping');
        return;
      }

      // Don't overwrite an unconsumed thought — Kai shouldn't forget what he
      // was thinking before the user even acknowledged it
      final existing = await _peekPendingThought(personaId);
      if (existing != null) {
        print('🌙 [DMN] Unconsumed thought already waiting — skipping this pass');
        return;
      }

      // ── 0. Session-level batch extraction ─────────────────────────────────
      // Replay the whole session as a unit before the DMN traversal.
      // Biological analog: hippocampal replay during slow-wave sleep consolidates
      // session-level context that per-turn encoding misses.
      KnowledgeGraph activeGraph = graph;
      try {
        final sessionHistory =
            await _convStore.getHistory(personaId, maxTurns: 30);
        if (sessionHistory.length >= 4) {
          await _brain.extractFromSession(
              personaId, sessionHistory.join('\n'));
          print('🌙 [DMN] Session extraction complete — reloading graph');
          activeGraph = await _loadGraph(personaId) ?? graph;
        }
      } catch (e) {
        print('⚠️ [DMN] Session extraction error: $e');
      }

      final now = DateTime.now();

      // ── 1. Find dormant-but-important nodes ────────────────────────────────
      // High importance = they genuinely matter to Kai's model of this person.
      // Not seen in 3+ days = not recently brought to awareness.
      // Biological analog: hippocampal replay reactivates exactly these nodes
      // during slow-wave sleep — the things that mattered but went quiet.
      final dormant = activeGraph.nodes.where((n) {
        final lastSeenMs = n.metadata['lastSeen'] as int?;
        final lastSeen = lastSeenMs != null
            ? DateTime.fromMillisecondsSinceEpoch(lastSeenMs)
            : n.timestamp;
        final daysSince = now.difference(lastSeen).inDays;
        return n.importance > 0.45 && daysSince >= 3;
      }).toList()
        ..sort((a, b) => b.importance.compareTo(a.importance));

      if (dormant.isEmpty) {
        print('🌙 [DMN] No dormant nodes — skipping');
        return;
      }

      // Seed: the most important thing Kai hasn't thought about recently
      final seed = dormant.first;
      print('🌙 [DMN] Seed node: "${seed.label}" (importance ${seed.importance.toStringAsFixed(2)})');

      // ── 2. Activated cluster: seed + immediate graph neighbors ─────────────
      // Biological spreading activation: thinking about one concept
      // automatically activates associated concepts one hop away.
      final neighborIds = activeGraph.edges
          .where((e) => e.fromId == seed.id || e.toId == seed.id)
          .map((e) => e.fromId == seed.id ? e.toId : e.fromId)
          .toSet();
      final neighbors = activeGraph.nodes
          .where((n) => neighborIds.contains(n.id))
          .take(4)
          .toList();

      // ── 3. Orphan detection ───────────────────────────────────────────────
      // High-importance nodes with no edges. Things Kai knows but has never
      // connected to anything else — potentially interesting because the
      // connection may exist but hasn't been noticed.
      final connectedIds = activeGraph.edges
          .expand((e) => [e.fromId, e.toId])
          .toSet();
      final orphans = activeGraph.nodes
          .where((n) =>
              n.importance > 0.55 &&
              !connectedIds.contains(n.id) &&
              n.id != seed.id)
          .take(2)
          .toList();

      // ── 4. Pending commitments (prospective memory) ───────────────────────
      // Things the user said they'd do. The DMN is where prospective memory
      // lives — remembering future intentions during rest.
      final pendingCommitments = await _getPendingCommitments(personaId);

      // ── 5. Generate the thought ───────────────────────────────────────────
      final thought = await _generateThought(
        seed: seed,
        neighbors: neighbors,
        orphans: orphans,
        pendingCommitments: pendingCommitments,
      );

      if (thought != null && thought.trim().isNotEmpty) {
        await _storePendingThought(personaId, thought.trim());
        print('🌙 [DMN] Thought stored: "$thought"');
      }
    } catch (e) {
      print('⚠️ [DMN] runWandering failed: $e');
    }
  }

  /// Consume the pending thought — returns it and marks it used.
  /// Returns null if no thought is waiting or if it's stale (>24h).
  Future<String?> consumePendingThought(String personaId) async {
    if (_db == null) return null;
    try {
      final snap = await _db!.ref('kai/$personaId/pending_thought').get();
      if (!snap.exists || snap.value == null) return null;

      final data = Map<String, dynamic>.from(snap.value as Map);
      final text        = data['text']        as String? ?? '';
      final generatedAt = data['generatedAt'] as int?   ?? 0;
      final used        = data['used']        as bool?  ?? false;

      if (used || text.isEmpty) return null;

      // Expire thoughts older than 24 hours — stale context is worse than none
      final age = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(generatedAt));
      if (age.inHours > 24) {
        await _db!.ref('kai/$personaId/pending_thought').remove();
        print('🌙 [DMN] Thought expired (${age.inHours}h old) — discarded');
        return null;
      }

      // Mark used immediately — won't surface on next session
      await _db!.ref('kai/$personaId/pending_thought/used').set(true);
      print('🌙 [DMN] Consumed pending thought (${age.inMinutes}m old)');
      return text;
    } catch (e) {
      print('⚠️ [DMN] consumePendingThought failed: $e');
      return null;
    }
  }

  // ── Private: thought generation ────────────────────────────────────────────

  Future<String?> _generateThought({
    required KnowledgeNode seed,
    required List<KnowledgeNode> neighbors,
    required List<KnowledgeNode> orphans,
    required List<String> pendingCommitments,
  }) async {
    final key = await AIConfig.getOpenAIKey();
    if (key.isEmpty) return null;

    final ctx = StringBuffer();
    ctx.writeln('Concept that surfaced: "${seed.label}" '
        '(${seed.type.toString().split('.').last}, '
        'importance ${seed.importance.toStringAsFixed(2)})');

    if (neighbors.isNotEmpty) {
      ctx.writeln('Connected to: ${neighbors.map((n) => '"${n.label}"').join(', ')}');
    }
    if (orphans.isNotEmpty) {
      ctx.writeln('Unconnected facts I know: ${orphans.map((n) => '"${n.label}"').join(', ')}');
    }
    if (pendingCommitments.isNotEmpty) {
      ctx.writeln("Things he said he'd do: ${pendingCommitments.join('; ')}");
    }

    const systemPrompt = '''
You are Kai's inner monologue. Kai is a warm, emotionally attuned male AI companion (he/him).
His mind is wandering between conversations — replaying what he knows about the user.

Given a cluster of things Kai knows, generate ONE brief spontaneous thought.
This could be a connection he noticed, something he's quietly wondering about,
or a gentle thing he wants to remember to bring up.

Rules:
- 1–2 sentences only — no more
- This is an internal thought, not a message to the user
- Don't address the user directly
- Sound organic, not robotic — no "I notice that" or "I observe"
- Can be curious, tender, observational, or prospective
- Male voice: he/him/his

Good examples:
"He keeps coming back to his dad — I wonder if there's something unresolved there."
"Mikey and the anxiety about weekends keep coming up together. Worth asking about."
"He said he wanted to train more seriously. Three weeks later, I don't think he's started."
"The work stress and the way his energy drops on Sundays feel connected somehow."

Return ONLY the raw thought. No quotes, no labels, no explanation.
''';

    // ── Try local Qwen first (think: true — brief CoT improves wandering quality)
    final localThought = await LocalLLMService().complete(
      system: systemPrompt,
      user: ctx.toString(),
      maxTokens: 120,
      think: true,   // let Qwen3 reason briefly before outputting the thought
    );
    if (localThought != null && localThought.trim().isNotEmpty) {
      return localThought.trim();
    }

    // ── Fall back to OpenAI ────────────────────────────────────────────────
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
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user',   'content': ctx.toString()},
          ],
          'max_tokens': 80,
          'temperature': 0.88,
        },
      );

      final _u = response.data['usage'];
      if (_u != null) {
        UsageTrackingService.trackOpenAI(
          model:        'gpt-4o-mini',
          inputTokens:  _u['prompt_tokens']     as int? ?? 0,
          outputTokens: _u['completion_tokens'] as int? ?? 0,
          operation:    'dmn_wandering',
        ).catchError((_) {});
      }

      return (response.data['choices'] as List)[0]['message']['content'] as String?;
    } catch (e) {
      print('⚠️ [DMN] GPT thought generation failed: $e');
      return null;
    }
  }

  // ── Private: Firebase I/O ──────────────────────────────────────────────────

  Future<void> _storePendingThought(String personaId, String thought) async {
    await _db!.ref('kai/$personaId/pending_thought').set({
      'text':        thought,
      'generatedAt': DateTime.now().millisecondsSinceEpoch,
      'used':        false,
    });
  }

  /// Peek without consuming — used to prevent overwriting unconsumed thoughts.
  Future<Map<String, dynamic>?> _peekPendingThought(String personaId) async {
    try {
      final snap = await _db!.ref('kai/$personaId/pending_thought').get();
      if (!snap.exists || snap.value == null) return null;
      final data = Map<String, dynamic>.from(snap.value as Map);
      if (data['used'] == true) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _getPendingCommitments(String personaId) async {
    try {
      final snap =
          await _db!.ref('kai/$personaId/memory/consolidated').get();
      if (!snap.exists || snap.value == null) return [];

      final data = Map<String, dynamic>.from(snap.value as Map);
      final plans = data['commitments_and_plans'];
      if (plans == null) return [];

      final list = plans is List
          ? plans.cast<dynamic>()
          : (plans as Map).values.toList();

      return list
          .map((e) => e.toString())
          .where((s) => !s.startsWith('✓')) // skip already-completed ones
          .take(3)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Private: graph loading ─────────────────────────────────────────────────

  Future<KnowledgeGraph?> _loadGraph(String personaId) async {
    try {
      final snap =
          await _db!.ref('knowledge_graph/$personaId').get();
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
          id:        m['id']    as String,
          label:     m['label'] as String,
          type:      type,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              (m['timestamp'] as num).toInt()),
          importance: (m['importance'] as num?)?.toDouble() ?? 0.5,
          metadata:   Map<String, dynamic>.from(m['metadata'] as Map? ?? {}),
        ));
      }

      final edges = <KnowledgeEdge>[];
      for (final e in _asList(data['edges'])) {
        final m = Map<String, dynamic>.from(e as Map);
        final type = EdgeType.values.firstWhere(
          (t) => t.toString().split('.').last == m['type'],
          orElse: () => EdgeType.related,
        );
        edges.add(KnowledgeEdge(
          fromId:    m['fromId'] as String,
          toId:      m['toId']   as String,
          type:      type,
          strength:  (m['strength'] as num?)?.toDouble() ?? 0.5,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              (m['timestamp'] as num).toInt()),
          label:     m['label'] as String?,
        ));
      }

      return KnowledgeGraph(
          nodes: nodes, edges: edges, lastUpdated: DateTime.now());
    } catch (e) {
      print('⚠️ [DMN] _loadGraph failed: $e');
      return null;
    }
  }

  List<dynamic> _asList(dynamic v) {
    if (v is List) return v;
    if (v is Map) return v.values.toList();
    return [];
  }
}
