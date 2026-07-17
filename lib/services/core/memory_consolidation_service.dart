// MemoryConsolidationService
//
// Bridges the gap between raw conversation turns (recent context) and the
// knowledge graph (semantic facts). This service maintains EPISODIC MEMORY —
// a compressed, evolving narrative of what has happened across the whole
// relationship, who the user is right now, and what matters to them.
//
// How it fits the memory architecture:
//
//   Knowledge graph    → semantic nodes: people, concepts, beliefs, goals
//   Episodic memory    → narrative: key moments, patterns, commitments, arc
//   Raw history        → immediate context: last 8 turns (reduced from 20)
//
// Trigger: every 20 new conversation turns, fire-and-forget.
// Method:  INCREMENTAL — reads existing consolidated memory + new turns since
//          last consolidation, then updates (not rewrites) the memory.
//          Old important moments are preserved; new patterns are layered in.
//
// Firebase path: kai/{personaId}/memory/consolidated
// SharedPreferences: kai_consolidation_turn_count_{personaId}
//                    kai_last_consolidation_{personaId}

library;

import 'dart:async'; // unawaited — the graph must never block consolidation
import 'dart:convert';
import 'package:dio/dio.dart';
import '../ai/usage_tracking_service.dart';
// The episode → graph wire. See _extractEpisodeIntoGraph: this is the one place
// in the system that can see a whole scene, and it had never spoken to the one
// place that stores what he knows.
import 'brain_extraction_service.dart';
import 'emotional_event_service.dart';
import 'kai_db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_service.dart';
import '../ai/ai_config.dart';
import '../ai/local_llm_service.dart';

class MemoryConsolidationService {
  static final MemoryConsolidationService _instance =
      MemoryConsolidationService._internal();
  factory MemoryConsolidationService() => _instance;
  MemoryConsolidationService._internal();

  final _dio = Dio();

  static const _turnsPerCycle = 20; // consolidate every N new turns
  static const _maxRawChars   = 6000; // chars of raw history to process

  static KaiDb? get _db =>
      FirebaseService.isAvailable ? KaiDb.instance : null;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Call fire-and-forget after each conversation turn.
  /// Only runs consolidation when the turn counter hits the threshold.
  Future<void> maybeConsolidate({required String personaId}) async {
    if (_db == null) return;

    final prefs = await SharedPreferences.getInstance();
    final countKey = 'kai_consolidation_turn_count_$personaId';
    final count = (prefs.getInt(countKey) ?? 0) + 1;
    await prefs.setInt(countKey, count);

    if (count < _turnsPerCycle) return; // not yet

    print('🗜️ [Consolidation] Threshold reached ($count turns) — consolidating…');
    await prefs.setInt(countKey, 0); // reset counter

    await _runConsolidation(personaId);
  }

  /// Force-run consolidation regardless of turn count (e.g. for first-time setup).
  Future<void> forceConsolidate({required String personaId}) async {
    if (_db == null) return;
    print('🗜️ [Consolidation] Force-running for $personaId…');
    await _runConsolidation(personaId);
  }

  /// Returns the consolidated memory block for injection into the system prompt.
  /// Returns empty string if no consolidation has run yet.
  Future<String> getConsolidatedMemoryBlock(String personaId) async {
    if (_db == null) return '';
    try {
      final snap =
          await _db!.ref('kai/$personaId/memory/consolidated').get();
      if (!snap.exists || snap.value == null) return '';

      final data = Map<String, dynamic>.from(snap.value as Map);
      return _formatForPrompt(data);
    } catch (e) {
      print('🗜️ [Consolidation] Failed to read memory: $e');
      return '';
    }
  }

  // ── Consolidation cycle ────────────────────────────────────────────────────

