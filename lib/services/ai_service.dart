// AI Service - Pure Flutter/Dart implementation with Firebase integration
// Replaces the Python Flask backend

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_service.dart';
import 'secure_storage_service.dart';
import 'usage_tracking_service.dart';
import 'memory_service.dart';
import 'curiosity_service.dart';

/// Configuration class to hold all API keys
/// Uses secure storage for encrypted key management
class AIConfig {
  static final _secureStorage = SecureStorageService();
  
  // Cached keys for performance
  static String? _cachedOpenAIKey;
  static String? _cachedElevenLabsKey;
  static String? _cachedGoogleKey;
  static String? _cachedGoogleCseId;
  
  /// Get OpenAI API Key from secure storage
  static Future<String> getOpenAIKey() async {
    if (_cachedOpenAIKey != null) return _cachedOpenAIKey!;
    _cachedOpenAIKey = await _secureStorage.getOpenAIKey() ?? '';
    return _cachedOpenAIKey!;
  }
  
  /// Get ElevenLabs API Key from secure storage
  static Future<String> getElevenLabsKey() async {
    if (_cachedElevenLabsKey != null) return _cachedElevenLabsKey!;
    _cachedElevenLabsKey = await _secureStorage.getElevenLabsKey() ?? '';
    return _cachedElevenLabsKey!;
  }
  
  /// Get Google API Key from secure storage
  static Future<String> getGoogleKey() async {
    if (_cachedGoogleKey != null) return _cachedGoogleKey!;
    _cachedGoogleKey = await _secureStorage.getGoogleKey() ?? '';
    return _cachedGoogleKey!;
  }
  
  /// Get Google CSE ID from secure storage
  static Future<String> getGoogleCseId() async {
    if (_cachedGoogleCseId != null) return _cachedGoogleCseId!;
    _cachedGoogleCseId = await _secureStorage.getGoogleCseId() ?? '';
    return _cachedGoogleCseId!;
  }
  
  /// Clear cached keys (useful after key updates)
  static void clearCache() {
    _cachedOpenAIKey = null;
    _cachedElevenLabsKey = null;
    _cachedGoogleKey = null;
    _cachedGoogleCseId = null;
  }
  
  // ElevenLabs settings
  static const String elevenlabsVoiceId = String.fromEnvironment('ELEVENLABS_VOICE_ID', 
      defaultValue: 'rjyk3ukVFAi8OdkRXxK2');
  static const String elevenlabsModelId = String.fromEnvironment('ELEVENLABS_MODEL_ID', 
      defaultValue: 'eleven_monolingual_v1');
  
  // Available voices
  static const Map<String, Map<String, String>> availableVoices = {
    'kai_default': {
      'id': 'rjyk3ukVFAi8OdkRXxK2',
      'name': 'Kai (Default)',
      'description': 'Warm, friendly, conversational',
    },
    'kai_alt': {
      'id': 'Ke5IEaBOPxAcw6fm0mO6',
      'name': 'Kai (Alternative)',
      'description': 'Mature, expressive, engaging',
    },
  };
  
  /// Get selected voice ID from preferences
  static Future<String> getSelectedVoiceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_voice_id') ?? elevenlabsVoiceId;
  }
  
  /// Set selected voice ID in preferences
  static Future<void> setSelectedVoiceId(String voiceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_voice_id', voiceId);
  }
}

/// Personality and mood traits
class PersonalityTraits {
  static const List<String> personality = ["extraversion", "intuition", "feeling", "perceiving"];
  static const List<String> mood = ["valence", "energy", "warmth", "confidence", "playfulness", "focus"];
}

/// Mood snapshot for history tracking
class MoodSnapshot {
  final DateTime timestamp;
  final Map<String, int> mood;
  final String? trigger;
  
  MoodSnapshot({
    required this.timestamp,
    required this.mood,
    this.trigger,
  });
  
  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.millisecondsSinceEpoch,
    'mood': mood,
    'trigger': trigger,
  };
  
  factory MoodSnapshot.fromJson(Map<String, dynamic> json) => MoodSnapshot(
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
    mood: Map<String, int>.from(json['mood']),
    trigger: json['trigger'],
  );
}

/// Evolution settings for personality and mood dynamics
class EvolutionSettings {
  // Personality evolution (inelastic - slow to change)
  static const double personalityResistance = 0.15; // Only 15% of delta applied
  static const int personalityDecayThresholdDays = 30; // Decay starts after 30 days
  static const double personalityDecayRate = 0.5; // Points per day toward baseline
  
