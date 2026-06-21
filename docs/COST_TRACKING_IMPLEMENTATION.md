# 💰 Token & Cost Tracking System

**Date**: October 21, 2025  
**Version**: v0.7.4+38  
**Status**: ✅ IMPLEMENTED

---

## 🎯 Overview

A comprehensive token and cost tracking system that monitors all API usage from OpenAI and ElevenLabs, providing real-time cost estimates and detailed usage analytics.

### Features
- ✅ Real-time token tracking for all OpenAI models
- ✅ Character-based cost tracking for ElevenLabs TTS
- ✅ Session-based and lifetime statistics
- ✅ Cost breakdown by model and operation
- ✅ Usage insights and monthly cost projections
- ✅ Persistent local storage
- ✅ Beautiful UI with detailed analytics

---

## 📊 What Gets Tracked

### OpenAI API Usage
1. **Chat Completions** (`gpt-4o`, `gpt-4o-mini`, `gpt-3.5-turbo`)
   - Input tokens (prompt tokens)
   - Output tokens (completion tokens)
   - Cost per call
   - Operation type (chat, tags, embedding)

2. **Embeddings** (`text-embedding-3-small`, `text-embedding-3-large`)
   - Input tokens
   - Cost per embedding

### ElevenLabs API Usage
1. **Text-to-Speech**
   - Character count
   - Cost per synthesis
   - Total TTS usage

### Aggregated Metrics
- Total tokens used
- Total cost (lifetime)
- Cost breakdown by service (OpenAI vs ElevenLabs)
- Cost breakdown by model
- Cost breakdown by operation type
- Average cost per conversation
- API call count
- Session statistics

---

## 🏗️ Architecture

### 1. Usage Tracking Service
**File**: `lib/services/usage_tracking_service.dart`

**Core Functions**:
```dart
// Track OpenAI usage
await UsageTrackingService.trackOpenAI(
  model: 'gpt-4o-mini',
  inputTokens: 150,
  outputTokens: 80,
  operation: 'chat',
);

// Track ElevenLabs usage
await UsageTrackingService.trackElevenLabs(
  characterCount: 250,
);

// Get current stats
final stats = await UsageTrackingService.getUsageStats();
final session = await UsageTrackingService.getSessionStats();
```

**Pricing Data** (as of October 2025):
```dart
OpenAI Pricing:
- gpt-4o: $2.50/1M input, $10.00/1M output
- gpt-4o-mini: $0.15/1M input, $0.60/1M output
- gpt-4-turbo: $10.00/1M input, $30.00/1M output
- gpt-3.5-turbo: $0.50/1M input, $1.50/1M output
- text-embedding-3-small: $0.02/1M tokens
- text-embedding-3-large: $0.13/1M tokens

ElevenLabs Pricing:
- TTS: $0.30/1000 characters
```

### 2. AI Service Integration
**File**: `lib/services/ai_service.dart`

**Automatic Tracking**:
```dart
// _callOpenAI method now tracks usage automatically
final usage = response.data['usage'];
if (usage != null) {
  await UsageTrackingService.trackOpenAI(
    model: model,
    inputTokens: usage['prompt_tokens'] as int,
    outputTokens: usage['completion_tokens'] as int,
    operation: operation,  // 'chat', 'tags', etc.
  );
}

// synthesizeTTS method tracks character count
await UsageTrackingService.trackElevenLabs(
  characterCount: text.length,
);
```

### 3. Usage Statistics Screen
**File**: `lib/screens/usage_stats_screen.dart`

**Sections**:
1. **Current Session Card**
   - Session cost
   - API calls
   - Tokens used
   - TTS characters
   - Time since session start
   - Reset button

2. **Total Cost Card**
   - Lifetime total cost
   - Total tokens used
   - Large, prominent display

3. **Cost Breakdown Card**
   - OpenAI cost vs ElevenLabs cost
   - Percentage breakdown
   - Visual progress bars

4. **Model Usage Card**
   - Per-model statistics
   - Input/output token breakdown
   - Cost per model
   - Call count per model

5. **Operation Usage Card**
   - Chat messages
   - Personality analysis
   - Memory embeddings
   - Token and cost per operation

6. **Insights Card**
   - Average cost per conversation
   - Estimated monthly cost
   - Most expensive model

### 4. Cost Indicator Widget
**File**: `lib/widgets/cost_indicator_widget.dart`

**Two Widgets**:

**CostIndicatorWidget** (Compact, for headers):
```dart
CostIndicatorWidget()
// Displays: $0.003 | 5 calls
// Tap to see quick summary dialog
```

**FloatingCostIndicator** (FAB style):
```dart
FloatingCostIndicator(
  onTap: () => Navigator.pushNamed(context, '/usage-stats'),
)
// Displays: $ 0.0030 with paid icon
```

---

## 💾 Data Storage

### Storage Method
Uses `SharedPreferences` for persistent local storage.