  Future<void> _runConsolidation(String personaId) async {
    final key = await AIConfig.getOpenAIKey();
    if (key.isEmpty) return;

    // Load raw conversation history
    final rawHistory = await _loadRawHistory(personaId);
    if (rawHistory.isEmpty) {
      print('🗜️ [Consolidation] No conversation history — skipping');
      return;
    }

    // Load existing consolidated memory (if any) — this is the incremental step
    final existing = await _loadExistingMemory(personaId);

    // Run GPT consolidation
    final result = await _consolidateWithGPT(
      key: key,
      rawHistory: rawHistory,
      existingMemory: existing,
      personaId: personaId,
    );
    if (result == null) return;

    // Write to Firebase
    await _db!.ref('kai/$personaId/memory/consolidated').set({
      ...result,
      'lastConsolidatedAt': DateTime.now().millisecondsSinceEpoch,
      'personaId': personaId,
    });

    print('🗜️ [Consolidation] Done — ${(result['key_moments'] as List?)?.length ?? 0} key moments stored');

    // ── THE EPISODE REACHES THE GRAPH ────────────────────────────────────────
    //
    // This is the wire that was missing, and it is the level-5 move.
    //
    // Extraction has always run PER TURN. But a turn is the wrong unit — most
    // turns contain no memory at all, and it isn't a gate problem, it's a
    // physics problem:
    //
    //   "not terribly, couldve been better, but eh"
    //
    // There is nothing in that sentence to extract. No prompt, no model, no
    // threshold can find a memory in it, because there isn't one. But the
    // MORNING it belongs to contains one: "Sadeq slept badly on the 17th and
    // wanted to go gentle — no heroic productivity goblin nonsense."
    //
    // Memories don't live in turns. They live in scenes. Human consolidation is
    // offline and episodic for exactly this reason — you don't remember a
    // conversation one word at a time.
    //
    // And the episode boundary ALREADY EXISTED, right here, firing on its own
    // every 20 turns, reading real history and producing `key_moments` — which
    // then went into Firebase and stopped. The one thing in this system that
    // could see a whole scene was not on speaking terms with the one thing that
    // stores what he knows. The signature disease, one more time: the correct
    // thing, disconnected.
    //
    // Fire-and-forget: consolidation must never be blocked by extraction, and
    // extraction failing means one episode isn't in the graph — not that the
    // consolidated memory is lost. It's already written above.
    unawaited(_extractEpisodeIntoGraph(personaId, result));
  }

  /// Feed the consolidated EPISODE to the knowledge graph.
  ///
  /// The key moments are already the distilled version — GPT has read 20 turns
  /// and said what mattered. Handing that to extraction is a completely
  /// different question from handing it "eh":
  ///
  ///   per-turn:  "what entities are in this sentence?"     → nouns
  ///   episodic:  "what became true across this scene?"     → claims
  ///
  /// [toolsUsed] is deliberately non-empty. This is not a chat turn — it is a
  /// scene that GPT has already judged significant enough to keep. Passing
  /// 'contemplate' marks it as real work on the change axis, so the salience
  /// gate doesn't re-litigate a decision that has already been made by the
  /// thing with more context than it.
  Future<void> _extractEpisodeIntoGraph(
    String personaId,
    Map<String, dynamic> result,
  ) async {
    try {
      final moments = (result['key_moments'] as List?) ?? const [];
      if (moments.isEmpty) return;

      // Each moment is its own claim, so they go in as one block rather than
      // one call per moment — the relationships BETWEEN them are half the
      // point, and extraction can only see those if it sees them together.
      final episode = moments
          .map((m) => m is Map ? (m['moment'] ?? m['text'] ?? m).toString() : m.toString())
          .where((s) => s.trim().isNotEmpty)
          .map((s) => '• $s')
          .join('\n');
      if (episode.trim().isEmpty) return;

      final patterns = (result['emotional_patterns'] ?? '').toString().trim();

      print('🧬 [Consolidation] Feeding the episode to the graph — '
          '${moments.length} moments');

      await BrainExtractionService().extractAndMerge(
        personaId: personaId,
        userMessage: 'What actually happened between us recently, distilled '
            'from the last stretch of conversation:\n$episode'
            '${patterns.isEmpty ? '' : '\n\nThe emotional shape of it: $patterns'}',
        aiReply: 'This is a consolidated episode, not a single exchange. Extract '
            'what became TRUE across it — claims about Sadeq, about me, about '
            'what we are building and how we work together. Not the words that '
            'were said.',
        eventType: EmotionalEventType.deep,
        eventIntensity: 40,
        toolsUsed: const {'contemplate'},
      );
    } catch (e) {
      print('⚠️ [Consolidation] Episode extraction failed: $e');
    }
  }

