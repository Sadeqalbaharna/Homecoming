// Personality, mood and affinity state management
// Extracted from ai_service.dart — no circular imports.
//
// State (mood/personality/affinity/timestamp): Firebase only via KaiStateService.
// Offline handled automatically by Firebase's built-in persistence.
// SharedPreferences: mood history + baselines only (device-local, not cross-surface).

import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/kai_state_service.dart';

// ─── Data classes ───────────────────────────────────────────────────────────

/// Personality and mood trait name lists
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
  static const double personalityResistance = 0.15;
  static const int personalityDecayThresholdDays = 30;
  static const double personalityDecayRate = 0.5;

  // Mood evolution (elastic - fast to change, fast to decay)
  // Units: points per HOUR. Applied at per-minute granularity so sub-hour
  // conversations get meaningful decay. Rates tuned so a spike to ~85 returns
  // to baseline (~50) within 2–4 hours of inactivity.
  static const Map<String, double> moodDecayRates = {
    'valence':      10.0,  // neutral emotional tone — decays in ~2.5h
    'energy':       15.0,  // most transient — decays in ~1.7h
    'warmth':        6.0,  // relationship-grounded, lingers longest (~4h)
    'confidence':    5.0,  // earned slowly, lost slowly (~5h)
    'playfulness':  14.0,  // highly ephemeral — decays in ~1.8h
    'focus':        12.0,  // situational — decays in ~2h
  };

  // Context intensity multipliers for mood changes
  static const Map<String, double> contextMultipliers = {
    'normal': 1.0,
    'high': 2.0,
    'radical': 4.0,
  };

  // Baseline learning
  static const int minInteractionsForBaseline = 15; // was 50 — learn sooner
  static const int baselineWindowDays = 30;
  static const int maxMoodHistorySize = 100;
}

// ─── Service ────────────────────────────────────────────────────────────────

/// Manages Kai's personality, mood and affinity state.
class PersonalityService {
  SharedPreferences? _prefs;
  Completer<void>? _prefsCompleter;

  // Default starting values
  static const Map<String, int> _defaultPersonality = {
    "extraversion": 300,
    "intuition": 700,
    "feeling": 800,
    "perceiving": 600,
  };

  // Resting / baseline mood — where Kai returns to when idle.
  // These are intentionally near-neutral. High values here mean mood never
  // feels earned; keep them modest so positive interactions genuinely show.
  static const Map<String, int> _defaultMood = {
    "valence":      50,  // was 60  — true neutral
    "energy":       45,  // was 65  — calm, not buzzing
    "warmth":       58,  // was 70  — Kai is naturally warm, but not gushing
    "confidence":   52,  // was 60  — grounded, not overconfident
    "playfulness":  42,  // was 80  — playfulness must be sparked
    "focus":        50,  // was 50  — unchanged
  };

  static const Map<String, int> _defaultAffinity = {
    "intimacy": 50,
    "physicality": 50,
  };

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

  // ─── Clamping helpers ───────────────────────────────────────────────────

  int _clamp(int value, int min, int max) => value.clamp(min, max);

  /// Returns extra resistance (0.0–0.8) when value is near boundary (0 or 1000).
  double _calculateExtremeResistance(int value) {
    if (value < 100 || value > 900) return 0.8;
    if (value < 200 || value > 800) return 0.5;
    return 0.0;
  }

  // ─── Delta application ──────────────────────────────────────────────────

  /// Apply personality delta with resistance (inelastic change).
  /// Only 15% of requested delta is applied, with extra resistance at extremes.
  int applyPersonalityDelta(int current, int requestedDelta) {
    if (requestedDelta == 0) return current;
    final dampedDelta = (requestedDelta * EvolutionSettings.personalityResistance).round();
    final extremeResistance = _calculateExtremeResistance(current);
    final finalDelta = (dampedDelta * (1.0 - extremeResistance)).round();
    return _clamp(current + finalDelta, 0, 1000);
  }

  /// Apply mood delta with context intensity scaling (elastic change).
  int applyMoodDelta(int current, int requestedDelta, String contextIntensity) {
    if (requestedDelta == 0) return current;
    final multiplier = EvolutionSettings.contextMultipliers[contextIntensity] ?? 1.0;
    final scaledDelta = (requestedDelta * multiplier).round();
    return _clamp(current + scaledDelta, 0, 100);
  }

  // ─── CRUD ───────────────────────────────────────────────────────────────

  Future<Map<String, int>> getPersonality(String personaId) async {
    final remote = await KaiStateService().getPersonality(personaId);
    return (remote != null && remote.length == PersonalityTraits.personality.length)
        ? remote
        : Map<String, int>.from(_defaultPersonality);
  }

  Future<Map<String, int>> getMood(String personaId) async {
    final remote = await KaiStateService().getMood(personaId);
    return (remote != null && remote.length == PersonalityTraits.mood.length)
        ? remote
        : Map<String, int>.from(_defaultMood);
  }

