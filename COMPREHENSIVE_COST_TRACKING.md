# Comprehensive Cost Tracking System

## Overview

The Homecoming app now tracks **ALL** costs across **EVERY** paid service used by the application. This provides complete visibility into the true cost of running and using the app.

## Services Tracked

### 1. **OpenAI (Chat & Embeddings)**
- **Models Tracked:**
  - `gpt-4o`: $2.50/1M input tokens, $10.00/1M output tokens
  - `gpt-4o-mini`: $0.15/1M input tokens, $0.60/1M output tokens  
  - `text-embedding-3-small`: $0.02/1M tokens
  - `text-embedding-3-large`: $0.13/1M tokens

- **What's Tracked:**
  - Input tokens per model
  - Output tokens per model
  - Cost per model
  - Per-operation breakdown (chat, tags, embeddings)

### 2. **ElevenLabs (Text-to-Speech)**
- **Pricing:** $0.30 per 1,000 characters
- **What's Tracked:**
  - Total characters processed
  - Total TTS cost

### 3. **Firebase Realtime Database**
- **Pricing:**
  - Reads: $1.00 per 100,000 operations
  - Writes: $5.00 per 100,000 operations (5x more expensive!)

- **What's Tracked:**
  - Total read operations
  - Total write operations
  - Separate cost calculation for reads vs writes
  - Operations tracked automatically in:
    - `savePersonalityData()` - 1 write
    - `loadPersonalityData()` - 1 read
    - `saveConversation()` - 1 write
    - `getRecentConversations()` - 1 read

### 4. **Cloud Functions**
- **Pricing:**
  - Invocations: $0.40 per 1,000,000 calls
  - Compute: $0.0000025 per GB-second
    - GB-seconds = (memory in GB) × (execution time in seconds)

- **What's Tracked:**
  - Total function invocations
  - Total compute time (seconds)
  - Cost per function (invocations + compute)
  - Per-function breakdown showing:
    - Function name
    - Number of calls
    - Individual cost

### 5. **Google Custom Search API** (if used)
- **Pricing:** $5.00 per 1,000 queries
- **What's Tracked:**
  - Total search queries
  - Search API cost

## Usage Stats Screen Features

### Current Session Card
Shows real-time stats for the current session:
- Total cost
- API calls
- Tokens used
- TTS characters
- Firebase operations (if any)
- Function calls (if any)
- Search queries (if any)
- Session start time

### Total Lifetime Cost
Large, prominent display showing:
- Total accumulated cost across all services
- Total tokens used

### Cost Breakdown
Visual breakdown with progress bars showing:
- OpenAI costs & percentage of total
- ElevenLabs costs & percentage of total
- Firebase costs & percentage of total
- Cloud Functions costs & percentage of total
- Google Search costs & percentage of total (if used)

### Firebase Database Card
Detailed Firebase usage showing:
- Total operations (reads + writes)
- Reads count
- Writes count
- Total Firebase cost
- Current pricing display

### Cloud Functions Card
Detailed function usage showing:
- Total invocations across all functions
- Total compute time
- Total functions cost
- **Per-function breakdown table:**
  - Each function's name
  - Number of calls
  - Individual cost
- Current pricing display

### Model Usage Card
Per-model breakdown showing:
- Model name (e.g., gpt-4o, gpt-4o-mini)
- Total cost for that model
- Number of API calls
- Total tokens (input + output)
- Input/output token split

### Operation Usage Card
Per-operation breakdown showing:
- Chat messages
- Personality analysis (tags)
- Memory embeddings
- For each: count, tokens, cost

### Insights Card
Smart analytics showing:
- Average cost per conversation
- Estimated monthly cost (extrapolated from session)
- Most expensive model

## Cost Calculation Examples

### Example 1: Simple Chat Interaction
```
User sends: "Hello, how are you?" (5 tokens)
AI responds: "I'm doing great, thanks!" (8 tokens)
Model: gpt-4o-mini

Input cost:  5 tokens × $0.15 / 1,000,000 = $0.00000075
Output cost: 8 tokens × $0.60 / 1,000,000 = $0.00000480
Save conversation (Firebase write): 1 × $5.00 / 100,000 = $0.00005

Total: ~$0.000056
```

