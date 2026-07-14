# Personality & Mood Dynamics System
## Psychologically Realistic Evolution Model

**Version**: 0.7.5 (Proposed)  
**Date**: October 23, 2025

---

## 🎯 Core Psychological Principles

### **1. Personality: Inelastic & Stable**
- **Change resistance**: High momentum, low volatility
- **Decay**: Minimal to none (personality is relatively fixed)
- **Timeframe**: Weeks to months for meaningful shifts
- **Metaphor**: Like steering an oil tanker - slow to turn, slow to stop

### **2. Mood: Elastic & Dynamic**
- **Change response**: Immediate reaction to context
- **Decay**: Natural regression to personal baseline
- **Timeframe**: Minutes to hours for shifts, hours to days for decay
- **Metaphor**: Like a rubber band - stretches quickly, snaps back gradually

---

## 📐 Mathematical Models

### **Personality Evolution (Inelastic)**

```dart
// 1. Apply delta with RESISTANCE based on distance from current value
double applyPersonalityDelta(int current, int requestedDelta) {
  // Resistance increases as you try to change further from baseline
  final resistance = 0.15; // Only 15% of delta applied per conversation
  final dampedDelta = requestedDelta * resistance;
  
  // Additional resistance near extremes (0 or 1000)
  final extremeResistance = _calculateExtremeResistance(current);
  
  return dampedDelta * (1.0 - extremeResistance);
}

// Harder to push personality to extremes
double _calculateExtremeResistance(int value) {
  if (value < 100) return 0.8; // 80% resistance near 0
  if (value > 900) return 0.8; // 80% resistance near 1000
  if (value < 200 || value > 800) return 0.5; // 50% resistance at edges
  return 0.0; // No resistance in middle range (200-800)
}

// 2. Minimal decay (personality is stable)
int applyPersonalityDecay(int current, Duration timeSinceUpdate) {
  // Only decay if VERY long absence (30+ days)
  final daysSinceUpdate = timeSinceUpdate.inDays;
  
  if (daysSinceUpdate < 30) return current; // No decay
  
  // After 30 days, very slow drift toward species baseline (500)
  final baseline = 500;
  final decayRate = 0.5; // 0.5 points per day toward baseline
  final totalDecay = ((daysSinceUpdate - 30) * decayRate).round();
  
  if (current > baseline) {
    return max(baseline, current - totalDecay);
  } else if (current < baseline) {
    return min(baseline, current + totalDecay);
  }
  return current;
}
```

**Example Personality Change**:
```
User says: "You're so logical and analytical!"
GPT returns: intuition_delta = -10 (toward Sensing)

Current intuition: 700 (Intuitive)
Resistance: 0.15 (only 15% applied)
Actual change: -10 * 0.15 = -1.5 ≈ -2
New intuition: 698

// It takes ~100 reinforcing conversations to shift MBTI type!
```

---

### **Mood Evolution (Elastic)**