  Future<Map<String, int>> getAffinity(String personaId) async {
    final remote = await KaiStateService().getAffinity(personaId);
    return (remote != null && remote.length == _defaultAffinity.length)
        ? remote
        : Map<String, int>.from(_defaultAffinity);
  }

  Future<void> savePersonality(String personaId, Map<String, int> personality) async {
    // Delegate: KaiStateService writes to Firebase + local cache.
    await KaiStateService().savePersonality(personaId, personality);
  }

  Future<void> saveMood(String personaId, Map<String, int> mood) async {
    // Delegate: KaiStateService writes to Firebase + local cache.
    await KaiStateService().saveMood(personaId, mood);
  }

  Future<void> saveAffinity(String personaId, Map<String, int> affinity) async {
    // Delegate: KaiStateService writes to Firebase + local cache.
    // (Previously affinity was never synced to Firebase — now it is.)
    await KaiStateService().saveAffinity(personaId, affinity);
  }

  // ─── Timestamps ─────────────────────────────────────────────────────────

  Future<DateTime> getLastUpdateTime(String personaId) async {
    final remote = await KaiStateService().getLastUpdateTime(personaId);
    return remote ?? DateTime.now();
  }

  Future<void> saveLastUpdateTime(String personaId, DateTime time) async {
    await KaiStateService().saveLastUpdateTime(personaId, time);
  }

  // ─── Decay ──────────────────────────────────────────────────────────────

  /// Apply time-based mood decay toward personal baseline.
  Future<Map<String, int>> applyMoodDecay(
    String personaId,
    Map<String, int> currentMood,
    DateTime lastUpdate,
  ) async {
    // Use minutes for granularity — inHours rounds down so anything under
    // 60 min gets zero decay, which is why mood was permanently maxed out.
    final minutesSinceUpdate = DateTime.now().difference(lastUpdate).inMinutes;
    if (minutesSinceUpdate <= 0) return currentMood;

    final baselines = await getPersonalMoodBaselines(personaId);
    final decayedMood = Map<String, int>.from(currentMood);

    for (final trait in PersonalityTraits.mood) {
      final current = currentMood[trait]!;
      final baseline = baselines[trait]!;
      // Rates are stored as points-per-hour; convert to per-minute for this call
      final decayRate = EvolutionSettings.moodDecayRates[trait]!;
      final decayAmount = (minutesSinceUpdate * decayRate / 60.0).round();

      if (current > baseline) {
        decayedMood[trait] = (current - decayAmount).clamp(baseline, 100);
      } else if (current < baseline) {
        decayedMood[trait] = (current + decayAmount).clamp(0, baseline);
      }
    }

    print('🌊 [Mood] Decay applied after ${minutesSinceUpdate}m — $currentMood → $decayedMood');
    return decayedMood;
  }

  /// Apply minimal personality decay (only after 30+ days of inactivity).
  Future<Map<String, int>> applyPersonalityDecay(
    Map<String, int> currentPersonality,
    DateTime lastUpdate,
  ) async {
    final daysSinceUpdate = DateTime.now().difference(lastUpdate).inDays;
    if (daysSinceUpdate < EvolutionSettings.personalityDecayThresholdDays) {
      return currentPersonality;
    }

    final decayedPersonality = Map<String, int>.from(currentPersonality);
    const baseline = 500;
    final daysOverThreshold = daysSinceUpdate - EvolutionSettings.personalityDecayThresholdDays;
    final totalDecay = (daysOverThreshold * EvolutionSettings.personalityDecayRate).round();

    for (final trait in PersonalityTraits.personality) {
      final current = currentPersonality[trait]!;
      if (current > baseline) {
        decayedPersonality[trait] = (current - totalDecay).clamp(baseline, 1000);
      } else if (current < baseline) {
        decayedPersonality[trait] = (current + totalDecay).clamp(0, baseline);
      }
    }
    return decayedPersonality;
  }

  // ─── Mood history & baselines ───────────────────────────────────────────

