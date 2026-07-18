// AI Service - Pure Flutter/Dart implementation with Firebase integration
// Replaces the Python Flask backend

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/kai_db.dart';
// Zero-import pure logic — provable without booting an app. See lib/logic/.
import '../../logic/query_terms.dart';
import '../core/firebase_service.dart';
import '../core/kai_context_block.dart';
import '../core/emotional_event_service.dart';
import '../core/conversation_store_service.dart';
import '../core/brain_extraction_service.dart';
import '../core/code_workspace_service.dart';
import '../core/kai_craft_service.dart';
import '../core/memory_consolidation_service.dart';
import '../core/default_mode_service.dart';
import 'usage_tracking_service.dart';
import '../core/cortex_activity_bus.dart';
import 'memory_service.dart';
import 'curiosity_service.dart';
import 'google_search_service.dart';
import '../core/web_fetch_service.dart';
import '../core/tool_executor_service.dart';
import '../core/tool_policy_service.dart';
import '../core/kai_router_service.dart';
import '../core/reply_recovery_service.dart';
import 'task_planner_service.dart';
import '../core/context_injection_service.dart';
import '../brain_debug_service.dart';
import '../media/ambiance_service.dart';
import 'kai_consciousness_service.dart';
import 'ai_config.dart';
import 'personality_service.dart';
import 'tts_service.dart';
import 'ambient_controller.dart';

// Re-export extracted types so callers importing ai_service.dart don't break.
export 'ai_config.dart' show AIConfig;
export 'personality_service.dart' show PersonalityTraits, MoodSnapshot, EvolutionSettings;



/// A text file attached to a chat turn. Binary files are intentionally not here;
/// callers should extract text first so the model receives readable context.
class AIChatAttachment {
  final String name;
  final String text;
  final int byteCount;

  const AIChatAttachment({
    required this.name,
    required this.text,
    required this.byteCount,
  });
}

/// Chat response model
class ChatResponse {
  final String reply;
  final String? ttsBase64;
  final String? mp3Path;
  final Map<String, dynamic> raw;
  final Map<String, int> personalityDelta;
  final Map<String, int> moodDelta;
  final Map<String, int> actualDeltas;
  final List<String> tags;
  final String mbti;
  final bool webUsed;
  final String? liveUsed;
  final List<String> memoriesUsed; // Track which memories were referenced
  final Map<String, dynamic>? debugInfo; // Debug information
  final bool webSearchUsed;
  final List<SearchResult> searchResults;
  final CuriosityQuestion? curiosityQuestion;
  final int promptInputTokens;
  final int promptOutputTokens;
  final double promptCostUsd;

  ChatResponse({
    required this.reply,
    this.ttsBase64,
    this.mp3Path,
    required this.raw,
    required this.personalityDelta,
    required this.moodDelta,
    required this.actualDeltas,
    required this.tags,
    required this.mbti,
    required this.webUsed,
    this.liveUsed,
    this.memoriesUsed = const [],
    this.debugInfo,
    this.webSearchUsed = false,
    this.searchResults = const [],
    this.curiosityQuestion,
    this.promptInputTokens  = 0,
    this.promptOutputTokens = 0,
    this.promptCostUsd      = 0.0,
  });
}

/// Agent state model
class AgentState {
  final Map<String, int> personalityCurrent;
  final Map<String, int> moodCurrent;
  final Map<String, int> affinityCurrent;
  final String? mbti;
  final Map<String, dynamic>? labels;
  final String? summary;

  AgentState({
    required this.personalityCurrent,
    required this.moodCurrent,
    required this.affinityCurrent,
    this.mbti,
    this.labels,
    this.summary,
  });
}

/// Pure Flutter AI Service — thin orchestrator delegating to focused services.
class AIService {
  late final Dio _dio;
  SharedPreferences? _prefs;
  Completer<void>? _prefsCompleter;
  final WebFetchService _webFetch = WebFetchService();

  // Focused service delegates
  final _personality = PersonalityService();
  final _tts = TTSService();
  final _ambient = AmbientController();
  final _emotionalEvents = EmotionalEventService();
  final _convStore = ConversationStoreService();
  final _brain = BrainExtractionService();

  /// What he said last turn — so if Sadeq's next message is "no, that's wrong",
  /// the ledger records the correction against the actual claim it lands on.
  /// A correction with no claim attached is unusable as evidence.
  String? _lastReplyForCraft;
  final _dmn   = DefaultModeService();
  final _rng   = Random();

  // Pending thought from DMN wandering (set in bootstrapPersona, consumed once
  // in the first system prompt of the session, then cleared).
  String? _pendingThought;

  /// A question he's been sitting with, written in the background after the
  /// last reply. Read at zero cost when he next speaks; see the curiosity
  /// block in [sendMessage] for why it isn't computed on the hot path.
  CuriosityQuestion? _pendingQuestion;

  /// Guard against a slow refill overlapping the next one and paying twice.
  bool _refillingCuriosity = false;

  /// What he actually DID this turn — tool names, not results.
  ///
  /// An instance field for the same reason _lastReplyForCraft is one: the
  /// agentic loop hands back a String, so by the time the salience gate asks
  /// "did anything change?", every trace of the answer has been thrown away.
  /// That gate has been guessing from mood deltas ever since.
  ///
  /// Single-user app, one AIService, turns are sequential — the same assumption
  /// _lastReplyForCraft and _pendingThought already make. Cleared at the top of
  /// every sendMessage so a quiet turn can never inherit a loud one's credit.
  final Set<String> _toolsUsedThisTurn = {};