### Example 2: Chat with TTS and Tags
```
Chat (gpt-4o-mini):
- Input: 150 tokens = $0.0000225
- Output: 200 tokens = $0.00012

Tags generation (gpt-4o-mini):
- Input: 50 tokens = $0.0000075
- Output: 30 tokens = $0.000018

TTS (ElevenLabs):
- Characters: 150 = $0.045

Firebase:
- Save conversation: $0.00005
- Save personality: $0.00005

Total: ~$0.045217
```

### Example 3: Complete Interaction with All Services
```
Chat (gpt-4o): $0.0003
Tags (gpt-4o-mini): $0.00004
Memory embedding: $0.00001
TTS (ElevenLabs): $0.045
Firebase writes (2): $0.0001
Cloud Function (processMessage): $0.000001

Total: ~$0.04545
```

## Implementation Details

### Automatic Tracking

All tracking happens **automatically** - you don't need to do anything special:

1. **OpenAI & ElevenLabs**: Tracked in `AIService` after every API call
2. **Firebase**: Tracked in `FirebaseService` after every database operation
3. **Cloud Functions**: Tracked by calling `UsageTrackingService.trackCloudFunction()`
4. **Google Search**: Tracked by calling `UsageTrackingService.trackGoogleSearch()`

### Data Storage

All usage data is stored locally using `SharedPreferences`:
- **Lifetime stats**: Accumulated across all sessions
- **Session stats**: Reset when you tap "Reset Session"
- **Persistent**: Survives app restarts

### Accessing the Stats

To view usage stats:
1. Open the Homecoming app
2. Navigate to Settings or Menu
3. Select "Usage & Cost Tracking"
4. View comprehensive breakdown

## API Reference

### Track Firebase Operations
```dart
await UsageTrackingService.trackFirebaseDatabase(
  reads: 1,   // Number of read operations
  writes: 0,  // Number of write operations
);
```

### Track Cloud Function
```dart
await UsageTrackingService.trackCloudFunction(
  functionName: 'processMessage',
  invocations: 1,
  computeTimeSeconds: 0.234,
  memoryMB: 256,
);
```

### Track Google Search
```dart
await UsageTrackingService.trackGoogleSearch(queries: 1);
```

### Get Cost Breakdown
```dart
final breakdown = await UsageTrackingService.getCostBreakdown();
print('OpenAI: ${breakdown['openai']}');
print('ElevenLabs: ${breakdown['elevenlabs']}');
print('Firebase: ${breakdown['firebase']}');
print('Functions: ${breakdown['functions']}');
print('Google: ${breakdown['google']}');
print('Total: ${breakdown['total']}');
```

## Cost Optimization Tips

### 1. **Use gpt-4o-mini Instead of gpt-4o**
- gpt-4o-mini is **16.7x cheaper** for input tokens ($0.15 vs $2.50)
- gpt-4o-mini is **16.7x cheaper** for output tokens ($0.60 vs $10.00)
- Use gpt-4o only for complex reasoning tasks

### 2. **Minimize Firebase Writes**
- Writes are **5x more expensive** than reads
- Batch multiple updates into single write operation
- Consider caching data locally before writing

### 3. **Optimize TTS Usage**
- TTS is often the **most expensive** operation ($0.045 per 150 chars)
- Consider shorter responses when appropriate
- Allow users to disable TTS if not needed

### 4. **Reduce Token Usage**
- Use concise prompts
- Limit conversation history length
- Use smaller context windows when possible

### 5. **Monitor Cloud Functions**
- Check per-function breakdown for expensive functions
- Optimize long-running functions
- Consider increasing memory allocation if it reduces execution time

## Pricing Sources & Updates

All pricing is based on current rates as of January 2025:
- **OpenAI**: https://openai.com/api/pricing/
- **ElevenLabs**: https://elevenlabs.io/pricing
- **Firebase**: https://firebase.google.com/pricing
- **Cloud Functions**: https://cloud.google.com/functions/pricing
- **Google Search**: https://developers.google.com/custom-search/v1/overview

**Note**: Pricing may change. Update the constants in `UsageTrackingService` if rates change:
```dart
// lib/services/usage_tracking_service.dart
static const double gpt4oInputCost = 2.50 / 1000000;
static const double firebaseWriteCost = 5.00 / 100000;
// etc.
```

## Complete Coverage

This system now tracks **100% of costs** for:
- ✅ All OpenAI API calls (chat, embeddings)
- ✅ All ElevenLabs TTS calls
- ✅ All Firebase Database operations (reads & writes)
- ✅ All Cloud Functions invocations and compute time
- ✅ All Google Custom Search API queries

You now have **complete visibility** into the true cost of using the Homecoming app!