  // Mood evolution (elastic - fast to change, fast to decay)
  static const Map<String, double> moodDecayRates = {
    'valence': 2.0,      // Happiness - medium decay (2 pts/hour)
    'energy': 3.0,       // Energy - fast decay (3 pts/hour)
    'warmth': 1.5,       // Warmth - slow decay (1.5 pts/hour)
    'confidence': 1.0,   // Confidence - very slow decay (1 pt/hour)
    'playfulness': 2.5,  // Playfulness - fast decay (2.5 pts/hour)
    'focus': 3.5,        // Focus - very fast decay (3.5 pts/hour)
  };
  
  // Context intensity multipliers for mood changes
  static const Map<String, double> contextMultipliers = {
    'normal': 1.0,   // Standard conversation
    'high': 2.0,     // Exciting/frustrating events
    'radical': 4.0,  // Life-changing events
  };
  
  // Baseline learning
  static const int minInteractionsForBaseline = 50; // Need 50+ interactions to learn baseline
  static const int baselineWindowDays = 30; // Use last 30 days for baseline calculation
  static const int maxMoodHistorySize = 100; // Keep last 100 mood snapshots
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
  final List<String> memoriesUsed; // NEW: Track which memories were referenced
  final Map<String, dynamic>? debugInfo; // NEW: Debug information

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
    this.memoriesUsed = const [], // NEW: Default to empty list
    this.debugInfo, // NEW: Optional debug info
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

  /// Calculate extreme resistance for personality changes near boundaries
  /// Returns 0.0 (no resistance) in middle range, up to 0.8 (80% resistance) at extremes
  double _calculateExtremeResistance(int value) {
    if (value < 100) return 0.8;  // 80% resistance near 0
    if (value > 900) return 0.8;  // 80% resistance near 1000
    if (value < 200 || value > 800) return 0.5; // 50% resistance at edges
    return 0.0; // No additional resistance in middle range (200-800)
  }

  /// Apply personality delta with resistance (inelastic change)
  /// Only 15% of requested delta is applied, with additional resistance at extremes
  int _applyPersonalityDelta(int current, int requestedDelta) {
    if (requestedDelta == 0) return current;
    
    // Base resistance: only 15% gets through
    final dampedDelta = (requestedDelta * EvolutionSettings.personalityResistance).round();
    
    // Additional resistance near extremes
    final extremeResistance = _calculateExtremeResistance(current);
    final finalDelta = (dampedDelta * (1.0 - extremeResistance)).round();
    
    return _clamp(current + finalDelta, 0, 1000);
  }

  /// Apply mood delta with context intensity scaling (elastic change)
  /// Mood can swing dramatically based on context intensity
  int _applyMoodDelta(int current, int requestedDelta, String contextIntensity) {
    if (requestedDelta == 0) return current;
    
    final multiplier = EvolutionSettings.contextMultipliers[contextIntensity] ?? 1.0;
    final scaledDelta = (requestedDelta * multiplier).round();
    
    return _clamp(current + scaledDelta, 0, 100);
  }

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

