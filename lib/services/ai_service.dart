// AI Service - Pure Flutter/Dart implementation
// Replaces the Python Flask backend

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configuration class to hold all API keys
class AIConfig {
  // PUT YOUR REAL OPENAI API KEY HERE:
  static const String openaiApiKey = 'your-openai-api-key-here';
  
  // PUT YOUR REAL ELEVENLABS API KEY HERE (optional for voice):
  static const String elevenlabsApiKey = 'your-elevenlabs-api-key-here';
  
  static const String googleApiKey = String.fromEnvironment('GOOGLE_API_KEY', defaultValue: '');
  static const String googleCseId = String.fromEnvironment('GOOGLE_CSE_ID', defaultValue: '');
  
  // ElevenLabs settings
  static const String elevenlabsVoiceId = String.fromEnvironment('ELEVENLABS_VOICE_ID', 
      defaultValue: 'rjyk3ukVFAi8OdkRXxK2');
  static const String elevenlabsModelId = String.fromEnvironment('ELEVENLABS_MODEL_ID', 
      defaultValue: 'eleven_monolingual_v1');
}

/// Personality and mood traits
class PersonalityTraits {
  static const List<String> personality = ["extraversion", "intuition", "feeling", "perceiving"];
  static const List<String> mood = ["valence", "energy", "warmth", "confidence", "playfulness", "focus"];
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

/// Pure Flutter AI Service
class AIService {
  late final Dio _dio;
  SharedPreferences? _prefs;
  Completer<void>? _prefsCompleter;
  
  // Default personality values (matching Python backend)
  static const Map<String, int> _defaultPersonality = {
    "extraversion": 300,
    "intuition": 700,
    "feeling": 800,
    "perceiving": 600,
  };
  
  static const Map<String, int> _defaultMood = {
    "valence": 60,
    "energy": 65,
    "warmth": 70,
    "confidence": 60,
    "playfulness": 80,
    "focus": 50,
  };

  static const Map<String, int> _defaultAffinity = {
    "intimacy": 50,
    "physicality": 50,
  };