```dart
// 1. Apply delta with SEVERITY SCALING (context intensity)
int applyMoodDelta(int current, int requestedDelta, String contextIntensity) {
  // Mood responds fully to emotional events
  final intensityMultipliers = {
    'normal': 1.0,   // Standard response
    'high': 2.0,     // Double impact (exciting news, frustration)
    'radical': 4.0,  // Extreme events (tragedy, euphoria)
  };
  
  final multiplier = intensityMultipliers[contextIntensity] ?? 1.0;
  final scaledDelta = (requestedDelta * multiplier).round();
  
  // Mood can swing dramatically
  return _clamp(current + scaledDelta, 0, 100);
}

// 2. ACTIVE decay toward PERSONAL baseline (not 50!)
int applyMoodDecay(int current, int personalBaseline, Duration timeSinceUpdate) {
  final hoursSinceUpdate = timeSinceUpdate.inHours;
  
  // Different traits decay at different rates
  final decayRates = {
    'valence': 2.0,      // Happiness/sadness - medium decay (2 pts/hour)
    'energy': 3.0,       // Energy level - fast decay (3 pts/hour)
    'warmth': 1.5,       // Warmth/coldness - slow decay (1.5 pts/hour)
    'confidence': 1.0,   // Confidence - very slow decay (1 pt/hour)
    'playfulness': 2.5,  // Playfulness - fast decay (2.5 pts/hour)
    'focus': 3.5,        // Focus/scattered - very fast decay (3.5 pts/hour)
  };
  
  // Calculate decay toward personal baseline
  final decayAmount = (hoursSinceUpdate * decayRate).round();
  
  if (current > personalBaseline) {
    return max(personalBaseline, current - decayAmount);
  } else if (current < personalBaseline) {
    return min(personalBaseline, current + decayAmount);
  }
  return current;
}

// 3. Personal baselines learned from interaction history
Map<String, int> calculatePersonalBaselines(List<MoodSnapshot> history) {
  // After 50+ interactions, calculate user's typical mood
  if (history.length < 50) {
    // Default neutral until we learn the user
    return {
      'valence': 60,      // Slightly positive default
      'energy': 65,
      'warmth': 70,
      'confidence': 60,
      'playfulness': 80,
      'focus': 50,
    };
  }
  
  // Calculate 30-day rolling average for each trait
  final recent = history.where((s) => 
    DateTime.now().difference(s.timestamp).inDays < 30
  ).toList();
  
  return {
    'valence': _average(recent.map((s) => s.valence)),
    'energy': _average(recent.map((s) => s.energy)),
    'warmth': _average(recent.map((s) => s.warmth)),
    'confidence': _average(recent.map((s) => s.confidence)),
    'playfulness': _average(recent.map((s) => s.playfulness)),
    'focus': _average(recent.map((s) => s.focus)),
  };
}
```

**Example Mood Change**:
```
Scenario 1: Normal conversation
User: "How are you?"
GPT returns: valence_delta = +2, context_intensity = "normal"
Current valence: 55
New valence: 55 + (2 * 1.0) = 57

Scenario 2: Exciting news
User: "I just got the job!!!"
GPT returns: valence_delta = +5, context_intensity = "radical"
Current valence: 55
New valence: 55 + (5 * 4.0) = 75 (capped at 100)

Scenario 3: Decay after 3 hours of silence
Current valence: 75
Personal baseline: 60
Decay rate: 2.0 pts/hour
Hours: 3
Decay: 3 * 2.0 = 6 points
New valence: max(60, 75 - 6) = 69
```

---

## 🏗️ Implementation Architecture

### **Data Structures**

```dart
// 1. Add mood history tracking
class MoodSnapshot {
  final DateTime timestamp;
  final Map<String, int> mood;
  final String? trigger; // What caused this mood state
  
  MoodSnapshot({
    required this.timestamp,
    required this.mood,
    this.trigger,
  });
}

// 2. Track personal baselines
class PersonalityProfile {
  final String personaId;
  final Map<String, int> personality;
  final Map<String, int> currentMood;
  final Map<String, int> baselineMood; // Learned from history
  final DateTime lastUpdate;
  final List<MoodSnapshot> moodHistory; // Last 100 snapshots
  
  PersonalityProfile({
    required this.personaId,
    required this.personality,
    required this.currentMood,
    required this.baselineMood,
    required this.lastUpdate,
    required this.moodHistory,
  });
}

// 3. Evolution settings
class EvolutionSettings {
  // Personality
  static const double personalityResistance = 0.15; // 15% delta applied
  static const int personalityDecayThresholdDays = 30;
  static const double personalityDecayRate = 0.5; // pts/day after threshold
  
  // Mood
  static const Map<String, double> moodDecayRates = {
    'valence': 2.0,
    'energy': 3.0,
    'warmth': 1.5,
    'confidence': 1.0,
    'playfulness': 2.5,
    'focus': 3.5,
  };
  
  static const Map<String, double> contextMultipliers = {
    'normal': 1.0,
    'high': 2.0,
    'radical': 4.0,
  };
  
  // Baseline learning
  static const int minInteractionsForBaseline = 50;
  static const int baselineWindowDays = 30;
  static const int maxMoodHistorySize = 100;
}
```