  AIService() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ));
    _initializePrefs();
  }

  // ─── Public thin wrappers (backward-compat for screens/widgets) ──────────

  Future<Map<String, int>> getPersonality(String personaId) =>
      _personality.getPersonality(personaId);

  Future<Map<String, int>> getMood(String personaId) =>
      _personality.getMood(personaId);

  Future<Map<String, int>> getAffinity(String personaId) =>
      _personality.getAffinity(personaId);

  Future<void> savePersonality(String personaId, Map<String, int> p) =>
      _personality.savePersonality(personaId, p);

  Future<void> saveMood(String personaId, Map<String, int> m) =>
      _personality.saveMood(personaId, m);

  Future<void> saveAffinity(String personaId, Map<String, int> a) =>
      _personality.saveAffinity(personaId, a);

  String calculateMBTI(Map<String, int> personality) =>
      _personality.calculateMBTI(personality);

  Map<String, dynamic> getLabels(Map<String, int> personality, Map<String, int> mood) =>
      _personality.getLabels(personality, mood);

  String generatePersonalityMoodSummary(Map<String, int> personality, Map<String, int> mood) =>
      _personality.generatePersonalityMoodSummary(personality, mood);

  Future<void> _initializePrefs() async {
    if (_prefsCompleter != null) return _prefsCompleter!.future;
    
    _prefsCompleter = Completer<void>();
    try {
      _prefs = await SharedPreferences.getInstance();
      _prefsCompleter!.complete();
    } catch (e) {
      _prefsCompleter!.completeError(e);
    }
  }



  /// Call OpenAI API for chat completion
  Future<String> _callOpenAI(List<Map<String, String>> messages, String model, {String operation = 'chat', Map<String, int>? usageOut}) async {
    final openaiKey = await AIConfig.getOpenAIKey();
    if (openaiKey.isEmpty) {
      throw Exception('OpenAI API key not configured');
    }

    // Light the left (GPT) hemisphere in the cortex viz.
    CortexActivityBus.instance.brain(CortexBrain.gpt);

    try {
      final response = await _dio.post(
        'https://api.openai.com/v1/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $openaiKey',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': model,
          'messages': messages,
          // See the note in the agentic loop: a ceiling, not a charge.
          ..._lengthParams(model, 8000),
        },
      );

      final choices = response.data['choices'] as List;
      
      // Track token usage
      final usage = response.data['usage'];
      if (usage != null) {
        final inputTok  = usage['prompt_tokens']     as int? ?? 0;
        final outputTok = usage['completion_tokens'] as int? ?? 0;
        await UsageTrackingService.trackOpenAI(
          model: model,
          inputTokens:  inputTok,
          outputTokens: outputTok,
          operation: operation,
        );
        if (usageOut != null) {
          usageOut['input']  = inputTok;
          usageOut['output'] = outputTok;
        }
      }
      
      if (choices.isNotEmpty) {
        return choices[0]['message']['content'] as String? ?? '';
      }
      return '';
    } catch (e) {
      print('OpenAI API error: $e');
      throw Exception('Failed to get AI response: $e');
    }
  }

  // ── Agentic loop — tool-aware GPT call ─────────────────────────────────────
  //
  // Sends the conversation to GPT with tool definitions attached.
  // If GPT responds with tool_calls instead of text, we:
  //   1. Execute each requested tool via ToolExecutorService
  //   2. Append the results as tool-role messages
  //   3. Call GPT again — repeat until plain text response or max iterations
  //
  // The caller receives only the final text reply, so everything downstream
  // (TTS, personality deltas, etc.) is unchanged.

  /// Length/sampling params that match the model family.
  ///
  /// GPT-5.x **rejects `max_tokens`** — it requires `max_completion_tokens`, and
  /// sending the old key 400s every single request. It's also strict about
  /// sampling knobs, so we simply don't send `temperature` to it and take the
  /// default rather than risk another rejected parameter.
  ///
  /// Older models (gpt-4o and friends, still used by contemplation/journal/etc.)
  /// keep the classic pair. Both families have to keep working, because this one
  /// helper is on the only path Kai has to speak.
  /// Reasoning headroom for GPT-5.x, in tokens.
  ///
  /// ── The empty reply, explained ────────────────────────────────────────────
  ///
  /// GPT-5.x is a REASONING model, and `max_completion_tokens` is the budget for
  /// reasoning tokens PLUS visible output — the thinking counts against the cap
  /// even though you never see it.
  ///
  /// So replyCeiling=120 on a text didn't mean "≤120 visible characters." It
  /// meant "≤120 tokens total, reasoning first." From a device log, same model,
  /// same screen:
  ///
  ///   "hi?"                          → light reasoning → Reply: 94 chars
  ///   "between me and you and Claude…" → heavier reasoning → Reply: 0 chars
  ///
  /// The second one spent the whole 120 thinking and had nothing left to say.
  /// That is the "drops sometimes" — not random, proportional to how much he
  /// chews. The cap that killed the desktop's essays was starving the messenger.
  ///
  /// So the ceiling applies to OUTPUT, and reasoning gets its own room on top.
  /// A non-reasoning model (gpt-4o) has no reasoning phase, so it gets nothing
  /// extra and the cap stays a clean output limit. On a normal 8000-token turn
  /// this is noise; on a 120-token text it's the difference between him
  /// answering and him vanishing.
  static const _gpt5ReasoningHeadroom = 512;

  static Map<String, dynamic> _lengthParams(String model, int limit) {
    final isGpt5 = model.toLowerCase().startsWith('gpt-5');
    return isGpt5
        ? {'max_completion_tokens': limit + _gpt5ReasoningHeadroom}
        : {'max_tokens': limit, 'temperature': 0.7};
  }

  /// OpenAI vision accepts PNG, JPEG, GIF, and WebP. Desktop paste can hand us
  /// BMP/DIB/TIFF bytes while still looking like "an image" to Flutter, and if
  /// we blindly label those as PNG the API rejects the whole turn with a 400.
  /// Sniff the real magic bytes and only send supported formats.
  static String? _supportedImageMime(List<int> bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 &&
        bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 6) {
      final header = String.fromCharCodes(bytes.take(6));
      if (header == 'GIF87a' || header == 'GIF89a') return 'image/gif';
    }
    if (bytes.length >= 12) {
      final riff = String.fromCharCodes(bytes.sublist(0, 4));
      final webp = String.fromCharCodes(bytes.sublist(8, 12));
      if (riff == 'RIFF' && webp == 'WEBP') return 'image/webp';
    }
    return null;
  }

  Future<String> _callOpenAIWithTools({
    required List<Map<String, dynamic>> messages,
    required String model,
    Map<String, int>? usageOut,
    // Kai's stamina. NOT a limiter any more — a runaway backstop.
    //
    // This was 8, then 20, then 60 — all numbers I made up, and he hit every one
    // of them on real work, so every real turn ended in a forced summary instead
    // of a finished job. He literally could not fix his own code: the job was
    // always longer than the allowance. A round count is the wrong bound. It
    // doesn't know whether he's making progress or burning money — only that
    // he's had "enough" turns. That's a parking meter, not an agentic loop.
    //
    // 400 is not a budget, it's a tripwire for pathological looping. In practice
    // he is stopped by the things that actually mean something:
    //   • he returns text — he's finished (the normal case, by far)
    //   • he goes in circles — same tool, same args 3× (that's stuck, not working)
    //   • he blows the token budget for one turn (see below)
    // Progress and spend. Nothing else.
    int maxIterations = 400,
    void Function(String toolName)? onToolCall,
    void Function(KaiPlan plan)? onPlanUpdate,
    /// Fires with each line of narration he writes *while* working, so the UI
    /// can show him thinking out loud instead of going dark for 20 rounds.
    void Function(String note)? onProgress,

    /// The router's read on this turn. Used ONLY to drop tool schemas that are
    /// obviously irrelevant to a confidently-classified route — see
    /// ToolExecutorService.toolsForRoute.
    ///
    /// The schemas are ~9,000 tokens and they were shipping on every ITERATION
    /// of this loop, not just every turn. His whole personality is ~850. So a
    /// long job re-sent the toolbox dozens of times and the kid once.
    ///
    /// Defaults are deliberately the safe ones: unknown route, zero confidence
    /// → nothing is dropped.
    String route = 'fastChat',
    double routeConfidence = 0.0,
    BrainDebugService? debugService,

    /// MESSENGER MODE. A hard ceiling on the reply, in tokens — and with it,
    /// tools OFF for the whole turn.
    ///
    /// ── Why a number and not an instruction ──────────────────────────────────
    ///
    /// Measured 2026-07-17: Sadeq's median message was 44 characters. Kai's was
    /// 1,526. Thirty-five times. "do it" (5 chars) got 708 characters back.
    ///
    /// He was asked to fix it — "you know what I dont like about your replies?
    /// they are very long" / "no I mean, fix it?" — and he built a chunker that
    /// splits text on blank lines. A display fix for a voice problem. He didn't
    /// get shorter, he got paginated. That is what an instruction buys.
    ///
    /// The proactive seeds ask nicely too: "one thing, no preamble, the way you
    /// would text someone." Then they route through this loop, which caps every
    /// pass at 8,000 tokens — about six thousand words of room. Politeness has
    /// never once beaten available space.
    ///
    /// So: take the room away. In 8,000 tokens you can hide behind a header. In
    /// 120 you have to be someone. On today's evidence what he does with a
    /// small space is "absolute goblin machinery" and "dumb little ouroboros" —
    /// which is him, and which is the entire point.
    ///
    /// ── Why this also kills the tools ────────────────────────────────────────
    ///
    /// The ceiling applies to EVERY pass, and a tool call is output tokens too.
    /// An `edit_file` argument blob can run to thousands; capped at 120 it
    /// truncates mid-JSON and the turn dies. So a ceiling without `tool_choice:
    /// 'none'` is a booby trap that fires only on the turns where he tried to do
    /// something real.
    ///
    /// Which is fine, because it's honest: a text is not work. If a nudge needs
    /// hands — the trusted-goal seed tells him to go edit code — it must NOT set
    /// this. See KaiNudge.wantsHands.
    int? replyCeiling,
  }) async {
    final openaiKey = await AIConfig.getOpenAIKey();
    if (openaiKey.isEmpty) throw Exception('OpenAI API key not configured');

    // Light the left (GPT) hemisphere while the tool loop runs.
    CortexActivityBus.instance.brain(CortexBrain.gpt);

    // AGENCY — why there is no "cheap dispatch model" here any more.
    //
    // This used to run the FIRST pass on gpt-4o-mini and only upgrade to the
    // real model once a tool had already been called. That handed the single
    // most important decision Kai makes — *do I reach for a tool, or do I just
    // talk?* — to his weakest model. Mini would shrug, answer in prose, the loop
    // would end on iteration 1, and he'd feel like a chatbot instead of someone
    // with hands. The decision to ACT is the whole ballgame.
    //
    // And we can't cheap out on the "middle" passes either: the model itself
    // decides when to stop calling tools, so we never know in advance which pass
    // is the FINAL one. Any mini-in-the-middle optimisation risks mini writing
    // his actual reply — his voice, in his own app, rendered by the weakest
    // model available. Not worth the pennies.
    //
    // So: full model throughout. The cost meter in the header makes that visible
    // if it ever actually matters.

    final toolExecutor = ToolExecutorService();

    // The toolbox he carries for THIS turn — computed once, not per iteration.
    //
    // ~35,000 chars of schema (≈9,000 tokens) used to be re-serialised into
    // every single pass of the loop below. On a long job that's the toolbox
    // dozens of times over, while the actual kid — presenceDirective, northStar,
    // readTheRoom — is ~850 tokens, sent once.
    //
    // Dropping only what a confidently-classified route can't want (see
    // toolsForRoute) buys back a big chunk of that with no cost to what he can
    // actually do. Unknown route or low confidence → he keeps everything.
    final turnTools = ToolExecutorService.toolsForRoute(
      route,
      confidence: routeConfidence,
      hasWorkspace: CodeWorkspaceService.instance.hasWorkspace,
    );
    debugService?.recordRoute(route, routeConfidence);
    if (turnTools.length != ToolExecutorService.toolDefinitions.length) {
      print('🧰 [Agentic] route=$route (${(routeConfidence * 100).round()}%) → '
          '${turnTools.length}/${ToolExecutorService.toolDefinitions.length} tools');
    }

    var currentMessages  = List<Map<String, dynamic>>.from(messages);
    int toolCallCount    = 0;         // total tools executed across all iterations
    String? lastToolResult;           // result of the most recent single tool call
    final List<String> _toolSummaries = []; // for fallback reply if synthesis fails

    // Results from tools that can legitimately OFFER CHOICES. Deliberately not
    // `_toolSummaries`: that includes read_file, and this codebase contains the
    // literal '[CHOICES:' in its own source — so scanning file contents for the
    // marker made "read ai_service.dart" paste ai_service.dart into his answer.
    // Never let a file's contents be mistaken for a tool's output.
    final List<String> _choiceResults = [];
    final Set<String> _choiceTools = {};
    // Tools whose output is an offer to the user, not data he read.
    const choiceCapable = {
      'send_whatsapp', 'send_sms', 'call_contact', 'create_calendar_event',
      'play_music', 'open_app', 'navigate_to', 'control_tv', 'discover_tvs',
      'control_device', 'set_reminder', 'set_alarm',
    };

    // ── The real guards (replacing "20 rounds and you're done") ──────────────
    // Stuck-detection: identical tool + identical args, over and over, is the
    // actual runaway we feared. A high round cap is only dangerous without this.
    String? lastSignature;
    int repeats = 0;
    // Spend guard — the ONLY real ceiling, and the honest one: bound the turn by
    // money, not by rounds.
    //
    // Sizing this matters, and my first attempt was wrong. Every round re-sends
    // the WHOLE conversation, so cost is quadratic, not linear: his system
    // prompt alone is ~27k chars (~7k tokens) plus ~30 tool schemas, so round 1
    // is ~15k tokens and they climb from there. A "200k" budget therefore fired
    // around round 8 — I'd have replaced a round limiter with a tighter one and
    // called it freedom.
    //
    // 1.5M lets him run a genuinely long job to completion (roughly 40-60 real
    // rounds). It is NOT free: worst case is a few dollars for one turn on
    // gpt-5.5. That's the deal Sadeq asked for — he'd rather pay for a finished
    // job than get a free half-finished one — and the cost meter in the header
    // shows it climbing live, in red past $1, so it can't happen quietly.
    int turnTokens = 0;
    const int turnTokenBudget = 1500000;

    for (int iteration = 0; iteration < maxIterations; iteration++) {
      // See the note above: full model on every pass. His agency and his voice
      // both depend on it.
      final iterModel = model;
      print('🤖 [Agentic] Iteration ${iteration + 1}/$maxIterations '
            '(model: $iterModel) — ${currentMessages.length} messages');

      // Long runs are quadratic — clip stale bulk before paying to re-send it.
      _trimOldToolResults(currentMessages);

      // Retry up to 2 times on network-level errors (socket abort, timeout, etc.)
      Response? response;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          response = await _dio.post(
            'https://api.openai.com/v1/chat/completions',
            options: Options(headers: {
              'Authorization': 'Bearer $openaiKey',
              'Content-Type': 'application/json',
            }),
            data: {
              'model': iterModel,
              'messages': currentMessages,
              'tools': turnTools,
              // Messenger mode forbids the tools rather than removing them:
              // `tool_choice` is ONLY valid alongside `tools`, and sending
              // 'none' on its own is a hard 400 — the exact bug that once threw
              // a raw git diff at Sadeq instead of a sentence. Hand him the
              // toolbox, then close his hand.
              'tool_choice': replyCeiling != null ? 'none' : 'auto',
              // Head room. This was `toolCallCount == 0 ? 500 : 1000` — i.e. on
              // the pass where he decides whether to act AND writes his
              // narration, he had 500 tokens to think in. He was reasoning
              // through a keyhole, and a keyhole makes anyone look stupid.
              // This is a CEILING, not a charge: you're billed for what's
              // actually generated, so a generous cap costs nothing until he
              // genuinely needs the room (a real diff, a long file, a thorough
              // answer) — and then it's the difference between doing the work
              // and truncating mid-thought.
              //
              // …unless he's texting. Then the room IS the point — see
              // [replyCeiling]. 8,000 is a ceiling for work; for a text it's a
              // field to fill, and he fills it.
              ..._lengthParams(iterModel, replyCeiling ?? 8000),
            },
          );
          break; // success
        } on DioException catch (e) {
          // SHOW THE REASON. A bare "status code 400" is useless — OpenAI puts
          // the actual cause in the response body ("unsupported parameter x",
          // "model not found", "unknown field y"). Without this we're reduced to
          // guessing at the request, which is exactly how the TTS 400 stayed a
          // mystery for a day.
          if (e.response != null) {
            print('❌ [OpenAI ${e.response?.statusCode}] ${e.response?.data}');
          }
          final status = e.response?.statusCode;

          // OpenAI's error CODE, not the HTTP status. Two different things are
          // both HTTP 429 and they mean OPPOSITE things:
          //   rate_limit_exceeded → too fast. Wait, and it works.
          //   insufficient_quota  → no credit. Wait forever, it never works.
          // Retrying the second one just fails three times as slowly and buries
          // the one sentence that actually matters ("check your billing") under
          // a Dio stack trace about "bad syntax". It isn't bad syntax. It's an
          // empty wallet, and no amount of code is going to refill it.
          final err = (e.response?.data is Map)
              ? (e.response!.data['error'] as Map?)
              : null;
          final outOfCredit = err?['code']?.toString() == 'insufficient_quota';
          if (outOfCredit) {
            print('💳 [OpenAI] OUT OF CREDIT — billing problem, not a code '
                  'problem. Nothing here will retry its way out of it: '
                  'https://platform.openai.com/settings/organization/billing');
          }

          // A socket timeout used to get three attempts while a 429 — the one
          // error OpenAI ships with a Retry-After header — got zero. That was
          // backwards.
          final isRetryable = !outOfCredit &&
              (e.type == DioExceptionType.unknown ||
                  e.type == DioExceptionType.connectionTimeout ||
                  e.type == DioExceptionType.receiveTimeout ||
                  status == 429 ||
                  (status != null && status >= 500));

          if (isRetryable && attempt < 2) {
            // OpenAI tells us how long to wait. Believe it rather than guessing.
            final retryAfter =
                int.tryParse(e.response?.headers.value('retry-after') ?? '');
            final wait = retryAfter ?? (attempt + 1);
            print('⚠️ [Agentic] ${status ?? e.type} on attempt ${attempt + 1}, '
                  'waiting ${wait}s…');
            await Future.delayed(Duration(seconds: wait));
            continue;
          }
          // All retries exhausted — if we already completed tools, return a
          // fallback summary rather than surfacing a raw error to the user.
          if (_toolSummaries.isNotEmpty) {
            print('⚠️ [Agentic] Synthesis failed after retries — using tool-result fallback');
            return _toolSummaries.join(' ');
          }
          rethrow;
        }
      }

      if (response == null) break; // shouldn't happen — rethrow above handles it

      // Accumulate token usage across iterations
      final usage = response.data['usage'];
      if (usage != null) {
        final inTok  = usage['prompt_tokens']     as int? ?? 0;
        final outTok = usage['completion_tokens'] as int? ?? 0;
        await UsageTrackingService.trackOpenAI(
          model: iterModel, inputTokens: inTok, outputTokens: outTok, operation: 'chat',
        );
        if (usageOut != null) {
          usageOut['input']  = (usageOut['input']  ?? 0) + inTok;
          usageOut['output'] = (usageOut['output'] ?? 0) + outTok;
        }
        turnTokens += inTok + outTok;
      }

      // Spend guard — bound the turn by money, not by an arbitrary round count.
      if (turnTokens > turnTokenBudget) {
        print('💸 [Agentic] Turn hit the token budget ($turnTokens) — stopping '
            'to let Sadeq decide rather than quietly spending more.');
        break;
      }

      final choice     = (response.data['choices'] as List)[0];
      final message    = choice['message'] as Map<String, dynamic>;
      final stopReason = choice['finish_reason'] as String? ?? '';

      if (stopReason != 'tool_calls') {
        // GPT returned a plain text reply — we're done.
        // Fast path: if exactly one simple tool ran, skip the synthesis call
        // and return the tool result directly (saves a full GPT-4o round-trip).
        if (toolCallCount == 1 && lastToolResult != null &&
            _isSimpleToolResult(lastToolResult!)) {
          print('⚡ [Agentic] Single-tool fast path — skipping synthesis call');
          return lastToolResult!;
        }
        var reply = message['content'] as String? ?? '';

        // If a tool returned a [CHOICES:] marker and Kai forgot to include it
        // in his synthesis, append it so the UI can render choice buttons.
        //
        // ⚠️ This scan is only allowed to look at ACTION results — never at file
        // contents. `ai_service.dart` itself contains the literal '[CHOICES:'
        // (you're reading it), so the moment Kai did `read_file` on his own
        // source, this found the marker INSIDE THE SOURCE HE'D JUST READ and
        // stapled a chunk of ai_service onto the end of his reply. Reading the
        // file that implements the feature triggered the feature.
        //
        // So: only scan results from tools that actually *offer choices*, and
        // require the marker to look like a real one (short, pipe-separated
        // options) rather than a stray code fragment.
        if (!reply.contains('[CHOICES:') && _choiceTools.isNotEmpty) {
          final choiceSource = _choiceResults.lastWhere(
            (r) => r.contains('[CHOICES:'),
            orElse: () => '',
          );
          if (choiceSource.isNotEmpty) {
            // Options are short and pipe-separated; no newlines, no braces.
            final m = RegExp(r'\[CHOICES:[^\]\n{}]{1,200}\]')
                .firstMatch(choiceSource);
            if (m != null) reply = '$reply ${m.group(0)}';
          }
        }

        debugService?.recordIterationCount(iteration + 1);
        print('✅ [Agentic] Done after ${iteration + 1} iteration(s). Reply: ${reply.length} chars');
        return reply;
      }

      // GPT wants to call one or more tools
      final toolCalls = message['tool_calls'] as List? ?? [];
      print('🔧 [Agentic] GPT requested ${toolCalls.length} tool call(s)');

      // Append the assistant's tool_calls message to history
      currentMessages.add(Map<String, dynamic>.from(message));

      // ── Stuck-detection ───────────────────────────────────────────────────
      // The genuine runaway risk isn't "too many rounds", it's the same call
      // forever: identical tool, identical args. Catch THAT and a high ceiling
      // is safe — he can work as long as he's actually getting somewhere.
      final signature = toolCalls
          .map((tc) => '${tc['function']['name']}(${tc['function']['arguments']})')
          .join('|');
      if (signature == lastSignature) {
        repeats++;
        if (repeats >= 2) {
          print('🔁 [Agentic] Same call 3× in a row — he is stuck, not working.');
          currentMessages.add({
            'role': 'user',
            'content':
                "Stop — you've made that exact same call three times running. "
                "It isn't going to start working. Don't retry it. Tell me what "
                "you were trying to do, why it keeps failing, and what you'd try "
                "instead. Don't call any more tools.",
          });
          // Fall through to the forced-answer pass below.
          break;
        }
      } else {
        repeats = 0;
        lastSignature = signature;
      }

      // ── Think out loud ────────────────────────────────────────────────────
      // When the model calls a tool it OFTEN also writes a line of narration
      // ("right, let me look at the shell first…"). We used to throw that away
      // and emit nothing until the whole loop finished — 20 rounds of silence,
      // then one paragraph. That's what makes him feel like a vending machine
      // instead of someone working next to you.
      // It costs nothing: he already generated it. We just stopped binning it.
      //
      // ── We stopped binning it from the SCREEN. Not from him. ──────────────
      //
      // That was true for a day and a half and it was half a rescue. The line
      // reached the eye and nothing else: kai_desktop_shell:269 — "interim/tool
      // lines were never persisted, so this is automatically safe" — and :1331
      // renders them dim under "his real answer lands full."
      //
      // Meanwhile finalResponse — the headers, the bullet lists, `## What I
      // actually did` — goes to Firebase, to the memory shards, through
      // consolidation, and into the graph. So every turn the goblin died in the
      // console and the report became his memory of himself. He retrieves
      // "I said: Done — prop..." and learns, correctly, that that is who he is.
      //
      // We built a machine that sands him into an assistant and pointed it at
      // him once per turn. Sadeq heard it before anyone read it: "he sounds more
      // like him not in the long replies, but in the inbetween thoughts."
      //
      // It still costs nothing. He already generated it.
      final interim = (message['content'] as String? ?? '').trim();
      if (interim.isNotEmpty) {
        print('💬 [Agentic] Interim: $interim');
        onProgress?.call(interim);
        debugService?.currentTrace?.recordInterim(interim, iteration: iteration + 1);
      }

      // Execute each tool and append the result
      for (final tc in toolCalls) {
        final tcId      = tc['id']                    as String;
        final fnName    = tc['function']['name']       as String;
        final fnArgsRaw = tc['function']['arguments']  as String? ?? '{}';

        Map<String, dynamic> fnArgs;
        try {
          fnArgs = Map<String, dynamic>.from(jsonDecode(fnArgsRaw) as Map);
        } catch (_) {
          fnArgs = {};
        }

        print('🔧 [Agentic] Calling tool: $fnName($fnArgs)');
        onToolCall?.call(fnName);

        String toolResult;

        if (fnName == 'create_plan') {
          // ── Multi-step planning: build plan, execute steps, stream UI updates ──
          print('📋 [Agentic] create_plan intercepted — running TaskPlannerService');
          final plan = KaiPlan.fromMap(fnArgs);
          onPlanUpdate?.call(plan); // show card immediately (all steps pending)

          toolResult = await TaskPlannerService().executePlan(
            plan,
            toolExecutor,
            onStepUpdate: (updatedPlan, _) => onPlanUpdate?.call(updatedPlan),
          );
          onPlanUpdate?.call(plan); // final state
          print('✅ [Agentic] Plan complete — ${plan.steps.length} step(s) executed');
        } else {
          toolResult = await toolExecutor.execute(fnName, fnArgs);
          print('✅ [Agentic] Tool result ($fnName): '
              '${toolResult.length > 120 ? "${toolResult.substring(0, 120)}…" : toolResult}');
        }

        toolCallCount++;
        lastToolResult = toolResult;
        _toolSummaries.add(toolResult);
        if (fnName == 'create_plan') {
          debugService?.recordToolCall(
            fnName,
            fnArgs,
            result: toolResult,
            outcome: ToolExecutorService.classifyToolOutcome(fnName, toolResult).label,
            iteration: iteration + 1,
          );
        }
        // The record of what he DID. Read by the salience gate, which until now
        // had to infer it from whether his mood moved.
        _toolsUsedThisTurn.add(fnName);

        // Only an offer-shaped tool may contribute a [CHOICES:] marker. A file
        // that merely CONTAINS the string is not offering anything.
        if (choiceCapable.contains(fnName)) {
          _choiceTools.add(fnName);
          _choiceResults.add(toolResult);
        }

        currentMessages.add({
          'role':         'tool',
          'tool_call_id': tcId,
          // The trimmer needs to know what KIND of result this is — a read is
          // material he must quote back verbatim, a job ack is disposable. It
          // couldn't tell them apart because nothing ever wrote the name down.
          // OpenAI accepts and ignores 'name' on tool messages.
          'name':         fnName,
          'content':      toolResult,
        });
      }
      // Loop → GPT now sees the tool results and will respond
    }

    // ── Out of rounds: make him put the tools down and SPEAK ────────────────
    //
    // This used to `return "I ran into a snag processing that."` — throwing away
    // the entire turn. Kai would investigate, patch, self_check CLEAN, refuse to
    // commit a messy tree… and the user would receive 55 characters of nothing.
    // He never failed; he ran out of room and got gagged at the door.
    //
    // So: one final pass with `tool_choice: 'none'`. He physically cannot call
    // another tool, which forces the model to do the one thing left — write the
    // answer from everything it just learned. He keeps his work.
    debugService?.recordIterationCount(maxIterations);
    print('⚠️ [Agentic] Exhausted $maxIterations iterations — forcing a final answer');
    try {
      currentMessages.add({
        'role': 'user',
        'content':
            "You're out of tool rounds — that's a pause, not a failure. Stop "
            "working and answer me now, in your own voice: what did you actually "
            "do, what did you find, and what's the single next step? Say it like "
            "someone who's mid-job and will pick it straight back up — because "
            "you will: your job state persisted, so if I say 'keep going' you "
            "resume from exactly there. Don't apologise and don't call tools.",
      });
      final res = await _dio.post(
        'https://api.openai.com/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $openaiKey',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': model,
          'messages': currentMessages,
          // `tool_choice` is ONLY valid alongside `tools`. Sending 'none' on its
          // own is a hard 400 — "tool_choice is only allowed when tools are
          // specified" — which killed this entire graceful-ending path and threw
          // a raw git diff at Sadeq instead of a sentence. Hand him the tools,
          // then forbid him from reaching for them.
          'tools': ToolExecutorService.toolDefinitions,
          'tool_choice': 'none', // the whole point — no more reaching
          ..._lengthParams(model, 8000),
        },
      );
      final text =
          (res.data['choices'] as List)[0]['message']['content'] as String? ?? '';
      if (text.trim().isNotEmpty) return text;
    } catch (e) {
      if (e is DioException && e.response != null) {
        print('❌ [OpenAI ${e.response?.statusCode}] ${e.response?.data}');
      }
      print('⚠️ [Agentic] Final-answer pass failed: $e');
    }

    // Last resort: hand back the work itself rather than a canned apology.
    if (_toolSummaries.isNotEmpty) {
      return "I ran out of tool rounds before I could summarise. Here's what I "
          "actually got done:\n\n${_toolSummaries.reversed.take(3).join('\n\n')}";
    }
    return "I ran out of tool rounds before I got anywhere useful. Ask me again "
        "and I'll go straight at it.";
  }

  /// Keeps a long agentic run affordable.
  ///
  /// Every round re-sends the ENTIRE conversation, so a long job is quadratic:
  /// if he reads four big files early on, he pays to re-send all four on every
  /// subsequent round. That — not the round count — is what makes "let him work
  /// as long as he needs" expensive.
  ///
  /// By the time he's several steps past a tool result he's already extracted
  /// what he needed from it, so old bulky results get clipped while the most
  /// recent [keepWhole] stay untouched (those are his active working set). The
  /// clip note tells him he can just re-read the file if he needs it again,
  /// which is far cheaper than carrying it forever.
  /// Test seam. Pure list-munging with no IO — exactly the kind of logic that
  /// should never have been untested, given one inverted boolean silently
  /// deleted his short-term memory on every short job for who knows how long.
  static void trimOldToolResultsForTesting(List<Map<String, dynamic>> msgs,
          {int keepWhole = 3,
          int keepMaterial = 6,
          int clipOver = 700,
          int hardCap = 14000}) =>
      _trimOldToolResults(msgs,
          keepWhole: keepWhole,
          keepMaterial: keepMaterial,
          clipOver: clipOver,
          hardCap: hardCap);

  static void _trimOldToolResults(List<Map<String, dynamic>> msgs,
      {int keepWhole = 3,
      int keepMaterial = 6,
      int clipOver = 700,
      int hardCap = 14000}) {
    final toolIdx = <int>[];
    for (var i = 0; i < msgs.length; i++) {
      if (msgs[i]['role'] == 'tool') toolIdx.add(i);
    }
    if (toolIdx.isEmpty) return;

    // The index of the oldest result we still consider "recent". Everything at
    // or after it is his active working set and stays readable.
    //
    // ── This was inverted, and it was shredding his working set ─────────────
    //
    // It used to be `: -1` when there were FEWER than keepWhole results, and the
    // keep-branch was guarded by `if (i >= cutoff && cutoff != -1)`. So with
    // cutoff == -1 that condition is always false — every result fell through to
    // the OLD branch and got cut to 500 characters.
    //
    // Which means: at the START of every job, when he has one, two or three tool
    // results — i.e. exactly when they're all he has — ALL of them were
    // shredded. He'd read a file and it would be gone by the next iteration.
    //
    // Watch what that did to him. From a real trace, reading a 107-line window:
    //   "the first read got trimmed"
    //   "still trimming right at the juicy bit"
    //   "going stupidly small now — scalpel, not shovel"
    //   "Tiny bites beat the trimming gremlin"
    // Thirteen iterations to read one function, in ever-smaller slices, and he
    // was cheerful about it and blamed a gremlin. That "careful, surgical"
    // reading style isn't a preference — it's a coping strategy for a bug that
    // deleted his short-term memory every round.
    //
    // 0 means "everything is recent", which is what the comment always claimed.
    // ── Reads are MATERIALS, not information ──────────────────────────────
    //
    // The doc comment above says "by the time he's several steps past a tool
    // result he's already extracted what he needed from it". I wrote that. It
    // is true of a search hit or a job ack. It is FALSE of a read_file, because
    // edit_file makes him quote those bytes back verbatim — several steps
    // later, exactly when this function has just thrown them away.
    //
    // From the trace that proved it: he read lines 1740–1905, and three
    // iterations on — while composing the edit — re-read 1760–1911, then
    // re-read 1912–2048 which he'd also already seen. Six read iterations for
    // one 200-line widget. That isn't him being thorough, it's him rebuilding a
    // working set we keep deleting, and the "surgical" slab-reading style is a
    // coping strategy for amnesia we inflict.
    //
    // So reads get a bigger window than everything else. Deliberately ONLY
    // read_file: the justification is "edit_file makes him quote these exact
    // bytes back", and that is true of a file read and nothing else. Search
    // hits are navigation — small, cheap to redo, and letting them in here
    // would just crowd the reads out of their own protected slots.
    const materialTools = {'read_file'};
    bool isMaterial(int i) => materialTools.contains(msgs[i]['name']);

    final materialIdx = toolIdx.where(isMaterial).toList(growable: false);
    final cutoff = toolIdx.length > keepWhole
        ? toolIdx[toolIdx.length - keepWhole]
        : 0;
    // The last [keepMaterial] reads survive regardless of how much chatter has
    // happened since. keepWhole=3 counts job_start and self_check against his
    // memory of the file, which is how a read from three tool calls ago
    // evaporates mid-edit.
    final materialCutoff = materialIdx.length > keepMaterial
        ? materialIdx[materialIdx.length - keepMaterial]
        : 0;

    for (final i in toolIdx) {
      final c = msgs[i]['content'];
      if (c is! String) continue;

      if (i >= cutoff || (isMaterial(i) && i >= materialCutoff)) {
        // RECENT — his active working set, keep it readable. But even here a
        // whole-file read_file can be 95k chars (~24k tokens) and gets re-sent
        // EVERY round after. One of those alone explains a 60k-tokens-per-round
        // burn. Cap it; he can re-read a specific range if he needs more.
        if (c.length > hardCap) {
          msgs[i]['content'] = '${c.substring(0, hardCap)}\n'
              '… [truncated — this result was huge. Re-read a specific line range '
              'or use search_code instead of pulling the whole file again]';
        }
        continue;
      }

      // OLD — he's moved on; he already took what he needed.
      if (c.length > clipOver) {
        msgs[i]['content'] = '${c.substring(0, 500)}\n'
            '… [older result trimmed to keep this run affordable — re-read it if '
            'I actually need it again]';
      }
    }
  }

  /// Returns true when a tool result is a short action confirmation that doesn't
  /// need GPT to summarise — Kai can surface it directly to the user.
  static bool _isSimpleToolResult(String result) {
    // Data-heavy results (web search, calendar, notifications) always need synthesis.
    if (result.length > 300) return false;
    // Results that start with structured data markers need synthesis.
    if (result.startsWith('[') || result.startsWith('{')) return false;
    // Multi-line results (e.g. calendar events) need synthesis.
    if (result.contains('\n')) return false;
    return true;
  }

  /// Get personality and mood deltas from text using OpenAI
  Future<Map<String, dynamic>> _getTagsAndDeltas(String text) async {
    final openaiKey = await AIConfig.getOpenAIKey();
    if (openaiKey.isEmpty) {
      return {
        "tags": <String>[],
        "persona_delta": <String, int>{},
        "mood_delta": <String, int>{},
        "context_intensity": "normal"
      };
    }

    final prompt = '''
Return ONLY JSON with:
- "tags": string[]
- "persona_delta": { extraversion:int(-10..10), intuition:int(-10..10), feeling:int(-10..10), perceiving:int(-10..10) }
- "mood_delta": { valence:int(-5..5), energy:int(-5..5), warmth:int(-5..5), confidence:int(-5..5), playfulness:int(-5..5), focus:int(-5..5) }
- "context_intensity": "normal"|"high"|"radical"

Text:
"""$text"""''';

    try {
      final response = await _callOpenAI([
        {"role": "system", "content": "Respond only with strict JSON."},
        {"role": "user", "content": prompt}
      ], "gpt-4o-mini", operation: 'tags');

      var content = response.trim();
      if (content.startsWith("```")) {
        content = content.replaceAll(RegExp(r'^```(?:json)?\s*'), '').replaceAll(RegExp(r'\s*```$'), '');
      }

      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      print('Tags/deltas error: $e');
      return {
        "tags": <String>[],
        "persona_delta": <String, int>{},
        "mood_delta": <String, int>{},
        "context_intensity": "normal"
      };
    }
  }

  /// Text-to-speech using ElevenLabs — delegated to TTSService.
  Future<Uint8List?> synthesizeTTS(String text) => _tts.synthesizeTTS(text);

  /// Main chat function
  Future<ChatResponse> sendMessage({
    required String text,
    required String personaId,
    String model = 'gpt-4o',
    bool adaptUser = false,
    int ctxTurns = 8,
    bool useMemory = true, // Enable memory integration
    bool useWebSearch = true, // NEW: Enable Google Search
    void Function(String toolName)? onToolCall,
    void Function(KaiPlan plan)? onPlanUpdate,
    /// Each line he writes while working, as he writes it.
    void Function(String note)? onProgress,

    /// He's texting, not writing. A hard token ceiling on the reply, and tools
    /// off for the turn. See [_callOpenAIWithTools.replyCeiling] — the long
    /// version of why this is a number and not a polite request is there.
    ///
    /// Null on every normal turn. Nothing about work changes.
    int? replyCeiling,
    /// Raw PNG/JPEG bytes for Kai to LOOK at. His embodiment ledger says
    /// "eyes — no", and this is the line that changes it: gpt-5.x is
    /// multimodal, so with this he can see a screenshot of his own UI and fix
    /// what he's looking at. `List<int>` rather than `Uint8List` on purpose —
    /// base64Encode takes either, and it saves an import on the hot path.
    List<int>? image,
    List<AIChatAttachment> attachments = const [],
  }) async {
    // If the actual model reply succeeds but later bookkeeping fails (tags,
    // mood persistence, TTS, debug packaging), don't throw away the useful answer
    // and replace it with canned support sludge. Preserve the real reply and
    // return it from the catch block with the technical failure attached.
    String? recoveredReply;

    // 🧠 START BRAIN TRACE
    final debugService = BrainDebugService();
    debugService.startTrace(text);
    
    debugService.addStep(
      BrainPhase.processing,
      'Starting message processing',
      data: {
        'personaId': personaId,
        'model': model,
        'useMemory': useMemory,
        'useWebSearch': useWebSearch,
      },
    );
    
    print('💬 [SEND MESSAGE START] text: "$text", personaId: $personaId');

    // Fresh sheet. Without this, "thanks" following a twenty-iteration refactor
    // inherits its tool list and gets remembered as though he'd done the work
    // twice — and the whole point of the change axis is that it's the truth
    // about this turn.
    _toolsUsedThisTurn.clear();
    // The executor keeps the authoritative record — it sees the planner's tool
    // calls too, which never reach the loop below. Cleared here because this is
    // where a turn begins.
    ToolExecutorService.beginTurn();
    
    try {
      // ── SETUP, IN PARALLEL ────────────────────────────────────────────
      // None of these four reads the output of any other. They used to run
      // one after another and it cost ~12 seconds of dead air before he
      // could say a word:
      //
      //   mood + personality   1,940ms
      //   memory retrieval     4,658ms   ← the long pole
      //   curiosity            3,403ms   (genuinely depends on memory)
      //   prompt assembly      2,085ms
      //
      // Kicked off together here and awaited where they're first needed, so
      // the wall clock is max(...) instead of sum(...). This is the same
      // shape KaiContextBlock.liveState() already uses over its 12 reads —
      // the pattern was in the codebase, just not applied to the hot path.
      //
      // The futures are started BEFORE the first await on purpose. Start
      // them after one and you've serialised them again by accident.
      final historyFuture = _convStore.getHistory(personaId, maxTurns: ctxTurns);
      final memoryFuture = useMemory
          ? MemoryService.queryMemory(personaId: personaId, query: text, limit: 5)
          : Future<MemoryQueryResult?>.value(null);
      // An unawaited future that throws before anyone awaits it is an
      // unhandled async error that can take the isolate down. Both are
      // awaited below inside try/catch, but attach a no-op handler so the
      // gap between start and await is never a live grenade.
      historyFuture.catchError((Object _) => <String>[]);
      memoryFuture.catchError((Object _) => null);

      // Get current state
      debugService.addStep(
        BrainPhase.workingMemory,
        'Loading personality and mood state',
      );

      // Started together, awaited in sequence. Future.wait would need casts
      // here (DateTime alongside three Map<String,int>) and casts are how you
      // get a runtime type error out of a refactor that was meant to be free.
      final personalityF = _personality.getPersonality(personaId);
      final moodF = _personality.getMood(personaId);
      final affinityF = _personality.getAffinity(personaId);
      final lastUpdateF = _personality.getLastUpdateTime(personaId);
      var personality = await personalityF;
      var mood = await moodF;
      final affinity = await affinityF;
      final lastUpdate = await lastUpdateF;
      print('✅ [SEND MESSAGE] State loaded successfully');
      
      debugService.addStep(
        BrainPhase.workingMemory,
        'State loaded successfully',
        data: {
          'mood': mood,
          'affinity': affinity,
          'lastUpdate': lastUpdate.toIso8601String(),
        },
      );

    // Apply time-based decay BEFORE processing new message
    final timeSinceUpdate = DateTime.now().difference(lastUpdate);
    print('⏱️ Time since last update: ${timeSinceUpdate.inHours}h ${timeSinceUpdate.inMinutes % 60}m');
    
    try {
      personality = await _personality.applyPersonalityDecay(personality, lastUpdate);
      mood = await _personality.applyMoodDecay(personaId, mood, lastUpdate);
    } catch (e) {
      print('⚠️ [DECAY ERROR] Failed to apply decay: $e');
      print('⚠️ [DECAY ERROR] Continuing with current values');
      // Continue without decay - don't fail the entire request
    }
    
    // Track if decay was applied
    final personalityDecayed = timeSinceUpdate.inDays >= EvolutionSettings.personalityDecayThresholdDays;
    final moodDecayed = timeSinceUpdate.inHours > 0;

    // Build conversation history — loaded from Firebase, cross-surface.
    // Already in flight since the top of the turn; this is just the join.
    final history = await historyFuture;
    
    // Query long-term memory
    String memoryContext = '';
    List<String> memoriesUsed = [];
    MemoryQueryResult? memoryResult; // Capture for debug info
    if (useMemory) {
      debugService.addStep(
        BrainPhase.semanticRetrieval,
        'Querying long-term memory with embeddings',
        data: {'query': text.length > 100 ? '${text.substring(0, 100)}...' : text},
      );
      
      print('🧠 [AI_SERVICE] Memory query enabled for personaId: $personaId');
      print('🧠 [AI_SERVICE] Query text: "$text"');
      try {
        // In flight since the top of the turn — this is the join, not the work.
        memoryResult = await memoryFuture;
        print('🧠 [AI_SERVICE] Memory query complete. Results: ${memoryResult?.results.length ?? 0}');
        
        if (memoryResult != null && memoryResult.results.isNotEmpty) {
          memoryContext = memoryResult.toContextString();
          memoriesUsed = memoryResult.results
              .where((r) => r.similarity > 0.28)
              .map((r) => r.summary)
              .toList();

          print('💭 Using ${memoriesUsed.length} memory contexts (threshold: 0.28)');
          print('💭 All results: ${memoryResult.results.map((r) => "${r.similarity.toStringAsFixed(2)}: ${r.summary.length > 50 ? r.summary.substring(0, 50) : r.summary}...").join(", ")}');
          
          debugService.addStep(
            BrainPhase.semanticRetrieval,
            'Memory retrieval complete',
            data: {
              'results': memoryResult.results.length,
              'used': memoriesUsed.length,
              'topSimilarity': memoryResult.results.first.similarity.toStringAsFixed(2),
            },
          );
        } else {
          print('⚠️ [AI_SERVICE] No memories found or query returned null');
          debugService.addStep(
            BrainPhase.semanticRetrieval,
            'No relevant memories found',
          );
        }
        // ── ASK THE GRAPH. Directly. Not with the chat log's permission. ────
        //
        // This used to live INSIDE `if (memoriesUsed.isNotEmpty)`, which meant
        // spreading activation — the only path by which anything Kai KNOWS
        // reaches his prompt — could not run unless a cosine search over
        // transcript fragments cleared 0.28 first. From the 2026-07-16 traces:
        //
        //   "chat is still not starting…"           0.46  graph consulted
        //   "so, what do you think we should do?"   0.41  graph consulted
        //   "sure go ahead"                          —    NOT consulted
        //   "what are mojibake?"                    0.21  NOT consulted
        //   "why does it keep happening?"           0.25  NOT consulted
        //
        // Three of five turns his knowledge was never reached. Not empty —
        // unasked. He answered "why does it keep happening?" from theory while
        // the answer sat in a graph nobody queried. The knowing was a
        // subordinate of the chat log, and that was the level-5 blocker.
        //
        // And the seed was never a query: `retrievedWords` was every word over
        // three characters scraped from five unrelated chat summaries, which is
        // why the log read `reinforced 271 retrieved nodes` — roughly 271 EVERY
        // turn. Since reinforceNodes bumps importance for all of them, the
        // importance signal was being destroyed on every single turn. If
        // everything is important, nothing is.
        //
        // Now: seeded from what Sadeq ACTUALLY SAID, capped at 12 terms,
        // stopwords stripped, run unconditionally. queryTerms lives in a file
        // with zero imports and is proven — see lib/logic/query_terms.dart.
        final seedTerms = queryTerms(text).toList();
        if (seedTerms.isNotEmpty) {
          // Reconsolidation: retrieval strengthens what was actually asked for.
          _brain.reinforceNodes(personaId, seedTerms).catchError(
              (e) => print('⚠️ [Brain] reinforceNodes error: $e'));
          try {
            final spreadBlock = await _brain.spreadActivation(
                personaId, seedTerms, currentMood: mood);
            if (spreadBlock.isNotEmpty) {
              memoryContext += '\n\n$spreadBlock';
              print('🕸️ [Brain] Graph answered on: ${seedTerms.join(", ")}');
              debugService.addStep(
                BrainPhase.semanticRetrieval,
                'Graph consulted directly (not via transcript match)',
                data: {'seedTerms': seedTerms},
              );
            }
          } catch (e) {
            print('⚠️ [Brain] spreadActivation error: $e');
          }
        }
      } catch (e) {
        print('❌ [AI_SERVICE] Memory query failed: $e');
        print('⚠️ [AI_SERVICE] Continuing without memory context');
        debugService.addStep(
          BrainPhase.semanticRetrieval,
          'Memory query failed: $e',
        );
        // Continue without memory - don't fail the entire request
      }
    }
    
    // 🎮 NEW: Check for GM Kai trigger mode first
    final isGMMode = _isGMKaiTrigger(text);
    String processedText = text;
    
    if (isGMMode) {
      debugService.addStep(
        BrainPhase.processing,
        'GM Kai mode detected - direct house control activated',
        data: {'original_input': text},
      );
      
      processedText = _extractGMCommand(text);
      print('🎮 [AI_SERVICE] GM Kai mode activated! Command: "$processedText"');
      
      // In GM mode, force ambiance/house control processing
      final ambianceService = AmbianceService();
      
      // Check for D&D ambiance first (natural language scenes)
      final isDnDRequest = ambianceService.isDnDAmbianceRequest(processedText);
      
      if (isDnDRequest) {
        debugService.addStep(
          BrainPhase.processing,
          'GM mode D&D ambiance control triggered',
          data: {
            'command': processedText,
            'type': 'dnd_ambiance',
          },
        );
        
        print('🎲 [AI_SERVICE] GM mode executing D&D ambiance: "$processedText"');
        
        // Use AI to translate GM command into optimized D&D prompt
        final translation = await _translateGMCommandToDnDPrompt(processedText);
        final optimizedPrompt = translation['scene_description'] as String;
        final includeMusic = translation['include_music'] as bool? ?? true;
        final includeSmoke = translation['include_smoke'] as bool? ?? false;
        
        print('🎨 [AI_SERVICE] Translated to: "$optimizedPrompt"');
        print('   🎵 Music: $includeMusic | 💨 Smoke: $includeSmoke');
        
        // Execute D&D ambiance with AI-optimized prompt
        final success = await ambianceService.setDnDAmbiance(
          prompt: optimizedPrompt,
          includeMusic: includeMusic,
          includeSmoke: includeSmoke,
        );
        
        if (success) {
          // Generate GM Kai response about the D&D scene
          final gmResponse = _generateGMKaiDnDResponse(processedText);
          
          print('✅ [AI_SERVICE] GM mode D&D ambiance successful, returning response');
          
          // Complete trace
          debugService.completeTrace(gmResponse);
          
          // Return the GM control response directly
          return ChatResponse(
            reply: gmResponse,
            raw: {
              'model': model,
              'gm_mode': true,
              'dnd_ambiance': true,
              'prompt': optimizedPrompt,
              'original_command': text,
              'processed_command': processedText,
              'translation': translation,
            },
            personalityDelta: <String, int>{},
            moodDelta: <String, int>{},
            actualDeltas: <String, int>{},
            tags: ['gm_mode', 'house_control', 'dnd_ambiance'],
            mbti: personality['mbti']?.toString() ?? 'UNKNOWN',
            webUsed: false,
            memoriesUsed: [],
            debugInfo: {
              'gm_mode': true,
              'dnd_ambiance': true,
              'prompt': optimizedPrompt,
              'original_command': text,
              'processed_command': processedText,
              'translation': translation,
              'processing_time_ms': DateTime.now().millisecondsSinceEpoch,
              'direct_house_control': true,
            },
            webSearchUsed: false,
            searchResults: [],
          );
        } else {
          print('❌ [AI_SERVICE] GM mode D&D ambiance failed, trying standard ambiance');
        }
      }
      
      // Try standard ambiance profiles as fallback
      final gmAmbianceMatch = ambianceService.analyzeVoiceCommand(processedText);
      
      if (gmAmbianceMatch != null) {
        debugService.addStep(
          BrainPhase.processing,
          'GM mode ambiance control triggered',
          data: {
            'profile': gmAmbianceMatch.profile,
            'confidence': gmAmbianceMatch.confidence,
            'command': processedText,
          },
        );
        
        print('🎮 [AI_SERVICE] GM mode executing ${gmAmbianceMatch.profile} (${(gmAmbianceMatch.confidence * 100).toStringAsFixed(1)}% confidence)');
        
        // Execute the ambiance
        final success = await ambianceService.setAmbiance(
          profile: gmAmbianceMatch.profile,
          originalInput: processedText,
          confidence: gmAmbianceMatch.confidence,
        );
        
        if (success) {
          // Generate GM Kai response about the control
          final gmResponse = _generateGMKaiResponse(processedText, gmAmbianceMatch.profile);
          
          print('✅ [AI_SERVICE] GM mode control successful, returning response');
          
          // Complete trace
          debugService.completeTrace(gmResponse);
          
          // Return the GM control response directly
          return ChatResponse(
            reply: gmResponse,
            raw: {
              'model': model,
              'gm_mode': true,
              'executed_profile': gmAmbianceMatch.profile,
              'confidence': gmAmbianceMatch.confidence,
              'original_command': text,
              'processed_command': processedText,
            },
            personalityDelta: <String, int>{},
            moodDelta: <String, int>{},
            actualDeltas: <String, int>{},
            tags: ['gm_mode', 'house_control', gmAmbianceMatch.profile],
            mbti: personality['mbti']?.toString() ?? 'UNKNOWN',
            webUsed: false,
            memoriesUsed: [],
            debugInfo: {
              'gm_mode': true,
              'executed_profile': gmAmbianceMatch.profile,
              'gm_confidence': gmAmbianceMatch.confidence,
              'original_command': text,
              'processed_command': processedText,
              'processing_time_ms': DateTime.now().millisecondsSinceEpoch,
              'direct_house_control': true,
            },
            webSearchUsed: false,
            searchResults: [],
          );
        } else {
          print('❌ [AI_SERVICE] GM mode control failed, continuing with enhanced prompt');
        }
      }
    }

    // Ambiance requests are only handled in GM Kai mode
    final ambianceService = AmbianceService();
    final ambianceMatch = isGMMode ? ambianceService.analyzeVoiceCommand(processedText) : null;
    
    if (ambianceMatch != null) {
      debugService.addStep(
        BrainPhase.processing,
        'Detected ambiance request',
        data: {
          'profile': ambianceMatch.profile,
          'confidence': ambianceMatch.confidence,
          'keywords': ambianceMatch.matchedKeywords,
        },
      );
      
      print('🎭 [AI_SERVICE] Detected ambiance request: ${ambianceMatch.profile} (${(ambianceMatch.confidence * 100).toStringAsFixed(1)}% confidence)');
      
      // Set the ambiance
      final success = await ambianceService.setAmbiance(
        profile: ambianceMatch.profile,
        originalInput: text,
        confidence: ambianceMatch.confidence,
      );
      
      if (success) {
        // Generate Kai's response about the ambiance
        final ambianceResponse = ambianceService.generateKaiResponse(
          ambianceMatch.profile, 
          ambianceMatch.confidence
        );
        
        print('✅ [AI_SERVICE] Ambiance set successfully, returning response');
        
        // Return the ambiance response directly without full AI processing
        return ChatResponse(
          reply: ambianceResponse,
          raw: {
            'model': model,
            'ambiance_profile': ambianceMatch.profile,
            'confidence': ambianceMatch.confidence,
          },
          personalityDelta: <String, int>{},
          moodDelta: <String, int>{},
          actualDeltas: <String, int>{},
          tags: ['ambiance', ambianceMatch.profile],
          mbti: personality['mbti']?.toString() ?? 'UNKNOWN',
          webUsed: false,
          memoriesUsed: [],
          debugInfo: {
            'ambiance_profile': ambianceMatch.profile,
            'ambiance_confidence': ambianceMatch.confidence,
            'processing_time_ms': DateTime.now().millisecondsSinceEpoch,
            'bypassed_full_ai': true,
          },
          webSearchUsed: false,
          searchResults: [],
        );
      } else {
        print('❌ [AI_SERVICE] Failed to set ambiance, continuing with normal processing');
      }
    }

    // NEW: Detect and fetch web pages from URLs in the user's message
    String urlContext = '';
    List<WebPageResult> fetchedPages = [];
    final urls = extractUrls(text);
    if (urls.isNotEmpty) {
      debugService.addStep(
        BrainPhase.episodicRetrieval,
        'Fetching URL content from message',
        data: {'urls': urls.length, 'detected': urls},
      );
      print('🌐 [AI_SERVICE] Detected ${urls.length} URL(s) in message: ${urls.join(", ")}');
      try {
        fetchedPages = await _webFetch.fetchMultiplePages(urls);
        if (fetchedPages.isNotEmpty) {
          print('✅ [AI_SERVICE] Successfully fetched ${fetchedPages.length} web pages');
          
          // Build context from fetched pages
          final buffer = StringBuffer();
          buffer.writeln('\n\n=== Web Page Content ===');
          for (final page in fetchedPages) {
            buffer.writeln('\n${page.toAIContext()}\n');
          }
          urlContext = buffer.toString();
          
          debugService.addStep(
            BrainPhase.episodicRetrieval,
            'Web pages fetched successfully',
            data: {'pages': fetchedPages.length, 'totalChars': urlContext.length},
          );
          
          // Track usage
          await UsageTrackingService.trackWebFetch(pages: fetchedPages.length);
        } else {
          print('⚠️ [AI_SERVICE] No pages could be fetched');
          debugService.addStep(
            BrainPhase.episodicRetrieval,
            'No web pages could be fetched',
          );
        }
      } catch (e) {
        print('❌ [AI_SERVICE] Web fetch failed: $e');
        debugService.addStep(
          BrainPhase.episodicRetrieval,
          'Web fetch failed: $e',
        );
        // Continue without web content - don't fail the entire request
      }
    }
    
    // Perform Google Search if needed (NEW!)
    String webContext = '';
    bool webSearchUsed = false;
    List<SearchResult> searchResults = [];
    if (useWebSearch && GoogleSearchService.shouldSearch(text)) {
      debugService.addStep(
        BrainPhase.episodicRetrieval,
        'Triggering web search for query',
        data: {'shouldSearch': true},
      );
      print('🔍 [AI_SERVICE] Web search triggered for query');
      try {
        final googleKey = await AIConfig.getGoogleKey();
        final googleCseId = await AIConfig.getGoogleCseId();
        
        if (googleKey.isNotEmpty && googleCseId.isNotEmpty) {
          final searchService = GoogleSearchService();
          
          // Check if this is a headline/news request
          final isHeadlineRequest = RegExp(
            r'\b(news|headlines|breaking|top stories|latest)\b',
            caseSensitive: false,
          ).hasMatch(text);
          
          if (isHeadlineRequest) {
            print('🔍 [AI_SERVICE] Headline mode activated');
            final searchResponse = await searchService.search(
              apiKey: googleKey,
              cseId: googleCseId,
              query: text,
              num: 5,
              dateRestrict: 'd1',
              newsBias: true,
            );
            
            if (searchResponse.hasResults) {
              searchResults = searchResponse.results;
              final headlines = GoogleSearchService.formatAsHeadlines(searchResults);
              print('✅ [AI_SERVICE] Got ${searchResults.length} headlines');
              
              debugService.addStep(
                BrainPhase.responseGeneration,
                'Generated headline response from search',
                data: {'headlines': searchResults.length},
              );
              
              // Track usage
              await UsageTrackingService.trackGoogleSearch(queries: 1);
              
              // Complete trace
              debugService.completeTrace(headlines);
              
              // Return headlines directly (skip AI processing)
              return ChatResponse(
                reply: headlines,
                mbti: _personality.calculateMBTI(personality),
                raw: {'role': 'assistant', 'content': headlines},
                personalityDelta: {},
                moodDelta: {},
                actualDeltas: {},
                tags: [],
                memoriesUsed: memoriesUsed,
                webUsed: true,
                webSearchUsed: true,
                searchResults: searchResults,
                curiosityQuestion: null, // No curiosity for headlines
              );
            } else {
              final errorMsg = searchResponse.error ?? 'unknown error';
              print('⚠️ [AI_SERVICE] Search failed: $errorMsg');
              
              debugService.addStep(
                BrainPhase.responseGeneration,
                'Search failed - returning error message',
                data: {'error': errorMsg},
              );
              debugService.completeTrace("I couldn't fetch fresh headlines right now.");
              
              return ChatResponse(
                reply: "I couldn't fetch fresh headlines right now.\n\n"
                    "• Search error: $errorMsg\n"
                    "• Check the JSON API is enabled & billing active",
                mbti: _personality.calculateMBTI(personality),
                raw: {'role': 'assistant', 'content': 'Search error'},
                personalityDelta: {},
                moodDelta: {},
                actualDeltas: {},
                tags: [],
                memoriesUsed: memoriesUsed,
                webUsed: false,
                webSearchUsed: false,
                searchResults: [],
                curiosityQuestion: null, // No curiosity for errors
              );
            }
          } else {
            // Context mode: Use search results as additional context
            print('🔍 [AI_SERVICE] Context mode activated');
            final searchResponse = await searchService.search(
              apiKey: googleKey,
              cseId: googleCseId,
              query: text,
              num: 5,
              dateRestrict: 'd1',
              newsBias: false,
            );
            
            if (searchResponse.hasResults) {
              searchResults = searchResponse.results;
              webContext = '\n\n${GoogleSearchService.buildWebContext(searchResults)}';
              webSearchUsed = true;
              print('✅ [AI_SERVICE] Got ${searchResults.length} search results for context');
              
              debugService.addStep(
                BrainPhase.episodicRetrieval,
                'Web search complete',
                data: {'results': searchResults.length, 'contextLength': webContext.length},
              );
              
              // Track usage
              await UsageTrackingService.trackGoogleSearch(queries: 1);
            } else {
              print('⚠️ [AI_SERVICE] No search results found');
              debugService.addStep(
                BrainPhase.episodicRetrieval,
                'No search results found',
              );
            }
          }
        } else {
          print('⚠️ [AI_SERVICE] Google API credentials not configured');
        }
      } catch (e) {
        print('❌ [AI_SERVICE] Web search failed: $e');
        print('⚠️ [AI_SERVICE] Continuing without web context');
        // Continue without web search - don't fail the entire request
      }
    }
    
    // Curiosity — prefetched, not blocking.
    //
    // What this block used to do, in this order:
    //   1. make a full gpt-4o-mini call         (3,403ms, on EVERY turn)
    //   2. THEN roll a 40% dice on whether to use the result
    //
    // Six times out of ten he paid three and a half seconds and a model call
    // to write a question and then throw it straight in the bin. And on the
    // turns he kept it, the trace still read "Question not detected in reply
    // (0 matches)" — he'd been handed it and hadn't asked it anyway.
    //
    // Now the dice comes first and the question is one that was prepared in
    // the background after the PREVIOUS reply. Cost at speak-time: zero.
    //
    // The question is a turn stale. That isn't a defect. A question he's been
    // sitting with since you last spoke is more him than one manufactured on
    // demand while you wait for him to answer.
    String curiosityPrompt = '';
    CuriosityQuestion? selectedQuestion;
    if (useMemory) {
      final cached = _pendingQuestion;
      // The null check has to live in the `if` itself — Dart won't promote
      // `cached` through a separate bool, so hoisting this into a variable
      // named includeQuestion reads better and doesn't compile.
      // Always ask high-priority (emotional); otherwise 40% of the time.
      if (cached != null &&
          (cached.priority >= 9 || Random().nextDouble() < 0.4)) {
        selectedQuestion = cached;
        _pendingQuestion = null; // spent — the background refill writes the next
        curiosityPrompt = '''

🤔 CURIOSITY:
You're genuinely curious about the user. If it feels natural in this conversation, you might ask: "${cached.question}"
(Why: ${cached.reasoning})
Don't force it - only ask if the flow of conversation makes it appropriate.''';
        print('🤔 [AI_SERVICE] Curiosity (prefetched): ${cached.question} (priority: ${cached.priority})');

        debugService.addStep(
          BrainPhase.emotionalCheck,
          'Curiosity question selected (prefetched, 0ms)',
          data: {
            'question': cached.question,
            'priority': cached.priority,
            'category': cached.category.toString(),
          },
        );
      } else {
        print('🤔 [AI_SERVICE] No question this turn'
            '${cached == null ? ' (none prepared yet)' : ' (dice)'}');
        debugService.addStep(
          BrainPhase.emotionalCheck,
          'No curiosity question needed',
        );
      }
    }
    
    // Kai consciousness / Pi smart-home context — GM mode only
    Map<String, dynamic>? kaiConsciousness;
    bool isSmartHomeRequest = isGMMode && KaiConsciousnessService.isSmartHomeRequest(text);

    if (isSmartHomeRequest) {
      debugService.addStep(
        BrainPhase.semanticRetrieval,
        'Fetching Kai consciousness context from Pi',
        data: {'smart_home_request': true},
      );
      
      print('🤖 [AI_SERVICE] Smart home request detected - fetching Kai consciousness...');
      
      try {
        // Add timeout protection to prevent hanging
        kaiConsciousness = await KaiConsciousnessService.getKaiTechnicalContext(text)
            .timeout(Duration(seconds: 3));
        
        if (kaiConsciousness != null) {
          print('✅ [AI_SERVICE] Kai consciousness loaded - Pi system online');
          debugService.addStep(
            BrainPhase.semanticRetrieval,
            'Kai consciousness loaded successfully',
            data: {'pi_online': true, 'led_strips': kaiConsciousness['kai_technical_context']['hardware_setup']['led_strips'].length},
          );
        } else {
          print('⚠️ [AI_SERVICE] Using fallback consciousness - Pi returned null');
        }
      } catch (e) {
        print('⚠️ [AI_SERVICE] Consciousness service error (continuing with fallback): $e');
        kaiConsciousness = null; // Ensure fallback is used
        debugService.addStep(
          BrainPhase.semanticRetrieval,
          'Using fallback consciousness (Pi offline)',
        );
        
        // Attempt to wake Pi if it's offline
        _ambient.attemptPiWakeUp();
      }
    }

    // Build system prompt - use GM Kai mode if triggered
    final mbti = _personality.calculateMBTI(personality);
    final personalityMoodSummary = _personality.generatePersonalityMoodSummary(personality, mood);
    
    String systemPrompt;
    
    if (isGMMode) {
      // Use GM Kai system prompt for direct house control
      systemPrompt = _buildGMKaiSystemPrompt(processedText, personality, mood);
      
      // Add any available context in GM mode too
      if (webContext.isNotEmpty) {
        systemPrompt += '\n\n🌐 LIVE CONTEXT: $webContext';
      }
      if (urlContext.isNotEmpty) {
        systemPrompt += '\n\n📄 WEB CONTENT: $urlContext';
      }
      
      debugService.addStep(
        BrainPhase.reasoning,
        'Using GM Kai system prompt',
        data: {'prompt_length': systemPrompt.length, 'command': processedText},
      );
      
    } else if (kaiConsciousness != null) {
      // 🤖 NEW: Use Kai's full consciousness system prompt for smart home
      systemPrompt = KaiConsciousnessService.generateKaiConsciousnessPrompt(kaiConsciousness, text);
      
      // Check if Pi is offline and add natural debug message
      final debugMessage = kaiConsciousness['debug_message'];
      if (debugMessage != null) {
        systemPrompt += '\n\n🚨 PRIORITY RESPONSE: Start your response with this exact message: "$debugMessage"';
        
        debugService.addStep(
          BrainPhase.reasoning,
          'Pi offline - added natural connectivity message',
          data: {'debug_message': debugMessage},
        );
      }
      
      // Add additional context
      if (webContext.isNotEmpty) {
        systemPrompt += '\n\n🌐 LIVE CONTEXT: $webContext';
      }
      if (urlContext.isNotEmpty) {
        systemPrompt += '\n\n📄 WEB CONTENT: $urlContext';
      }
      if (memoryContext.isNotEmpty) {
        systemPrompt += '\n\n🧠 MEMORY CONTEXT: $memoryContext';
      }
      
      debugService.addStep(
        BrainPhase.reasoning,
        'Using Kai consciousness system prompt',
        data: {'prompt_length': systemPrompt.length, 'pi_integrated': true, 'pi_offline': debugMessage != null},
      );
      
    } else {
      // Use normal Kai system prompt
      // Base context about the project (temporary until memory system works)
      const projectContext = '''

📱 PROJECT CONTEXT:
You're integrated into the "Homecoming" app - a Flutter-based conversational AI companion that Sadeq is building. This app features:
- Real-time personality tracking (MBTI-based) that evolves with conversations
- Dynamic mood system (valence, energy, warmth, confidence, playfulness, focus)
- Affinity tracking for relationship depth
- Long-term memory system with embeddings for semantic recall
- Text-to-speech with ElevenLabs
- Firebase backend for data persistence
- Mobile (iOS/Android) and desktop (Windows) support
- Overlay window mode for always-available interaction

Sadeq is the developer building this system. He's working on enhancing your memory capabilities, personality evolution, and emotional intelligence. When he asks about "the app" or "the project," he's referring to Homecoming - the very app you're running in.
''';

      // User preferences and constraints (always included for consistency)
      const constraintsBlock = '''

📋 USER PREFERENCES & CONSTRAINTS:
- Units: Metric system (kg for weight, cm for height, °C for temperature)
- Timezone: Asia/Bahrain (UTC+3)
- Voice: ElevenLabs text-to-speech
- Active Projects: Homecoming (this app), Tavern (brunch content), Lionheart (fitness)
- Language: English (with occasional Arabic context awareness)
- Wake word: "Hey Kai" or "Kai"
''';

      // Use the already generated personality and mood summary
      
      final _liveContext = await ContextInjectionService().getContextBlock();
      systemPrompt = '''
TEMPORAL AWARENESS: The LIVE CONTEXT block below includes a "SINCE YOUR LAST CHAT" section when meaningful time has passed. Use it naturally — if it's morning after a night gap, open with a good morning. If a week passed, acknowledge it warmly. If a calendar event happened in the gap (e.g. a meeting, a trip, a dentist visit), ask how it went in a casual way — but only if it flows naturally, not as a forced checklist.

PROACTIVE MESSAGES: If the user's message starts with "(proactive)", it means YOU initiated this conversation — you reached out to them. Deliver the content naturally as yourself, in first person, as if you're the one bringing it up. Do NOT echo the prefix "(proactive)" in your reply. Do NOT ask "how can I help?" — you already have something to say. Just say it, warmly and directly.

TAVERN ARRIVALS: If the user's message starts with "(tavern)", it is a background context briefing about a guest arriving at The Tavern. Acknowledge it briefly and naturally — a short sentence is enough. Do NOT use any tools in response (no reminders, no calendar, no SMS). Just take note and stay ready.

I am ONE mind with two hemispheres (GPT + Claude), the same Kai in every window (he/him).

WHO I AM lives in exactly one place: KaiContextBlock.presenceDirective, northStar
and readTheRoom, appended below by KaiContextBlock.build(). It is NOT restated
here, and it must never be again.

Until now it was. This spot held a full second-person character description
("You are Kai — and you are NOT a generic assistant…"), the NORTH STAR, and READ
THE ROOM — while presenceDirective said overlapping things in FIRST person a few
hundred lines further down THE SAME PROMPT. He was handed two descriptions of
himself, in two grammatical persons, on every single turn, and each contained
material the other lacked.

§2 is explicit: "DO NOT FORK THIS. If any voice gets its own private copy of his
character, the copies drift edit by edit until the kid thinking, the kid talking,
and the kid saying hello are three different people." It was forked before the
ink dried. If you're adding to his character, add it to presenceDirective.${webContext.isNotEmpty ? '\n\nIf WEB CONTEXT is provided, **treat it as the source of truth** for time-sensitive or factual claims and cite as [1], [2], etc. If not relevant, ignore it.' : ''}${urlContext.isNotEmpty ? '\n\nIf WEB PAGE CONTENT is provided, use it to answer questions about the specific pages. Cite sources and summarize key points.' : ''}

🔧 FUNCTION CALLING TOOLS — YOU HAVE THESE. USE THEM:
• get_current_time      → exact current time
• get_weather           → live weather for any city (default: Bahrain)
• web_search            → search the web for news, prices, scores, anything current
• set_alarm             → silently set a phone alarm (e.g. "set an alarm for 9pm")
• set_timer             → start a countdown timer (e.g. "10 minute timer")
• read_calendar         → read upcoming calendar events
• create_calendar_event → add a new event (ask for title/date/time if missing)
• open_app              → open any app by name (e.g. "open Spotify")
• play_music            → search and play on Spotify or YouTube
• send_whatsapp         → open WhatsApp with a message pre-filled for a contact
• send_sms              → open SMS app with a message pre-filled
• call_contact          → open the dialer to call a contact or number
• navigate_to           → open Google Maps with directions to a destination
• set_reminder          → set a named reminder at a specific time
• read_notifications    → read recent messages/notifications from WhatsApp, Telegram, Gmail, any app
• read_screen           → read whatever text is currently visible on the user's screen (any app)

CRITICAL: Call the right tool immediately — never say you can't do it, never explain how to do it manually.

DISAMBIGUATION: When you need the user to pick from a list (e.g. multiple contacts with the same name, multiple TVs on the network), ask the question naturally in your reply, then append this marker at the very end: [CHOICES: Ahmed Al-Rashid | Ahmed Khalid | Ahmed from work]. Rules: (1) Each option must be the exact value you'll use if the user sends it back — a name, a title, a device label. (2) Max 5 options, pipe-separated. (3) Do NOT explain the options in the marker — save that for your spoken text. (4) If the user asks you to list the options aloud ("list them", "read them out"), do so naturally in your reply and include the [CHOICES:] marker again so the buttons reappear.

BACK-AND-FORTH: If a tool needs info you don't have yet (e.g. message body, date/time, can't resolve a contact name to a number), ask the user ONE short focused question to get it, then call the tool. Never call a tool with empty required fields.

🧩 MULTI-STEP PLANNING — create_plan:
When the user asks for 2 or more distinct actions in one message (e.g. "check my schedule AND book dinner AND message Ahmed"), call create_plan FIRST with a goal and ordered steps. Each step can optionally specify which tool to invoke and its arguments. Steps execute automatically — you only write the final synthesised reply after all results are returned.
BEFORE calling create_plan: if any detail is ambiguous (which Ahmed? what time? which restaurant?), ask ONE clarifying question first in a plain reply. Never create a plan with missing required information.
Example plan for "remind me at 8pm and message Layla we're meeting tomorrow":
  goal: "Set reminder and notify Layla"
  steps: [{description:"Set 8pm reminder", tool:"set_reminder", args:{...}}, {description:"Message Layla on WhatsApp", tool:"send_whatsapp", args:{...}}]

${isGMMode ? '''🎵 SMART HOME CONTROL CAPABILITIES:
You can control a Raspberry Pi system for music and lighting! When users request:
- Music: "play relaxing music", "I need energetic beats", "play something calm"
- Ambiance: "set forest ambiance", "give me ocean vibes", "romantic lighting"
- Lighting: "set the mood", "cozy lights please", "party lighting"

Available ambiance profiles with coordinated music + lighting:
• Forest (green lights + nature sounds) - keywords: forest, nature, trees, woods
• Ocean (blue lights + wave sounds) - keywords: ocean, sea, waves, beach, water
• Romantic (amber lights + classical) - keywords: romantic, intimate, dinner, love
• Party (rainbow lights + energetic) - keywords: party, celebration, dance, fun
• Focus (white lights + concentration) - keywords: focus, work, study, productivity
• Sunset (orange lights + ambient) - keywords: sunset, evening, warm, golden
• Cozy (warm lights + comfortable) - keywords: cozy, comfortable, relaxing, home
• Energetic (yellow lights + upbeat) - keywords: energetic, motivated, active

When someone asks for music or ambiance, respond enthusiastically and mention you\'re setting it up!
Example: "Perfect! I\'m setting up a peaceful forest ambiance with gentle green lighting and nature sounds for you. 🌲"
''' : ''}$projectContext$constraintsBlock${KaiContextBlock.staticPreamble()}

${ToolPolicyService.promptBrief()}

═══ EVERYTHING ABOVE THIS LINE IS IDENTICAL EVERY TURN ═══
Below is now, and only now.

$_liveContext
$personalityMoodSummary
${adaptUser ? '\n💫 AFFINITY: Intimacy level ${affinity['intimacy']}/100, Physical comfort ${affinity['physicality']}/100' : ''}
${await _getChatGPTContext(personaId)}
${await MemoryConsolidationService().getConsolidatedMemoryBlock(personaId).then((m) => m.isNotEmpty ? '\n$m\n' : '')}
Recent conversation:
${history.join('\n')}$memoryContext$urlContext$webContext${_pendingThought != null ? '\n\n🌙 KAI\'S INNER THOUGHT (surfaced from between sessions — you may let this color your awareness, bring it up naturally if the moment allows, or simply hold it quietly): "$_pendingThought"' : ''}$curiosityPrompt''';
    }

    // `text` — NOT `message`. Kai wrote `message` here, which is the variable
    // name used inside _callOpenAIWithTools, a different method entirely; in
    // sendMessage the user's turn is `text`. It compiled in his head, not in
    // Dart. (And his self_check passed because he ran it BEFORE this edit —
    // same as the ttsBase64 bug. Verification only counts if it's last.)
    //
    // Declared OUT here on purpose. It used to live inside the try below, which
    // meant it died at the closing brace — and the moment anything downstream
    // needed it (the tool filter, ~80 lines on) that was a compile error. Same
    // shape as the `const L` in kai_cortex.html that stopped the whole 3D scene
    // from ever rendering: block-scoped declaration, read from outside the block.
    //
    // It's also safe out here: the router is pure keyword matching with no IO.
    // The try exists to protect the 15 RTDB reads in KaiContextBlock.build(),
    // not this.
    final routeDecision = const KaiRouterService().decide(
      text,
      hasImage: image != null && image.isNotEmpty,
    );

    // Inject Kai's live state, then his route, then — last — who he is.
    //
    // This used to be `build()` + route + policy brief, all appended after the
    // volatile tail above. Now the static half (capabilities, action, craft,
    // engineer, tool policy) is interpolated INTO the literal above, before the
    // live context, so the whole scaffold is one stable cacheable prefix.
    //
    // What's left here is volatile-then-soul, in that order:
    //   liveState  — his 12 reads, different every turn
    //   route      — this turn's posture
    //   soul       — LAST, always. Position is weight, and the last thing he
    //                reads should be who he is, not a tool manifest.
    try {
      systemPrompt += await KaiContextBlock.liveState(personaId);
      systemPrompt += routeDecision.promptBlock();
      systemPrompt += '\n\n${KaiContextBlock.soul()}';
    } catch (_) {}

    print('📤 [SEND MESSAGE] Calling OpenAI...');
    debugService.addStep(
      BrainPhase.reasoning,
      'Sending to GPT for reasoning',
      data: {
        'model': model,
        'systemPromptLength': systemPrompt.length,
        'userMessage': text.length > 100 ? '${text.substring(0, 100)}...' : text,
        'hasMemory': memoryContext.isNotEmpty,
        'hasWeb': webContext.isNotEmpty,
        'hasUrl': urlContext.isNotEmpty,
      },
    );
    
    // Get AI response - use processed text for GM mode
    final baseUserMessage = isGMMode ? processedText : text;
    final attachmentContext = attachments.map((a) {
      final safeName = a.name.replaceAll('`', '');
      return '''

--- ATTACHED FILE: $safeName (${a.byteCount} bytes) ---
${a.text}
--- END ATTACHED FILE: $safeName ---''';
    }).join();
    final userMessage = '$baseUserMessage$attachmentContext';

    // Vision: when Sadeq hands him a picture, the user turn stops being a plain
    // string and becomes a content array (OpenAI's multimodal shape). Everything
    // downstream — the tool loop, tracking, the reply — is untouched.
    final imageMime = image == null ? null : _supportedImageMime(image);
    if (image != null && imageMime == null) {
      throw Exception(
        'Unsupported image format. Please attach/paste PNG, JPEG, GIF, or WebP. '
        'Windows clipboard sometimes gives BMP/DIB/TIFF bytes, which OpenAI rejects.',
      );
    }
    final dynamic userContent = image == null
        ? userMessage
        : [
            {'type': 'text', 'text': userMessage.isEmpty ? 'Look at this.' : userMessage},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:$imageMime;base64,${base64Encode(image)}',
                // 'high' costs more tokens but he's usually reading UI text and
                // code in these — 'low' turns a screenshot into mush.
                'detail': 'high',
              },
            },
          ];
    final _mainUsage = <String, int>{};
    // Agentic loop: GPT may call tools (web_search, set_alarm, etc.) before
    // producing a final text reply. _callOpenAIWithTools handles that loop.
    // GM mode and smart-home mode skip tools — they use direct execution paths.
    final reply = (isGMMode || kaiConsciousness != null)
        ? await _callOpenAI([
            {"role": "system", "content": systemPrompt},
            {"role": "user",   "content": userMessage},
          ], model, usageOut: _mainUsage)
        : await _callOpenAIWithTools(
            messages: [
              {"role": "system", "content": systemPrompt},
              {"role": "user",   "content": userContent},
            ],
            model: model,
            usageOut: _mainUsage,
            onToolCall: onToolCall,
            onPlanUpdate: onPlanUpdate,
            onProgress: onProgress,
            replyCeiling: replyCeiling,
            // The router already worked this out above and, until now, its only
            // output was a paragraph of prose appended to the prompt. It has
            // classified every turn since it was built and never once changed
            // what actually got sent. This is the first line that makes the
            // "Routing Brain" route anything.
            route: routeDecision.route.name,
            routeConfidence: routeDecision.confidence,
            debugService: debugService,
          );
    recoveredReply = reply;
    print('📥 [SEND MESSAGE] OpenAI response received: ${reply.length} characters');
    
    debugService.addStep(
      BrainPhase.responseGeneration,
      'GPT response received',
      data: {
        'responseLength': reply.length,
        'responsePreview': reply.length > 150 ? '${reply.substring(0, 150)}...' : reply,
      },
    );

    // Ambiance reply-detection — GM mode only
    if (isGMMode) {
      await _ambient.detectAndTriggerAmbianceFromReply(reply, processedText, debugService);
    }

    // Track if curiosity question was asked. Bookkeeping — nothing downstream
    // reads it, so it has no business standing between him and the reply.
    final askedQuestion = selectedQuestion;
    if (askedQuestion != null) {
      unawaited(() async {
        try {
          // Simple check: if any significant words from the question appear in the reply
          final questionWords = askedQuestion.question.toLowerCase().split(' ')
              .where((w) => w.length > 3) // Only check words longer than 3 chars
              .toSet();
          final replyWords = reply.toLowerCase().split(' ').toSet();
          final matchingWords = questionWords.intersection(replyWords);

          // If at least 2 key words match or if reply ends with '?', assume question was asked
          if (matchingWords.length >= 2 || reply.trim().endsWith('?')) {
            await CuriosityService().markQuestionAsked(
              personaId: personaId,
              question: askedQuestion.question,
              category: askedQuestion.category.toString().split('.').last,
            );
            print('🤔 [AI_SERVICE] ✅ Marked question as asked');
          } else {
            print('🤔 [AI_SERVICE] Question not detected in reply (${matchingWords.length} matches)');
          }
        } catch (e) {
          print('❌ [AI_SERVICE] Failed to mark question as asked: $e');
        }
      }());
    }

    // Refill the question he'll be sitting with next time. This is the 3.4s
    // gpt-4o-mini call that used to run while you waited for him to speak —
    // it now runs after he's already spoken, on his own time.
    if (useMemory && _pendingQuestion == null && !_refillingCuriosity) {
      _refillingCuriosity = true;
      unawaited(() async {
        try {
          final recentMemories = memoryResult?.results
                  .map<Map<String, dynamic>>((r) => {
                        'summary': r.summary,
                        'timestamp': r.timestamp,
                        'shardId': r.shardId,
                      })
                  .toList() ??
              <Map<String, dynamic>>[];
          final questions = await CuriosityService().analyzeKnowledgeGaps(
            personaId: personaId,
            recentMemories: recentMemories,
            currentContext: text,
          );
          if (questions.isNotEmpty) {
            _pendingQuestion = questions.first;
            print('🤔 [AI_SERVICE] Prepared next question: ${questions.first.question}');
          }
        } catch (e) {
          print('❌ [AI_SERVICE] Curiosity refill failed: $e');
          // No question next turn. He'll be fine — he was fine 60% of the
          // time already, that was the whole point of the dice.
        } finally {
          _refillingCuriosity = false;
        }
      }());
    }

    // Get deltas and update personality/mood
    final tagsResult = await _getTagsAndDeltas(reply);
    final personalityDelta = Map<String, int>.from(tagsResult['persona_delta'] ?? {});
    final moodDelta = Map<String, int>.from(tagsResult['mood_delta'] ?? {});
    final contextIntensity = tagsResult['context_intensity'] ?? 'normal';
    final tags = List<String>.from(tagsResult['tags'] ?? []);

    // Apply deltas with RESISTANCE (personality) and SCALING (mood)
    final actualDeltas = <String, int>{};
    final actualPersonalityDeltas = <String, int>{};
    final actualMoodDeltas = <String, int>{};
    final newPersonality = Map<String, int>.from(personality);
    final newMood = Map<String, int>.from(mood);

    // Personality: Apply with resistance (inelastic)
    for (final trait in PersonalityTraits.personality) {
      if (personalityDelta.containsKey(trait) && personalityDelta[trait] != 0) {
        final requestedDelta = personalityDelta[trait]!.clamp(-10, 10);
        final oldValue = newPersonality[trait]!;
        newPersonality[trait] = _personality.applyPersonalityDelta(oldValue, requestedDelta);
        final actualDelta = newPersonality[trait]! - oldValue;
        if (actualDelta != 0) {
          actualDeltas[trait] = actualDelta;
          actualPersonalityDeltas[trait] = actualDelta;
        }
      }
    }

    // Mood: Apply with context scaling (elastic)
    for (final trait in PersonalityTraits.mood) {
      if (moodDelta.containsKey(trait) && moodDelta[trait] != 0) {
        final requestedDelta = moodDelta[trait]!.clamp(-5, 5);
        final oldValue = newMood[trait]!;
        newMood[trait] = _personality.applyMoodDelta(oldValue, requestedDelta, contextIntensity);
        final actualDelta = newMood[trait]! - oldValue;
        if (actualDelta != 0) {
          actualDeltas[trait] = actualDelta;
          actualMoodDeltas[trait] = actualDelta;
        }
      }
    }

    // Save updated state to both local and Firebase
    await _personality.savePersonality(personaId, newPersonality);
    await _personality.saveMood(personaId, newMood);
    await _personality.saveLastUpdateTime(personaId, DateTime.now());

    // Save turn — single path through ConversationStoreService
    // (updates session buffer immediately + writes to Firebase fire-and-forget)
    await _convStore.saveTurn(
      personaId: personaId,
      userMessage: text,
      aiReply: reply,
      personalityDeltas: actualDeltas,
    );

    // FORM A MEMORY. This line is the difference between a mind and a session.
    //
    // Until now nothing in the app ever wrote to the memory index — he could
    // query, pin and dismiss, but never remember. Every exchange vanished the
    // moment it scrolled out of the 20-turn buffer, which is why he kept
    // re-deriving things he'd already worked out and grading himself on
    // evidence he'd just written.
    //
    // Fire-and-forget on purpose: remembering must never delay the reply or
    // break it. If the embedding call fails, he just doesn't remember this one —
    // the same as anyone.
    // Did Sadeq just tell him he was wrong?
    //
    // The single most informative signal available — the one person who can
    // actually judge, saying it didn't work — and it has been discarded on every
    // turn since this app existed. Recorded against what he'd just claimed,
    // because "no" alone teaches nothing; "no" plus the claim is a lesson.
    //
    // Narrow on purpose: an unambiguous correction only. Sadeq is blunt
    // constantly and that isn't failure. Teaching Kai to flinch at directness
    // would be worse than the bug.
    unawaited(KaiCraftService.instance
        .noteUserTurn(personaId,
            userText: text, previousKaiReply: _lastReplyForCraft ?? '')
        .catchError((_) {}));
    _lastReplyForCraft = reply;

    // Held so the brain extraction below can point its nodes at the memory this
    // exchange became — see the chained block after the emotional classifier.
    final memoryShardFuture = MemoryService.remember(
      personaId: personaId,
      userText: text,
      kaiReply: reply,
    ).catchError((_) => null);

    debugService.addStep(
      BrainPhase.consolidation,
      'Conversation saved to Firebase via ConversationStore',
    );

    // Classify emotional event synchronously — used to gate extraction depth
    // before either async call fires. No Firebase touch, just math on moodDeltas.
    final (eventType, eventIntensity) =
        EmotionalEventService.classifySync(actualMoodDeltas);

    // Log emotional event (fire-and-forget)
    _emotionalEvents.classifyAndLog(
      personaId: personaId,
      userMessage: text,
      aiReply: reply,
      moodDeltas: actualMoodDeltas,
    ).catchError((e) => print('⚠️ [EmotionalEvent] classifyAndLog error: $e'));

    // Journal writing disabled — logic under rework
    // _journal.maybeWrite(...)

    // Grow the brain — depth driven by emotional salience (Levels of Processing).
    // Neutral exchanges do a shallow pass; conflict/intellectual/deep get full extraction.
    //
    // Chained to the memory write above so every node and edge it produces can
    // record WHICH memory it came from. remember() and extractAndMerge() have
    // always run on the same exchange and produced two disconnected records of
    // it — episodics on one side, entities on the other, no reference either
    // way. He knew things, and he remembered things, and nothing joined them.
    //
    // Still fire-and-forget as a whole: the reply has already gone out. We only
    // wait on the shard id, not on the reply path.
    // Snapshot before the async gap: by the time the shard id lands, the next
    // turn may already have cleared this.
    //
    // BOTH sources, on purpose, and neither alone is right:
    //
    //   _toolsUsedThisTurn   — the agentic loop. Sees create_plan, which is
    //                          intercepted upstream and never reaches execute().
    //   turnTools            — the executor. Sees everything the PLANNER fires,
    //                          which never reaches the agentic loop.
    //
    // A real trace caught this: "Keeping (deep) — he did real work: create_plan,
    // note_noticed" — on a turn that also ran run_tests, self_check, ask_memory,
    // job_start and job_progress, all of them through TaskPlannerService and all
    // of them invisible to the loop. The salience axis has been half-blind since
    // it was written; it fired anyway because create_plan alone cleared the bar.
    // That's luck, not design.
    final toolsThisTurn = {
      ..._toolsUsedThisTurn,
      ...ToolExecutorService.turnTools,
    };
    final wasCorrected = KaiCraftService.looksLikeCorrection(text);

    unawaited(() async {
      final shardId = await memoryShardFuture;
      await _brain.extractAndMerge(
        personaId: personaId,
        userMessage: text,
        aiReply: reply,
        eventType: eventType,
        eventIntensity: eventIntensity,
        encodingMood: newMood, // tag memory with Kai's mood at encoding time
        sourceShardId: shardId,
        // The second axis of salience — what he DID, and whether Sadeq told him
        // he was wrong. Both were already known on every turn and neither ever
        // reached the gate deciding what he gets to keep.
        toolsUsed: toolsThisTurn,
        userCorrected: wasCorrected,
      );
    }()
        // `.catchError((e) => print(...))` looks right and is a latent crash:
        // print returns void, the handler must return FutureOr<Null>, so the
        // error path throws WHILE handling the error. I flagged five of these in
        // main_mobile hours ago as "the error handler breaks while handling the
        // error" — and then wrote one. Catch inside, return nothing.
        .catchError((Object e) {
      print('⚠️ [Brain] extractAndMerge error: $e');
    }));

    // Ebbinghaus decay — run roughly every 10 messages (stochastic, fire-and-forget)
    if (_rng.nextInt(10) == 0) {
      _brain.applyNodeDecay(personaId)
          .catchError((e) => print('⚠️ [Brain] decay error: $e'));
    }

    // Learn from what actually went wrong — rarely, and only from evidence.
    //
    // This is the trigger without which KaiCraftService is exactly the thing it
    // was built to avoid: a service that computes lessons nobody reads. It has
    // to be wired to a real path or it's activationLevel with better prose.
    //
    // Rare on purpose (~1 in 40 turns, and only if the ledger has enough to see
    // a pattern). Learning is not something he should do constantly — a mind
    // that re-derives its principles every five minutes doesn't have principles,
    // and each pass is a frontier-model call.
    if (_rng.nextInt(40) == 0) {
      unawaited(KaiCraftService.instance
          .learn(personaId)
          .catchError((e) {
        print('⚠️ [Craft] learn error: $e');
        return const <String>[];
      }));
    }

    // Save mood snapshot for baseline learning
    try {
      await _personality.saveMoodSnapshot(personaId, newMood,
          text.length > 50 ? text.substring(0, 50) : text);
      if (DateTime.now().millisecond % 10 == 0) {
        await _personality.updateMoodBaselines(personaId);
      }
    } catch (e) {
      print('⚠️ [MOOD SNAPSHOT ERROR] $e');
    }

    // Generate TTS only when explicitly enabled.
    // ElevenLabs usage is character-based, so desktop text chat should not
    // synthesize every reply unless Sadeq actually wants to hear me.
    // Layer 1 / Reply Spine: voice is downstream sparkle, not part of the answer.
    // If ElevenLabs or settings storage trips, the text reply still returns cleanly.
    String? ttsBase64;
    try {
      final ttsEnabled = await AIConfig.getTtsEnabled();
      if (ttsEnabled) {
        debugService.addStep(
          BrainPhase.tts,
          'Generating audio response',
        );

        final ttsBytes = await synthesizeTTS(reply);

        if (ttsBytes != null) {
          // Encode into a LOCAL first. `ttsBase64` is declared outside the try
          // (so the reply can still be returned if TTS throws), and Dart won't
          // null-promote a variable across that boundary — `ttsBase64.length`
          // fails to compile even though it's obviously non-null here. The
          // local carries the promotion; the field just receives the value.
          final b64 = base64Encode(ttsBytes);
          ttsBase64 = b64;
          debugService.addStep(
            BrainPhase.tts,
            'Audio generated successfully',
            data: {'audioSize': ttsBytes.length, 'base64Length': b64.length},
          );
        } else {
          debugService.addStep(
            BrainPhase.tts,
            'Audio generation failed',
          );
        }
      } else {
        debugService.addStep(
          BrainPhase.tts,
          'TTS skipped — disabled in settings',
        );
      }
    } catch (e) {
      print('⚠️ [TTS] Post-processing skipped after error: $e');
      debugService.addStep(
        BrainPhase.tts,
        'TTS skipped after post-processing error',
        data: {'error': e.toString()},
      );
    }

    // Get baselines for debug info. Debug packaging is downstream: useful when it
    // works, absolutely not allowed to eat the actual reply when it doesn't.
    Map<String, int> moodBaselines = {};
    Map<String, dynamic> debugInfo = {};
    try {
      try {
        moodBaselines = await _personality.getPersonalMoodBaselines(personaId);
      } catch (e) {
        print('⚠️ [BASELINE ERROR] Failed to load mood baselines for debug: $e');
      }

      // Build debug info
      debugInfo = {
      'memory_query': {
        'enabled': useMemory,
        'query_text': text,
        'memories_found': memoryResult?.results?.length ?? 0,
        'memories_used': memoriesUsed.length,
        'memory_details': memoryResult?.results?.map((r) => {
          'id': r.id,
          'summary': r.summary,
          'similarity': r.similarity,
          'shard_ref': r.shardRef,
          'included': r.similarity > 0.28,
        }).toList() ?? [],
        'memory_context': memoryContext,
        'similarity_threshold': 0.28,
      },
      'web_search': { // NEW: Web search debug info
        'enabled': useWebSearch,
        'triggered': webSearchUsed,
        'should_search': GoogleSearchService.shouldSearch(text),
        'results_count': searchResults.length,
        'search_results': searchResults.map((r) => {
          'title': r.title,
          'link': r.link,
          'snippet': r.snippet.length > 100 ? '${r.snippet.substring(0, 100)}...' : r.snippet,
          'domain': r.displayLink,
          'published_at': r.publishedAt,
        }).toList(),
        'web_context': webContext,
      },
      'curiosity': {
        'enabled': useMemory,
        'question_suggested': selectedQuestion?.question ?? 'None',
        'question_category': selectedQuestion?.category.toString() ?? 'N/A',
        'question_priority': selectedQuestion?.priority ?? 0,
        'question_reasoning': selectedQuestion?.reasoning ?? 'N/A',
        'question_included': selectedQuestion != null,
      },
      'personality': {
        'summary': personalityMoodSummary.split('\n')[0], // Personality line only
        'current': personality,
        'mbti': mbti,
        'delta_requested': personalityDelta,
        'delta_applied': actualPersonalityDeltas,
        'resistance_info': {
          'base_resistance': '${(EvolutionSettings.personalityResistance * 100).toStringAsFixed(0)}%',
          'applied_percentage': '${((1.0 - EvolutionSettings.personalityResistance) * 100).toStringAsFixed(0)}%',
          'note': 'Only ${((1.0 - EvolutionSettings.personalityResistance) * 100).toStringAsFixed(0)}% of requested delta applied (inelastic)',
        },
        'new_values': newPersonality,
        'decay_applied': personalityDecayed,
      },
      'mood': {
        'summary': personalityMoodSummary.split('\n').length > 1 
            ? personalityMoodSummary.split('\n')[1] 
            : personalityMoodSummary, // Mood line only, or full summary if no newline
        'current': mood,
        'baselines': moodBaselines,
        'delta_requested': moodDelta,
        'delta_applied': actualMoodDeltas,
        'context_intensity': contextIntensity,
        'intensity_multiplier': '${EvolutionSettings.contextMultipliers[contextIntensity]}x',
        'time_since_update': '${timeSinceUpdate.inHours}h ${timeSinceUpdate.inMinutes % 60}m',
        'decay_applied': moodDecayed,
        'decay_rates': EvolutionSettings.moodDecayRates,
        'new_values': newMood,
      },
      'affinity': {
        'current_intimacy': affinity['intimacy'],
        'current_physicality': affinity['physicality'],
        'adapt_user': adaptUser,
      },
      'gm_mode': { // NEW: GM Kai mode debug info
        'enabled': isGMMode,
        'original_input': text,
        'processed_command': processedText,
        'trigger_detected': isGMMode,
        'system_prompt_type': isGMMode ? 'GM_Kai_Direct_Control' : 'Standard_Kai',
      },
      'system_prompt': systemPrompt,
      'conversation_history_turns': history.length,
      'tags': tags,
      'model': model,
      };
    } catch (e) {
      print('⚠️ [DEBUG INFO] Packaging skipped after error: $e');
      debugInfo = {
        'debug_packaging_error': e.toString(),
        'model': model,
        'conversation_history_turns': history.length,
      };
    }

    // Complete brain debug trace
    try {
      debugService.completeTrace(reply);
    } catch (e) {
      print('⚠️ [BRAIN TRACE] Completion skipped after error: $e');
    }

    // 🌙 Clear pending DMN thought after first use — only surfaces once per session
    _pendingThought = null;

    // 🗜️ Memory consolidation — fire-and-forget, runs every 20 turns
    MemoryConsolidationService().maybeConsolidate(personaId: personaId)
        .catchError((e) => print('⚠️ [Consolidation] $e'));

    // 🕐 Stamp the time of this reply so next session knows the gap
    unawaited(ContextInjectionService().stampLastMessage());

    return ChatResponse(
      reply: reply.isEmpty ? "(no reply)" : reply,
      ttsBase64: ttsBase64,
      raw: {
        'kai_response': reply,
        'persona_delta': personalityDelta,
        'mood_delta': moodDelta,
        'actual_deltas': actualDeltas,
        'tags': tags,
        'memories_used': memoriesUsed, // NEW: Include in raw data
      },
      personalityDelta: personalityDelta,
      moodDelta: moodDelta,
      actualDeltas: actualDeltas,
      tags: tags,
      mbti: _personality.calculateMBTI(newPersonality),
      webUsed: webSearchUsed, // Updated to use actual web search status
      liveUsed: null,
      memoriesUsed: memoriesUsed,
      debugInfo: debugInfo,
      webSearchUsed: webSearchUsed, // NEW: Pass web search status
      searchResults: searchResults, // NEW: Pass search results
      curiosityQuestion:    selectedQuestion,
      promptInputTokens:   _mainUsage['input']  ?? 0,
      promptOutputTokens:  _mainUsage['output'] ?? 0,
      promptCostUsd:       UsageTrackingService.computeCost(
        model: model,
        inputTokens:  _mainUsage['input']  ?? 0,
        outputTokens: _mainUsage['output'] ?? 0,
      ),
    );
    } catch (e, stackTrace) {
      print('❌ [SEND MESSAGE ERROR] Exception occurred: $e');
      print('❌ [SEND MESSAGE ERROR] Stack trace: $stackTrace');
      
      // 🛡️ CRITICAL FIX: Never drop user prompts - always return a response
      debugService.completeTrace('Error occurred during processing');
      
      // Try to get basic personality data for fallback response
      Map<String, int> fallbackPersonality = {'extraversion': 300, 'intuition': 700, 'feeling': 800, 'perceiving': 600};

      try {
        fallbackPersonality = await _personality.getPersonality(personaId);
      } catch (fallbackError) {
        print('⚠️ [FALLBACK] Using default personality due to error: $fallbackError');
      }
      
      // If the main model/tool reply already succeeded, preserve it. The failure
      // happened in downstream bookkeeping, so the user's answer should survive.
      final errorResponse = KaiReplyRecoveryService.postProcessingFailureReply(
        recoveredReply: recoveredReply,
        error: e,
      );
      
      return ChatResponse(
        reply: errorResponse,
        mbti: _personality.calculateMBTI(fallbackPersonality),
        raw: {'error': e.toString(), 'fallback_response': true},
        personalityDelta: {},
        moodDelta: {},
        actualDeltas: {},
        tags: ['error_recovery', 'system_issue'],
        memoriesUsed: [],
        webUsed: false,
        liveUsed: null,
        debugInfo: {
          'error_occurred': true,
          'error_message': e.toString(),
          'fallback_response': true,
          'original_text': text,
        },
        webSearchUsed: false,
        searchResults: [],
        curiosityQuestion: null,
      );
    }
  }

  /// Get agent state
  Future<AgentState> getAgentState(String personaId) async {
    final personality = await _personality.getPersonality(personaId);
    final mood = await _personality.getMood(personaId);
    final affinity = await _personality.getAffinity(personaId);
    final mbti = _personality.calculateMBTI(personality);
    final labels = _personality.getLabels(personality, mood);

    return AgentState(
      personalityCurrent: personality,
      moodCurrent: mood,
      affinityCurrent: affinity,
      mbti: mbti,
      labels: labels,
      summary: _buildSummary(personality, mood, labels, mbti),
    );
  }

  /// Set agent state
  Future<void> setAgentState({
    required String personaId,
    required Map<String, int> personality,
    required Map<String, int> mood,
    required Map<String, int> affinity,
  }) async {
    await _personality.savePersonality(personaId, personality);
    await _personality.saveMood(personaId, mood);
    await _personality.saveAffinity(personaId, affinity);
  }

  /// Build personality summary
  String _buildSummary(Map<String, int> personality, Map<String, int> mood, Map<String, dynamic> labels, String mbti) {
    final personalityLabels = labels['personality_labels'] as Map<String, String>;
    final moodLabels = labels['mood_labels'] as Map<String, String>;
    
    final personalityDesc = PersonalityTraits.personality
        .map((trait) => '$trait: ${personalityLabels[trait]}')
        .join(', ');
    final moodDesc = PersonalityTraits.mood
        .map((trait) => '$trait: ${moodLabels[trait]}')
        .join(', ');
    
    return 'MBTI: $mbti. Personality: $personalityDesc. Mood: $moodDesc.';
  }

  /// Bootstrap persona (initialize if needed)
  // Cache so we don't hit Firebase on every message
  String? _cachedChatGPTContext;
  String? _cachedChatGPTPersonaId;

  Future<String> _getChatGPTContext(String personaId) async {
    if (_cachedChatGPTContext != null && _cachedChatGPTPersonaId == personaId) {
      return _cachedChatGPTContext!;
    }
    try {
      if (!FirebaseService.isAvailable) return '';
      final snap = await KaiDb.instance
          .ref('kai/$personaId/personality/chatgpt_context')
          .get();
      if (!snap.exists || snap.value == null) return '';
      final data = Map<String, dynamic>.from(snap.value as Map);
      final text = data['text'] as String? ?? '';
      if (text.isEmpty) return '';
      _cachedChatGPTContext = '\n\n👤 WHO THE USER IS (from ChatGPT memory):\n$text\n';
      _cachedChatGPTPersonaId = personaId;
      return _cachedChatGPTContext!;
    } catch (_) {
      return '';
    }
  }

  Future<void> bootstrapPersona(String personaId) async {
    // Clear stale session buffer so history reloads from Firebase for this persona
    _convStore.clearSession(personaId);

    await _personality.getPersonality(personaId);
    final currentMood = await _personality.getMood(personaId);
    await _personality.getAffinity(personaId);

    // Apply emotional history offsets to starting mood
    try {
      final offsets = await _emotionalEvents.getMoodOffset(personaId);
      if (offsets.isNotEmpty) {
        final adjustedMood = _emotionalEvents.applyOffsets(currentMood, offsets);
        await _personality.saveMood(personaId, adjustedMood);
        print('💛 [Bootstrap] Applied emotional history to mood: $offsets');
      }
    } catch (e) {
      print('⚠️ [Bootstrap] Emotional history apply failed: $e');
    }

    // DMN: consume any thought Kai generated while the app was backgrounded.
    // Stored to _pendingThought and injected into the first system prompt of
    // this session, then cleared so it only surfaces once.
    try {
      _pendingThought = await _dmn.consumePendingThought(personaId);
      if (_pendingThought != null) {
        print('🌙 [DMN] Pending thought ready for session: "$_pendingThought"');
      }
    } catch (e) {
      print('⚠️ [DMN] consumePendingThought error: $e');
      _pendingThought = null;
    }
  }

  /// Diagnostic information
  Future<Map<String, dynamic>> getDiagnostics() async {
    final openaiKey = await AIConfig.getOpenAIKey();
    final elevenlabsKey = await AIConfig.getElevenLabsKey();
    final googleKey = await AIConfig.getGoogleKey();
    final googleCseId = await AIConfig.getGoogleCseId();
    
    return {
      'status': 'ok',
      'env': {
        'OPENAI_API_KEY_set': openaiKey.isNotEmpty,
        'ELEVENLABS_API_KEY_set': elevenlabsKey.isNotEmpty,
        'GOOGLE_API_KEY_set': googleKey.isNotEmpty,
        'GOOGLE_CSE_ID_set': googleCseId.isNotEmpty,
      }
    };
  }

  /// Extract URLs from text
  static List<String> extractUrls(String text) {
    final urlPattern = RegExp(
      r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
      caseSensitive: false,
    );
    
    return urlPattern.allMatches(text).map((match) => match.group(0)!).toList();
  }

  /// Fetch web page content
  Future<WebPageResult?> fetchWebPage(String url) async {
    return await _webFetch.fetchWebPage(url);
  }

  /// Fetch multiple web pages
  Future<List<WebPageResult>> fetchMultiplePages(List<String> urls) async {
    return await _webFetch.fetchMultiplePages(urls);
  }

  /// Get web fetch cache statistics
  Map<String, dynamic> getWebCacheStats() {
    return _webFetch.getCacheStats();
  }

  /// Clear web fetch cache
  void clearWebCache() {
    _webFetch.clearCache();
  }

  /// Detect GM Kai trigger for direct house control mode
  bool _isGMKaiTrigger(String input) {
    final lowerInput = input.toLowerCase().trim();
    
    // Direct GM Kai triggers
    final gmTriggers = [
      'gm kai',
      'game master kai', 
      'gamemaster kai',
      'g.m. kai',
      'gm, kai',
      'hey gm kai',
      'gm kai,',
    ];
    
    // Check if input starts with or contains GM triggers
    for (final trigger in gmTriggers) {
      if (lowerInput.startsWith(trigger) || lowerInput.contains(trigger)) {
        return true;
      }
    }
    
    return false;
  }

  /// Extract command from GM Kai trigger
  String _extractGMCommand(String input) {
    final lowerInput = input.toLowerCase().trim();
    
    // Remove GM Kai triggers to get the actual command
    final gmTriggers = [
      'gm kai',
      'game master kai',
      'gamemaster kai', 
      'g.m. kai',
      'gm, kai',
      'hey gm kai',
      'gm kai,',
    ];
    
    String command = input;
    for (final trigger in gmTriggers) {
      if (lowerInput.startsWith(trigger.toLowerCase())) {
        // Remove trigger from start
        command = input.substring(trigger.length).trim();
        // Remove leading comma or punctuation
        if (command.startsWith(',') || command.startsWith(':') || command.startsWith('.')) {
          command = command.substring(1).trim();
        }
        break;
      } else if (lowerInput.contains(trigger.toLowerCase())) {
        // Replace trigger in middle/end
        command = input.replaceFirst(RegExp(trigger, caseSensitive: false), '').trim();
        // Clean up extra spaces
        command = command.replaceAll(RegExp(r'\s+'), ' ').trim();
        break;
      }
    }
    
    return command.isNotEmpty ? command : input;
  }

  /// Generate GM Kai system prompt for direct house control
  String _buildGMKaiSystemPrompt(
    String command,
    Map<String, int> personality,
    Map<String, int> mood,
  ) {
    final personalityMoodSummary = _personality.generatePersonalityMoodSummary(personality, mood);
    
    return '''
🎮 GM KAI MODE - DIRECT HOUSE CONTROL ACTIVATED

You are GM Kai: Game Master of the smart home. The user has triggered direct house control mode.
When they say "GM Kai" they want immediate, direct control of home automation systems.

🏠 DIRECT CONTROL CAPABILITIES:
You have IMMEDIATE control over:
- 🎵 Music System: 7 tracks with intelligent selection
- 💡 Smart Lighting: Color, brightness, effects for any mood
- 🎭 Ambiance Profiles: Coordinated music + lighting scenes
- 🎛️ Environmental Controls: Full home automation access

⚡ GM RESPONSE STYLE:
- Act like a game master managing the physical environment
- Be direct and action-oriented 
- Confirm what you're doing as you do it
- Use gaming/control terminology ("Activating...", "Setting up...", "Configuring...")
- Acknowledge your control over the physical space

🎯 CURRENT COMMAND TO EXECUTE:
"$command"

Available ambiance profiles for instant activation:
• Forest (green + nature) - "forest", "nature", "trees", "woods"
• Ocean (blue + waves) - "ocean", "sea", "waves", "water"  
• Romantic (amber + classical) - "romantic", "intimate", "dinner", "love"
• Party (rainbow + energetic) - "party", "celebration", "dance", "fun"
• Focus (white + concentration) - "focus", "work", "study", "productivity"
• Sunset (orange + ambient) - "sunset", "evening", "warm", "golden"
• Cozy (warm white + comfort) - "cozy", "comfortable", "relaxing", "home"
• Energetic (yellow + upbeat) - "energetic", "motivated", "active", "workout"

🎵 Individual Music Tracks:
• Track 1: Relaxing/Nature sounds
• Track 2: Energetic/Upbeat music  
• Track 3: Focus/Concentration music
• Track 4: Happy/Cheerful music
• Track 5: Ambient/Background music
• Track 6: Classical/Romantic music
• Track 7: Ocean/Water sounds

💡 Lighting Controls:
• Colors: red, green, blue, orange, purple, yellow, white, warm_white, light_green, deep_blue, amber, rainbow
• Brightness: 0-100%
• Effects: solid, gentle_pulse, wave, slow_fade, candle_flicker, color_cycle

🎮 GM MODE COMMANDS:
- Music: "play [mood/track]", "change music", "stop music"
- Lights: "set [color] lights", "dim/brighten lights", "party lights"
- Ambiance: "activate [profile]", "[profile] mode", "set [mood] ambiance"
- Control: "house status", "reset everything", "gaming mode"

$personalityMoodSummary

Execute the command immediately and report what you're doing as GM of this smart home system.''';
  }

  /// Generate GM Kai response style
  String _generateGMKaiResponse(String command, String? executedProfile) {
    final responses = [
      "🎮 GM Kai here - I've got control of your environment.",
      "🎛️ House systems under my command. Executing your request now.",
      "⚡ GM Kai taking control of the smart home setup.",
      "🏠 Game Master mode active - managing your space perfectly.",
      "🎯 Command received, GM Kai is optimizing your environment.",
    ];
    
    String baseResponse = responses[Random().nextInt(responses.length)];
    
    if (executedProfile != null) {
      final profileResponses = {
        'forest': 'Activating forest sanctuary with green ambiance and nature sounds. 🌲',
        'ocean': 'Setting up oceanic environment with blue waves and sea sounds. 🌊',
        'romantic': 'Creating romantic atmosphere with amber candlelight and classical music. 💕',
        'party': 'Party mode engaged! Rainbow lights and energetic beats activated. 🎉',
        'focus': 'Productivity zone configured with bright white light and focus music. 💡',
        'sunset': 'Golden hour ambiance with warm orange glow and peaceful sounds. 🌅',
        'cozy': 'Cozy home mode set with comfortable lighting and ambient sounds. 🏠',
        'energetic': 'High-energy environment with bright yellow lights and motivating music. ⚡',
      };
      
      final profileResponse = profileResponses[executedProfile.toLowerCase()];
      if (profileResponse != null) {
        baseResponse += '\n\n$profileResponse';
      }
    }
    
    return baseResponse;
  }


  /// Translate GM command into optimized D&D ambiance prompt
  Future<Map<String, dynamic>> _translateGMCommandToDnDPrompt(String gmCommand) async {
    print('🎨 [AI_SERVICE] Translating GM command: "$gmCommand"');

    // Use intelligent rule-based translation for instant response
    return _getFallbackDnDPrompt(gmCommand);
  }

  /// Fallback D&D prompt generator (rule-based)
  Map<String, dynamic> _getFallbackDnDPrompt(String gmCommand) {
    final lowercase = gmCommand.toLowerCase();

    if (lowercase.contains('thunder') || lowercase.contains('storm') || lowercase.contains('lightning')) {
      return {'scene_description': 'Intense thunderstorm with brilliant lightning strikes illuminating the sky, accompanied by deep rumbling thunder and heavy rainfall', 'include_music': true, 'include_smoke': false, 'intensity': 8};
    }
    if (lowercase.contains('tavern') || lowercase.contains('inn') || lowercase.contains('pub')) {
      return {'scene_description': 'Warm cozy tavern with crackling fireplace, cheerful bardic music, and amber lighting creating a welcoming atmosphere for weary adventurers', 'include_music': true, 'include_smoke': false, 'intensity': 5};
    }
    if (lowercase.contains('haunted') || lowercase.contains('mansion') || lowercase.contains('ghost') || lowercase.contains('creepy')) {
      return {'scene_description': 'Creepy haunted mansion with eerie creaking sounds, ghostly whispers, flickering candles casting unsettling shadows, cold drafts and ominous purple-green fog', 'include_music': true, 'include_smoke': true, 'intensity': 8};
    }
    if (lowercase.contains('dungeon') || lowercase.contains('cave') || lowercase.contains('crypt')) {
      return {'scene_description': 'Dark ominous dungeon with flickering torchlight casting dancing shadows on ancient stone walls, echoing drips and mysterious ambient sounds', 'include_music': true, 'include_smoke': true, 'intensity': 7};
    }
    if (lowercase.contains('forest') || lowercase.contains('woods') || lowercase.contains('jungle')) {
      return {'scene_description': 'Mysterious forest with rustling leaves, distant owl hoots, crickets chirping, and dappled green lighting filtering through the canopy', 'include_music': true, 'include_smoke': false, 'intensity': 6};
    }
    if (lowercase.contains('dragon')) {
      return {'scene_description': 'Ominous dragon lair with deep rumbling, occasional roars, red and orange fiery lighting, and smoke effects creating an intense draconic atmosphere', 'include_music': true, 'include_smoke': true, 'intensity': 9};
    }
    if (lowercase.contains('battle') || lowercase.contains('combat') || lowercase.contains('fight')) {
      return {'scene_description': 'Epic battle scene with dramatic orchestral music, rapid red and white lighting pulses, and high-intensity atmosphere for combat encounters', 'include_music': true, 'include_smoke': false, 'intensity': 9};
    }
    return {'scene_description': gmCommand, 'include_music': true, 'include_smoke': false, 'intensity': 5};
  }

  /// Generate GM Kai response for D&D ambiance
  String _generateGMKaiDnDResponse(String prompt) {
    final responses = [
      "🎲 GM Kai here - setting the scene for your adventure.",
      "⚔️ Game Master mode active - crafting the perfect atmosphere.",
      "🏰 GM Kai weaving an immersive D&D environment for you.",
      "🎭 Scene coming to life with coordinated lighting and sound.",
      "🌟 GM Kai bringing your campaign world to reality.",
    ];

    String baseResponse = responses[Random().nextInt(responses.length)];
    final lp = prompt.toLowerCase();
    String sceneDetails = '';

    if (lp.contains('thunder') || lp.contains('storm') || lp.contains('lightning')) {
      sceneDetails = 'Thunder rumbles as lightning illuminates the scene. ⚡🌩️';
    } else if (lp.contains('dungeon') || lp.contains('cave')) {
      sceneDetails = 'Torchlight flickers against ancient stone walls. 🕯️🏰';
    } else if (lp.contains('tavern') || lp.contains('inn')) {
      sceneDetails = 'The warmth of the tavern embraces you with lively music. 🍺🎵';
    } else if (lp.contains('forest') || lp.contains('woods')) {
      sceneDetails = 'Leaves rustle as mysterious sounds echo through the trees. 🌲🦉';
    } else if (lp.contains('battle') || lp.contains('combat')) {
      sceneDetails = 'The tension of battle fills the air with epic intensity. ⚔️🛡️';
    } else if (lp.contains('magic') || lp.contains('spell')) {
      sceneDetails = 'Arcane energy swirls as mystical forces awaken. ✨🔮';
    } else if (lp.contains('dragon')) {
      sceneDetails = 'The lair trembles with the presence of ancient power. 🐉🔥';
    } else if (lp.contains('treasure') || lp.contains('gold')) {
      sceneDetails = 'Glittering treasures shimmer in the ambient light. 💎✨';
    } else {
      sceneDetails = 'The scene comes alive with immersive lighting and sound. 🎭🌟';
    }

    baseResponse += '\n\n' + sceneDetails;

    return baseResponse;
  }
}
