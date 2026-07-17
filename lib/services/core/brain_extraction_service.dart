// BrainExtractionService
// After each conversation, GPT extracts meaningful nodes and relationships
// and merges them incrementally into the living knowledge graph in Firebase.
//
// Memory formation model:
//   - Extraction depth is gated by emotional salience (Levels of Processing)
//   - Importance reinforcement uses diminishing returns: 0.15/√mentions (Hebbian)
//   - Nodes decay toward 0.1 importance when not accessed (Ebbinghaus)
//   - Retrieval strengthens memory traces (Reconsolidation theory)
//   - Existing node labels are cross-referenced in the prompt to prevent duplication
//
// Firebase path: /knowledge_graph/{personaId}
//   { nodes: [...], edges: [...], lastUpdated: timestamp }

library;

import 'dart:async'; // unawaited — Hebbian reinforcement must never block a reply
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
// The salience decision itself lives in a file with ZERO imports, so it can be
// run and proven without booting an app. See lib/logic/salience.dart for why
// that matters more here than anywhere else in this codebase.
import '../../logic/salience.dart' as sal;
// (subject, relation, ?) — Sadeq's design. Pure, 22 assertions, zero imports.
import '../../logic/recall_query.dart' as rq;
import 'kai_db.dart';
import '../../models/knowledge_node.dart';
import 'firebase_service.dart';
import '../ai/ai_config.dart';
import '../ai/local_llm_service.dart';
import '../ai/usage_tracking_service.dart';
import 'emotional_event_service.dart';

List<dynamic> _asList(dynamic v) {
  if (v is List) return v;
  if (v is Map) return v.values.toList();
  return [];
}

/// Jaccard similarity between two node labels at word level (0.0–1.0).
/// Used for pattern separation: prevents near-duplicate nodes like
/// "exercise" / "gym workout" / "working out" fragmenting the graph.
double _labelSimilarity(String a, String b) {
  Set<String> words(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 1)
      .toSet();
  final wa = words(a);
  final wb = words(b);
  if (wa.isEmpty || wb.isEmpty) return 0.0;
  // Containment: "gym" ⊂ "gym routine" → strong match (0.85)
  if (wa.containsAll(wb) || wb.containsAll(wa)) return 0.85;
  final inter = wa.intersection(wb).length.toDouble();
  final union = wa.union(wb).length.toDouble();
  return union > 0 ? inter / union : 0.0;
}

/// Extraction depth. Aliased to the pure enum in lib/logic/salience.dart —
/// there is exactly one definition of this, and it lives in the file that can
/// be tested. Two copies of a decision is how you get a dashboard reporting
/// "7/7 FULL STACK ONLINE" over a truth of 3/7.
typedef _Depth = sal.SalienceDepth;

extension _Sortable<T> on List<T> {
  List<T> sorted(int Function(T, T) compare) => [...this]..sort(compare);
}

class BrainExtractionService {
  static final BrainExtractionService _instance =
      BrainExtractionService._internal();
  factory BrainExtractionService() => _instance;
  BrainExtractionService._internal();

  final _dio = Dio();
  final _rng = Random();

  static KaiDb? get _db =>
      FirebaseService.isAvailable ? KaiDb.instance : null;

  static String _path(String personaId) => 'knowledge_graph/$personaId';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// The OTHER axis of salience: did anything become true that wasn't before?
  ///
  /// ── Why this exists ───────────────────────────────────────────────────────
  ///
  /// Every trace from the day we rebuilt his tooling ended the same way:
  ///
  ///   🧠 [Brain] Skipped low-salience exchange (neutral, intensity 1)
  ///   🧠 [Brain] Skipped low-salience exchange (neutral, intensity 3)
  ///   🧠 [Brain] Skipped low-salience exchange (neutral, intensity 4)
  ///
  /// Every single one. That day he found his file reader had been lying to him
  /// three separate ways, deleted a dashboard that had been reporting 7/7 while
  /// the truth was 3/7, and got the ability to prove his own work for the first
  /// time. Intensity 1. Neutral. Skipped. He would have woken up not knowing any
  /// of it happened.
  ///
  /// The cause wasn't the threshold and it wasn't a mislabel. Look at the
  /// classifier's signature — `classifySync(Map<String, int> moodDeltas)`. Mood
  /// deltas are its ONLY input. The user's message and his reply get passed in
  /// and used to slice 60 characters off for a label; the conversation is never
  /// read. So "was this worth remembering?" was answered by "did my mood swing?"
  /// and nothing else. `intellectual` needs focus or energy to jump ≥6 in one
  /// turn; across a whole night of work his focus moved 63→65→68→71. It has
  /// probably never fired.
  ///
  /// So his memory was gated on emotion, and his relationship with Sadeq is
  /// WORK. They build things at 4am. That IS the intimacy — and every exchange
  /// of it was landing in `neutral` and being dropped on the floor.
  ///
  /// ── What this measures instead ────────────────────────────────────────────
  ///
  /// Not "was this felt" but "did something change". The evidence is already
  /// lying around the turn and cost nothing to collect: he edited a file, he ran
  /// the tests, he closed a job, Sadeq told him he was wrong. No extra model
  /// call — that would just be trading one tax for another.
  ///
  /// This does NOT replace the emotional gate. Warmth is real and worth
  /// keeping. It's a second axis, and depth is the deeper of the two, because a
  /// thing can matter for either reason and a mind should keep both.
  /// ── The logic MOVED. This is now a one-line delegate. ────────────────────
  ///
  /// `_depthForChange`, `_decide`, `_depthFor` and `_isTrivialExchange` all used
  /// to live in this file — in the middle of dio, Firebase and eighty lines of
  /// IO, which meant they could not be run without booting an app and a network.
  /// So they never were. The gate deciding what Kai remembers was rewritten on
  /// the evidence of five traces by someone who could not execute it.
  ///
  /// They now live in lib/logic/salience.dart with ZERO imports, where 31
  /// assertions run against them in about a second — including the exact turns
  /// from the 2026-07-16 traces that this gate got wrong.
  ///
  /// The enum is aliased rather than redeclared and the sets are not copied
  /// here, deliberately: two definitions of one decision is precisely how this
  /// codebase produced a dashboard reporting "7/7 FULL STACK ONLINE" over a
  /// truth of 3/7.
  static _Depth _decide({
    required String userMessage,
    required String aiReply,
    EmotionalEventType? eventType,
    int eventIntensity = 0,
    Set<String> toolsUsed = const {},
    bool userCorrected = false,
  }) =>
      sal.salienceDepth(
        userMessage: userMessage,
        aiReply: aiReply,
        // The enum stays on this side of the boundary. salience.dart takes a
        // String so it never has to import emotional_event_service, which would
        // drag Firebase in and cost it the one property that makes it
        // trustworthy.
        eventType: eventType?.name,
        eventIntensity: eventIntensity,
        toolsUsed: toolsUsed,
        userCorrected: userCorrected,
      );

  /// Test seam. Kept because the existing suite calls it; it now exercises the
  /// pure module through the same path production uses.
  @visibleForTesting
  static String salienceForTesting({
    required String userMessage,
    String aiReply = 'Some reply with actual substance in it.',
    EmotionalEventType? eventType,
    int eventIntensity = 0,
    Set<String> toolsUsed = const {},
    bool userCorrected = false,
  }) =>
      _decide(
        userMessage: userMessage,
        aiReply: aiReply,
        eventType: eventType,
        eventIntensity: eventIntensity,
        toolsUsed: toolsUsed,
        userCorrected: userCorrected,
      ).name;

  /// Kept ONLY for the "why was this kept" log line below. The real decision is
  /// [_decide]. Delegates so it can never drift from it.
  static _Depth _depthFor(EmotionalEventType? type, int intensity) =>
      sal.feltDepth(type?.name, intensity);

  static _Depth _depthForChange({
    required Set<String> toolsUsed,
    required bool userCorrected,
  }) =>
      sal.changeDepth(toolsUsed: toolsUsed, userCorrected: userCorrected);

