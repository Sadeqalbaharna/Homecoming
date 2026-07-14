# 🧠 Kai Brain - Memory System

## Overview

Kai's brain is a sophisticated memory architecture built on Firebase Cloud Functions that gives Kai:
- **Long-term memory** through conversation sharding and summarization
- **Semantic search** using embedding vectors
- **Fact extraction** for durable knowledge
- **Daily summaries** for temporal awareness

## Architecture

```
User Conversation
       ↓
[1] onTurnWrite → Rolling Buffer
       ↓ (threshold reached)
    Create Shard + Summary
       ↓
[2] onShardWrite → Generate Embedding
       ↓
[3] extractFacts → Extract Durable Facts
       ↓
[4] dailyCompactor (CRON) → Daily Summary
```

## 🗄️ Firebase Structure

```
/conversations/{personaId}/{conversationId}
  - userMessage: string
  - aiResponse: string
  - timestamp: number
  - personalityDeltas: object

/memory
  /buffers/{personaId}
    - turns: array
    - firstTurnTime: number
    - turnCount: number
  
  /shards/{personaId}/{shardId}
    - turns: array
    - summary: string
    - turnCount: number
    - startTime: number
    - endTime: number
    - createdAt: number
  
  /embeddings/{personaId}/{shardId}
    - vector: array[1536]
    - dimensions: number
    - summary: string
    - shardRef: string
    - createdAt: number
  
  /facts/{personaId}/{factId}
    - type: string (preference|personal|goal)
    - fact: string
    - shardSource: string
    - extractedAt: number
    - confidence: number
  
  /daily/{personaId}/{YYYY-MM-DD}
    - date: string
    - summary: string
    - stats: object
    - conversationCount: number
    - createdAt: number
```

## 🚀 Deployment

### Step 1: Setup Firebase Functions

```powershell
# Navigate to functions directory
cd functions

# Install dependencies
npm install

# Login to Firebase (if not already)
firebase login

# Set Firebase project
firebase use homecoming-74f73
```

### Step 2: Configure OpenAI API Key

```powershell
# Set OpenAI key in Firebase config
firebase functions:config:set openai.key="YOUR_OPENAI_API_KEY"

# View current config
firebase functions:config:get
```

### Step 3: Deploy Functions

```powershell
# Deploy all functions
firebase deploy --only functions

# Or deploy specific function
firebase deploy --only functions:onTurnWrite
firebase deploy --only functions:onShardWrite
firebase deploy --only functions:extractFacts
firebase deploy --only functions:dailyCompactor
```

### Step 4: Deploy Database Rules

```powershell
# Deploy security rules
firebase deploy --only database
```

## 📊 System Details

### System 1: onTurnWrite (Rolling Buffer)

**Trigger**: New conversation added to `/conversations/{personaId}/`
**Action**:
1. Append turn to rolling buffer
2. Check thresholds:
   - Size: 10 turns
   - Time: 1 hour
3. If threshold met:
   - Create shard with summary
   - Clear buffer

**Configuration**:
```javascript
BUFFER_SIZE_THRESHOLD: 10
BUFFER_TIME_THRESHOLD: 3600000 // 1 hour
```

### System 2: onShardWrite (Embedder)

**Trigger**: New shard created in `/memory/shards/{personaId}/`
**Action**:
1. Generate embedding from shard summary
2. Store vector in `/memory/embeddings/`

**Model**: `text-embedding-3-small` (1536 dimensions)

### System 3: extractFacts (Fact Extractor)

**Trigger**: New shard created (same as onShardWrite)
**Action**:
1. Analyze conversation turns
2. Extract durable facts using GPT-4o-mini
3. Categorize: preference, personal, goal
4. Store in `/memory/facts/`

**Fact Types**:
- **preference**: User likes/dislikes
- **personal**: User info (name, job, etc.)
- **goal**: Recurring intentions

### System 4: dailyCompactor (CRON)

**Schedule**: Every day at 2 AM UTC
**Action**:
1. Collect previous day's conversations
2. Create comprehensive daily summary
3. Calculate personality change totals
4. Store in `/memory/daily/{YYYY-MM-DD}`

**Schedule Expression**: `0 2 * * *`

## 🔧 Usage

### Query Memory (Semantic Search)

Call from app:
```dart
final result = await FirebaseFunctions.instance
  .httpsCallable('queryMemory')
  .call({
    'personaId': 'truekai',
    'query': 'What does the user like for breakfast?',
    'limit': 5,
  });

print('Results: ${result.data['results']}');
```

### Manual Fact Extraction

Force extraction for specific shard:
```dart
await FirebaseFunctions.instance
  .httpsCallable('extractFactsManual')
  .call({
    'personaId': 'truekai',
    'shardId': 'shard_1234567890',
  });
```

### View Memory

```dart
// Get recent facts
final factsRef = FirebaseDatabase.instance
  .ref('memory/facts/truekai');
final snapshot = await factsRef
  .orderByChild('extractedAt')
  .limitToLast(20)
  .once();

// Get daily summaries
final dailyRef = FirebaseDatabase.instance
  .ref('memory/daily/truekai');
final days = await dailyRef
  .orderByKey()
  .limitToLast(7) // Last 7 days
  .once();
```

## 🎯 Integration with Kai

### Update AI Service

Add memory context to AI calls:

```dart
// In ai_service.dart
Future<ChatResponse> sendMessage({
  required String text,
  required String personaId,
  // ... other params
}) async {
  // 1. Query memory for relevant context
  final memoryContext = await _queryMemory(text, personaId);
  
  // 2. Get recent facts
  final facts = await _getRecentFacts(personaId);
  
  // 3. Build enhanced system prompt
  final systemPrompt = '''
You are Kai, an AI companion with long-term memory.

Relevant memories:
${memoryContext.map((m) => m['summary']).join('\n')}

Known facts about user:
${facts.map((f) => f['fact']).join('\n')}

Current personality: [existing personality state]
''';
  
  // 4. Send to OpenAI with context
  // ... existing logic
}

Future<List<Map>> _queryMemory(String query, String personaId) async {
  final result = await FirebaseFunctions.instance
    .httpsCallable('queryMemory')
    .call({
      'personaId': personaId,
      'query': query,
      'limit': 3,
    });
  
  return List<Map>.from(result.data['results']);
}

Future<List<Map>> _getRecentFacts(String personaId) async {
  final snapshot = await FirebaseDatabase.instance
    .ref('memory/facts/$personaId')
    .orderByChild('extractedAt')
    .limitToLast(10)
    .once();
  
  if (snapshot.value == null) return [];
  
  final facts = Map<String, dynamic>.from(snapshot.value as Map);
  return facts.values.toList().cast<Map>();
}
```

## 📈 Monitoring

### View Logs

```powershell
# Real-time logs
firebase functions:log --only onTurnWrite

# Filter by function
firebase functions:log --only dailyCompactor

# Tail logs
firebase functions:log --tail
```

### Check Function Status

```powershell
# List deployed functions
firebase functions:list

# View function details
firebase functions:config:get
```

## 🔍 Testing

### Local Emulator

```powershell
# Start emulators
firebase emulators:start

# Test functions locally before deploying
```

### Manual Trigger

Test individual functions:

```javascript
// In Firebase Console → Functions → Select function → Testing
// Or use curl:
curl -X POST \
  https://us-central1-homecoming-74f73.cloudfunctions.net/queryMemory \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "personaId": "truekai",
      "query": "What does the user enjoy?",
      "limit": 5
    }
  }'
```

## 🎨 Enhancements

### Future Improvements

1. **Vector Database**: Replace Firebase with Pinecone/Weaviate for faster similarity search
2. **Importance Scoring**: Rank memories by importance/frequency
3. **Memory Decay**: Fade old memories over time
4. **Cross-Reference**: Link related shards and facts
5. **Conflict Resolution**: Handle contradicting facts
6. **Emotional Memory**: Tag memories with emotional context
7. **Dream State**: Offline memory consolidation (like sleep)

### Advanced Queries

```dart
// Search by date range
final memories = await FirebaseDatabase.instance
  .ref('memory/daily/truekai')
  .orderByKey()
  .startAt('2025-10-01')
  .endAt('2025-10-31')
  .once();

// Get facts by type
final preferences = await FirebaseDatabase.instance
  .ref('memory/facts/truekai')
  .orderByChild('type')
  .equalTo('preference')
  .once();

// Find recent personality changes
final shards = await FirebaseDatabase.instance
  .ref('memory/shards/truekai')
  .orderByChild('endTime')
  .limitToLast(5)
  .once();
```

## 💡 Best Practices

1. **Monitor Costs**: OpenAI API calls add up (especially embeddings)
2. **Rate Limiting**: Add throttling for fact extraction
3. **Cache Results**: Store query results temporarily
4. **Batch Operations**: Process multiple shards together
5. **Error Handling**: Add retry logic for API failures
6. **Privacy**: Implement data retention policies

## 🚨 Troubleshooting

### Functions Not Triggering

```powershell
# Check function logs
firebase functions:log

# Verify database triggers
# Ensure paths match exactly: /conversations/{personaId}/{conversationId}

# Test database write
firebase database:set /conversations/truekai/test_123 '{"userMessage":"test","aiResponse":"test","timestamp":1234567890}'
```

### OpenAI API Errors

```powershell
# Verify API key
firebase functions:config:get openai.key

# Check quota
# Visit: https://platform.openai.com/usage

# Increase timeout if needed (in firebase.json)
"functions": {
  "timeoutSeconds": 540,
  "memory": "2GB"
}
```

### High Costs

```javascript
// Reduce embedding frequency
// Only embed important shards (e.g., turnCount > 5)

// Use cheaper models
SUMMARY_MODEL: 'gpt-4o-mini' // Instead of gpt-4o
EMBEDDING_MODEL: 'text-embedding-3-small' // Smallest model
```

## ✅ Deployment Checklist

- [ ] Install Node.js dependencies (`npm install`)
- [ ] Set OpenAI API key (`firebase functions:config:set`)
- [ ] Deploy functions (`firebase deploy --only functions`)
- [ ] Deploy database rules (`firebase deploy --only database`)
- [ ] Test onTurnWrite (send test conversation)
- [ ] Verify shard creation in Firebase Console
- [ ] Check embedding generation
- [ ] Test fact extraction
- [ ] Wait for first daily compactor run (or trigger manually)
- [ ] Integrate memory queries into AI service
- [ ] Monitor logs for errors
- [ ] Test semantic search from app

## 🎉 Result

After deployment, Kai will:
- ✅ Remember past conversations (sharded storage)
- ✅ Understand context semantically (embeddings)
- ✅ Recall user preferences/facts (extracted knowledge)
- ✅ Reflect on daily interactions (summaries)
- ✅ Answer questions about history ("What did we talk about yesterday?")

**Kai now has TRUE long-term memory!** 🧠✨
