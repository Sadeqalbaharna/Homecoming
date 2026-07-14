# 🚀 Quick Start: Access Kai's Brain

**Current Status**: Build v0.7.4+33 complete, Cloud Functions need deployment

---

## ⚡ Fastest Way to Check the Brain (3 steps)

### Step 1: Deploy Cloud Functions (5 minutes)

```powershell
.\deploy-kai-brain.ps1
```

**Note**: For production deployment, the API key is automatically pulled from GitHub Secrets. See [GITHUB_SECRETS_FUNCTIONS.md](GITHUB_SECRETS_FUNCTIONS.md) for details.

### Step 2: Send Test Conversations (1 minute)

```powershell
.\test-memory.ps1
```

This sends 10 test messages with extractable facts:
- "My name is Sadeq"
- "I love coffee in the morning"
- "I live in Bahrain"
- etc.

### Step 3: Open Firebase Console (instant)

Click these direct links:

**📊 Main Dashboard**:
https://console.firebase.google.com/project/homecoming-74f73/database

**🔍 Quick Links**:

1. **Conversation Buffer** (shows current 10-turn window):
   https://console.firebase.google.com/project/homecoming-74f73/database/data/~2Fmemory~2Fbuffers~2Ftruekai

2. **Memory Shards** (GPT-generated summaries):
   https://console.firebase.google.com/project/homecoming-74f73/database/data/~2Fmemory~2Fshards~2Ftruekai

3. **Extracted Facts** (learned knowledge):
   https://console.firebase.google.com/project/homecoming-74f73/database/data/~2Fmemory~2Ffacts~2Ftruekai

4. **Embeddings** (semantic search vectors):
   https://console.firebase.google.com/project/homecoming-74f73/database/data/~2Fmemory~2Fembeddings~2Ftruekai

5. **Cloud Functions** (status & logs):
   https://console.firebase.google.com/project/homecoming-74f73/functions

---

## 📋 What You'll See

### In the Buffer (`/memory/buffers/truekai`)
```json
{
  "turnCount": 10,
  "firstTurnTime": 1729547123456,
  "turns": [
    {
      "userMessage": "My name is Sadeq",
      "aiResponse": "Nice to meet you, Sadeq!",
      "timestamp": 1729547123456
    }
    // ... 9 more turns
  ]
}
```

### In Memory Shards (`/memory/shards/truekai/shard_xxx`)
```json
{
  "summary": "User introduced themselves as Sadeq, shared preferences for coffee in the morning and Flutter development, mentioned living in Bahrain and working on an AI project...",
  "turnCount": 10,
  "startTime": 1729547123456,
  "endTime": 1729547130000,
  "turns": [ /* conversation history */ ]
}
```

### In Extracted Facts (`/memory/facts/truekai/fact_xxx`)
```json
{
  "type": "personal",
  "fact": "User's name is Sadeq",
  "shardSource": "shard_20251021_001234",
  "confidence": 1.0,
  "extractedAt": 1729547145678
}
```

### In Embeddings (`/memory/embeddings/truekai/shard_xxx`)
```json
{
  "vector": [0.123, -0.456, 0.789, ... /* 1536 numbers */],
  "dimensions": 1536,
  "summary": "User introduced themselves...",
  "shardRef": "shard_20251021_001234"
}
```

---

## 💻 CLI Commands (Alternative to Console)

### View Data
```powershell
# Check buffer
firebase database:get /memory/buffers/truekai

# Check shards
firebase database:get /memory/shards/truekai

# Check facts
firebase database:get /memory/facts/truekai

# View conversations
firebase database:get /conversations/truekai
```

### Monitor Functions
```powershell
# Real-time logs
firebase functions:log --tail

# Recent activity
firebase functions:log --limit 50

# Specific function
firebase functions:log --only onTurnWrite
```

---

## 🎯 Timeline

**After running test-memory.ps1:**

- **0 seconds**: 10 conversations saved to `/conversations/truekai/`
- **1-5 seconds**: `onTurnWrite` triggers, creates buffer
- **30-60 seconds**: Buffer threshold reached, shard created
- **60-90 seconds**: `onShardWrite` generates embedding
- **60-90 seconds**: `extractFacts` extracts knowledge
- **✅ Complete**: Memory fully formed and searchable!

**Daily at 2 AM UTC:**
- `dailyCompactor` runs automatically
- Creates summary in `/memory/daily/truekai/YYYY-MM-DD`

---

## 🔧 Troubleshooting

### Functions not deploying?
```powershell
# Check Node.js version (need 18+)
node --version

# Install dependencies
cd functions
npm install
cd ..

# Deploy again
firebase deploy --only functions
```

### No memory data appearing?
```powershell
# 1. Check if functions are deployed
firebase functions:list

# 2. View function logs
firebase functions:log --limit 50

# 3. Verify OpenAI key is set
firebase functions:config:get openai.key

# 4. Re-run test script
.\test-memory.ps1
```

### Can't access Firebase Console?
```powershell
# Login to Firebase
firebase login

# Select project
firebase use homecoming-74f73
```

---

## 📱 From the App (After Functions Deploy)

Your app automatically logs conversations to Firebase. Just:

1. Open Kai app (v0.7.4+33)
2. Send 10+ messages
3. Wait 1 minute
4. Check Firebase Console
5. See memories forming automatically!

No app changes needed - it's already integrated! ✨

---

## 🎉 Expected Results

After deployment and testing, you should have:

✅ **6 Cloud Functions** running in Firebase  
✅ **10 Conversations** in `/conversations/truekai/`  
✅ **1 Memory Shard** with GPT summary  
✅ **1 Embedding Vector** (1536 dimensions)  
✅ **3-5 Extracted Facts** about you  
✅ **Semantic Search** working (test with queryMemory)  

---

## 🚀 Ready?

Run these commands now:

```powershell
# 1. Deploy the brain
.\deploy-kai-brain.ps1

# 2. Test it
.\test-memory.ps1

# 3. Open console
Start-Process "https://console.firebase.google.com/project/homecoming-74f73/database"
```

**Then watch the magic happen! 🧠✨**