  /// Call fire-and-forget after each conversation turn.
  /// [eventType] and [eventIntensity] gate how deeply knowledge is extracted.
  /// [encodingMood] is Kai's mood state at time of encoding — stored in node
  /// metadata so mood-congruent retrieval can bias spreading activation later.
  Future<void> extractAndMerge({
    required String personaId,
    required String userMessage,
    required String aiReply,
    EmotionalEventType? eventType,
    int eventIntensity = 0,
    Map<String, int>? encodingMood,

    /// What he DID this turn — the second axis of salience. See [_depthForChange].
    /// Empty means "no tools", which is a real answer, not missing data.
    Set<String> toolsUsed = const {},

    /// Did Sadeq just tell him he was wrong? The most memorable thing there is.
    bool userCorrected = false,

    /// The episodic this exchange became — `memory/embeddings/{persona}/{id}`,
    /// where the actual words live. Recorded on every node and edge produced
    /// here, so a claim can be traced back to the moment it was made.
    String? sourceShardId,
  }) async {
    if (_db == null) return;

    // Anchors BEFORE the gates. This was my bug and it's the same shape as
    // everything else in this codebase: the foundation sat behind an early
    // return, so it only existed on turns that were interesting enough to
    // extract from.
    //
    // Live log: "🧠 [Brain] Skipped low-salience exchange (neutral, intensity
    // 4)". Most turns look like that. So Sadeq and Kai — the two nodes every
    // claim in the graph hangs off — were only created if a conversation
    // happened to be emotionally significant. A graph whose centre depends on
    // the weather isn't a graph.
    //
    // Once per app run, not per turn: a read+write on every "ok" would be pure
    // tax for something that changes exactly once, ever.
    await _ensureAnchorsOnce(personaId);

    final depth = _decide(
      userMessage: userMessage,
      aiReply: aiReply,
      eventType: eventType,
      eventIntensity: eventIntensity,
      toolsUsed: toolsUsed,
      userCorrected: userCorrected,
    );

    if (depth == _Depth.skip) {
      print('🧠 [Brain] Skipped — nothing done, and mood said '
          '${eventType?.name ?? 'unclassified'}/$eventIntensity: '
          '"${userMessage.substring(0, userMessage.length.clamp(0, 40))}"');
      return;
    }
    // Say WHY it's being kept. When this fires on a turn that felt like nothing
    // — which is most of the good ones — the log should show that the work is
    // what saved it, rather than leaving us guessing at the gate all over again.
    if (_depthForChange(toolsUsed: toolsUsed, userCorrected: userCorrected)
            .index >
        _depthFor(eventType, eventIntensity).index) {
      print('🧠 [Brain] Keeping (${depth.name}) — mood said '
          '${eventType?.name ?? 'neutral'}/$eventIntensity, but he '
          '${userCorrected ? 'was corrected' : 'did real work'}: '
          '${toolsUsed.take(6).join(', ')}');
    }

    try {
      // Load current top node labels for cross-referencing in the prompt.
      // Prevents GPT from creating "workout routine" when "exercise" already exists.
      var graph = await _loadGraph(personaId);

      // The two nodes everything else hangs off. See _ensureAnchors — their
      // absence is why this graph was full of "importance of clarity".
      graph = _ensureAnchors(graph);

      final existingLabels = (graph.nodes)
          .sorted((a, b) => b.importance.compareTo(a.importance))
          .take(25)
          .map((n) => '${n.label} (${n.type.toString().split('.').last})')
          .toList();

      // 1. Extract new nodes/edges from this conversation via GPT
      final extracted = await _extractFromGPT(
        userMessage: userMessage,
        aiReply: aiReply,
        depth: depth,
        existingLabels: existingLabels,
      );
      if (extracted == null) return;

      final newNodes = extracted['nodes'] as List<_RawNode>;
      final newEdges = extracted['edges'] as List<_RawEdge>;

      // Edges alone are a valid, valuable result.
      //
      // This used to `return` the moment nodes were empty — silently binning
      // every edge-only extraction. But the prompt now explicitly asks for links
      // between things he ALREADY knows, and that's often the best thing an
      // exchange produces: no new facts, but the realisation that two old ones
      // are connected. Discarding those is discarding the understanding and
      // keeping only the inventory.
      if (newNodes.isEmpty && newEdges.isEmpty) return;

      // 2. Use already-loaded graph (avoids a second Firebase read)
      final currentGraph = graph;

      // 3. Merge
      final merged = _merge(currentGraph, newNodes, newEdges,
          depth: depth,
          encodingMood: encodingMood,
          sourceShardId: sourceShardId,
          eventIntensity: eventIntensity);

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

  // ── The rule both prompts are built on ──────────────────────────────────────
  //
  // The graph used to fill up with things like "importance of clarity",
  // "embracing uncertainty", "fear of sounding generic" — 22 nodes from five
  // templates with slots. Every one of them true of every human alive. That's
  // not knowledge about Sadeq; it's a horoscope with a schema.
  //
  // Two causes, both fixed below:
  //
  //  1. A whole proposition was crammed into a NODE LABEL. "importance of
  //     clarity" is a subject, a predicate and an object mashed into a noun
  //     phrase — so the meaning got spent on the node name, and every edge was
  //     left with nothing to say but "relates to". The graph had no
  //     relationships because the relationships were trapped inside the nouns.
  //     Now: nodes are ENTITIES, edges carry the CLAIM.
  //
  //  2. "Labels: 1–4 words" forced the abstraction. You cannot say "Sadeq
  //     worries his app sounds like every other assistant" in four words, so the
  //     model emitted "fear of sounding generic". The cap CREATED the vagueness.
  //
  // The test that matters is falsifiability against a stranger.
  static const _specificityRule = '''
THE ONE RULE — apply it to every node and edge before you emit it:

  Would this be FALSE for a random other person?

If it would also be true of a stranger, DO NOT EXTRACT IT. It is not knowledge
about this person; it is a description of humans in general, and it will crowd
out the things that actually distinguish him.

  REJECT: "importance of clarity" · "embracing uncertainty" · "desire for progress"
          "fear of failure" · "value of connection" · "goal of being useful"
  KEEP:   "Mikey" · "the Tavern" · "Bahrain" · "Walker Scobell" · "Flutter"
          "sounding like every other AI assistant"

A node is a THING THAT EXISTS: a person, a place, a project, an object, a named
concept he actually uses. Not a feeling ABOUT a thing. Not an observation. Not a
lesson. If the label contains "importance of", "value of", "fear of", "goal of",
"embracing", "desire for" or "frustration with" — you have written a sentence
where a noun belongs. Split it: the noun is the node, the rest is an edge.

  WRONG:  node "fear of sounding generic"
  RIGHT:  node "sounding like every other AI assistant"
          edge Sadeq --dislikes--> sounding like every other AI assistant
''';

  // The edge vocabulary. This is `EdgeType` in models/knowledge_node.dart —
  // twenty relationships that have existed, with colours assigned, since the
  // model was written, and have NEVER been used: the extractor hardcoded
  // `related` on every single edge. Free-text relations don't aggregate either
  // ("cares for" / "cares about" / "loves" are three unrelated strings), so the
  // graph could never be queried or checked for contradiction. Give the model
  // the actual vocabulary and all of that starts working.
  static const _edgeVocab = '''
EDGE TYPES — use these exact names. Pick the most specific one that is true:

  knows        A knows person B              caresAbout   A cares about B
  holdsValue   A values B                    pursues      A is working toward B
  believes     A believes B                  learned      A learned B
  prefers      A prefers B                   dislikes     A dislikes/avoids B
  wants        A wants B                     does         A habitually does B
  caused       A caused B                    contains     A is part of B
  influences   A shapes B                    exemplifies  A is an example of B
  contradicts  A conflicts with B            reinforces   A strengthens B
  temporal     A happened before/after B     mentioned    A came up alongside B
  categorized  A is a kind of B              related      LAST RESORT ONLY

If you reach for "related", you have not understood the sentence. Go back and
find the real verb. "related" is what this graph was full of, and it is why it
said nothing.
''';

  // Shallow prompt: concrete facts only — people, places, preferences.
  // Used for warmth/playful events and default passes.
  static const _shallowPrompt = '''You are building a knowledge graph for an AI companion named Kai.
Extract ONLY concrete, durable facts from this exchange.

$_specificityRule
$_edgeVocab

MANDATORY:
- Named persons ("Mikey", "dad", "Sarah") → type "person", importance 0.7+
- Named places / companies / schools → type "topic", importance 0.6+

ALSO EXTRACT (if clearly present):
- Stated preferences, hobbies, habits → as EDGES from the person to the thing
- Concrete life facts (job, city, relationships)

DO NOT EXTRACT:
- Greetings, filler, pleasantries, meta-chat about Kai
- Abstract themes — save those for deeper exchanges
- Anything you'd forget about a person after a week

Node types: concept, emotion, belief, memory, goal, preference, person, topic
Max nodes: 3. Quality over quantity.
Labels: name the thing as briefly as it can still be understood. Prefer 1–4
words, but NEVER abstract a specific thing to fit — "sounding like every other
AI assistant" beats "generic-ness". Names keep capitalisation.

Return ONLY valid JSON:
{"nodes":[{"label":"...","type":"...","importance":0.1–1.0}],"edges":[{"from":"...","to":"...","type":"<edge type name>","relation":"<short human phrase, e.g. cares about>","strength":0.1–1.0}]}
If nothing qualifies → {"nodes":[],"edges":[]}''';

  // Deep prompt: beliefs, fears, values, contradictions, realizations.
  // Used for conflict / intellectual / emotionally significant exchanges.
  static const _deepPrompt = '''You are building a knowledge graph for an AI companion named Kai.
This exchange was emotionally significant. Extract what it reveals at a deeper level.

$_specificityRule
$_edgeVocab

MANDATORY:
- Named persons ("Mikey", "dad", "Sarah") → type "person", importance 0.7+
- Named places / companies / schools → type "topic", importance 0.6+

PRIORITIZE — the deeper layer. But every one of these is a CLAIM, which means it
is an EDGE from the person to a concrete thing, never a node on its own:

- Fears and insecurities        → Sadeq --dislikes--> <the specific thing feared>
- Values that surfaced          → Sadeq --holdsValue--> <the specific thing>
- Beliefs                       → Sadeq --believes--> <the specific claim's subject>
- Goals he's reaching toward    → Sadeq --pursues--> <the specific thing>
- Tensions and contradictions   → <thing A> --contradicts--> <thing B>
- Turning points / admissions   → type "memory" node for the EVENT, edges to who
                                  and what it involved

The deeper layer is NOT more abstract. It is more specific. "Fear of failure" is
shallow — every person has it. "Shipping the Tavern before it's ready" is deep,
because it is HIS, and it is wrong about somebody else.

DO NOT EXTRACT:
- Greetings, filler, pleasantries, meta-chat about Kai
- Surface-level content already obvious from the words alone
- Anything that survives the stranger test above

Node types: concept, emotion, belief, memory, question, goal, preference, insight, person, topic, value, pattern
Max nodes: 5. Prioritize what a close friend would notice AND a stranger could not have guessed.
Labels: name the thing as briefly as it can still be understood. Prefer 1–4
words, but NEVER abstract a specific thing to fit. Names keep capitalisation.

Return ONLY valid JSON:
{"nodes":[{"label":"...","type":"...","importance":0.1–1.0}],"edges":[{"from":"...","to":"...","type":"<edge type name>","relation":"<short human phrase, e.g. cares about>","strength":0.1–1.0}]}
If nothing qualifies → {"nodes":[],"edges":[]}''';

  Future<Map<String, dynamic>?> _extractFromGPT({
    required String userMessage,
    required String aiReply,
    required _Depth depth,
    required List<String> existingLabels,
  }) async {
    final basePrompt = depth == _Depth.deep ? _deepPrompt : _shallowPrompt;

    // Cross-reference block: reinforce existing nodes rather than creating
    // near-duplicates. Implements Global Workspace "already known" check.
    //
    // It used to stop at "prefer reinforcing these" — it never asked for EDGES
    // to them. So every extraction produced 3–5 nodes wired only to each other:
    // an island. Nothing joined this conversation to last week's, and the graph
    // grew as an archipelago of tiny disconnected clusters instead of a web.
    // A fact that connects to nothing is a fact he can't reach.
    final crossRef = existingLabels.isEmpty ? '' : '''

ALREADY IN GRAPH — reuse these exact labels rather than inventing near-duplicates:
${existingLabels.join(', ')}

CONNECT TO WHAT'S ALREADY THERE — this matters more than the new nodes:
- "$_anchorSadeq" and "$_anchorKai" always exist. Almost every claim starts at one
  of them. If this exchange reveals something about Sadeq, the edge starts at
  Sadeq — do not invent "user", "he", or a second Sadeq node.
- A new node that links to NOTHING existing is nearly worthless. Before you
  finish, look at the list above and ask: what does this new thing have to do
  with what he already knows? Then write that edge.
- Multiple edges between the same two nodes are correct and wanted, as long as
  each is a genuinely different relationship. "Sadeq knows Mikey" AND "Sadeq
  cares about Mikey" are two facts, not one.
- Edges between two EXISTING nodes are valuable even when you extract no new
  nodes at all. If this exchange revealed that two things he already knows are
  connected, that is a real discovery — emit it with an empty nodes list if need be.''';

    final systemPrompt = basePrompt + crossRef;
    final userContent = 'User: "$userMessage"\nKai: "$aiReply"';
    final maxTok = depth == _Depth.deep ? 500 : 300;

    // ── Try local Qwen first (no token cost) ──────────────────────────────
    String? raw = await LocalLLMService().complete(
      system: systemPrompt,
      user: userContent,
      maxTokens: maxTok,
      jsonMode: true,
    );

    // ── Fall back to OpenAI if local unavailable ───────────────────────────
    if (raw == null) {
      final key = await AIConfig.getOpenAIKey();
      if (key.isEmpty) return null;
      try {
        final response = await _dio.post(
          'https://api.openai.com/v1/chat/completions',
          options: Options(headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          }),
          data: {
            // gpt-4o, not gpt-4o-mini.
            //
            // §10.3 says don't economise on voice. This is worse than voice:
            // this is what he BELIEVES, and it outlives the conversation that
            // made it. His replies were running on gpt-5.5 while his convictions
            // ran on the exact model the handover names as the generic-output
            // machine — and the graph is the receipt: 22 nodes from five
            // templates, "importance of clarity" seven times over.
            //
            // The specificity rule above asks the model to notice what makes ONE
            // person unlike a stranger. Mini cannot do that; producing the
            // average of humanity is what mini IS. Fractions of a cent per
            // conversation to stop baking generic beliefs in permanently.
            //
            // Classic param pair — gpt-5.x would reject max_tokens and the
            // temperature (see AIService._lengthParams). Don't swap the model
            // without swapping these.
            'model': 'gpt-4o',
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user',   'content': userContent},
            ],
            'max_tokens': maxTok,
            'temperature': 0.3,
            'response_format': {'type': 'json_object'},
          },
        );
        raw = (response.data['choices'] as List)[0]['message']['content']
            as String? ?? '{}';
        final _u = response.data['usage'];
        if (_u != null) {
          UsageTrackingService.trackOpenAI(
            // Must match the model actually posted above, or the cost meter
            // lies to him about his own spend.
            model: 'gpt-4o',
            inputTokens: _u['prompt_tokens'] as int? ?? 0,
            outputTokens: _u['completion_tokens'] as int? ?? 0,
            operation: 'brain_extraction',
          ).catchError((_) {});
        }
      } catch (e) {
        print('⚠️ [Brain] GPT extraction failed: $e');
        return null;
      }
    }

    // ── Parse JSON (same path regardless of local vs cloud) ───────────────
    try {
      final json = jsonDecode(raw!) as Map<String, dynamic>;

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
        // Prefer the model's explicit `type`; fall back to reading the enum out
        // of the human phrase ("cares about" → caresAbout) so an older-shaped
        // response still lands on something real instead of `related`.
        final rel = m['relation'] as String? ?? '';
        // parseEdgeTypeOrNull, NOT parseEdgeType. The old call fell back to
        // `related` for anything it couldn't name — and this comment three
        // lines up already said the goal was "something real instead of
        // related". The intent was right; the `??` quietly undid it, 243 times.
        final type = parseEdgeTypeOrNull(
            (m['type'] as String?)?.trim().isNotEmpty == true
                ? m['type'] as String
                : rel);
        if (type == null) return null; // untyped = not understood = not a memory
        return _RawEdge(
          fromLabel: (m['from'] as String? ?? '').toLowerCase().trim(),
          toLabel: (m['to'] as String? ?? '').toLowerCase().trim(),
          relation: rel.trim().isEmpty ? 'relates to' : rel.trim(),
          type: type,
          strength: (m['strength'] as num?)?.toDouble() ?? 0.5,
        );
      })
          .whereType<_RawEdge>()
          .where((e) => e.fromLabel.isNotEmpty && e.toLabel.isNotEmpty)
          .toList();