  Future<List<MoodSnapshot>> _getMoodHistory(String personaId) async {
    final prefs = await _prefsInstance;
    final historyJson = prefs.getString('${personaId}_mood_history') ?? '[]';
    final historyList = jsonDecode(historyJson) as List;
    return historyList.map((item) => MoodSnapshot.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<void> saveMoodSnapshot(
    String personaId,
    Map<String, int> mood,
    String? trigger,
  ) async {
    final prefs = await _prefsInstance;
    final history = await _getMoodHistory(personaId);

    history.add(MoodSnapshot(
      timestamp: DateTime.now(),
      mood: mood,
      trigger: trigger,
    ));

    if (history.length > EvolutionSettings.maxMoodHistorySize) {
      history.removeRange(0, history.length - EvolutionSettings.maxMoodHistorySize);
    }

    final newHistoryJson = jsonEncode(history.map((s) => s.toJson()).toList());
    await prefs.setString('${personaId}_mood_history', newHistoryJson);
  }

  Future<void> updateMoodBaselines(String personaId) async {
    final history = await _getMoodHistory(personaId);
    if (history.length < EvolutionSettings.minInteractionsForBaseline) return;

    final cutoff = DateTime.now().subtract(
      const Duration(days: EvolutionSettings.baselineWindowDays),
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

  Future<Map<String, int>> getPersonalMoodBaselines(String personaId) async {
    final prefs = await _prefsInstance;
    final baselines = <String, int>{};
    bool hasBaselines = true;

    for (final trait in PersonalityTraits.mood) {
      final value = prefs.getInt('${personaId}_baseline_$trait');
      if (value == null) {
        hasBaselines = false;
        break;
      }
      baselines[trait] = value;
    }

    return hasBaselines ? baselines : Map<String, int>.from(_defaultMood);
  }

  // ─── MBTI & labels ──────────────────────────────────────────────────────

  String calculateMBTI(Map<String, int> personality) {
    return (personality["extraversion"]! >= 500 ? "E" : "I") +
           (personality["intuition"]! >= 500 ? "N" : "S") +
           (personality["feeling"]! >= 500 ? "F" : "T") +
           (personality["perceiving"]! >= 500 ? "P" : "J");
  }

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
      final index = (entry.value / 100).floor().clamp(0, 9);
      personalityLabelMap[entry.key] = personalityLabels[entry.key]![index];
    }

    for (final entry in mood.entries) {
      final index = (entry.value / 10).floor().clamp(0, 9);
      moodLabelMap[entry.key] = moodLabels[entry.key]![index];
    }

    return {
      "personality_labels": personalityLabelMap,
      "mood_labels": moodLabelMap,
    };
  }

  /// Generate compact personality + mood summary for AI prompt injection.
  String generatePersonalityMoodSummary(Map<String, int> personality, Map<String, int> mood) {
    final mbti = calculateMBTI(personality);
    final labels = getLabels(personality, mood);
    final pLabels = labels['personality_labels'] as Map<String, String>;
    final mLabels = labels['mood_labels'] as Map<String, String>;

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

    final personalitySummary = "🎭 PERSONALITY ($mbti): You're ${_addArticle(archetype)}—"
        "${pLabels['extraversion']} and ${_getSocialDescriptor(pLabels['extraversion']!)}, "
        "${pLabels['intuition']}ly ${_getThinkingStyle(pLabels['intuition']!)}, "
        "${pLabels['feeling']}ly ${_getDecisionStyle(pLabels['feeling']!)}, "
        "and ${pLabels['perceiving']}ly ${_getLifestyleDescriptor(pLabels['perceiving']!)}.";

    final moodSummary = "🌈 MOOD: You're feeling ${mLabels['valence']} right now, "
        "with ${mLabels['energy']} energy and ${mLabels['warmth']} warmth. "
        "Your confidence is ${mLabels['confidence']}, "
        "expressing ${mLabels['playfulness']} energy, "
        "${_getFocusDescriptor(mLabels['focus']!)}.";

    return '$personalitySummary $moodSummary';
  }

  // ─── Summary helpers (private) ──────────────────────────────────────────

  String _addArticle(String word) {
    const vowels = ['a', 'e', 'i', 'o', 'u'];
    return vowels.contains(word[0].toLowerCase()) ? 'an $word' : 'a $word';
  }

  String _getSocialDescriptor(String level) {
    const d = {
      'withdrawn': 'introspective', 'introverted': 'reflective', 'reserved': 'composed',
      'quiet': 'thoughtful', 'neutral': 'balanced', 'sociable': 'engaging',
      'friendly': 'approachable', 'talkative': 'expressive', 'outgoing': 'animated',
      'vivacious': 'vibrant',
    };
    return d[level] ?? 'present';
  }

  String _getThinkingStyle(String level) {
    const d = {
      'concrete': 'practical', 'practical': 'grounded', 'grounded': 'realistic',
      'realistic': 'factual', 'balanced': 'flexible', 'imaginative': 'creative',
      'inventive': 'innovative', 'intuitive': 'insightful', 'visionary': 'forward-thinking',
      'dreamy': 'abstract',
    };
    return d[level] ?? 'thoughtful';
  }

  String _getDecisionStyle(String level) {
    const d = {
      'detached': 'analytical', 'objective': 'logical', 'logical': 'rational',
      'analytical': 'systematic', 'even': 'balanced', 'gentle': 'considerate',
      'caring': 'compassionate', 'empathetic': 'understanding', 'warm': 'heartfelt',
      'compassionate': 'deeply caring',
    };
    return d[level] ?? 'measured';
  }

  String _getLifestyleDescriptor(String level) {
    const d = {
      'rigid': 'structured', 'structured': 'organized', 'methodical': 'systematic',
      'organized': 'planful', 'flexible': 'adaptable', 'casual': 'easygoing',
      'adaptive': 'responsive', 'spontaneous': 'improvisational', 'chaotic': 'free-flowing',
      'free-spirited': 'unbounded',
    };
    return d[level] ?? 'present';
  }

  String _getFocusDescriptor(String level) {
    const d = {
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
    return d[level] ?? 'with present awareness';
  }
}