### Data Structure
```json
{
  "total_tokens": 15234,
  "total_cost": 0.0234,
  "openai_cost": 0.0214,
  "elevenlabs_cost": 0.0020,
  "elevenlabs_characters": 6789,
  "models": {
    "gpt-4o-mini": {
      "input_tokens": 8500,
      "output_tokens": 4200,
      "total_cost": 0.0180,
      "call_count": 42
    },
    "gpt-4o": {
      "input_tokens": 2034,
      "output_tokens": 500,
      "total_cost": 0.0034,
      "call_count": 5
    }
  },
  "operations": {
    "chat": {
      "count": 35,
      "tokens": 10200,
      "cost": 0.0150
    },
    "tags": {
      "count": 35,
      "tokens": 4534,
      "cost": 0.0064
    }
  },
  "current_session": {
    "tokens": 2450,
    "tts_characters": 1250,
    "cost": 0.0045,
    "api_calls": 8,
    "started_at": "2025-10-21T16:30:00.000Z"
  },
  "created_at": "2025-10-20T10:00:00.000Z"
}
```

### Reset Options
```dart
// Reset session only (keeps lifetime data)
await UsageTrackingService.resetSession();

// Reset all stats (deletes everything)
await UsageTrackingService.resetAllStats();
```

---

## 🎨 UI Integration

### Navigation Setup
Add route to your main app:
```dart
routes: {
  '/usage-stats': (context) => const UsageStatsScreen(),
  // ... other routes
}
```

### Chat Screen Integration
Add cost indicator to AppBar:
```dart
AppBar(
  title: const Text('Chat'),
  actions: [
    const CostIndicatorWidget(),
    IconButton(
      icon: const Icon(Icons.analytics),
      onPressed: () => Navigator.pushNamed(context, '/usage-stats'),
    ),
  ],
)
```

Or as a floating button:
```dart
floatingActionButton: FloatingCostIndicator(
  onTap: () => Navigator.pushNamed(context, '/usage-stats'),
),
```

### Settings Screen Integration
Add a settings tile:
```dart
ListTile(
  leading: const Icon(Icons.attach_money),
  title: const Text('Usage & Costs'),
  subtitle: const Text('Track API usage and expenses'),
  trailing: const Icon(Icons.chevron_right),
  onTap: () => Navigator.pushNamed(context, '/usage-stats'),
)
```

---

## 📈 Usage Examples

### Check Current Session Cost
```dart
final session = await UsageTrackingService.getSessionStats();
print('Session cost: \$${session['cost']}');
print('API calls: ${session['api_calls']}');
```

### Get Lifetime Statistics
```dart
final stats = await UsageTrackingService.getUsageStats();
print('Total cost: \$${stats['total_cost']}');
print('Total tokens: ${stats['total_tokens']}');
```

### Get Cost Breakdown
```dart
final breakdown = await UsageTrackingService.getCostBreakdown();
print('OpenAI: \$${breakdown['openai']}');
print('ElevenLabs: \$${breakdown['elevenlabs']}');
```

### Estimate Message Cost (Before Sending)
```dart
final estimatedCost = UsageTrackingService.estimateMessageCost(
  userMessage: 'Hello, how are you?',
  systemPrompt: personalityPrompt,
  model: 'gpt-4o-mini',
  estimatedResponseTokens: 150,
);
print('Estimated cost: \$${estimatedCost.toStringAsFixed(4)}');
```

### Get Average Cost Per Conversation
```dart
final avgCost = await UsageTrackingService.getAverageCostPerConversation();
print('Average: \$${avgCost.toStringAsFixed(4)} per conversation');
```

---

## 🧪 Testing the System

### 1. Send Test Messages
```dart
// Send a few chat messages
final service = AIService();
for (int i = 0; i < 5; i++) {
  await service.sendMessage(
    text: 'Test message $i',
    personaId: 'truekai',
  );
}

// Check usage
final stats = await UsageTrackingService.getUsageStats();
print('Cost for 5 messages: \$${stats['total_cost']}');
```

### 2. Test TTS Tracking
```dart
final service = AIService();
final audio = await service.synthesizeTTS('Hello, this is a test!');

final stats = await UsageTrackingService.getUsageStats();
print('TTS cost: \$${stats['elevenlabs_cost']}');
```

### 3. View Analytics
```dart
// Navigate to usage stats screen
Navigator.pushNamed(context, '/usage-stats');
```

---

## 💡 Cost Insights

### Typical Costs Per Operation

**Chat Message (gpt-4o-mini)**:
- Input: ~100 tokens (~$0.000015)
- Output: ~150 tokens (~$0.000090)
- **Total: ~$0.0001 per message**

**Personality Analysis (gpt-4o-mini)**:
- Input: ~80 tokens (~$0.000012)
- Output: ~50 tokens (~$0.000030)
- **Total: ~$0.00004 per analysis**

**Text-to-Speech (ElevenLabs)**:
- 100 characters: $0.03
- **Average response: ~$0.045 per TTS**