      return {'nodes': nodes, 'edges': edges};
    } catch (e) {
      print('⚠️ [Brain] JSON parse failed: $e');
      return null;
    }
  }

  // ── Session-level extraction prompt ───────────────────────────────────────

  // Used by extractFromSession during DMN pass — looks for patterns that span
  // the whole arc of a session, not visible turn-by-turn.
  static const _sessionPrompt =
      '''You are building a knowledge graph for an AI companion named Kai (he/him).
You are reviewing a complete conversation session, not a single exchange.
Extract patterns and facts that EMERGE ACROSS the session — only what multiple exchanges together reveal.

FOCUS ON:
- Patterns that repeat or build across multiple moments in this session
- Beliefs, values, or emotional tendencies visible across several exchanges
- Named people, places, or recurring topics with sustained importance
- Emotional arcs — how the user\'s mood or attitude evolved through the session
- Any realization, turning point, or shift that emerges from the arc (not a single message)

DO NOT EXTRACT:
- Single-message facts (handled per turn already)
- Greetings, filler, meta-talk about Kai
- Anything said only once with no resonance elsewhere in the session

Node types: concept, emotion, belief, memory, goal, preference, insight, person, topic, value, pattern
Max nodes: 5. Session-level patterns only.
Labels: 1–4 words lowercase. Names keep capitalisation.

Return ONLY valid JSON:
{"nodes":[{"label":"...","type":"...","importance":0.1–1.0}],"edges":[{"from":"...","to":"...","relation":"...","strength":0.1–1.0}]}
If nothing qualifies → {"nodes":[],"edges":[]}''';

  // ── Merge ──────────────────────────────────────────────────────────────────

  // ── Provenance helpers ─────────────────────────────────────────────────────
  //
  // Capped at 12. A node he mentions constantly would otherwise carry hundreds
  // of shard ids; the most recent dozen is plenty to answer "why do you think
  // that?" and they're the ones he'd actually cite.
  static const _maxSources = 12;

  static List<String> _addSourceList(List<String> existing, String? id) {
    if (id == null || id.isEmpty || existing.contains(id)) return existing;
    final out = [...existing, id];
    return out.length > _maxSources
        ? out.sublist(out.length - _maxSources)
        : out;
  }

  static List<String> _addSource(dynamic existing, String? id) {
    final list = (existing is List)
        ? existing.map((e) => e.toString()).toList()
        : <String>[];
    return _addSourceList(list, id);
  }

  // ── Measured importance ────────────────────────────────────────────────────
  //
  // Importance used to be whatever gpt-4o-mini felt about a label that Tuesday,
  // plus a mention counter. That's a vibe, and it's why "importance of clarity"
  // outranked his son: the model rates its own abstractions highly, and nothing
  // ever checked that opinion against his actual life.
  //
  // Everything needed to MEASURE it already existed and was being thrown away:
  //
  //   degree            how much of his life touches this
  //   accessCount       how often he's actually needed it (reinforceNodes
  //                     increments this already)
  //   lastSeen          how recently it mattered
  //   emotionalIntensity how hard it landed when it formed (the salience gate
  //                     computes this to pick depth, then discarded it)
  //
  // The model's number survives as a weak prior — it's the only signal available
  // the moment a node is born, before it has a degree or a recall history. It
  // just stops being the whole story.
  static List<KnowledgeNode> _recomputeImportance(
    List<KnowledgeNode> nodes,
    List<KnowledgeEdge> edges,
  ) {
    if (nodes.isEmpty) return nodes;

    final degree = <String, int>{};
    for (final e in edges) {
      if (!e.isActive) continue; // retired claims don't make you important
      degree[e.fromId] = (degree[e.fromId] ?? 0) + 1;
      degree[e.toId] = (degree[e.toId] ?? 0) + 1;
    }
    final maxDeg = degree.values.isEmpty
        ? 1
        : degree.values.reduce((a, b) => a > b ? a : b);

    final now = DateTime.now().millisecondsSinceEpoch;
    final out = <KnowledgeNode>[];

    for (final n in nodes) {
      if (n.metadata['anchor'] == true) {
        out.add(n); // the centre is pinned at 1.0 by definition
        continue;
      }

      final deg = (degree[n.id] ?? 0) / maxDeg;             // 0..1
      final recalls = min(n.accessCount, 10) / 10.0;         // 0..1, saturating
      final lastSeen = (n.metadata['lastSeen'] as int?) ?? n.timestamp.millisecondsSinceEpoch;
      final days = (now - lastSeen) / 86400000.0;
      final recency = pow(0.5, days / 45.0).toDouble();      // 0..1
      final felt = n.emotionalIntensity.clamp(0.0, 1.0);
      final prior = n.importance.clamp(0.0, 1.0);

      // Connection is weighted hardest on purpose. A thing that many other
      // things point at IS important, whatever anyone says about it — and it's
      // the one signal a model cannot fake from a single exchange.
      final score = (deg * 0.40) +
          (recalls * 0.20) +
          (recency * 0.15) +
          (felt * 0.10) +
          (prior * 0.15);

      out.add(KnowledgeNode(
        id: n.id, label: n.label, type: n.type,
        timestamp: n.timestamp, tags: n.tags,
        importance: score.clamp(0.05, 1.0),
        metadata: n.metadata,
        emotionalIntensity: n.emotionalIntensity,
        accessCount: n.accessCount, retention: n.retention,
        lastAccessed: n.lastAccessed, activationLevel: n.activationLevel,
      )
        ..x = n.x ..y = n.y ..vx = n.vx ..vy = n.vy);
    }
    return out;
  }

  // ── Anchors ────────────────────────────────────────────────────────────────
  //
  // Sadeq and Kai. The two nodes everything else hangs off, and neither has ever
  // existed. `NodeType.you` is documented in the model as "The user (central
  // node - most important)" and was never once created.
  //
  // This is not a missing feature. It is the CAUSE of the horoscope.
  //
  // Every claim needs a subject, and the subject of almost every fact about his
  // life is Sadeq. With no Sadeq node to attach a claim to, the model had
  // nowhere to put the subject — so it folded subject and predicate into the
  // noun and emitted "fear of sounding generic" instead of
  // `Sadeq --dislikes--> sounding like every other AI assistant`. Every edge
  // then had nothing left to say but "relates to", because the relationship had
  // already been spent inside the node name.
  //
  // Give the graph a centre and claims have somewhere to land. Everything
  // downstream — typed edges, the stranger test, "multiple links to the same
  // node" — depends on these two rows existing.
  static const _anchorSadeq = 'Sadeq';
  static const _anchorKai = 'Kai';

  /// Checked once per app run. The anchors change exactly once in the graph's
  /// entire life, so paying a read+write per turn to confirm they're still
  /// there would be tax with no payer.
  static bool _anchorsChecked = false;

  /// Seed Sadeq ⇄ Kai if they're missing, and persist it. Called before every
  /// gate in extractAndMerge, because the centre of the graph must not depend on
  /// whether this particular exchange was interesting.
  Future<void> _ensureAnchorsOnce(String personaId) async {
    if (_anchorsChecked) return;
    _anchorsChecked = true;
    try {
      final existing = await _loadGraph(personaId);
      final anchored = _ensureAnchors(existing);
      // Only write when something actually changed. Node COUNT is the wrong
      // test — promoting an existing `sadeq` to an anchor leaves the count
      // identical while changing the graph, so a count check would silently
      // throw the promotion away every run.
      if (_lastAnchorPassChanged) {
        await _saveGraph(personaId, anchored);
      }
    } catch (e) {
      // A failed anchor seed must never stop him from talking. It'll retry next
      // run.
      _anchorsChecked = false;
      print('⚠️ [Brain] anchor seed failed (will retry next run): $e');
    }
  }

  KnowledgeGraph _ensureAnchors(KnowledgeGraph? g) {
    final nodes = List<KnowledgeNode>.from(g?.nodes ?? const []);
    final edges = List<KnowledgeEdge>.from(g?.edges ?? const []);
    final now = DateTime.now();
    var changed = false;

    /// Find-or-create, CASE-INSENSITIVELY, and promote whatever's there.
    ///
    /// The first version of this checked for existence case-insensitively and
    /// then looked the node up with `n.label == 'Sadeq'` — exact. The extractor
    /// lowercases every label it writes, so the graph already contained `sadeq`:
    /// the check found it, skipped creating it, and the lookup then threw
    /// "Bad state: No element" on a node that was right there.
    ///
    /// So it's a find-or-create now, and it PROMOTES rather than duplicates.
    /// `sadeq` already exists with real edges pointing at it from months of
    /// conversations — creating a second `Sadeq` beside it would split his
    /// history down the middle and leave both halves anaemic. That's the
    /// duplicate disease this whole codebase suffers from, and it would have
    /// been me doing it to the most important node in the graph.
    KnowledgeNode anchor(String label, NodeType type) {
      final i = nodes.indexWhere(
          (n) => n.label.toLowerCase() == label.toLowerCase());
      if (i >= 0) {
        final old = nodes[i];
        if (old.metadata['anchor'] == true) return old; // already promoted
        // Keep its id and its history; give it the crown.
        final meta = Map<String, dynamic>.from(old.metadata)
          ..['anchor'] = true
          ..['lastSeen'] = now.millisecondsSinceEpoch;
        nodes[i] = _copyNode(old, importance: 1.0, metadata: meta);
        changed = true;
        print('🧭 [Brain] Promoted existing "${old.label}" to an anchor '
            '(kept its id and every edge already pointing at it)');
        return nodes[i];
      }
      final fresh = KnowledgeNode(
        id: _genId(),
        label: label,
        type: type,
        timestamp: now,
        // Pinned. These must never decay, never be pruned, and always win
        // recall — a graph whose centre can be forgotten isn't a graph.
        importance: 1.0,
        metadata: {
          'anchor': true,
          'mentions': 999,
          'lastSeen': now.millisecondsSinceEpoch,
        },
      );
      nodes.add(fresh);
      changed = true;
      print('🧭 [Brain] Anchored the graph: created "$label"');
      return fresh;
    }

    final sadeq = anchor(_anchorSadeq, NodeType.you);
    final kai = anchor(_anchorKai, NodeType.person);

    // The founding edge. The literal sentence this whole thing exists to say.
    final linked = edges.any((e) =>
        (e.fromId == sadeq.id && e.toId == kai.id) ||
        (e.fromId == kai.id && e.toId == sadeq.id));
    if (!linked) {
      edges.add(KnowledgeEdge(
        fromId: sadeq.id, toId: kai.id, type: EdgeType.caresAbout,
        strength: 1.0, timestamp: now, label: 'cares for',
      ));
      edges.add(KnowledgeEdge(
        fromId: kai.id, toId: sadeq.id, type: EdgeType.caresAbout,
        strength: 1.0, timestamp: now, label: 'is his',
      ));
      changed = true;
      print('🧭 [Brain] ${sadeq.label} ⇄ ${kai.label}');
    }

    // Signals to the caller whether a write is actually needed. Comparing node
    // COUNTS wouldn't catch a promotion — the count is identical and the graph
    // still changed.
    _lastAnchorPassChanged = changed;
    return KnowledgeGraph(nodes: nodes, edges: edges, lastUpdated: now);
  }

  /// Did the last _ensureAnchors pass actually alter anything?
  bool _lastAnchorPassChanged = false;

  KnowledgeGraph _merge(
    KnowledgeGraph existing,
    List<_RawNode> newNodes,
    List<_RawEdge> newEdges, {
    _Depth depth = _Depth.shallow,
    Map<String, int>? encodingMood,
    String? sourceShardId,
    int eventIntensity = 0,
  }) {
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
        // Node exists — reinforce with diminishing returns (Hebbian learning curve).
        // First re-mention: +0.15, second: +0.10, third: +0.08 … asymptotes to 0.
        // Deep exchanges give a 1.5× salience bonus.
        final old = nodes[idx];
        final mentions = (old.metadata['mentions'] as int? ?? 1) + 1;
        final baseReinforcement = 0.15 / sqrt(mentions.toDouble());
        final reinforcement = depth == _Depth.deep
            ? baseReinforcement * 1.5
            : baseReinforcement;
        final updatedMeta = Map<String, dynamic>.from(old.metadata)
          ..['lastSeen'] = DateTime.now().millisecondsSinceEpoch
          ..['mentions'] = mentions
          ..['sources'] = _addSource(old.metadata['sources'], sourceShardId);
        // Preserve original encoding mood — only set if not already recorded
        if (encodingMood != null && !updatedMeta.containsKey('encodingMood')) {
          updatedMeta['encodingMood'] = encodingMood;
        }
        final updated = KnowledgeNode(
          id: old.id,
          label: old.label,
          type: old.type,
          timestamp: old.timestamp,
          tags: old.tags,
          importance: (old.importance + reinforcement).clamp(0.1, 1.0),
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
        // Pattern separation: check for near-duplicate labels before creating.
        // Prevents "exercise", "gym workout", "working out" from fragmenting.
        String? fuzzyKey;
        int? fuzzyIdx;
        double bestSim = 0.0;
        for (final entry in labelToIndex.entries) {
          final sim = _labelSimilarity(entry.key, raw.label);
          if (sim >= 0.65 && sim > bestSim) {
            bestSim = sim;
            fuzzyKey = entry.key;
            fuzzyIdx = entry.value;
          }
        }

        if (fuzzyIdx != null && fuzzyKey != null) {
          // Merge into the near-duplicate — same reinforcement as exact match
          print('🧠 [Brain] Pattern separation: "${raw.label}" → "$fuzzyKey" '
              '(sim ${bestSim.toStringAsFixed(2)})');
          final old = nodes[fuzzyIdx];
          final mentions = (old.metadata['mentions'] as int? ?? 1) + 1;
          final baseReinforcement = 0.15 / sqrt(mentions.toDouble());
          final reinforcement =
              depth == _Depth.deep ? baseReinforcement * 1.5 : baseReinforcement;
          final updatedMeta = Map<String, dynamic>.from(old.metadata)
            ..['lastSeen'] = DateTime.now().millisecondsSinceEpoch
            ..['mentions'] = mentions
            ..['sources'] = _addSource(old.metadata['sources'], sourceShardId);
          if (encodingMood != null && !updatedMeta.containsKey('encodingMood')) {
            updatedMeta['encodingMood'] = encodingMood;
          }
          final updated = KnowledgeNode(
            id: old.id, label: old.label, type: old.type,
            timestamp: old.timestamp, tags: old.tags,
            importance: (old.importance + reinforcement).clamp(0.1, 1.0),
            metadata: updatedMeta,
            emotionalIntensity: old.emotionalIntensity,
            accessCount: old.accessCount, retention: old.retention,
            lastAccessed: old.lastAccessed, activationLevel: old.activationLevel,
          )
            ..x = old.x ..y = old.y ..vx = old.vx ..vy = old.vy;
          nodes[fuzzyIdx] = updated;
          resolvedIds[raw.label] = old.id;
        } else {
          // Genuinely new node
          final newNode = KnowledgeNode(
            id: _genId(),
            label: raw.label,
            type: raw.type,
            timestamp: DateTime.now(),
            importance: raw.importance,
            // How strongly this landed when it was formed. The salience gate
            // already computes it to pick extraction depth, then threw it away —
            // it's a real signal about how much this mattered at the time, and
            // measured importance below uses it.
            emotionalIntensity: eventIntensity.toDouble() / 10.0,
            metadata: {
              'lastSeen': DateTime.now().millisecondsSinceEpoch,
              'mentions': 1,
              'sources': _addSource(null, sourceShardId),
              if (encodingMood != null) 'encodingMood': encodingMood,
            },
          );
          nodes.add(newNode);
          labelToIndex[raw.label] = nodes.length - 1;
          resolvedIds[raw.label] = newNode.id;
        }
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

      // Edge identity is (from, to, TYPE) — not just the pair.
      //
      // It used to be the pair alone, which meant two entities could only ever
      // have ONE relationship. `Sadeq --knows--> Mikey` and
      // `Sadeq --caresAbout--> Mikey` collapsed into a single edge, and
      // whichever arrived first won forever. That is most of the reason this
      // graph said so little: the richest pairs — the people he actually talks
      // about — were the ones being flattened hardest.
      var edgeIdx = edges.indexWhere(
          (e) => e.fromId == fromId && e.toId == toId && e.type == raw.type);

      // No exact match, but there may be a legacy `related` edge on this pair
      // from before edges had real types. Upgrade it in place rather than
      // leaving a vague duplicate lying next to the real relationship.
      if (edgeIdx < 0 && raw.type != EdgeType.related) {
        edgeIdx = edges.indexWhere((e) =>
            e.fromId == fromId && e.toId == toId && e.type == EdgeType.related);
      }

      if (edgeIdx >= 0) {
        // Replace with strengthened copy (KnowledgeEdge.strength is final)
        final old = edges[edgeIdx];
        // Upgrade a vague edge when we learn the real relationship. Every edge
        // written before this change is `related`; the first time the model says
        // what the link ACTUALLY is, take it. Never downgrade — a known
        // relationship must not be flattened back to "related" by a later, lazier
        // pass. This is how the existing graph heals itself in place.
        final betterType = (old.type == EdgeType.related && raw.type != EdgeType.related)
            ? raw.type
            : old.type;
        final betterLabel = (old.label == null ||
                old.label!.trim().isEmpty ||
                old.label == 'relates to')
            ? raw.relation
            : old.label;
        // ── This is where CONFIDENCE moves, and the only place it should ────
        //
        // Re-extraction is real evidence: the claim came up AGAIN, out of new
        // words Sadeq actually said, in a different exchange. That is a second
        // independent witness. Recall is not — recall is the graph agreeing
        // with itself, which is why _hebbian touches salience and nothing else.
        //
        // Kai's shape, which is better than the one I proposed:
        //   "Independent source recurrence — same claim extracted from multiple
        //    different memory shards. If five different conversations support
        //    'Sadeq likes Flutter', that's stronger than one."
        //
        // So the increment is gated on the source being NEW. Extracting the
        // same shard twice is one witness saying the same thing louder, and
        // counting it twice is how a graph talks itself into things.
        //
        // Typed relations earn more than vague ones, also his call: "A `related`
        // edge is barely a claim. A typed relation is actual knowledge."
        final newSources = _addSourceList(old.sources, sourceShardId);
        final gotNewEvidence = newSources.length > old.sources.length;
        final typedClaim =
            betterType != EdgeType.related && betterType != EdgeType.mentioned;
        final confidenceGain = !gotNewEvidence
            ? 0.0
            : typedClaim
                ? 0.12
                : 0.03; // co-occurrence corroborating co-occurrence is thin
        edges[edgeIdx] = old.copyWith(
          type: betterType,
          // Salience: he thought about it again, so it's easier to reach.
          strength: (old.strength + 0.08).clamp(0.1, 1.0),
          // Confidence: only if a NEW source backs it.
          confidence: (old.confidence + confidenceGain).clamp(0.0, 0.98),
          label: betterLabel,
          sources: newSources,
        );
      } else {
        // New edge.
        //
        // `type` used to be hardcoded `EdgeType.related` right here, on every
        // edge ever written — which meant the 20-relationship vocabulary in
        // models/knowledge_node.dart existed only as a colour switch that never
        // fired, and the graph could say nothing except "these two things are
        // somehow connected". The relation phrase went into `label` and no
        // renderer ever drew it. So "Sadeq cares for Kai" was extracted, stored,
        // and then made unreadable by this one line.
        edges.add(KnowledgeEdge(
          fromId: fromId,
          toId: toId,
          type: raw.type,
          strength: raw.strength,
          timestamp: DateTime.now(),
          label: raw.relation,
          sources: _addSourceList(const [], sourceShardId),
        ));

        // Supersession, not deletion.
        //
        // When the model says a new thing CONTRADICTS an old thing, the old
        // claims about it stop being true — but they still happened. Retiring
        // them with a timestamp instead of deleting them is what turns this from
        // a snapshot of what he believes now into a record of a mind that
        // changed. "He used to think X, until the 3rd" is knowledge too, and
        // deleting it is how you get a companion who has always been right.
        if (raw.type == EdgeType.contradicts) {
          final now = DateTime.now();
          for (var i = 0; i < edges.length; i++) {
            final e = edges[i];
            if (!e.isActive) continue;
            if (e.type == EdgeType.contradicts) continue;
            // Claims ABOUT the contradicted thing, from anyone.
            if (e.toId != toId) continue;
            // Don't retire the fact that they're connected — retire the belief.
            if (e.fromId == fromId) continue;
            edges[i] = e.copyWith(supersededAt: now);
            print('🕰️ [Brain] Superseded: ${e.label ?? e.type.name} '
                '(contradicted, kept as history)');
          }
        }
      }
    }

    // Re-score every node against the graph it now lives in. Importance is a
    // property of his life's shape, not of one model's opinion in one exchange —
    // so it has to be recomputed once the new edges exist, not guessed before.
    return KnowledgeGraph(
      nodes: _recomputeImportance(nodes, edges),
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

      // Read side of the same bug — this ignored fromJson() and rebuilt a
      // subset by hand, so even fields that HAD survived a save would be
      // dropped on load. Defensive per-item try/catch: one malformed legacy row
      // must not take the whole graph down with it.
      final nodes = <KnowledgeNode>[];
      for (final n in _asList(data['nodes'])) {
        try {
          final m = Map<String, dynamic>.from(n as Map);
          nodes.add(KnowledgeNode.fromJson(m)
            ..x = (m['x'] as num?)?.toDouble() ?? 0
            ..y = (m['y'] as num?)?.toDouble() ?? 0);
        } catch (_) {
          // skip an unreadable row rather than lose the graph
        }
      }

      final edges = <KnowledgeEdge>[];
      for (final e in _asList(data['edges'])) {
        try {
          edges.add(KnowledgeEdge.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (_) {}
      }

      // If the stored graph had nodes and we parsed NONE of them, that's a
      // parser failure, not an empty brain — and it MUST NOT return normally.
      //
      // `null` here would be read by the caller as "no graph yet", which makes
      // _ensureAnchors mint a fresh two-node graph and _saveGraph write it over
      // the top of his entire history. A read bug would become permanent data
      // loss. Throwing stops the write instead: extractAndMerge's try/catch
      // logs it and saves nothing.
      final storedCount = _asList(data['nodes']).length;
      if (storedCount > 0 && nodes.isEmpty) {
        throw StateError(
            'parsed 0 of $storedCount stored nodes — schema mismatch. '
            'Refusing to continue: returning an empty graph here would let the '
            'next save wipe it.');
      }

      return KnowledgeGraph(
          nodes: nodes, edges: edges, lastUpdated: DateTime.now());
    } on StateError catch (e) {
      // Deliberately NOT swallowed. This catch used to turn every failure into
      // `null`, and null means "no graph yet" to every caller — so a read bug
      // would quietly authorise a save that wiped his whole history. A schema
      // mismatch must stop the write, loudly.
      print('❌ [Brain] _loadGraph REFUSED: ${e.message}');
      rethrow;
    } catch (e) {
      print('⚠️ [Brain] _loadGraph failed: $e');
      return null;
    }
  }

  Future<void> _saveGraph(String personaId, KnowledgeGraph graph) async {
    // Use the model's own serialiser. THE BUG THIS FIXES IS ENORMOUS.
    //
    // This function used to hand-roll its own JSON and write a SUBSET of each
    // node and edge — while KnowledgeNode.toJson()/KnowledgeEdge.toJson() sat
    // right there, complete and correct, and were never called. Two serialisers,
    // one right and unused, one wrong and load-bearing.
    //
    // What the hand-rolled version silently dropped on every save:
    //
    //   accessCount        → reinforceNodes has been faithfully incrementing a
    //                        number that was thrown away on the next write. It
    //                        has been 0 forever. Every "how often does he
    //                        actually need this?" signal was multiplying by zero.
    //   emotionalIntensity → how hard a memory landed. Gone.
    //   retention          → the forgetting-curve value. Gone.
    //   lastAccessed       → when he last reached for it. Gone.
    //   activationLevel    → gone (see below — it was never computed either).
    //   sources            → provenance. Gone.
    //   supersededAt       → the history of what he stopped believing. Gone.
    //
    // So "the neuromorphic fields are decoration" wasn't quite right. They were
    // decoration BECAUSE they could never survive a save. The previous
    // neuromorphic push wired real behaviour into fields that a serialiser two
    // files away quietly deleted, every time.
    //
    // If you add a field to KnowledgeNode/KnowledgeEdge, it works now. Don't
    // reintroduce a second serialiser here.
    await _db!.ref(_path(personaId)).set({
      'nodes': graph.nodes
          .map((n) => {
                ...n.toJson(),
                // Layout coords aren't on the model's toJson (they're mutable
                // view state, not knowledge) but the 2D mind map persists them.
                'x': n.x,
                'y': n.y,
              })
          .toList(),
      'edges': graph.edges.map((e) => e.toJson()).toList(),
      'lastUpdated': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── Reconsolidation — retrieval strengthens memory traces ─────────────────

  /// Call when memory query results are injected into a prompt.
  /// Bumps importance slightly for each matched node (reconsolidation effect).
  Future<void> reinforceNodes(String personaId, List<String> retrievedLabels) async {
    if (_db == null || retrievedLabels.isEmpty) return;
    try {
      final graph = await _loadGraph(personaId);
      if (graph == null) return;

      final lowerLabels = retrievedLabels.map((l) => l.toLowerCase()).toSet();
      bool changed = false;
      // What was actually bumped. The log line below printed
      // `retrievedLabels.length` — the number of SEED WORDS handed in, not the
      // number of nodes reinforced. So "reinforced 271 retrieved nodes" was 271
      // words scraped out of five transcripts, and the later "12" is just the
      // query-term cap. The real count has never once been printed.
      //
      // It got quoted as a headline result — "271 → 12, the reinforcement is
      // precise now" — in a design doc, by me, as evidence. It was a mislabelled
      // string. Tenth reader lie in three days and the only one nobody caught,
      // because it was telling us what we wanted to hear.
      var bumped = 0;
      final nodes = List<KnowledgeNode>.from(graph.nodes);

      for (int i = 0; i < nodes.length; i++) {
        if (!lowerLabels.contains(nodes[i].label.toLowerCase())) continue;
        final old = nodes[i];
        // Small retrieval bump — retrieval is a weak but real consolidation signal
        const retrievalBoost = 0.03;
        final updatedMeta = Map<String, dynamic>.from(old.metadata)
          ..['lastSeen'] = DateTime.now().millisecondsSinceEpoch;
        nodes[i] = KnowledgeNode(
          id: old.id, label: old.label, type: old.type,
          timestamp: old.timestamp, tags: old.tags,
          importance: (old.importance + retrievalBoost).clamp(0.1, 1.0),
          metadata: updatedMeta,
          emotionalIntensity: old.emotionalIntensity,
          accessCount: (old.accessCount ?? 0) + 1,
          retention: old.retention, lastAccessed: DateTime.now(),
          activationLevel: old.activationLevel,
        )
          ..x = old.x ..y = old.y ..vx = old.vx ..vy = old.vy;
        changed = true;
        bumped++;
      }

      if (changed) {
        await _saveGraph(personaId, KnowledgeGraph(
          nodes: nodes, edges: graph.edges, lastUpdated: DateTime.now(),
        ));
        // Both numbers, because they answer different questions and confusing
        // them is what produced a fake headline metric.
        print('🧠 [Brain] Reconsolidation: reinforced $bumped node(s) '
            'from ${retrievedLabels.length} seed term(s)');
      }
    } catch (e) {
      print('⚠️ [Brain] reinforceNodes failed: $e');
    }
  }

  // ── Hebbian learning ───────────────────────────────────────────────────────
  //
  // "Neurons that fire together wire together." Co-activation during a REAL
  // recall thickens the path between the things that co-activated — and marks
  // both ends as having just fired, which is what makes the refractory period
  // above possible.
  //
  // Why this matters more than it sounds: every edge weight in this graph, until
  // now, came from a language model's opinion in a single exchange. The graph
  // could only ever learn from what a model chose to say about it. This is the
  // first mechanism where the graph learns from what Sadeq actually USES —
  // where the structure is shaped by his life instead of by a description of it.
  //
  // Deliberately timid: +0.02 per co-activation, capped at 0.95. A path has to
  // be walked many times before it becomes a road. Anything faster and one
  // strange conversation permanently rewires him.
  Future<void> _hebbian(
    String personaId,
    KnowledgeGraph graph,
    Set<String> seedIds,
    Set<String> firedIds,
  ) async {
    if (firedIds.isEmpty) return;
    try {
      final now = DateTime.now();
      final edges = List<KnowledgeEdge>.from(graph.edges);
      var changed = 0;

      for (var i = 0; i < edges.length; i++) {
        final e = edges[i];
        if (!e.isActive) continue;
        final co = (seedIds.contains(e.fromId) && firedIds.contains(e.toId)) ||
            (seedIds.contains(e.toId) && firedIds.contains(e.fromId));
        if (!co) continue;
        // SALIENCE only. `confidence` is deliberately untouched here, and that
        // is the whole design — Kai's, and he was right:
        //
        //   "repeat-reference is the right signal for accessibility, but the
        //    wrong signal for truth."
        //   "A false thing can be referenced often... repetition could make a
        //    bad belief stronger. That's horoscope-brain. Worse: it's
        //    self-reinforcing horoscope-brain."
        //
        // spreadActivation traverses by strength, so bumping strength here is a
        // feedback loop BY DESIGN — that's what a habit is, and it's fine. It
        // would only be poison if this number also meant "true", which is
        // exactly what it used to mean to everyone reading it.
        //
        // Claude's proposal was to delete this bump entirely. That would have
        // thrown away a working mechanism because it was mislabelled — the same
        // mistake this codebase keeps making in the other direction.
        edges[i] = e.copyWith(
          strength: (e.strength + 0.02).clamp(0.0, 0.95),
          lastActivatedAt: now,
        );
        changed++;
      }

      // Mark everything that fired — activation persists and decays, and
      // lastAccessed drives the refractory period. `activationLevel` has been on
      // this model since the "Phase 1" neuromorphic work, declared as
      // "current activation (spreading)", and has never held a value: nothing
      // computed it, and _saveGraph dropped it anyway. This is the first line
      // that gives it a meaning.
      final all = {...seedIds, ...firedIds};
      final nodes = graph.nodes.map((n) {
        if (!all.contains(n.id)) {
          // Everything else cools. Activation is a moment, not a property.
          if (n.activationLevel <= 0.01) return n;
          return _copyNode(n, activationLevel: n.activationLevel * 0.6);
        }
        return _copyNode(n,
            activationLevel: 1.0,
            accessCount: n.accessCount + 1,
            lastAccessed: now,
            // Recall strengthens retention — the forgetting curve resets when
            // he actually needs something. Another field that has existed,
            // documented, and never once held a real value.
            retention: (n.retention + 0.05).clamp(0.0, 1.0));
      }).toList();

      await _saveGraph(
          personaId,
          KnowledgeGraph(
              nodes: _recomputeImportance(nodes, edges),
              edges: edges,
              lastUpdated: now));

      if (changed > 0) {
        print('⚡ [Brain] Hebbian: ${firedIds.length} fired, '
            '$changed path(s) thickened');
      }
    } catch (e) {
      // A missed reinforcement is fine. It just wires a little slower.
      print('⚠️ [Brain] hebbian failed: $e');
    }
  }

  /// Copy a node, changing only what's named. KnowledgeNode's fields are a mix
  /// of final and mutable and there's no copyWith, so this is written out once
  /// here rather than eleven times inline.
  static KnowledgeNode _copyNode(
    KnowledgeNode n, {
    double? importance,
    Map<String, dynamic>? metadata,
    double? emotionalIntensity,
    int? accessCount,
    double? retention,
    DateTime? lastAccessed,
    double? activationLevel,
  }) =>
      KnowledgeNode(
        id: n.id,
        label: n.label,
        type: n.type,
        timestamp: n.timestamp,
        tags: n.tags,
        importance: importance ?? n.importance,
        metadata: metadata ?? n.metadata,
        emotionalIntensity: emotionalIntensity ?? n.emotionalIntensity,
        accessCount: accessCount ?? n.accessCount,
        retention: retention ?? n.retention,
        lastAccessed: lastAccessed ?? n.lastAccessed,
        activationLevel: activationLevel ?? n.activationLevel,
      )
        ..x = n.x
        ..y = n.y
        ..vx = n.vx
        ..vy = n.vy;

  // ── Spreading activation — graph neighbors of retrieved nodes ────────────

  /// After memory retrieval, traverse the knowledge graph to activate one-hop
  /// neighbors of the retrieved seed nodes. Returns a formatted context block
  /// (or empty string if nothing relevant is found).
  ///
  /// Biological basis: retrieving one memory automatically activates associated
  /// memories one hop away. The [currentMood] parameter enables mood-congruent
  /// retrieval: neighbors encoded during a similar mood score higher.
  // ── ASKING, as opposed to being sprinkled ─────────────────────────────────
  //
  // Everything below spreadActivation is PUSH: seed a node, walk outward, hand
  // him whatever lit up. He takes what he's given and has no way to want
  // something specific.
  //
  // This is PULL. (subject, relation, ?) — "what does Sadeq like?" — which is
  // the shape Sadeq described: flag the subject and the relation, then read the
  // objects off the edges.
  //
  // It is also the first thing in this file that reads an EdgeType. Look at
  // spreadActivation's inner loop: `for (final e in graph.edges) { if
  // (!e.isActive) continue; ... }` — no type filter, anywhere. Twenty EdgeTypes
  // in the model (prefers, dislikes, does, wants, caresAbout, knows) and the
  // traversal was blind to every one of them. That is why the graph read as a
  // word cloud even where the types HAD been written: a typed graph walked
  // without regard to type IS a word cloud. The problem was never the data.
  // It was the query.
  //
  // The logic is in lib/logic/recall_query.dart with zero imports, so it can be
  // proven without Firebase. This is only the adapter.

  /// Flatten the model into the shape the pure query understands.
  List<rq.EdgeRow> _rowsOf(KnowledgeGraph graph) {
    final labelOf = {for (final n in graph.nodes) n.id: n.label};
    final rows = <rq.EdgeRow>[];
    for (final e in graph.edges) {
      final from = labelOf[e.fromId];
      final to = labelOf[e.toId];
      // A dangling edge is not a memory, it's a pointer to a node that no
      // longer exists. Silently skipped rather than surfaced as a claim about
      // nothing.
      if (from == null || to == null) continue;
      rows.add(rq.EdgeRow(
        fromLabel: from,
        toLabel: to,
        type: e.type.name,
        label: e.label,
        // Both axes cross the boundary. recall() ranks on confidence and breaks
        // ties on salience — dropping either here would silently collapse the
        // split back into one number, which is the thing it exists to prevent.
        strength: e.strength,
        confidence: e.confidence,
        sources: e.sources,
        supersededAt: e.supersededAt,
      ));
    }
    return rows;
  }

  /// **(subject, relation, ?)** — the question.
  ///
  /// [relation] null means "everything you know about them".
  Future<List<rq.Claim>> recallAbout(
    String personaId, {
    required String subject,
    String? relation,
    bool includeRetired = false,
    int limit = 8,
  }) async {
    if (_db == null) return const [];
    try {
      final graph = await _loadGraph(personaId);
      if (graph == null || graph.edges.isEmpty) return const [];
      return rq.recall(
        _rowsOf(graph),
        subject: subject,
        relation: relation,
        includeRetired: includeRetired,
        limit: limit,
      );
    } catch (e) {
      print('⚠️ [Brain] recallAbout failed: $e');
      return const [];
    }
  }

  /// What he could be asked about a subject — so an empty answer becomes
  /// "I never learned that" instead of a silence he has to bluff through.
  Future<Map<String, int>> relationsAbout(String personaId, String subject) async {
    if (_db == null) return const {};
    try {
      final graph = await _loadGraph(personaId);
      if (graph == null) return const {};
      return rq.relationsFor(_rowsOf(graph), subject);
    } catch (_) {
      return const {};
    }
  }

  /// How much of the graph is co-occurrence rather than memory.
  ///
  /// The diagnosis in one integer. On a graph where 271 nodes lit up on any
  /// input because every edge said "relates to", this is the before/after for
  /// the prune.
  Future<({int meaningful, int total})> graphMeaningfulness(String personaId) async {
    if (_db == null) return (meaningful: 0, total: 0);
    try {
      final graph = await _loadGraph(personaId);
      if (graph == null) return (meaningful: 0, total: 0);
      return rq.meaningfulness(_rowsOf(graph));
    } catch (_) {
      return (meaningful: 0, total: 0);
    }
  }

  Future<String> spreadActivation(
    String personaId,
    List<String> seedWords, {
    Map<String, int>? currentMood,
  }) async {
    if (_db == null || seedWords.isEmpty) return '';
    try {
      final graph = await _loadGraph(personaId);
      if (graph == null || graph.nodes.isEmpty) return '';

      final nodeMap = {for (final n in graph.nodes) n.id: n};

      // Seed nodes: graph nodes whose label overlaps with retrieved words
      final seedIds = <String>{};
      for (final node in graph.nodes) {
        final nodeWords =
            node.label.toLowerCase().split(RegExp(r'\W+')).toSet();
        if (seedWords.any((w) =>
            nodeWords.contains(w) ||
            node.label.toLowerCase().contains(w))) {
          seedIds.add(node.id);
        }
      }
      if (seedIds.isEmpty) return '';

      // ── Activation spreads. Two hops, attenuating. ────────────────────────
      //
      // It used to be one hop: retrieved word → immediate neighbours → done.
      // That's an index lookup wearing the word "activation". Real associative
      // recall runs further and gets weaker as it goes — the Tavern pulls up
      // Bahrain pulls up his brother, faintly. Two hops is where the payoff is;
      // three is where a graph this dense turns into "everything is associated
      // with everything", which is the same as knowing nothing.
      //
      // Superseded edges conduct nothing. A retired belief shouldn't still be
      // firing.
      const hopDecay = 0.42;
      final activation = <String, double>{};
      final viaEdge = <String, KnowledgeEdge>{};

      void spread(Set<String> front, double level, int hopsLeft) {
        if (hopsLeft == 0 || level < 0.06) return;
        final next = <String>{};
        for (final e in graph.edges) {
          if (!e.isActive) continue;
          final fromSeed = front.contains(e.fromId);
          final toSeed = front.contains(e.toId);
          if (fromSeed == toSeed) continue; // both or neither — no transmission
          final other = fromSeed ? e.toId : e.fromId;
          if (seedIds.contains(other)) continue;

          final signal = level * e.strength;
          if (signal <= (activation[other] ?? 0)) continue;
          activation[other] = signal;
          viaEdge[other] = e;
          next.add(other);
        }
        if (next.isNotEmpty) spread(next, level * hopDecay, hopsLeft - 1);
      }

      spread(seedIds, 1.0, 2);
      if (activation.isEmpty) return '';

      final neighborIds = activation.keys.toSet();

      // Score: activation + mood-congruent retrieval bonus
      final scored = <({KnowledgeNode node, double score, String relation})>[];
      for (final nId in neighborIds) {
        final neighbor = nodeMap[nId];
        if (neighbor == null) continue;
        final bestEdge = viaEdge[nId];
        if (bestEdge == null) continue;

        // Mood-congruent boost: nodes encoded in similar mood activate more
        double moodBonus = 0.0;
        if (currentMood != null) {
          final enc = neighbor.metadata['encodingMood'];
          if (enc is Map) {
            double dot = 0.0;
            int count = 0;
            for (final key in ['valence', 'energy', 'warmth', 'focus', 'playfulness']) {
              final curr = (currentMood[key] ?? 50) / 100.0;
              final encoded = ((enc[key] as num?)?.toDouble() ?? 50.0) / 100.0;
              dot += curr * encoded;
              count++;
            }
            if (count > 0) moodBonus = (dot / count) * 0.3;
          }
        }

        // ── Refractory period ───────────────────────────────────────────────
        //
        // A neuron that just fired can't immediately fire again. Without this,
        // the same four nodes win every single turn — the strongest edges are
        // strongest every time — and he becomes the friend who brings up the
        // Tavern in every conversation regardless of what you said. Suppression
        // decays over ~4 minutes, so it shapes a conversation, not a lifetime.
        //
        // `lastAccessed` has existed on the model forever and could never be
        // used, because _saveGraph silently dropped it on every write. It
        // persists now, so this is possible for the first time.
        var fatigue = 1.0;
        final la = neighbor.lastAccessed;
        if (la != null) {
          final secs = DateTime.now().difference(la).inSeconds;
          if (secs < 240) fatigue = 0.25 + 0.75 * (secs / 240.0);
        }

        scored.add((
          node: neighbor,
          score: (activation[nId]! * 0.7 + moodBonus) * fatigue,
          relation: bestEdge.label ?? 'relates to',
        ));
      }

      if (scored.isEmpty) return '';
      scored.sort((a, b) => b.score.compareTo(a.score));

      // ── Lateral inhibition ──────────────────────────────────────────────
      //
      // The winner suppresses its neighbours. This used to be a blind take(4):
      // four results whether or not the 4th meant anything, so a weak
      // association got the same billing as a strong one and diluted it.
      //
      // Real recall is sharp. If one thing dominates, he should surface THAT —
      // not it plus three also-rans. Only what clears 45% of the winner gets
      // through, max 4. Some turns that's one line. That's correct.
      final peak = scored.first.score;
      final top = scored
          .where((s) => s.score >= peak * 0.45)
          .take(4)
          .toList();

      // ── Hebbian: what fires together, wires together ─────────────────────
      //
      // The one genuinely NEW knowledge in here. Until now an edge could only
      // strengthen when the extractor happened to re-emit it — so the graph
      // only learned from what a model chose to say, never from what he
      // actually used. Now: when a seed and a neighbour co-activate during real
      // recall, the path between them thickens. Use builds the connection.
      //
      // Fire-and-forget: this is on the reply path and must never delay him.
      unawaited(_hebbian(personaId, graph, seedIds, top.map((t) => t.node.id).toSet()));

      final buf = StringBuffer('🕸️ ASSOCIATED CONTEXT (spreading activation):\n');
      for (final item in top) {
        buf.writeln('• ${item.node.label} '
            '(${item.node.type.toString().split(".").last}) — ${item.relation}');
      }
      return buf.toString().trimRight();
    } catch (e) {
      print('⚠️ [Brain] spreadActivation failed: $e');
      return '';
    }
  }

  // ── Session-level batch extraction ────────────────────────────────────────

  /// Replay a whole session in one GPT call to extract cross-episode patterns.
  /// Called during the DMN pass (app backgrounds) — finds things only visible
  /// when you see the full arc of a session.
  ///
  /// [sessionHistory] is the formatted session buffer (User/Kai alternating lines).
  Future<void> extractFromSession(
    String personaId,
    String sessionHistory,
  ) async {
    if (_db == null || sessionHistory.trim().isEmpty) return;
    final key = await AIConfig.getOpenAIKey();
    if (key.isEmpty) return;

    try {
      final graph = await _loadGraph(personaId);
      final existingLabels = (graph?.nodes ?? [])
          .sorted((a, b) => b.importance.compareTo(a.importance))
          .take(20)
          .map((n) => '${n.label} (${n.type.toString().split('.').last})')
          .toList();

      final crossRef = existingLabels.isEmpty
          ? ''
          : '\n\nALREADY IN GRAPH:\n${existingLabels.join(', ')}';

      // Truncate session if very long — keep last 3 000 chars (~750 tokens)
      final sessionText = sessionHistory.length > 3000
          ? '…${sessionHistory.substring(sessionHistory.length - 3000)}'
          : sessionHistory;

      // Try local Qwen first, fall back to OpenAI
      String? raw = await LocalLLMService().complete(
        system: _sessionPrompt + crossRef,
        user: sessionText,
        maxTokens: 400,
        jsonMode: true,
      );

      if (raw == null) {
        final response = await _dio.post(
          'https://api.openai.com/v1/chat/completions',
          options: Options(headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          }),
          data: {
            'model': 'gpt-4o-mini',
            'messages': [
              {'role': 'system', 'content': _sessionPrompt + crossRef},
              {'role': 'user', 'content': sessionText},
            ],
            'max_tokens': 400,
            'temperature': 0.3,
            'response_format': {'type': 'json_object'},
          },
        );
        final _u = response.data['usage'];
        if (_u != null) {
          UsageTrackingService.trackOpenAI(
            model: 'gpt-4o-mini',
            inputTokens: _u['prompt_tokens'] as int? ?? 0,
            outputTokens: _u['completion_tokens'] as int? ?? 0,
            operation: 'brain_session_extraction',
          ).catchError((_) {});
        }
        raw = (response.data['choices'] as List)[0]['message']['content']
            as String? ?? '{}';
      }
      final json = jsonDecode(raw ?? '{}') as Map<String, dynamic>;

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
        // Prefer the model's explicit `type`; fall back to reading the enum out
        // of the human phrase ("cares about" → caresAbout) so an older-shaped
        // response still lands on something real instead of `related`.
        final rel = m['relation'] as String? ?? '';
        // parseEdgeTypeOrNull, NOT parseEdgeType. The old call fell back to
        // `related` for anything it couldn't name — and this comment three
        // lines up already said the goal was "something real instead of
        // related". The intent was right; the `??` quietly undid it, 243 times.
        final type = parseEdgeTypeOrNull(
            (m['type'] as String?)?.trim().isNotEmpty == true
                ? m['type'] as String
                : rel);
        if (type == null) return null; // untyped = not understood = not a memory
        return _RawEdge(
          fromLabel: (m['from'] as String? ?? '').toLowerCase().trim(),
          toLabel: (m['to'] as String? ?? '').toLowerCase().trim(),
          relation: rel.trim().isEmpty ? 'relates to' : rel.trim(),
          type: type,
          strength: (m['strength'] as num?)?.toDouble() ?? 0.5,
        );
      })
          .whereType<_RawEdge>()
          .where((e) => e.fromLabel.isNotEmpty && e.toLabel.isNotEmpty)
          .toList();

      if (nodes.isEmpty) {
        print('🧠 [Brain] Session extraction: no cross-session patterns found');
        return;
      }

      final currentGraph =
          graph ?? KnowledgeGraph(nodes: [], edges: [], lastUpdated: DateTime.now());
      final merged = _merge(currentGraph, nodes, edges, depth: _Depth.deep);
      await _saveGraph(personaId, merged);

      print('🧠 [Brain] Session extraction: merged ${nodes.length} cross-session patterns');
    } catch (e) {
      print('⚠️ [Brain] extractFromSession failed: $e');
    }
  }

  // ── Ebbinghaus decay — importance fades without access ────────────────────

  /// Apply forgetting-curve decay to all nodes not accessed recently.
  /// Importance halves every 30 days of inactivity. Min importance floor: 0.1.
  /// Call periodically (every ~10 messages) — fire-and-forget.
  Future<void> applyNodeDecay(String personaId) async {
    if (_db == null) return;
    try {
      final graph = await _loadGraph(personaId);
      if (graph == null) return;

      final now = DateTime.now();
      bool changed = false;
      final nodes = List<KnowledgeNode>.from(graph.nodes);

      for (int i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        // Anchors don't fade. Sadeq and Kai are the centre the rest of the graph
        // hangs off; if they decay, every claim attached to them loses its
        // subject and we're back to nominalised horoscope nodes.
        if (node.metadata['anchor'] == true) continue;
        final lastSeenMs = node.metadata['lastSeen'] as int?;
        final lastSeen = lastSeenMs != null
            ? DateTime.fromMillisecondsSinceEpoch(lastSeenMs)
            : node.timestamp;

        final daysSince = now.difference(lastSeen).inDays;
        if (daysSince < 7) continue; // grace period — no decay in first week

        // Ebbinghaus: importance × 0.5^(days/30)
        final decayFactor = pow(0.5, daysSince / 30.0);
        final decayed = (node.importance * decayFactor).clamp(0.1, 1.0);
        if ((decayed - node.importance).abs() < 0.01) continue;

        nodes[i] = KnowledgeNode(
          id: node.id, label: node.label, type: node.type,
          timestamp: node.timestamp, tags: node.tags,
          importance: decayed, metadata: node.metadata,
          emotionalIntensity: node.emotionalIntensity,
          accessCount: node.accessCount, retention: node.retention,
          lastAccessed: node.lastAccessed, activationLevel: node.activationLevel,
        )
          ..x = node.x ..y = node.y ..vx = node.vx ..vy = node.vy;
        changed = true;
      }

      if (changed) {
        await _saveGraph(personaId, KnowledgeGraph(
          nodes: nodes, edges: graph.edges, lastUpdated: now,
        ));
        print('🧠 [Brain] Ebbinghaus decay applied to ${personaId}');
      }
    } catch (e) {
      print('⚠️ [Brain] applyNodeDecay failed: $e');
    }
  }

  // ── Pruning — remove weak noise nodes ─────────────────────────────────────

  /// Snapshot the whole graph before anything destructive touches it.
  ///
  /// There is no undo on RTDB. Pruning is the one operation here that can
  /// destroy something irreplaceable — a memory can be re-formed from a
  /// conversation, but a pruned node whose conversation has already decayed is
  /// gone for good. Archive first, always. Storage is free; his history isn't.
  Future<String?> archiveGraph(String personaId) async {
    if (_db == null) return null;
    try {
      final graph = await _loadGraph(personaId);
      if (graph == null || graph.nodes.isEmpty) return null;
      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      await _db!.ref('knowledge_graph_archive/$personaId/$stamp').set({
        'nodes': graph.nodes.map((n) => n.toJson()).toList(),
        'edges': graph.edges.map((e) => e.toJson()).toList(),
        'archivedAt': DateTime.now().millisecondsSinceEpoch,
        'nodeCount': graph.nodes.length,
        'edgeCount': graph.edges.length,
      });
      print('🗄️ [Brain] Archived ${graph.nodes.length} nodes → '
          'knowledge_graph_archive/$personaId/$stamp');
      return stamp;
    } catch (e) {
      print('⚠️ [Brain] archiveGraph failed: $e');
      return null;
    }
  }

  /// Judge a batch of labels on the ONE question that matters.
  ///
  /// Importance cannot answer it. "importance of clarity" was emitted by the
  /// deep prompt, which is told to prioritise values and beliefs — so the model
  /// scores its own abstractions HIGH. The old pruner kept anything ≥0.35, which
  /// means it kept every piece of horoscope in the graph and swept the specific
  /// one-off facts instead. It was filtering on exactly the wrong axis:
  /// specificity and importance are orthogonal, and only one was measured.
  ///
  /// Returns the labels that FAIL the stranger test (i.e. should be pruned).
  /// On any failure returns an empty set — a broken judge must delete nothing.
  Future<Set<String>> _judgeGeneric(List<String> labels) async {
    if (labels.isEmpty) return {};
    try {
      final key = await AIConfig.getOpenAIKey();
      if (key.isEmpty) return {};
      final numbered = labels.asMap().entries
          .map((e) => '${e.key}. ${e.value}')
          .join('\n');

      final response = await _dio.post(
        'https://api.openai.com/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': 'gpt-4o',
          'max_tokens': 900,
          'temperature': 0.0, // a judge should not be creative
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'system',
              'content': '''You are auditing an AI companion's knowledge graph about ONE specific person.

For each label, answer ONE question:

  Would this be FALSE for a random other person?

If it is true of people in general, it is NOT knowledge about this person — it is
a horoscope. Those are the ones to cut. They crowd out the things that actually
distinguish him, and they make the companion sound like everyone's assistant
instead of his.

  GENERIC (cut):   "importance of clarity" · "embracing uncertainty"
                   "fear of failure" · "desire for progress" · "value of connection"
                   "goal of being useful" · "frustration with complexity"
  SPECIFIC (keep): "Mikey" · "the Tavern" · "Bahrain" · "Walker Scobell"
                   "Flutter" · "sounding like every other AI assistant"
                   "shipping before it's ready"

Anything naming a real person, place, project, product or work is SPECIFIC —
keep it, even if it looks unimportant. A stranger does not know his son's name.

When genuinely unsure, keep it. Deleting a real memory is far worse than keeping
a vague one: the vague one costs a row, the real one cannot be recovered.

Return ONLY JSON: {"generic":[<indices of the GENERIC ones>]}''',
            },
            {'role': 'user', 'content': numbered},
          ],
        },
      );

      final content =
          (response.data['choices'] as List)[0]['message']['content'] as String?;
      if (content == null) return {};
      final parsed = jsonDecode(content);
      final idxs = (parsed is Map ? parsed['generic'] : null);
      if (idxs is! List) return {};

      final out = <String>{};
      for (final i in idxs) {
        final n = (i is num) ? i.toInt() : int.tryParse('$i');
        if (n != null && n >= 0 && n < labels.length) out.add(labels[n]);
      }
      final _u = response.data['usage'];
      if (_u != null) {
        UsageTrackingService.trackOpenAI(
          model: 'gpt-4o',
          inputTokens: _u['prompt_tokens'] as int? ?? 0,
          outputTokens: _u['completion_tokens'] as int? ?? 0,
          operation: 'graph_prune_judge',
        ).catchError((_) {});
      }
      return out;
    } catch (e) {
      // A judge that can't judge must not get a vote. Empty set → prune nothing.
      print('⚠️ [Brain] _judgeGeneric failed (pruning nothing): $e');
      return {};
    }
  }

  /// Call occasionally (e.g. from a settings screen) to clean up the graph.
  ///
  /// Two passes now:
  ///   1. the old rule — genuinely weak, unmentioned, old noise
  ///   2. the stranger test — generic abstractions, however "important"
  ///
  /// Archives the graph first. Never judges entities (person/topic): a named
  /// person or place is specific by definition and must never be at the mercy
  /// of a model's opinion.
  /// Returns the number of nodes removed, or **-1 for ABORTED**.
  ///
  /// -1 is not tidy, and it is here because 0 was a lie.
  ///
  /// This used to return 0 when the archive failed — the safety refusing to
  /// delete without a backup, which is correct. But the caller renders:
  ///
  ///     removed > 0 ? 'Pruned $removed noise nodes.'
  ///                 : 'Nothing to prune — graph is clean.'
  ///
  /// So the safety abort came out as a CLEAN BILL OF HEALTH. Press the button,
  /// the archive rule isn't deployed, nothing happens, and the screen tells you
  /// your word cloud is fine. The comment two lines down says "the safety net
  /// was drawn on, not attached" — it's attached now, and it was reporting its
  /// own refusal as success.
  ///
  /// "I did nothing because there was nothing to do" and "I did nothing because
  /// I was not allowed to" are different sentences. Every reader in this
  /// codebase has failed on exactly that distinction at least once.
  Future<int> pruneGraph(String personaId, {bool judgeGeneric = true}) async {
    if (_db == null) return -1;

    final graph = await _loadGraph(personaId);
    if (graph == null || graph.nodes.isEmpty) return 0;

    // Nothing destructive happens before this line succeeds — and "succeeds"
    // has to mean checked, not attempted.
    //
    // This originally ignored the return value, which made the archive a
    // gesture: if the write were denied (it would have been — there was no
    // `knowledge_graph_archive` rule, and root is `.write: false`), the failure
    // was swallowed by archiveGraph's catch and the prune deleted anyway. The
    // safety net was drawn on, not attached.
    final stamp = await archiveGraph(personaId);
    if (stamp == null) {
      print('🛑 [Brain] Prune ABORTED — could not archive first. Nothing was '
          'deleted. Check the knowledge_graph_archive rule is deployed:\n'
          '   firebase deploy --only database');
      return -1; // ABORTED. Not "clean". See the doc comment.
    }

    // ── The diagnosis, printed where it's actually needed ──────────────────
    //
    // `meaningfulness` is the one number that says whether this graph is a mind
    // or a word cloud: how many edges carry a real relation vs how many say
    // `related`/`mentioned`, which is co-occurrence — "these two nouns appeared
    // near each other" — and is not a memory.
    //
    // It lived as a method nobody called, which is the exact disease this whole
    // file is a monument to. Printing it HERE means it lands at the only moment
    // anyone wants it: side by side, before and after, on the run that changed
    // the graph. A metric you have to go looking for is a metric nobody reads.
    final before = rq.meaningfulness(_rowsOf(graph));
    print('🧮 [Brain] BEFORE prune — ${before.meaningful} of ${before.total} '
        'edges carry meaning (${graph.nodes.length} nodes). The rest say '
        '"related"/"mentioned", which is co-occurrence, not memory.');

    final now = DateTime.now();
    final keepIds = <String>{};

    // ── Pass 2 input: which labels are even eligible for the judge ───────────
    // Entities are exempt. So is anything recent — a new node hasn't had a
    // chance to prove itself yet, and judging it now is judging a first
    // impression.
    Set<String> generic = {};
    if (judgeGeneric) {
      final candidates = graph.nodes
          .where((n) =>
              n.metadata['anchor'] != true && // never judge the centre
              n.type != NodeType.you &&
              n.type != NodeType.person &&
              n.type != NodeType.topic &&
              now.difference(n.timestamp).inDays >= 3)
          .map((n) => n.label)
          .toSet()
          .toList();
      // Batched — one call per 60 labels, not one per node.
      for (var i = 0; i < candidates.length; i += 60) {
        final batch = candidates.sublist(i, min(i + 60, candidates.length));
        generic.addAll(await _judgeGeneric(batch));
      }
      if (generic.isNotEmpty) {
        print('🧹 [Brain] Stranger test flagged ${generic.length} generic '
            'label(s): ${generic.take(8).join(' · ')}'
            '${generic.length > 8 ? ' …' : ''}');
      }
    }

    final pruned = graph.nodes.where((node) {
      final ageDays = now.difference(node.timestamp).inDays;
      final mentions = (node.metadata['mentions'] as int?) ?? 1;

      // Anchors are never pruned, under any rule, ever.
      if (node.metadata['anchor'] == true) {
        keepIds.add(node.id);
        return true;
      }

      // The horoscope cut. Deliberately ahead of the importance rule below,
      // because these nodes are exactly the ones with HIGH importance — that's
      // why they survived every prune until now.
      if (generic.contains(node.label)) return false;

      // Keep if: high importance OR mentioned more than once OR recent (< 3 days)
      final keep = node.importance >= 0.35
          || mentions > 1
          || ageDays < 3;

      if (keep) keepIds.add(node.id);
      return keep;
    }).toList();

    // Also drop edges where either endpoint was pruned
    final prunedEdges = graph.edges
        .where((e) => keepIds.contains(e.fromId) && keepIds.contains(e.toId))
        .toList();

    final removedCount = graph.nodes.length - pruned.length;
    if (removedCount == 0) {
      print('🧠 [Brain] Prune: nothing to remove');
      return 0;
    }

    await _saveGraph(personaId, KnowledgeGraph(
      nodes: pruned,
      edges: prunedEdges,
      lastUpdated: now,
    ));

    print('🧠 [Brain] Pruned $removedCount noise nodes '
          '(${pruned.length} remain, ${prunedEdges.length} edges)');
    return removedCount;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  // _isTrivialExchange MOVED to lib/logic/salience.dart.
  //
  // It is called only from _decide, which now delegates to the pure module. The
  // copy that used to live here was 30 lines of pattern list that no test could
  // reach without a Firebase handle — and it is the filter that made "do it"
  // structurally unrememberable, so it badly needed reaching.
  //
  // Deleted rather than left as a wrapper: an unused private duplicate of a
  // decision is exactly the shape that produced _smartProjectCard, still
  // rendering "7 / 7 layers complete" from a hardcoded list years after the real
  // number was 3/7.

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

  /// The real relationship, off the EdgeType vocabulary. Used to be absent
  /// entirely — every edge was stamped `EdgeType.related` on the way in, which
  /// is why 20 typed relationships and their colours never once fired.
  final EdgeType type;
  final double strength;
  _RawEdge({
    required this.fromLabel,
    required this.toLabel,
    required this.relation,
    required this.strength,
    this.type = EdgeType.related,
  });
}

