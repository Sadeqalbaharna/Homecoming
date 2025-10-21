# Memory System Not Working - Debug Guide

## 🔍 **Issue:** Memory queries returning no results

Based on your screenshot, Kai is **not accessing memories** - no purple badge appears.

---

## 🕵️ **Root Cause Analysis**

### Checked:
✅ **Code is correct**:
- `MemoryService.queryMemory()` calls `functions.httpsCallable('queryMemory')`
- `AIService.sendMessage()` queries memory before OpenAI call
- Purple badge logic exists in `main_overlay.dart`
- Console log `💭 Using X memory contexts` is present

✅ **Cloud Function exists**:
- `exports.queryMemory` in `functions/index.js` (line 430)
- Uses Firebase Realtime Database for memory storage

✅ **Conversations are being saved**:
- `FirebaseService.saveConversation()` writes to `/conversations/{personaId}`
- PersonaId: `truekai`
- Saves userMessage, aiResponse, personalityDeltas

---

## 🎯 **Most Likely Issues**

### **Issue #1: Not Enough Conversations** (90% likely)

**Problem**: Memory shards only form after **10+ conversation turns**

**Check**:
1. Open Firebase Console: https://console.firebase.google.com
2. Go to **Realtime Database**
3. Navigate to `/conversations/truekai/`
4. Count the entries

**Expected**: Need at least 10 conversation documents

**If less than 10**:
- ✅ This is normal! Keep chatting
- Memory will form automatically after 10 turns
- First query will work after that

---

### **Issue #2: Cloud Functions Not Deployed** (5% likely)

**Problem**: Cloud Functions might not be deployed to Firebase

**Check**:
```powershell
cd functions
firebase functions:list
```

**Expected output**:
```
✔ queryMemory (us-central1)
✔ onTurnWrite (us-central1)
✔ onShardWrite (us-central1)
✔ extractFacts (us-central1)
```

**If empty or missing**:
```powershell
cd functions
firebase deploy --only functions
```

---

### **Issue #3: Persona ID Mismatch** (3% likely)

**Problem**: Using different persona IDs in different places

**Check files**:
- `lib/main_overlay.dart` line 1224: `personaId: 'truekai'` ✅
- `functions/index.js`: Expects any persona ID ✅
- Should work fine

---

### **Issue #4: Firebase Realtime Database Not Enabled** (2% likely)

**Problem**: Realtime Database might not be enabled in Firebase project

**Check**:
1. Open Firebase Console
2. Go to **Realtime Database** (not Firestore!)
3. Should see data at `/conversations/truekai/`

**If "Get started" button appears**:
1. Click "Create Database"
2. Choose location
3. Start in **test mode** (for development)

---

## 🧪 **Step-by-Step Debug Process**

### **Step 1: Check Conversation Count**

Open Firebase Console → Realtime Database:

```
/conversations
  └─ truekai
      ├─ -ABC123xyz (conversation 1)
      ├─ -ABC124xyz (conversation 2)
      ├─ -ABC125xyz (conversation 3)
      ...
      └─ -ABC132xyz (conversation 10) ← Need at least this many!
```

**If < 10 conversations**:
- **Action**: Have more conversations! Memory forms at 10 turns
- **Why**: This is by design (CONFIG.BUFFER_SIZE_THRESHOLD = 10)

---

### **Step 2: Check Memory Shards**

After 10+ conversations, check for shards:

```
/memory
  ├─ buffers
  │   └─ truekai
  │       └─ turns: [array of 10 conversations]
  └─ shards
      └─ truekai
          └─ shard_123456789
              ├─ summary: "User discussed..."
              ├─ turns: [array of conversations]
              └─ timestamp: 1234567890
```

**If no shards**:
- **Problem**: `onTurnWrite` function not triggering
- **Action**: Check Cloud Functions logs

---

### **Step 3: Check Embeddings**

After shards are created, check embeddings:

```
/memory
  └─ embeddings
      └─ truekai
          └─ shard_123456789
              ├─ embedding: [1536 numbers]
              ├─ summary: "User discussed..."
              └─ shardRef: "/memory/shards/truekai/shard_123456789"
```

**If no embeddings**:
- **Problem**: `onShardWrite` function not triggering
- **Action**: Check Cloud Functions logs

---

### **Step 4: Test Memory Query**

Add debug logging to `memory_service.dart`:

```dart
static Future<MemoryQueryResponse?> queryMemory({
  required String personaId,
  required String query,
  int limit = 5,
}) async {
  try {
    print('🔍 [DEBUG] Querying memory...');
    print('🔍 [DEBUG] PersonaId: $personaId');
    print('🔍 [DEBUG] Query: "$query"');
    print('🔍 [DEBUG] Limit: $limit');
    
    final callable = _functions.httpsCallable('queryMemory');
    print('🔍 [DEBUG] Calling Cloud Function...');
    
    final result = await callable.call({
      'personaId': personaId,
      'query': query,
      'limit': limit,
    });

    print('🔍 [DEBUG] Cloud Function response: ${result.data}');

    if (result.data == null) {
      print('⚠️ [DEBUG] Memory query returned no data');
      return null;
    }

    final response = MemoryQueryResponse.fromJson(
      result.data as Map<String, dynamic>
    );

    print('✅ [DEBUG] Found ${response.results.length} relevant memories');
    
    return response;
  } catch (e, stackTrace) {
    print('❌ [DEBUG] Memory query error: $e');
    print('❌ [DEBUG] Stack trace: $stackTrace');
    return null;
  }
}
```

