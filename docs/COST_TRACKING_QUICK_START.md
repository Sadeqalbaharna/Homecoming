# 💰 Token & Cost Tracking - Quick Start Guide

**Commit**: 601a06d  
**Status**: ✅ READY TO USE

---

## 🎯 What Was Built

A complete cost tracking system that automatically monitors:
- ✅ Every OpenAI API call (chat, embeddings, tags)
- ✅ Every ElevenLabs TTS synthesis
- ✅ Token counts (input & output)
- ✅ Real-time cost calculations
- ✅ Session and lifetime statistics

---

## 🚀 How to Use

### 1. View Usage Statistics
Navigate to the new Usage Stats screen:
```dart
Navigator.pushNamed(context, '/usage-stats');
```

Or add to your app's routes:
```dart
'/usage-stats': (context) => const UsageStatsScreen(),
```

### 2. Add Cost Indicator to Chat Screen
In your AppBar:
```dart
AppBar(
  title: const Text('Chat with Kai'),
  actions: [
    const CostIndicatorWidget(), // Shows: $0.003 | 5 calls
  ],
)
```

### 3. Check Costs Programmatically
```dart
// Get session cost
final session = await UsageTrackingService.getSessionStats();
print('Session cost: ${session['cost']}');

// Get total cost
final stats = await UsageTrackingService.getUsageStats();
print('Total cost: ${stats['total_cost']}');
```

---

## 📊 What Gets Tracked

### Automatic Tracking (No Code Needed!)
Every time you call:
- `AIService.sendMessage()` → Tracks chat tokens & cost
- `AIService._getTagsAndDeltas()` → Tracks personality analysis
- `AIService.synthesizeTTS()` → Tracks TTS characters & cost

All tracking happens automatically in the background!

### Data Stored
```json
{
  "total_cost": 0.0234,
  "total_tokens": 15234,
  "openai_cost": 0.0214,
  "elevenlabs_cost": 0.0020,
  "models": {
    "gpt-4o-mini": {
      "input_tokens": 8500,
      "output_tokens": 4200,
      "total_cost": 0.0180,
      "call_count": 42
    }
  },
  "operations": {
    "chat": {"count": 35, "tokens": 10200, "cost": 0.0150},
    "tags": {"count": 35, "tokens": 4534, "cost": 0.0064}
  },
  "current_session": {
    "cost": 0.0045,
    "tokens": 2450,
    "api_calls": 8
  }
}
```

---

## 💵 Current Pricing (Built-In)

### OpenAI
- **gpt-4o**: $2.50 / 1M input, $10.00 / 1M output
- **gpt-4o-mini**: $0.15 / 1M input, $0.60 / 1M output
- **text-embedding-3-small**: $0.02 / 1M tokens

### ElevenLabs
- **TTS**: $0.30 / 1000 characters

---

## 📈 Typical Costs

### Per Message (gpt-4o-mini)
- Chat: ~$0.0001
- Personality analysis: ~$0.00004
- TTS synthesis: ~$0.045
- **Total per interaction: ~$0.045**

### Daily/Monthly (at 10 conversations/day)
- Daily: $0.45
- Monthly: $13.50

### At 100 conversations/day
- Daily: $4.50
- Monthly: $135.00

---

## 🎨 UI Features

### Usage Stats Screen Shows:
1. **Current Session**
   - Cost so far
   - API calls
   - Tokens used
   - TTS characters

2. **Total Cost** (lifetime)
   - Big, prominent display
   - Total tokens

3. **Cost Breakdown**
   - OpenAI vs ElevenLabs
   - Percentage breakdown with bars

4. **Model Usage**
   - Per-model statistics
   - Input/output tokens
   - Cost and call count

5. **Operation Usage**
   - Chat, tags, embeddings
   - Tokens and cost per operation

6. **Insights**
   - Average cost per conversation
   - Estimated monthly cost
   - Most expensive model

### Cost Indicator Widget
- Compact display: `$0.003 | 5 calls`
- Tap to see quick summary
- Perfect for AppBar

---

## 🔧 Reset Options

### Reset Session Only
```dart
await UsageTrackingService.resetSession();
```
Keeps lifetime data, resets session counters.

### Reset All Stats
```dart
await UsageTrackingService.resetAllStats();
```
Deletes everything (with confirmation dialog).

---

## 🧪 Test It Out

### 1. Send a few messages
Just chat with Kai normally!

### 2. Check the stats
```dart
Navigator.pushNamed(context, '/usage-stats');
```

### 3. See real-time costs
Watch the cost indicator update as you chat!

---

## 📝 Files Created

1. **`lib/services/usage_tracking_service.dart`**
   - Core tracking service
   - Pricing data
   - Statistics calculations

2. **`lib/screens/usage_stats_screen.dart`**
   - Full analytics UI
   - Detailed breakdowns
   - Insights and projections

3. **`lib/widgets/cost_indicator_widget.dart`**
   - Compact cost display
   - Quick summary dialog
   - Floating button variant

4. **`lib/services/ai_service.dart`** (modified)
   - Added automatic tracking
   - Integrated with all API calls

5. **`COST_TRACKING_IMPLEMENTATION.md`**
   - Complete documentation
   - Implementation details
   - Configuration guide

---

## ✅ Next Steps

### Integration
1. Add route to main app:
   ```dart
   '/usage-stats': (context) => const UsageStatsScreen(),
   ```

2. Add to settings screen:
   ```dart
   ListTile(
     leading: const Icon(Icons.attach_money),
     title: const Text('Usage & Costs'),
     onTap: () => Navigator.pushNamed(context, '/usage-stats'),
   )
   ```

3. Add cost indicator to chat:
   ```dart
   actions: [const CostIndicatorWidget()],
   ```

### Optional: Firebase Sync
For tracking across devices, extend with Firebase:
```dart
// Save to Firebase on session end
await FirebaseDatabase.instance
    .ref('usage/${userId}')
    .set(usageData);
```

---

## 🎉 You're Done!

The cost tracking system is **fully implemented and working**! It will:
- ✅ Automatically track every API call
- ✅ Calculate costs in real-time
- ✅ Show detailed analytics
- ✅ Help you budget and optimize

**Just chat normally and check `/usage-stats` to see your costs! 💰✨**