  AIService() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ));
    _initializePrefs();
  }

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

  /// Clamp values to valid ranges
  int _clamp(int value, int min, int max) => value.clamp(min, max);

  /// Get current personality from local storage
  Future<Map<String, int>> getPersonality(String personaId) async {
    final prefs = await _prefsInstance;
    final personality = <String, int>{};
    for (final trait in PersonalityTraits.personality) {
      final key = '${personaId}_personality_$trait';
      personality[trait] = prefs.getInt(key) ?? _defaultPersonality[trait]!;
    }
    return personality;
  }

  /// Get current mood from local storage
  Future<Map<String, int>> getMood(String personaId) async {
    final prefs = await _prefsInstance;
    final mood = <String, int>{};
    for (final trait in PersonalityTraits.mood) {
      final key = '${personaId}_mood_$trait';
      mood[trait] = prefs.getInt(key) ?? _defaultMood[trait]!;
    }
    return mood;
  }

  /// Get current affinity from local storage
  Future<Map<String, int>> getAffinity(String personaId) async {
    final prefs = await _prefsInstance;
    final affinity = <String, int>{};
    for (final key in _defaultAffinity.keys) {
      final prefKey = '${personaId}_affinity_$key';
      affinity[key] = prefs.getInt(prefKey) ?? _defaultAffinity[key]!;
    }
    return affinity;
  }

  /// Save personality to local storage
  Future<void> savePersonality(String personaId, Map<String, int> personality) async {
    final prefs = await _prefsInstance;
    for (final entry in personality.entries) {
      final key = '${personaId}_personality_${entry.key}';
      await prefs.setInt(key, entry.value);
    }
  }

  /// Save mood to local storage
  Future<void> saveMood(String personaId, Map<String, int> mood) async {
    final prefs = await _prefsInstance;
    for (final entry in mood.entries) {
      final key = '${personaId}_mood_${entry.key}';
      await prefs.setInt(key, entry.value);
    }
  }

  /// Save affinity to local storage
  Future<void> saveAffinity(String personaId, Map<String, int> affinity) async {
    final prefs = await _prefsInstance;
    for (final entry in affinity.entries) {
      final key = '${personaId}_affinity_${entry.key}';
      await prefs.setInt(key, entry.value);
    }
  }

  /// Calculate MBTI from personality values
  String calculateMBTI(Map<String, int> personality) {
    return (personality["extraversion"]! >= 500 ? "E" : "I") +
           (personality["intuition"]! >= 500 ? "N" : "S") +
           (personality["feeling"]! >= 500 ? "F" : "T") +
           (personality["perceiving"]! >= 500 ? "P" : "J");
  }

  /// Get personality and mood labels
  Map<String, dynamic> getLabels(Map<String, int> personality, Map<String, int> mood) {
    const personalityLabels = {
      "extraversion": ["withdrawn","introverted","reserved","quiet","neutral","sociable","friendly","talkative","outgoing","vivacious"],
      "intuition": ["concrete","practical","grounded","realistic","balanced","imaginative","inventive","intuitive","visionary","dreamy"],
      "feeling": ["detached","objective","logical","analytical","even","gentle","caring","empathetic","warm","compassionate"],
      "perceiving": ["rigid","structured","methodical","organized","flexible","casual","adaptive","spontaneous","chaotic","free-spirited"],
    };
    
    const moodLabels = {
      "valence": ["depressed","down","flat","neutral","mild","content","pleased","cheerful","happy","euphoric"],
      "energy": ["exhausted","tired","lethargic","calm","easygoing","rested","lively","active","energized","wired"],
      "warmth": ["cold","aloof","distant","reserved","neutral","pleasant","friendly","warm","caring","loving"],
      "confidence": ["insecure","unsure","timid","hesitant","steady","stable","assured","confident","bold","fearless"],
      "playfulness": ["serious","strict","reserved","formal","casual","silly","goofy","cheeky","mischievous","whimsical"],
      "focus": ["scattered","distracted","unfocused","wandering","neutral","collected","attentive","engaged","laser","locked-in"],
    };

    final personalityLabelMap = <String, String>{};
    final moodLabelMap = <String, String>{};

    for (final entry in personality.entries) {
      final trait = entry.key;
      final value = entry.value;
      final index = (value / 100).floor().clamp(0, 9);
      personalityLabelMap[trait] = personalityLabels[trait]![index];
    }

    for (final entry in mood.entries) {
      final trait = entry.key;
      final value = entry.value;
      final index = (value / 10).floor().clamp(0, 9);
      moodLabelMap[trait] = moodLabels[trait]![index];
    }

    return {
      "personality_labels": personalityLabelMap,
      "mood_labels": moodLabelMap,
    };
  }

  /// Call OpenAI API for chat completion
  Future<String> _callOpenAI(List<Map<String, String>> messages, String model) async {
    if (AIConfig.openaiApiKey.isEmpty) {
      throw Exception('OpenAI API key not configured');
    }

    try {
      final response = await _dio.post(
        'https://api.openai.com/v1/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer ${AIConfig.openaiApiKey}',
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
    if (AIConfig.openaiApiKey.isEmpty) {
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
      ], "gpt-4o-mini");

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

  /// Text-to-speech using ElevenLabs
  Future<Uint8List?> synthesizeTTS(String text) async {
    if (AIConfig.elevenlabsApiKey.isEmpty) {
      print('ElevenLabs API key not configured');
      return null;
    }

    try {
      final response = await _dio.post(
        'https://api.elevenlabs.io/v1/text-to-speech/${AIConfig.elevenlabsVoiceId}',
        options: Options(
          headers: {
            'xi-api-key': AIConfig.elevenlabsApiKey,
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.bytes,
        ),
        data: {
          'text': text,
          'model_id': AIConfig.elevenlabsModelId,
          'voice_settings': {
            'stability': 0.6,
            'similarity_boost': 0.75,
          },
        },
      );

      return Uint8List.fromList(response.data);
    } catch (e) {
      print('TTS error: $e');
      return null;
    }
  }

  /// Main chat function
  Future<ChatResponse> sendMessage({
    required String text,
    required String personaId,
    String model = 'gpt-4o',
    bool adaptUser = false,
    int ctxTurns = 20,
  }) async {
    // Get current state
    final personality = await getPersonality(personaId);
    final mood = await getMood(personaId);
    final affinity = await getAffinity(personaId);

    // Build conversation history (simplified for now)
    final history = await _getConversationHistory(personaId, ctxTurns);
    
    // Build system prompt
    final mbti = calculateMBTI(personality);
    
    final systemPrompt = '''
You are Kai: warm, witty, emotionally attuned AI companion.
Answer concisely and helpfully.

Current MBTI: $mbti
Personality: $personality
Mood: $mood
${adaptUser ? 'Affinity: $affinity' : ''}

Recent conversation:
${history.join('\n')}''';

    // Get AI response
    final reply = await _callOpenAI([
      {"role": "system", "content": systemPrompt},
      {"role": "user", "content": text}
    ], model);

    // Get deltas and update personality/mood
    final tagsResult = await _getTagsAndDeltas(reply);
    final personalityDelta = Map<String, int>.from(tagsResult['persona_delta'] ?? {});
    final moodDelta = Map<String, int>.from(tagsResult['mood_delta'] ?? {});
    final tags = List<String>.from(tagsResult['tags'] ?? []);

    // Apply deltas
    final actualDeltas = <String, int>{};
    final newPersonality = Map<String, int>.from(personality);
    final newMood = Map<String, int>.from(mood);

    for (final trait in PersonalityTraits.personality) {
      final delta = _clamp(personalityDelta[trait] ?? 0, -10, 10);
      newPersonality[trait] = _clamp(newPersonality[trait]! + delta, 0, 1000);
      if (delta != 0) actualDeltas[trait] = delta;
    }

    for (final trait in PersonalityTraits.mood) {
      final delta = _clamp(moodDelta[trait] ?? 0, -5, 5);
      newMood[trait] = _clamp(newMood[trait]! + delta, 0, 100);
      if (delta != 0) actualDeltas[trait] = delta;
    }

    // Save updated state
    await savePersonality(personaId, newPersonality);
    await saveMood(personaId, newMood);
    await _saveMessage(personaId, text, reply);

    // Generate TTS
    final ttsBytes = await synthesizeTTS(reply);
    final ttsBase64 = ttsBytes != null ? base64Encode(ttsBytes) : null;

    return ChatResponse(
      reply: reply.isEmpty ? "(no reply)" : reply,
      ttsBase64: ttsBase64,
      raw: {
        'kai_response': reply,
        'persona_delta': personalityDelta,
        'mood_delta': moodDelta,
        'actual_deltas': actualDeltas,
        'tags': tags,
      },
      personalityDelta: personalityDelta,
      moodDelta: moodDelta,
      actualDeltas: actualDeltas,
      tags: tags,
      mbti: calculateMBTI(newPersonality),
      webUsed: false,
      liveUsed: null,
    );
  }

  /// Get agent state
  Future<AgentState> getAgentState(String personaId) async {
    final personality = await getPersonality(personaId);
    final mood = await getMood(personaId);
    final affinity = await getAffinity(personaId);
    final mbti = calculateMBTI(personality);
    final labels = getLabels(personality, mood);

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
    await savePersonality(personaId, personality);
    await saveMood(personaId, mood);
    await saveAffinity(personaId, affinity);
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

  /// Save message to conversation history
  Future<void> _saveMessage(String personaId, String userMessage, String aiReply) async {
    final prefs = await _prefsInstance;
    final key = '${personaId}_history';
    final existing = prefs.getStringList(key) ?? [];
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    existing.add('[$timestamp] User: $userMessage');
    existing.add('[$timestamp] Kai: $aiReply');
    
    // Keep only last 40 messages (20 exchanges)
    if (existing.length > 40) {
      existing.removeRange(0, existing.length - 40);
    }
    
    await prefs.setStringList(key, existing);
  }

  /// Get conversation history
  Future<List<String>> _getConversationHistory(String personaId, int maxTurns) async {
    final prefs = await _prefsInstance;
    final key = '${personaId}_history';
    final history = prefs.getStringList(key) ?? [];
    final maxMessages = maxTurns * 2; // Each turn has user + AI message
    
    if (history.length <= maxMessages) return history;
    return history.sublist(history.length - maxMessages);
  }

  /// Bootstrap persona (initialize if needed)
  Future<void> bootstrapPersona(String personaId) async {
    // This just ensures the persona exists with default values
    await getPersonality(personaId);
    await getMood(personaId);
    await getAffinity(personaId);
  }

  /// Diagnostic information
  Future<Map<String, dynamic>> getDiagnostics() async {
    return {
      'status': 'ok',
      'env': {
        'OPENAI_API_KEY_set': AIConfig.openaiApiKey.isNotEmpty,
        'ELEVENLABS_API_KEY_set': AIConfig.elevenlabsApiKey.isNotEmpty,
        'GOOGLE_API_KEY_set': AIConfig.googleApiKey.isNotEmpty,
        'GOOGLE_CSE_ID_set': AIConfig.googleCseId.isNotEmpty,
      }
    };
  }
}