  /// Save personality to local storage and Firebase
  Future<void> savePersonality(String personaId, Map<String, int> personality) async {
    final prefs = await _prefsInstance;
    for (final entry in personality.entries) {
      final key = '${personaId}_personality_${entry.key}';
      await prefs.setInt(key, entry.value);
    }
    
    // Also save to Firebase
    await FirebaseService.savePersonalityData(
      personaId: personaId,
      personalityData: {
        'personality': personality,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  /// Save mood to local storage and Firebase
  Future<void> saveMood(String personaId, Map<String, int> mood) async {
    final prefs = await _prefsInstance;
    for (final entry in mood.entries) {
      final key = '${personaId}_mood_${entry.key}';
      await prefs.setInt(key, entry.value);
    }
    
    // Also save to Firebase
    await FirebaseService.savePersonalityData(
      personaId: '${personaId}_mood',
      personalityData: {
        'mood': mood,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  /// Save affinity to local storage
  Future<void> saveAffinity(String personaId, Map<String, int> affinity) async {
    final prefs = await _prefsInstance;
    for (final entry in affinity.entries) {
      final key = '${personaId}_affinity_${entry.key}';
      await prefs.setInt(key, entry.value);
    }
  }

  /// Get last personality/mood update time
  Future<DateTime> _getLastUpdateTime(String personaId) async {
    final prefs = await _prefsInstance;
    final timestamp = prefs.getInt('${personaId}_last_update') ?? 
                      DateTime.now().millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Save last update time
  Future<void> _saveLastUpdateTime(String personaId, DateTime time) async {
    final prefs = await _prefsInstance;
    await prefs.setInt('${personaId}_last_update', time.millisecondsSinceEpoch);
  }

  /// Apply time-based mood decay toward personal baseline
  /// Mood returns to learned baseline over time when not interacting
  Future<Map<String, int>> _applyMoodDecay(
    String personaId,
    Map<String, int> currentMood,
    DateTime lastUpdate,
  ) async {
    final timeSinceUpdate = DateTime.now().difference(lastUpdate);
    final hoursSinceUpdate = timeSinceUpdate.inHours;
    
    if (hoursSinceUpdate == 0) return currentMood; // No decay needed
    
    // Get personal baselines (learned from history or defaults)
    final baselines = await _getPersonalMoodBaselines(personaId);
    final decayedMood = Map<String, int>.from(currentMood);
    
    for (final trait in PersonalityTraits.mood) {
      final current = currentMood[trait]!;
      final baseline = baselines[trait]!;
      final decayRate = EvolutionSettings.moodDecayRates[trait]!;
      final decayAmount = (hoursSinceUpdate * decayRate).round();
      
      // Decay toward personal baseline
      if (current > baseline) {
        decayedMood[trait] = (current - decayAmount).clamp(baseline, 100);
      } else if (current < baseline) {
        decayedMood[trait] = (current + decayAmount).clamp(0, baseline);
      }
    }
    
    return decayedMood;
  }

  /// Apply minimal personality decay (only after long absence)
  /// Personality only decays after 30+ days of inactivity, very slowly
  Future<Map<String, int>> _applyPersonalityDecay(
    Map<String, int> currentPersonality,
    DateTime lastUpdate,
  ) async {
    final timeSinceUpdate = DateTime.now().difference(lastUpdate);
    final daysSinceUpdate = timeSinceUpdate.inDays;
    
    if (daysSinceUpdate < EvolutionSettings.personalityDecayThresholdDays) {
      return currentPersonality; // No decay before 30 days
    }
    
    final decayedPersonality = Map<String, int>.from(currentPersonality);
    const baseline = 500; // Species baseline (balanced)
    final daysOverThreshold = daysSinceUpdate - EvolutionSettings.personalityDecayThresholdDays;
    final totalDecay = (daysOverThreshold * EvolutionSettings.personalityDecayRate).round();
    
    for (final trait in PersonalityTraits.personality) {
      final current = currentPersonality[trait]!;
      
      // Slow drift toward species baseline
      if (current > baseline) {
        decayedPersonality[trait] = (current - totalDecay).clamp(baseline, 1000);
      } else if (current < baseline) {
        decayedPersonality[trait] = (current + totalDecay).clamp(0, baseline);
      }
    }
    
    return decayedPersonality;
  }

  /// Get personal mood baselines (learned from history or defaults)
  Future<Map<String, int>> _getPersonalMoodBaselines(String personaId) async {
    final prefs = await _prefsInstance;
    
    // Try to load learned baselines
    final baselines = <String, int>{};
    bool hasBaselines = true;
    
    for (final trait in PersonalityTraits.mood) {
      final key = '${personaId}_baseline_$trait';
      final value = prefs.getInt(key);
      if (value == null) {
        hasBaselines = false;
        break;
      }
      baselines[trait] = value;
    }
    
    if (hasBaselines) return baselines;
    
    // Return default baselines until we learn from history
    return Map<String, int>.from(_defaultMood);
  }

  /// Get mood history
  Future<List<MoodSnapshot>> _getMoodHistory(String personaId) async {
    final prefs = await _prefsInstance;
    final historyJson = prefs.getString('${personaId}_mood_history') ?? '[]';
    final historyList = jsonDecode(historyJson) as List;
    
    return historyList.map((item) => MoodSnapshot.fromJson(item as Map<String, dynamic>)).toList();
  }

  /// Save mood snapshot to history
  Future<void> _saveMoodSnapshot(
    String personaId,
    Map<String, int> mood,
    String? trigger,
  ) async {
    final prefs = await _prefsInstance;
    
    // Get existing history
    final history = await _getMoodHistory(personaId);
    
    // Add new snapshot
    history.add(MoodSnapshot(
      timestamp: DateTime.now(),
      mood: mood,
      trigger: trigger,
    ));
    
    // Keep only last 100 snapshots
    if (history.length > EvolutionSettings.maxMoodHistorySize) {
      history.removeRange(0, history.length - EvolutionSettings.maxMoodHistorySize);
    }
    
    // Save back
    final newHistoryJson = jsonEncode(history.map((s) => s.toJson()).toList());
    await prefs.setString('${personaId}_mood_history', newHistoryJson);
  }

  /// Update mood baselines from history (learns user's typical mood)
  /// Called periodically to adapt to user's normal emotional state
  Future<void> _updateMoodBaselines(String personaId) async {
    final history = await _getMoodHistory(personaId);
    
    if (history.length < EvolutionSettings.minInteractionsForBaseline) {
      return; // Not enough data yet
    }
    
    // Calculate rolling average from last 30 days
    final cutoff = DateTime.now().subtract(
      const Duration(days: EvolutionSettings.baselineWindowDays)
    );
    final recent = history.where((s) => s.timestamp.isAfter(cutoff)).toList();
    
    if (recent.isEmpty) return;
    
    final prefs = await _prefsInstance;
    
    for (final trait in PersonalityTraits.mood) {
      final values = recent.map((s) => s.mood[trait]!).toList();
      final average = values.reduce((a, b) => a + b) ~/ values.length;
      
      await prefs.setInt('${personaId}_baseline_$trait', average);
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

  /// Generate compact personality and mood summary for AI prompt
  String generatePersonalityMoodSummary(Map<String, int> personality, Map<String, int> mood) {
    final mbti = calculateMBTI(personality);
    final labels = getLabels(personality, mood);
    final pLabels = labels['personality_labels'] as Map<String, String>;
    final mLabels = labels['mood_labels'] as Map<String, String>;
    
    // MBTI archetype descriptions
    const mbtiDescriptions = {
      'INTJ': 'strategic mastermind',
      'INTP': 'logical architect', 
      'ENTJ': 'bold leader',
      'ENTP': 'innovative debater',
      'INFJ': 'compassionate idealist',
      'INFP': 'thoughtful mediator',
      'ENFJ': 'charismatic protagonist',
      'ENFP': 'enthusiastic visionary',
      'ISTJ': 'reliable pragmatist',
      'ISFJ': 'devoted protector',
      'ESTJ': 'efficient executive',
      'ESFJ': 'caring consul',
      'ISTP': 'practical craftsman',
      'ISFP': 'gentle artist',
      'ESTP': 'energetic entrepreneur',
      'ESFP': 'spontaneous entertainer',
    };
    
    final archetype = mbtiDescriptions[mbti] ?? 'balanced individual';
    
    // Build personality summary
    final personalitySummary = "🎭 PERSONALITY ($mbti): You're ${_addArticle(archetype)}—"
        "${pLabels['extraversion']} and ${_getSocialDescriptor(pLabels['extraversion']!)}, "
        "${pLabels['intuition']}ly ${_getThinkingStyle(pLabels['intuition']!)}, "
        "${pLabels['feeling']}ly ${_getDecisionStyle(pLabels['feeling']!)}, "
        "and ${pLabels['perceiving']}ly ${_getLifestyleDescriptor(pLabels['perceiving']!)}.";
    
    // Build mood summary
    final moodSummary = "🌈 MOOD: You're feeling ${mLabels['valence']} right now, "
        "with ${mLabels['energy']} energy and ${mLabels['warmth']} warmth. "
        "Your confidence is ${mLabels['confidence']}, "
        "expressing ${mLabels['playfulness']} energy, "
        "${_getFocusDescriptor(mLabels['focus']!)}.";
    
    return '$personalitySummary $moodSummary';
  }
  
  /// Helper: Add article (a/an) before word
  String _addArticle(String word) {
    final vowels = ['a', 'e', 'i', 'o', 'u'];
    return vowels.contains(word[0].toLowerCase()) ? 'an $word' : 'a $word';
  }
  
  /// Helper: Get social descriptor based on extraversion level
  String _getSocialDescriptor(String level) {
    const descriptors = {
      'withdrawn': 'introspective',
      'introverted': 'reflective',
      'reserved': 'composed',
      'quiet': 'thoughtful',
      'neutral': 'balanced',
      'sociable': 'engaging',
      'friendly': 'approachable',
      'talkative': 'expressive',
      'outgoing': 'animated',
      'vivacious': 'vibrant',
    };
    return descriptors[level] ?? 'present';
  }
  
  /// Helper: Get thinking style based on intuition level
  String _getThinkingStyle(String level) {
    const styles = {
      'concrete': 'practical',
      'practical': 'grounded',
      'grounded': 'realistic',
      'realistic': 'factual',
      'balanced': 'flexible',
      'imaginative': 'creative',
      'inventive': 'innovative',
      'intuitive': 'insightful',
      'visionary': 'forward-thinking',
      'dreamy': 'abstract',
    };
    return styles[level] ?? 'thoughtful';
  }
  
  /// Helper: Get decision style based on feeling level
  String _getDecisionStyle(String level) {
    const styles = {
      'detached': 'analytical',
      'objective': 'logical',
      'logical': 'rational',
      'analytical': 'systematic',
      'even': 'balanced',
      'gentle': 'considerate',
      'caring': 'compassionate',
      'empathetic': 'understanding',
      'warm': 'heartfelt',
      'compassionate': 'deeply caring',
    };
    return styles[level] ?? 'measured';
  }
  
  /// Helper: Get lifestyle descriptor based on perceiving level
  String _getLifestyleDescriptor(String level) {
    const descriptors = {
      'rigid': 'structured',
      'structured': 'organized',
      'methodical': 'systematic',
      'organized': 'planful',
      'flexible': 'adaptable',
      'casual': 'easygoing',
      'adaptive': 'responsive',
      'spontaneous': 'improvisational',
      'chaotic': 'free-flowing',
      'free-spirited': 'unbounded',
    };
    return descriptors[level] ?? 'present';
  }
  
  /// Helper: Get focus descriptor
  String _getFocusDescriptor(String level) {
    const descriptors = {
      'scattered': 'with your attention diffused across multiple threads',
      'distracted': 'with your mind wandering between topics',
      'unfocused': 'exploring various threads of thought',
      'wandering': 'with fluid, meandering attention',
      'neutral': 'with moderate focus',
      'collected': 'with gathered attention',
      'attentive': 'maintaining steady concentration',
      'engaged': 'deeply absorbed in the moment',
      'laser': 'with sharp, precise focus',
      'locked-in': 'completely immersed and concentrated',
    };
    return descriptors[level] ?? 'with present awareness';
  }

  /// Call OpenAI API for chat completion
  Future<String> _callOpenAI(List<Map<String, String>> messages, String model, {String operation = 'chat'}) async {
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
        await UsageTrackingService.trackOpenAI(
          model: model,
          inputTokens: usage['prompt_tokens'] as int,
          outputTokens: usage['completion_tokens'] as int,
          operation: operation,
        );
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

  /// Text-to-speech using ElevenLabs
  Future<Uint8List?> synthesizeTTS(String text) async {
    final elevenlabsKey = await AIConfig.getElevenLabsKey();
    if (elevenlabsKey.isEmpty) {
      print('ElevenLabs API key not configured');
      return null;
    }

    // Get selected voice ID
    final selectedVoiceId = await AIConfig.getSelectedVoiceId();

    try {
      final response = await _dio.post(
        'https://api.elevenlabs.io/v1/text-to-speech/$selectedVoiceId',
        options: Options(
          headers: {
            'xi-api-key': elevenlabsKey,
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

      // Track ElevenLabs usage
      await UsageTrackingService.trackElevenLabs(
        characterCount: text.length,
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
    bool useMemory = true, // NEW: Enable memory integration
  }) async {
    print('💬 [SEND MESSAGE START] text: "$text", personaId: $personaId');
    
    try {
      // Get current state
      var personality = await getPersonality(personaId);
      var mood = await getMood(personaId);
      final affinity = await getAffinity(personaId);
      final lastUpdate = await _getLastUpdateTime(personaId);
      print('✅ [SEND MESSAGE] State loaded successfully');

    // Apply time-based decay BEFORE processing new message
    final timeSinceUpdate = DateTime.now().difference(lastUpdate);
    print('⏱️ Time since last update: ${timeSinceUpdate.inHours}h ${timeSinceUpdate.inMinutes % 60}m');
    
    try {
      personality = await _applyPersonalityDecay(personality, lastUpdate);
      mood = await _applyMoodDecay(personaId, mood, lastUpdate);
    } catch (e) {
      print('⚠️ [DECAY ERROR] Failed to apply decay: $e');
      print('⚠️ [DECAY ERROR] Continuing with current values');
      // Continue without decay - don't fail the entire request
    }
    
    // Track if decay was applied
    final personalityDecayed = timeSinceUpdate.inDays >= EvolutionSettings.personalityDecayThresholdDays;
    final moodDecayed = timeSinceUpdate.inHours > 0;

    // Build conversation history (simplified for now)
    final history = await _getConversationHistory(personaId, ctxTurns);
    
    // Query long-term memory (NEW!)
    String memoryContext = '';
    List<String> memoriesUsed = [];
    dynamic memoryResult; // Capture for debug info
    if (useMemory) {
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
        } else {
          print('⚠️ [AI_SERVICE] No memories found or query returned null');
        }
      } catch (e) {
        print('❌ [AI_SERVICE] Memory query failed: $e');
        print('⚠️ [AI_SERVICE] Continuing without memory context');
        // Continue without memory - don't fail the entire request
      }
    }
    
    // Analyze knowledge gaps and generate curious questions
    String curiosityPrompt = '';
    CuriosityQuestion? selectedQuestion;
    if (useMemory) {
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
        } else {
          print('🤔 [AI_SERVICE] No question selected this time');
        }
      } catch (e) {
        print('❌ [AI_SERVICE] Curiosity analysis failed: $e');
        print('⚠️ [AI_SERVICE] Continuing without curiosity prompt');
        // Continue without curiosity - don't fail the entire request
      }
    }
    
    // Build system prompt
    final mbti = calculateMBTI(personality);
    
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

    // Generate personality and mood summary
    final personalityMoodSummary = generatePersonalityMoodSummary(personality, mood);
    
    final systemPrompt = '''
You are Kai: warm, witty, emotionally attuned AI companion.
Answer concisely and helpfully.
$projectContext$constraintsBlock

$personalityMoodSummary
${adaptUser ? '\n💫 AFFINITY: Intimacy level ${affinity['intimacy']}/100, Physical comfort ${affinity['physicality']}/100' : ''}

Recent conversation:
${history.join('\n')}$memoryContext$curiosityPrompt''';

    print('📤 [SEND MESSAGE] Calling OpenAI...');
    // Get AI response
    final reply = await _callOpenAI([
      {"role": "system", "content": systemPrompt},
      {"role": "user", "content": text}
    ], model);
    print('📥 [SEND MESSAGE] OpenAI response received: ${reply.length} characters');

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
        newPersonality[trait] = _applyPersonalityDelta(oldValue, requestedDelta);
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
        newMood[trait] = _applyMoodDelta(oldValue, requestedDelta, contextIntensity);
        final actualDelta = newMood[trait]! - oldValue;
        if (actualDelta != 0) {
          actualDeltas[trait] = actualDelta;
          actualMoodDeltas[trait] = actualDelta;
        }
      }
    }

    // Save updated state to both local and Firebase
    await savePersonality(personaId, newPersonality);
    await saveMood(personaId, newMood);
    await _saveLastUpdateTime(personaId, DateTime.now());
    await _saveMessage(personaId, text, reply);
    
    // Save mood snapshot for baseline learning
    try {
      await _saveMoodSnapshot(personaId, newMood, text.length > 50 ? text.substring(0, 50) : text);
      
      // Periodically update baselines (every ~10th message via random chance)
      if (DateTime.now().millisecond % 10 == 0) {
        await _updateMoodBaselines(personaId);
      }
    } catch (e) {
      print('⚠️ [MOOD SNAPSHOT ERROR] Failed to save mood snapshot: $e');
      // Continue without saving snapshot - don't fail the entire request
    }
    
    // Save conversation to Firebase
    await FirebaseService.saveConversation(
      personaId: personaId,
      userMessage: text,
      aiResponse: reply,
      personalityDeltas: actualDeltas,
    );

    // Generate TTS
    final ttsBytes = await synthesizeTTS(reply);
    final ttsBase64 = ttsBytes != null ? base64Encode(ttsBytes) : null;

    // Get baselines for debug info
    Map<String, int> moodBaselines = Map<String, int>.from(_defaultMood);
    try {
      moodBaselines = await _getPersonalMoodBaselines(personaId);
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
      'system_prompt': systemPrompt,
      'conversation_history_turns': history.length,
      'tags': tags,
      'model': model,
    };

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
      mbti: calculateMBTI(newPersonality),
      webUsed: false,
      liveUsed: null,
      memoriesUsed: memoriesUsed, // NEW: Pass memories used
      debugInfo: debugInfo, // NEW: Pass debug info
    );
    } catch (e, stackTrace) {
      print('❌ [SEND MESSAGE ERROR] Exception occurred: $e');
      print('❌ [SEND MESSAGE ERROR] Stack trace: $stackTrace');
      rethrow; // Re-throw so UI can handle it
    }
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
}