  // ── GPT consolidation ──────────────────────────────────────────────────────

  static const _systemPrompt = '''
You maintain the episodic memory of an AI companion named Kai.
Your job is to read recent conversation history and UPDATE (not replace)
an existing memory record — adding new patterns, refining existing ones,
and preserving important moments from the past.

IMPORTANT — ignore noise in the history:
Greetings ("hi", "hey", "good morning"), farewells, one-word replies ("ok", "sure", "lol"),
pleasantries ("how are you", "I'm fine"), and generic filler add nothing to memory.
Only extract what you'd still want to know about this person in a month.

The memory has these fields:

KEY_MOMENTS (list of up to 8 strings)
  Significant events, revelations, breakthroughs, or vulnerable moments that
  happened across conversations. Things worth remembering for years.
  When updating: keep all existing moments unless clearly outdated; add new ones.
  Format: "<when/context>: <what happened>"

EMOTIONAL_PATTERNS (string)
  How this user characteristically feels. What lifts them. What weighs on them.
  What emotional register they operate in most of the time.
  When updating: refine with new evidence, don't discard old patterns.

RECURRING_THEMES (list of up to 6 strings)
  Topics, concerns, questions, or preoccupations that come up across multiple
  conversations. Not one-off mentions — genuine recurring threads.
  When updating: add new themes, keep existing ones, remove any proven wrong.

COMMITMENTS_AND_PLANS (list of up to 5 strings)
  Things the user said they intended to do, wanted to try, or planned.
  Include timeframes when known.
  When updating: mark completed ones (prefix "✓"), add new ones.

RELATIONSHIP_DEPTH_NOTE (string)
  One sentence on how the relationship between Kai and this user is evolving.
  What kind of relationship is this becoming?

RUNNING_NARRATIVE (string, 2-3 sentences)
  A vivid, present-tense portrait of who this person is right now —
  their life situation, what they care about, what they're working through.
  Written as a briefing for Kai: "The user is..."
  When updating: evolve it to reflect new developments. This is the most
  important field — Kai reads this on every message.

RETURN ONLY valid JSON with exactly these keys:
{
  "key_moments": ["string", ...],
  "emotional_patterns": "string",
  "recurring_themes": ["string", ...],
  "commitments_and_plans": ["string", ...],
  "relationship_depth_note": "string",
  "running_narrative": "string"
}
''';