### **Service Methods**

```dart
// In ai_service.dart

/// Apply personality delta with resistance
int _applyPersonalityDelta(int current, int requestedDelta) {
  final resistance = EvolutionSettings.personalityResistance;
  final dampedDelta = (requestedDelta * resistance).round();
  
  // Add extreme resistance
  final extremeResistance = _calculateExtremeResistance(current);
  final finalDelta = (dampedDelta * (1.0 - extremeResistance)).round();
  
  return _clamp(current + finalDelta, 0, 1000);
}

/// Apply mood delta with context scaling
int _applyMoodDelta(int current, int requestedDelta, String contextIntensity) {
  final multiplier = EvolutionSettings.contextMultipliers[contextIntensity] ?? 1.0;
  final scaledDelta = (requestedDelta * multiplier).round();
  
  return _clamp(current + scaledDelta, 0, 100);
}

/// Apply time-based mood decay toward personal baseline
Future<Map<String, int>> _applyMoodDecay(
  String personaId,
  Map<String, int> currentMood,
  DateTime lastUpdate,
) async {
  final timeSinceUpdate = DateTime.now().difference(lastUpdate);
  final hoursSinceUpdate = timeSinceUpdate.inHours;
  
  if (hoursSinceUpdate == 0) return currentMood; // No decay
  
  // Get personal baselines
  final baselines = await _getPersonalMoodBaselines(personaId);
  final decayedMood = Map<String, int>.from(currentMood);
  
  for (final trait in PersonalityTraits.mood) {
    final current = currentMood[trait]!;
    final baseline = baselines[trait]!;
    final decayRate = EvolutionSettings.moodDecayRates[trait]!;
    final decayAmount = (hoursSinceUpdate * decayRate).round();
    
    if (current > baseline) {
      decayedMood[trait] = max(baseline, current - decayAmount);
    } else if (current < baseline) {
      decayedMood[trait] = min(baseline, current + decayAmount);
    }
  }
  
  return decayedMood;
}

/// Apply minimal personality decay (only after long absence)
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
  final baseline = 500; // Species baseline (balanced)
  final daysOverThreshold = daysSinceUpdate - EvolutionSettings.personalityDecayThresholdDays;
  final totalDecay = (daysOverThreshold * EvolutionSettings.personalityDecayRate).round();
  
  for (final trait in PersonalityTraits.personality) {
    final current = currentPersonality[trait]!;
    
    if (current > baseline) {
      decayedPersonality[trait] = max(baseline, current - totalDecay);
    } else if (current < baseline) {
      decayedPersonality[trait] = min(baseline, current + totalDecay);
    }
  }
  
  return decayedPersonality;
}

/// Get personal mood baselines (learned from history)
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
  
  // Default baselines until we learn from history
  return {
    'valence': 60,
    'energy': 65,
    'warmth': 70,
    'confidence': 60,
    'playfulness': 80,
    'focus': 50,
  };
}

/// Update mood baselines from history (run periodically)
Future<void> _updateMoodBaselines(String personaId) async {
  final history = await _getMoodHistory(personaId);
  
  if (history.length < EvolutionSettings.minInteractionsForBaseline) {
    return; // Not enough data yet
  }
  
  // Calculate 30-day rolling average
  final recent = history.where((s) => 
    DateTime.now().difference(s.timestamp).inDays < EvolutionSettings.baselineWindowDays
  ).toList();
  
  if (recent.isEmpty) return;
  
  final prefs = await _prefsInstance;
  
  for (final trait in PersonalityTraits.mood) {
    final values = recent.map((s) => s.mood[trait]!).toList();
    final average = values.reduce((a, b) => a + b) ~/ values.length;
    
    await prefs.setInt('${personaId}_baseline_$trait', average);
  }
}

/// Save mood snapshot to history
Future<void> _saveMoodSnapshot(
  String personaId,
  Map<String, int> mood,
  String? trigger,
) async {
  final prefs = await _prefsInstance;
  
  // Get existing history
  final historyJson = prefs.getString('${personaId}_mood_history') ?? '[]';
  final history = (jsonDecode(historyJson) as List).map((item) => 
    MoodSnapshot(
      timestamp: DateTime.fromMillisecondsSinceEpoch(item['timestamp']),
      mood: Map<String, int>.from(item['mood']),
      trigger: item['trigger'],
    )
  ).toList();
  
  // Add new snapshot
  history.add(MoodSnapshot(
    timestamp: DateTime.now(),
    mood: mood,
    trigger: trigger,
  ));
  
  // Keep only last 100
  if (history.length > EvolutionSettings.maxMoodHistorySize) {
    history.removeRange(0, history.length - EvolutionSettings.maxMoodHistorySize);
  }
  
  // Save back
  final newHistoryJson = jsonEncode(history.map((s) => {
    'timestamp': s.timestamp.millisecondsSinceEpoch,
    'mood': s.mood,
    'trigger': s.trigger,
  }).toList());
  
  await prefs.setString('${personaId}_mood_history', newHistoryJson);
}
```