**Run app and send a message**. Look for debug logs.

---

## 🔧 **Quick Fix: Force Memory Creation**

If you want to test memory immediately without waiting for 10 conversations:

### **Option 1: Lower the threshold (temporary)**

Edit `functions/index.js`:

```javascript
const CONFIG = {
  BUFFER_SIZE_THRESHOLD: 3, // Changed from 10 to 3
  BUFFER_TIME_THRESHOLD: 3600000,
  EMBEDDING_MODEL: 'text-embedding-3-small',
  EMBEDDING_DIMENSIONS: 1536,
  FACT_EXTRACTION_MODEL: 'gpt-4o-mini',
  SUMMARY_MODEL: 'gpt-4o-mini',
};
```

Then redeploy:
```powershell
cd functions
firebase deploy --only functions
```

Now memory shards will form after just **3 conversations**!

---

### **Option 2: Manually trigger memory formation**

1. Open Firebase Console → Functions
2. Find `onTurnWrite` function
3. Click "Logs"
4. Should see logs like:
   ```
   [onTurnWrite] Processing conversation for truekai
   [onTurnWrite] Buffer size: 10, creating shard
   ```

If no logs appear → Function not triggering → Check deployment

---

## 🎯 **Expected Flow (When Working)**

```
1. User sends message
   ↓
2. AIService.sendMessage() called
   ↓
3. MemoryService.queryMemory() called
   ↓
4. Cloud Function "queryMemory" executes
   ↓
5. Searches /memory/embeddings/truekai/*
   ↓
6. Returns relevant memories (or empty array if none)
   ↓
7. If memories found → memoryContext added to prompt
   ↓
8. Purple badge appears on Kai's message
   ↓
9. Console shows: 💭 Using X memory contexts
```

---

## 📊 **Check Firebase Console Right Now**

### **1. Realtime Database**

Go to: https://console.firebase.google.com → Realtime Database

**Check**:
```
✅ /conversations/truekai/ exists?
✅ How many conversation entries? (need 10+)
✅ /memory/shards/truekai/ exists?
✅ /memory/embeddings/truekai/ exists?
```

### **2. Functions**

Go to: Functions → Logs

**Filter by**: `truekai`

**Look for**:
```
[onTurnWrite] Processing conversation for truekai
[onTurnWrite] Buffer size: 10, creating shard
[onShardWrite] Generating embedding for shard_...
[queryMemory] Query received: "..."
```

If **no logs** → Functions not deployed or not triggering

---

## 🚀 **Most Likely Solution**

Based on probability:

### **90% chance**: You need more conversations

**Action**:
1. Keep chatting with Kai
2. Have at least 10 conversation turns
3. Check Firebase Console → `/memory/shards/truekai/`
4. After shard appears, next query will work!

**Test**:
```
Turn 1:  "Hi Kai, my name is Sarah"
Turn 2:  "I love hiking"
Turn 3:  "My favorite color is blue"
Turn 4:  "I work as a teacher"
Turn 5:  "I have two cats"
Turn 6:  "I'm learning Spanish"
Turn 7:  "I live in Portland"
Turn 8:  "I enjoy photography"
Turn 9:  "I play piano"
Turn 10: "I'm 32 years old"

[Wait 30 seconds for Cloud Function to process]

Turn 11: "What's my name?"
→ Should see purple badge: "1 memory recalled"
→ Kai responds: "Your name is Sarah!"
```

---

## 🔍 **Next Steps**

1. **Check Firebase Console** → Realtime Database → `/conversations/truekai/`
   - If < 10 entries → **Have more conversations**
   - If 10+ entries → Check `/memory/shards/`

2. **Check Cloud Functions**:
   ```powershell
   cd functions
   firebase functions:list
   ```
   - If empty → Deploy: `firebase deploy --only functions`

3. **Add debug logging** to `memory_service.dart` (code above)

4. **Test with 10+ conversations**

5. **Check logs** in console when sending message

---

## 💡 **Quick Test Command**

Run this to see detailed logs:

```powershell
cd c:\code\homecoming_app
flutter run --verbose 2>&1 | Select-String -Pattern "🔍|💭|❌|✅|memory|Memory"
```

Then send a message and watch for:
- `🔍 [DEBUG] Querying memory...`
- `✅ [DEBUG] Found X relevant memories`
- `💭 Using X memory contexts`

---

## ✅ **Success Indicators**

You'll know memory is working when you see:

1. **In chat**: Purple badge "X memories recalled"
2. **In console**: `💭 Using 3 memory contexts`
3. **In Firebase**: `/memory/shards/truekai/` has entries
4. **In response**: Kai references past conversations

---

**Most likely issue**: Need 10+ conversations first! 🎯
