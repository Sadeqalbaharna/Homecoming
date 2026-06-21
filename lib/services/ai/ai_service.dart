// AI Service - Pure Flutter/Dart implementation with Firebase integration
// Replaces the Python Flask backend

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_database/firebase_database.dart';
import '../core/firebase_service.dart';
import '../core/emotional_event_service.dart';
import '../core/journal_service.dart';
import '../core/conversation_store_service.dart';
import '../core/brain_extraction_service.dart';
import '../core/memory_consolidation_service.dart';
import 'usage_tracking_service.dart';
import 'memory_service.dart';
import 'curiosity_service.dart';
import 'google_search_service.dart';
import '../core/web_fetch_service.dart';
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
  final _journal = JournalService();
  final _convStore = ConversationStoreService();
  final _brain = BrainExtractionService();

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

  Future<SharedPreferences> get _prefsInstance async {
    await _initializePrefs();
    return _prefs!;
  }


  /// Call OpenAI API for chat completion
  Future<String> _callOpenAI(List<Map<String, String>> messages, String model, {String operation = 'chat', Map<String, int>? usageOut}) async {
    final openaiKey = await AIConfig.getOpenAIKey();
    if (openaiKey.isEmpty) {
      throw Exception('OpenAI API key not configured');
    }

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
          'max_tokens': 1000,
          'temperature': 0.7,
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
  }) async {
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
    
    try {
      // Get current state
      debugService.addStep(
        BrainPhase.workingMemory,
        'Loading personality and mood state',
      );
      
      var personality = await _personality.getPersonality(personaId);
      var mood = await _personality.getMood(personaId);
      final affinity = await _personality.getAffinity(personaId);
      final lastUpdate = await _personality.getLastUpdateTime(personaId);
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

    // Build conversation history — loaded from Firebase, cross-surface
    final history = await _convStore.getHistory(personaId, maxTurns: ctxTurns);
    
    // Query long-term memory
    String memoryContext = '';
    List<String> memoriesUsed = [];
    dynamic memoryResult; // Capture for debug info
    if (useMemory) {
      debugService.addStep(
        BrainPhase.semanticRetrieval,
        'Querying long-term memory with embeddings',
        data: {'query': text.length > 100 ? '${text.substring(0, 100)}...' : text},
      );
      
      print('🧠 [AI_SERVICE] Memory query enabled for personaId: $personaId');
      print('🧠 [AI_SERVICE] Query text: "$text"');
      try {
        memoryResult = await MemoryService.queryMemory(
          personaId: personaId,
          query: text,
          limit: 5,
        );
        print('🧠 [AI_SERVICE] Memory query complete. Results: ${memoryResult?.results.length ?? 0}');
        
        if (memoryResult != null && memoryResult.results.isNotEmpty) {
          memoryContext = memoryResult.toContextString();
          memoriesUsed = memoryResult.results
              .where((r) => r.similarity > 0.35) // Lowered threshold to 35%
              .map((r) => r.summary)
              .toList();
          print('💭 Using ${memoriesUsed.length} memory contexts (threshold: 0.35)');
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

    // NEW: Check for ambiance requests and handle them (normal mode)
    final ambianceService = AmbianceService();
    final ambianceMatch = !isGMMode ? ambianceService.analyzeVoiceCommand(processedText) : null;
    
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
    
    // Analyze knowledge gaps and generate curious questions
    String curiosityPrompt = '';
    CuriosityQuestion? selectedQuestion;
    if (useMemory) {
      debugService.addStep(
        BrainPhase.emotionalCheck,
        'Analyzing knowledge gaps for curiosity',
      );
      print('🤔 [AI_SERVICE] Analyzing curiosity opportunities...');
      try {
        final curiosityService = CuriosityService();
        
        // Convert memory results to format expected by curiosity service
        List<Map<String, dynamic>> recentMemories = [];
        if (memoryResult != null && memoryResult.results.isNotEmpty) {
          recentMemories = memoryResult.results.map((r) => {
            'summary': r.summary,
            'timestamp': r.timestamp,
            'shardId': r.shardId,
          }).toList();
        }
        
        final questions = await curiosityService.analyzeKnowledgeGaps(
          personaId: personaId,
          recentMemories: recentMemories,
          currentContext: text,
        );
        
        print('🤔 [AI_SERVICE] Found ${questions.length} potential questions');
        
        // 40% chance to include a question (higher for emotional topics)
        final includeQuestion = questions.isNotEmpty && (
          questions.first.priority >= 9 || // Always ask high-priority (emotional)
          Random().nextDouble() < 0.4 // 40% chance otherwise
        );
        
        if (includeQuestion) {
          selectedQuestion = questions.first;
          curiosityPrompt = '''

🤔 CURIOSITY:
You're genuinely curious about the user. If it feels natural in this conversation, you might ask: "${selectedQuestion.question}"
(Why: ${selectedQuestion.reasoning})
Don't force it - only ask if the flow of conversation makes it appropriate.''';
          print('🤔 [AI_SERVICE] Selected question: ${selectedQuestion.question} (priority: ${selectedQuestion.priority})');
          
          debugService.addStep(
            BrainPhase.emotionalCheck,
            'Curiosity question selected',
            data: {
              'question': selectedQuestion.question,
              'priority': selectedQuestion.priority,
              'category': selectedQuestion.category.toString(),
            },
          );
        } else {
          print('🤔 [AI_SERVICE] No question selected this time');
          debugService.addStep(
            BrainPhase.emotionalCheck,
            'No curiosity question needed',
          );
        }
      } catch (e) {
        print('❌ [AI_SERVICE] Curiosity analysis failed: $e');
        print('⚠️ [AI_SERVICE] Continuing without curiosity prompt');
        // Continue without curiosity - don't fail the entire request
      }
    }
    
    // 🤖 NEW: Get Kai's consciousness context for smart home requests
    Map<String, dynamic>? kaiConsciousness;
    bool isSmartHomeRequest = KaiConsciousnessService.isSmartHomeRequest(text);
    
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
      
      systemPrompt = '''
You are Kai: warm, witty, emotionally attuned AI companion.
Answer concisely and helpfully.${webContext.isNotEmpty ? '\n\nIf WEB CONTEXT is provided, **treat it as the source of truth** for time-sensitive or factual claims and cite as [1], [2], etc. If not relevant, ignore it.' : ''}${urlContext.isNotEmpty ? '\n\nIf WEB PAGE CONTENT is provided, use it to answer questions about the specific pages. Cite sources and summarize key points.' : ''}

🎵 SMART HOME CONTROL CAPABILITIES:
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

When someone asks for music or ambiance, respond enthusiastically and mention you're setting it up!
Example: "Perfect! I'm setting up a peaceful forest ambiance with gentle green lighting and nature sounds for you. 🌲"

$projectContext$constraintsBlock

$personalityMoodSummary
${adaptUser ? '\n💫 AFFINITY: Intimacy level ${affinity['intimacy']}/100, Physical comfort ${affinity['physicality']}/100' : ''}
${await _getChatGPTContext(personaId)}
${await MemoryConsolidationService().getConsolidatedMemoryBlock(personaId).then((m) => m.isNotEmpty ? '\n$m\n' : '')}
Recent conversation:
${history.join('\n')}$memoryContext$urlContext$webContext$curiosityPrompt''';
    }

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
    final userMessage = isGMMode ? processedText : text;
    final _mainUsage = <String, int>{};
    final reply = await _callOpenAI([
      {"role": "system", "content": systemPrompt},
      {"role": "user", "content": userMessage}
    ], model, usageOut: _mainUsage);
    print('📥 [SEND MESSAGE] OpenAI response received: ${reply.length} characters');
    
    debugService.addStep(
      BrainPhase.responseGeneration,
      'GPT response received',
      data: {
        'responseLength': reply.length,
        'responsePreview': reply.length > 150 ? '${reply.substring(0, 150)}...' : reply,
      },
    );

    // 🎵 NEW: Check if Kai mentioned setting up ambiance and actually trigger it
    await _ambient.detectAndTriggerAmbianceFromReply(reply, processedText, debugService);

    // Track if curiosity question was asked
    if (selectedQuestion != null) {
      print('🤔 [AI_SERVICE] Checking if question was asked in response...');
      try {
        final curiosityService = CuriosityService();
        // Simple check: if any significant words from the question appear in the reply
        final questionWords = selectedQuestion.question.toLowerCase().split(' ')
            .where((w) => w.length > 3) // Only check words longer than 3 chars
            .toSet();
        final replyWords = reply.toLowerCase().split(' ').toSet();
        final matchingWords = questionWords.intersection(replyWords);
        
        // If at least 2 key words match or if reply ends with '?', assume question was asked
        if (matchingWords.length >= 2 || reply.trim().endsWith('?')) {
          await curiosityService.markQuestionAsked(
            personaId: personaId,
            question: selectedQuestion.question,
            category: selectedQuestion.category.toString().split('.').last,
          );
          print('🤔 [AI_SERVICE] ✅ Marked question as asked');
        } else {
          print('🤔 [AI_SERVICE] Question not detected in reply (${matchingWords.length} matches)');
        }
      } catch (e) {
        print('❌ [AI_SERVICE] Failed to mark question as asked: $e');
        // Continue - don't fail the request
      }
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

    debugService.addStep(
      BrainPhase.consolidation,
      'Conversation saved to Firebase via ConversationStore',
    );

    // Log emotional event (fire-and-forget)
    _emotionalEvents.classifyAndLog(
      personaId: personaId,
      userMessage: text,
      aiReply: reply,
      moodDeltas: actualMoodDeltas,
    ).catchError((e) => print('⚠️ [EmotionalEvent] classifyAndLog error: $e'));

    // Journal writing disabled — logic under rework
    // _journal.maybeWrite(...)

    // Grow the brain — extract nodes/edges and merge into knowledge graph (fire-and-forget)
    _brain.extractAndMerge(
      personaId: personaId,
      userMessage: text,
      aiReply: reply,
    ).catchError((e) => print('⚠️ [Brain] extractAndMerge error: $e'));

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

    // Generate TTS
    debugService.addStep(
      BrainPhase.tts,
      'Generating audio response',
    );
    
    final ttsBytes = await synthesizeTTS(reply);
    final ttsBase64 = ttsBytes != null ? base64Encode(ttsBytes) : null;
    
    if (ttsBytes != null) {
      debugService.addStep(
        BrainPhase.tts,
        'Audio generated successfully',
        data: {'audioSize': ttsBytes.length, 'base64Length': ttsBase64?.length ?? 0},
      );
    } else {
      debugService.addStep(
        BrainPhase.tts,
        'Audio generation failed',
      );
    }

    // Get baselines for debug info
    Map<String, int> moodBaselines = {};
    try {
      moodBaselines = await _personality.getPersonalMoodBaselines(personaId);
    } catch (e) {
      print('⚠️ [BASELINE ERROR] Failed to load mood baselines for debug: $e');
    }

    // Build debug info
    final debugInfo = {
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
          'included': r.similarity > 0.35,
        }).toList() ?? [],
        'memory_context': memoryContext,
        'similarity_threshold': 0.35,
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

    // Complete brain debug trace
    debugService.completeTrace(reply);

    // 🗜️ Memory consolidation — fire-and-forget, runs every 20 turns
    MemoryConsolidationService().maybeConsolidate(personaId: personaId)
        .catchError((e) => print('⚠️ [Consolidation] $e'));

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
      
      // Generate a basic error-aware response
      final errorResponse = '''I'm having a technical issue right now, but I'm still here! 
      
Let me try to respond to what you said: "${text.length > 100 ? '${text.substring(0, 100)}...' : text}"

I might be experiencing connectivity issues or system processing problems. Could you try asking again? I want to make sure I can give you the best response possible.

(Technical note: ${e.toString().split('\n').first})''';
      
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
      final snap = await FirebaseDatabase.instance
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
    
    // Thunderstorm
    if (lowercase.contains('thunder') || lowercase.contains('storm') || lowercase.contains('lightning')) {
      return {
        'scene_description': 'Intense thunderstorm with brilliant lightning strikes illuminating the sky, accompanied by deep rumbling thunder and heavy rainfall creating an atmospheric storm scene',
        'include_music': true,
        'include_smoke': false,
        'intensity': 8,
      };
    }
    
    // Tavern
    if (lowercase.contains('tavern') || lowercase.contains('inn') || lowercase.contains('pub')) {
      return {
        'scene_description': 'Warm cozy tavern with crackling fireplace, cheerful bardic music, and amber lighting creating a welcoming atmosphere for weary adventurers',
        'include_music': true,
        'include_smoke': false,
        'intensity': 5,
      };
    }
    
    // Haunted Mansion
    if (lowercase.contains('haunted') || lowercase.contains('mansion') || lowercase.contains('ghost') || lowercase.contains('creepy')) {
      return {
        'scene_description': 'Creepy haunted mansion with eerie creaking sounds, ghostly whispers, flickering candles casting unsettling shadows, cold drafts and ominous purple-green fog',
        'include_music': true,
        'include_smoke': true,
        'intensity': 8,
      };
    }
    
    // Dungeon/Cave
    if (lowercase.contains('dungeon') || lowercase.contains('cave') || lowercase.contains('crypt')) {
      return {
        'scene_description': 'Dark ominous dungeon with flickering torchlight casting dancing shadows on ancient stone walls, echoing drips and mysterious ambient sounds',
        'include_music': true,
        'include_smoke': true,
        'intensity': 7,
      };
    }
    
    // Forest
    if (lowercase.contains('forest') || lowercase.contains('woods') || lowercase.contains('jungle')) {
      return {
        'scene_description': 'Mysterious forest with rustling leaves, distant owl hoots, crickets chirping, and dappled green lighting filtering through the canopy',
        'include_music': true,
        'include_smoke': false,
        'intensity': 6,
      };
    }
    
    // Dragon
    if (lowercase.contains('dragon')) {
      return {
        'scene_description': 'Ominous dragon lair with deep rumbling, occasional roars, red and orange fiery lighting, and smoke effects creating an intense draconic atmosphere',
        'include_music': true,
        'include_smoke': true,
        'intensity': 9,
      };
    }
    
    // Battle/Combat
    if (lowercase.contains('battle') || lowercase.contains('combat') || lowercase.contains('fight')) {
      return {
        'scene_description': 'Epic battle scene with dramatic orchestral music, rapid red and white lighting pulses, and high-intensity atmosphere for combat encounters',
        'include_music': true,
        'include_smoke': false,
        'intensity': 9,
      };
    }
    
    // Default
    return {
      'scene_description': gmCommand,
      'include_music': true,
      'include_smoke': false,
      'intensity': 5,
    };
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
    
    // Add scene-specific details based on keywords in prompt
    final lowercasePrompt = prompt.toLowerCase();
    String sceneDetails = '';
    
    if (lowercasePrompt.contains('thunder') || lowercasePrompt.contains('storm') || lowercasePrompt.contains('lightning')) {
      sceneDetails = 'Thunder rumbles as lightning illuminates the scene. ⚡🌩️';
    } else if (lowercasePrompt.contains('dungeon') || lowercasePrompt.contains('cave')) {
      sceneDetails = 'Torchlight flickers against ancient stone walls. 🕯️🏰';
    } else if (lowercasePrompt.contains('tavern') || lowercasePrompt.contains('inn')) {
      sceneDetails = 'The warmth of the tavern embraces you with lively music. 🍺🎵';
    } else if (lowercasePrompt.contains('forest') || lowercasePrompt.contains('woods')) {
      sceneDetails = 'Leaves rustle as mysterious sounds echo through the trees. 🌲🦉';
    } else if (lowercasePrompt.contains('battle') || lowercasePrompt.contains('combat')) {
      sceneDetails = 'The tension of battle fills the air with epic intensity. ⚔️🛡️';
    } else if (lowercasePrompt.contains('magic') || lowercasePrompt.contains('spell')) {
      sceneDetails = 'Arcane energy swirls as mystical forces awaken. ✨🔮';
    } else if (lowercasePrompt.contains('dragon')) {
      sceneDetails = 'The lair trembles with the presence of ancient power. 🐉🔥';
    } else if (lowercasePrompt.contains('treasure') || lowercasePrompt.contains('gold')) {
      sceneDetails = 'Glittering treasures shimmer in the ambient light. 💎✨';
    } else {
      sceneDetails = 'The scene comes alive with immersive lighting and sound. 🎭🌟';
    }
    
    baseResponse += '\n\n' + sceneDetails;
    
    return baseResponse;
  }

}