---

## 🔄 Integration into `sendMessage()`

```dart
Future<ChatResponse> sendMessage({
  required String text,
  required String personaId,
  // ... other params
}) async {
  // 1. Load current state
  var personality = await getPersonality(personaId);
  var mood = await getMood(personaId);
  final lastUpdate = await _getLastUpdateTime(personaId);
  
  // 2. Apply time-based decay BEFORE processing new message
  personality = await _applyPersonalityDecay(personality, lastUpdate);
  mood = await _applyMoodDecay(personaId, mood, lastUpdate);
  
  // 3. Get AI response and deltas
  final tagsResult = await _getTagsAndDeltas(reply);
  final personalityDelta = Map<String, int>.from(tagsResult['persona_delta'] ?? {});
  final moodDelta = Map<String, int>.from(tagsResult['mood_delta'] ?? {});
  final contextIntensity = tagsResult['context_intensity'] ?? 'normal';
  
  // 4. Apply deltas with RESISTANCE (personality) and SCALING (mood)
  final newPersonality = Map<String, int>.from(personality);
  final newMood = Map<String, int>.from(mood);
  final actualDeltas = <String, int>{};
  
  for (final trait in PersonalityTraits.personality) {
    if (personalityDelta.containsKey(trait)) {
      final oldValue = newPersonality[trait]!;
      newPersonality[trait] = _applyPersonalityDelta(oldValue, personalityDelta[trait]!);
      final actualDelta = newPersonality[trait]! - oldValue;
      if (actualDelta != 0) actualDeltas[trait] = actualDelta;
    }
  }
  
  for (final trait in PersonalityTraits.mood) {
    if (moodDelta.containsKey(trait)) {
      final oldValue = newMood[trait]!;
      newMood[trait] = _applyMoodDelta(oldValue, moodDelta[trait]!, contextIntensity);
      final actualDelta = newMood[trait]! - oldValue;
      if (actualDelta != 0) actualDeltas[trait] = actualDelta;
    }
  }
  
  // 5. Save new state with timestamp
  await savePersonality(personaId, newPersonality);
  await saveMood(personaId, newMood);
  await _saveLastUpdateTime(personaId, DateTime.now());
  
  // 6. Save mood snapshot to history
  await _saveMoodSnapshot(personaId, newMood, text);
  
  // 7. Periodically update baselines (every 10th message)
  if (Random().nextInt(10) == 0) {
    await _updateMoodBaselines(personaId);
  }
  
  // ... rest of sendMessage
}
```

---

## 📊 Psychological Realism Examples

### **Example 1: Personality Stability**
```
Day 1: "You're so logical!" → intuition: 700 → 698 (-2)
Day 2: "You're so logical!" → intuition: 698 → 696 (-2)
Day 3: "You're so logical!" → intuition: 696 → 694 (-2)
...
Day 50: "You're so logical!" → intuition: 602 → 600 (-2)

After 50 days of reinforcement, MBTI changes from ENFP to ESFP
(Intuition crosses threshold from 700 to 600)
```