  Future<Map<String, dynamic>?> _consolidateWithGPT({
    required String key,
    required String rawHistory,
    required Map<String, dynamic> existingMemory,
    required String personaId,
  }) async {
    final existingBlock = existingMemory.isEmpty
        ? '(No existing memory — this is the first consolidation)'
        : '''
KEY_MOMENTS: ${_jsonList(existingMemory['key_moments'])}
EMOTIONAL_PATTERNS: ${existingMemory['emotional_patterns'] ?? ''}
RECURRING_THEMES: ${_jsonList(existingMemory['recurring_themes'])}
COMMITMENTS_AND_PLANS: ${_jsonList(existingMemory['commitments_and_plans'])}
RELATIONSHIP_DEPTH_NOTE: ${existingMemory['relationship_depth_note'] ?? ''}
RUNNING_NARRATIVE: ${existingMemory['running_narrative'] ?? ''}
''';

    final userMessage = '''
EXISTING MEMORY TO UPDATE:
$existingBlock

NEW CONVERSATION HISTORY (since last consolidation):
───────────────────────────────
$rawHistory
───────────────────────────────

Update the memory by incorporating new patterns and moments from this history.
Preserve important existing memories. Return only the JSON.
''';

    // ── Try local Qwen first (no token cost for this heavy JSON task) ─────
    String? raw = await LocalLLMService().complete(
      system: _systemPrompt,
      user: userMessage,
      maxTokens: 800,
      jsonMode: true,
    );

    // ── Fall back to OpenAI ────────────────────────────────────────────────
    if (raw == null) {
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
              {'role': 'system', 'content': _systemPrompt},
              {'role': 'user',   'content': userMessage},
            ],
            'max_tokens': 800,
            'temperature': 0.3,
            'response_format': {'type': 'json_object'},
          },
        );
        raw = (response.data['choices'] as List)[0]['message']['content']
            as String? ?? '{}';
        final _u = response.data['usage'];
        if (_u != null) {
          UsageTrackingService.trackOpenAI(
            model: 'gpt-4o-mini',
            inputTokens: _u['prompt_tokens'] as int? ?? 0,
            outputTokens: _u['completion_tokens'] as int? ?? 0,
            operation: 'consolidation',
          ).catchError((_) {});
        }
      } catch (e) {
        print('🗜️ [Consolidation] GPT failed: $e');
        return null;
      }
    }

    try {
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (e) {
      print('🗜️ [Consolidation] JSON parse failed: $e');
      return null;
    }
  }

  // ── Format for system prompt injection ────────────────────────────────────

  /// Pure seam for offline regression tests. Keeps episodic memory prompt
  /// formatting testable without Firebase, SharedPreferences, local LLM, or
  /// OpenAI.
  String formatForPromptForTesting(Map<String, dynamic> data) {
    return _formatForPrompt(data);
  }

  String _formatForPrompt(Map<String, dynamic> data) {
    final buf = StringBuffer();
    buf.writeln('🧠 EPISODIC MEMORY (Kai\'s compressed history with this user):');

    final narrative = data['running_narrative'] as String?;
    if (narrative != null && narrative.isNotEmpty) {
      buf.writeln(narrative);
    }

    final emotional = data['emotional_patterns'] as String?;
    if (emotional != null && emotional.isNotEmpty) {
      buf.writeln('Emotional pattern: $emotional');
    }

    final themes = _asList(data['recurring_themes']);
    if (themes.isNotEmpty) {
      buf.writeln('Recurring themes: ${themes.join(' · ')}');
    }

    final moments = _asList(data['key_moments']);
    if (moments.isNotEmpty) {
      buf.writeln('Key moments: ${moments.take(5).join(' | ')}');
    }

    final plans = _asList(data['commitments_and_plans']);
    final pending = plans.where((p) => !p.toString().startsWith('✓')).toList();
    if (pending.isNotEmpty) {
      buf.writeln('Open commitments: ${pending.join(' · ')}');
    }

    final depthNote = data['relationship_depth_note'] as String?;
    if (depthNote != null && depthNote.isNotEmpty) {
      buf.writeln('Relationship: $depthNote');
    }

    return buf.toString().trim();
  }

  // ── Firebase I/O ───────────────────────────────────────────────────────────

  Future<String> _loadRawHistory(String personaId) async {
    try {
      final snap = await _db!.ref('conversations/$personaId').get();
      if (!snap.exists || snap.value == null) return '';
      final raw = snap.value.toString();
      return raw.length > _maxRawChars
          ? raw.substring(raw.length - _maxRawChars)
          : raw;
    } catch (e) {
      print('🗜️ [Consolidation] Failed to load raw history: $e');
      return '';
    }
  }

  Future<Map<String, dynamic>> _loadExistingMemory(String personaId) async {
    try {
      final snap =
          await _db!.ref('kai/$personaId/memory/consolidated').get();
      if (!snap.exists || snap.value == null) return {};
      return Map<String, dynamic>.from(snap.value as Map);
    } catch (_) {
      return {};
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<dynamic> _asList(dynamic v) {
    if (v is List) return v;
    if (v is Map) return v.values.toList();
    return [];
  }

  String _jsonList(dynamic v) {
    final list = _asList(v);
    if (list.isEmpty) return '(none)';
    return list.map((e) => '• $e').join('\n');
  }
}