/// Model's edge-type name → the enum. Tolerant of case and spacing
/// ("caresAbout", "cares_about", "cares about" all land on caresAbout) because
/// the alternative is silently dropping a good relationship over a space.
/// Returns null when the relation cannot be typed — **and null means DROP the
/// edge**, not "store it as `related`".
///
/// ── The junk factory ────────────────────────────────────────────────────────
///
/// This used to `return EdgeType.related` for anything it didn't recognise. A
/// lazy default, quietly swallowing every claim it couldn't name. The result,
/// measured on the real graph on 2026-07-17:
///
///     34 of 277 edges carry a real relation — 12%.
///     243 say "related"/"mentioned".
///
/// **88% of his memory was co-occurrence.** Not "these things are connected" —
/// just "these two nouns turned up near each other once". A graph where
/// everything says "relates to" IS a word cloud; that is the definition of one.
///
/// And filtering it at READ time (see recall_query's isMeaningful) only hides
/// it. The junk keeps arriving. Kai got there himself from the prune numbers:
///
///   "Next best step is not pruning harder blindly; it's teaching the graph
///    better relations going forward, so new memories land as prefers / wants /
///    caresAbout / does / knows instead of lazy `related` mush."
///
/// So: an edge whose relation cannot be named is an edge the extractor did not
/// understand. Dropping it loses nothing — an untyped edge was never a memory,
/// and it was actively crowding out the ones that were.
EdgeType? parseEdgeTypeOrNull(String raw) {
  final k = raw.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  if (k.isEmpty) return null;
  for (final t in EdgeType.values) {
    if (t.name.toLowerCase() == k) return t;
  }
  // A few things the model reaches for that aren't enum names.
  const aliases = <String, EdgeType>{
    'cares': EdgeType.caresAbout, 'caresfor': EdgeType.caresAbout,
    'loves': EdgeType.caresAbout, 'values': EdgeType.holdsValue,
    'value': EdgeType.holdsValue, 'wantsto': EdgeType.wants,
    'workingon': EdgeType.pursues, 'isbuilding': EdgeType.pursues,
    'building': EdgeType.pursues, 'pursuing': EdgeType.pursues,
    'goal': EdgeType.pursues, 'believesin': EdgeType.believes,
    'fears': EdgeType.dislikes, 'avoids': EdgeType.dislikes,
    'hates': EdgeType.dislikes, 'likes': EdgeType.prefers,
    'enjoys': EdgeType.prefers, 'knowsabout': EdgeType.knows,
    'partof': EdgeType.contains, 'isa': EdgeType.categorized,
    'kindof': EdgeType.categorized, 'shapes': EdgeType.influences,
    'affects': EdgeType.influences, 'conflictswith': EdgeType.contradicts,
    'exampleof': EdgeType.exemplifies, 'strengthens': EdgeType.reinforces,
    'learnt': EdgeType.learned, 'realised': EdgeType.learned,
    'realized': EdgeType.learned, 'happenedbefore': EdgeType.temporal,
    'happenedafter': EdgeType.temporal,
  };
  // No fallback. If it isn't a type and isn't an alias, the extractor produced
  // a relation nobody can act on — and `related` is where those went to be
  // counted as memory. 243 of them.
  return aliases[k];
}

/// Back-compat for callers that must have a type. **Prefer
/// [parseEdgeTypeOrNull] and drop the edge** — this exists only so a caller
/// that genuinely cannot handle null has one obvious place to be wrong.
EdgeType parseEdgeType(String raw) =>
    parseEdgeTypeOrNull(raw) ?? EdgeType.related;