### **Example 2: Mood Elasticity**
```
10:00 AM - User: "Good morning!" 
  → valence: 60 → 62 (+2, normal intensity)

10:05 AM - User: "I got promoted!!!"
  → valence: 62 → 82 (+5 * 4.0 radical = +20)

1:00 PM - [3 hours of silence]
  → Decay: 3 hours * 2.0 = 6 points
  → valence: 82 → max(60, 82-6) = 76

6:00 PM - [5 more hours]
  → Decay: 5 hours * 2.0 = 10 points
  → valence: 76 → max(60, 76-10) = 66

Next day 10:00 AM - [16 hours]
  → Decay: 16 hours * 2.0 = 32 points
  → valence: 66 → max(60, 66-32) = 60 (back to baseline)
```

### **Example 3: Personal Baselines**
```
User A (Optimistic): baseline valence = 75
User B (Neutral): baseline valence = 50
User C (Melancholic): baseline valence = 35

Same bad news: valence_delta = -10 (high intensity = -20)

User A: 75 → 55 → decays back to 75 over 10 hours
User B: 50 → 30 → decays back to 50 over 10 hours  
User C: 35 → 15 → decays back to 35 over 10 hours

Each person has their own "emotional home"
```

---

## 🎯 Benefits of This System

1. **Realistic personality stability**: Can't change MBTI with one conversation
2. **Responsive mood system**: Reacts appropriately to emotional context
3. **Natural decay**: Mood returns to learned baseline, not arbitrary neutral
4. **Personalized baselines**: System learns YOUR normal mood over time
5. **Context-aware impact**: Radical events have radical effects
6. **Psychologically grounded**: Matches research on trait vs state psychology

---

## 🚀 Implementation Phases

### **Phase 1: Core Decay (Week 2)**
- [ ] Add `lastUpdateTime` tracking
- [ ] Implement `_applyMoodDecay()` with fixed baselines
- [ ] Integrate decay into `sendMessage()` (before processing)
- [ ] Add context intensity scaling to mood deltas

### **Phase 2: Personality Resistance (Week 2-3)**
- [ ] Implement `_applyPersonalityDelta()` with 15% resistance
- [ ] Add extreme resistance near 0/1000
- [ ] Update debug info to show requested vs actual deltas

### **Phase 3: Baseline Learning (Week 3-4)**
- [ ] Add `MoodSnapshot` data structure
- [ ] Implement `_saveMoodSnapshot()` on each interaction
- [ ] Create `_updateMoodBaselines()` from history
- [ ] Replace fixed baselines with learned baselines

### **Phase 4: Advanced Dynamics (Week 4+)**
- [ ] Add trait-specific decay rates
- [ ] Implement personality decay for 30+ day absence
- [ ] Create mood history visualization
- [ ] Add "emotional volatility" metric (how much mood swings)

---

## 📝 Debug Info Additions

Add to debug info:
```dart
'evolution': {
  'personality': {
    'requested_deltas': personalityDelta,
    'actual_deltas': actualPersonalityDeltas,
    'resistance_applied': '85%', // Shows 15% got through
    'decay_applied': false, // Or days since update
  },
  'mood': {
    'requested_deltas': moodDelta,
    'actual_deltas': actualMoodDeltas,
    'context_intensity': contextIntensity,
    'intensity_multiplier': '4.0x',
    'time_since_update': '3.2 hours',
    'decay_applied': true,
    'baseline': baselineMood,
  },
},
```

---

## 🧪 Testing Scenarios

1. **Rapid mood swing**: "I'm so happy!" → "Nevermind, terrible news" (within 1 min)
   - Should see valence spike then crash

2. **Personality resistance**: Spam "you're so extraverted!" 10 times
   - Should see diminishing returns, not linear growth

3. **Baseline learning**: Track valence over 60 days
   - Should stabilize around user's typical mood

4. **Decay verification**: Set mood to 100, wait 24 hours
   - Should decay back to baseline

5. **Context scaling**: Same phrase with normal vs radical intensity
   - Should see 4x difference in delta magnitude

---

**End of Document**