**Complete Conversation** (message + analysis + TTS):
- Chat: $0.0001
- Tags: $0.00004
- TTS: $0.045
- **Total: ~$0.045 per complete interaction**

### Cost Projections

**Light Usage** (10 conversations/day):
- Daily: $0.45
- Monthly: $13.50

**Moderate Usage** (50 conversations/day):
- Daily: $2.25
- Monthly: $67.50

**Heavy Usage** (100 conversations/day):
- Daily: $4.50
- Monthly: $135.00

**Note**: These are estimates. Actual costs depend on:
- Message length
- Response length
- Model choice (gpt-4o vs gpt-4o-mini)
- TTS usage (text vs voice)
- Memory system usage (embeddings)

---

## 🔧 Configuration

### Update Pricing
If OpenAI or ElevenLabs changes pricing, update in `usage_tracking_service.dart`:

```dart
static const Map<String, Map<String, double>> openAIPricing = {
  'gpt-4o-mini': {
    'input': 0.150 / 1000000,  // Update here
    'output': 0.600 / 1000000, // And here
  },
  // ... other models
};

static const double elevenlabsCharacterCost = 0.30 / 1000; // Update here
```

### Customize Display
Modify formatting functions:
```dart
// Change currency display
static String formatCost(double cost) {
  if (cost < 0.01) {
    return '\$${(cost * 100).toStringAsFixed(4)}¢';  // Show cents
  }
  return '\$${cost.toStringAsFixed(4)}';  // Show dollars
}

// Change token display
static String formatTokens(int tokens) {
  return tokens.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (Match m) => '${m[1]},',  // Add commas
  );
}
```

---

## 🚀 Future Enhancements

### Planned Features
1. **Firebase Cloud Storage**
   - Sync usage across devices
   - Historical tracking
   - Cloud backup

2. **Budget Alerts**
   - Set daily/monthly budgets
   - Alert when approaching limit
   - Automatic pause at threshold

3. **Advanced Analytics**
   - Usage trends over time
   - Cost graphs and charts
   - Model comparison

4. **Export Functionality**
   - Export to CSV
   - Generate usage reports
   - Email summaries

5. **Optimization Suggestions**
   - Recommend cheaper models
   - Identify high-cost operations
   - Suggest caching strategies

6. **Team Usage Tracking**
   - Multi-user tracking
   - Per-user cost allocation
   - Team budgets

---

## 📊 Sample Output

### Usage Stats Screen Preview
```
┌─ Current Session ────────────────────┐
│ Started: 2h ago                [Reset]│
│ ────────────────────────────────────  │
│ Total Cost        $0.0234             │
│ API Calls         42                  │
│ Tokens Used       12,450              │
│ TTS Characters    6,780               │
└───────────────────────────────────────┘

┌─ Total Lifetime Cost ────────────────┐
│        $0.1234                        │
│     125,678 tokens                    │
└───────────────────────────────────────┘

┌─ Cost Breakdown ─────────────────────┐
│ OpenAI (Chat & Embeddings)            │
│ $0.1100 ████████████████████ 89.1%   │
│                                       │
│ ElevenLabs (TTS)                      │
│ $0.0134 ██ 10.9%                     │
└───────────────────────────────────────┘

┌─ Model Usage ────────────────────────┐
│ gpt-4o-mini            $0.0890        │
│ 85 calls • 98,450 tokens              │
│ In: 65,200 • Out: 33,250              │
│                                       │
│ gpt-4o                 $0.0210        │
│ 10 calls • 12,580 tokens              │
│ In: 8,450 • Out: 4,130                │
└───────────────────────────────────────┘

┌─ Insights ───────────────────────────┐
│ 💬 Avg cost per conversation $0.0012  │
│ 📊 Est. monthly cost (30d)   $36.00  │
│ 📈 Most expensive model    gpt-4o-mini│
└───────────────────────────────────────┘
```

---

## ✅ Implementation Checklist

- ✅ Created `UsageTrackingService` with pricing data
- ✅ Integrated tracking into `AIService._callOpenAI()`
- ✅ Integrated tracking into `AIService.synthesizeTTS()`
- ✅ Created `UsageStatsScreen` with comprehensive UI
- ✅ Created `CostIndicatorWidget` for chat header
- ✅ Created `FloatingCostIndicator` for FAB
- ✅ Added SharedPreferences persistence
- ✅ Implemented session tracking
- ✅ Added cost estimation functions
- ✅ Created detailed documentation

---

## 🎉 Benefits

### For Users
- 💰 Know exactly how much the app costs to use
- 📊 Understand usage patterns
- 🎯 Budget accordingly
- 📈 Track expenses over time

### For Developers
- 🔍 Monitor API consumption
- ⚠️ Identify expensive operations
- 🛠️ Optimize based on real data
- 💡 Make informed architecture decisions

---

**The token and cost tracking system is now fully implemented and ready to use! Every API call is automatically tracked with detailed analytics available in the Usage Stats screen. 💰✨**
