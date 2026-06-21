# Testing Memory Access - Quick Guide

## ✅ How to Verify Memory is Working

### **Step 1: Have Conversations to Build Memory**

You need **10+ conversation turns** for memory shards to form:

```
Turn 1:  "Hi Kai!"
Turn 2:  "I love hiking in the mountains"
Turn 3:  "My favorite color is blue"
Turn 4:  "I work as a software engineer"
Turn 5:  "I have a dog named Max"
Turn 6:  "I'm planning a trip to Japan"
Turn 7:  "What's the weather like?"
Turn 8:  "Tell me a joke"
Turn 9:  "I'm feeling tired today"
Turn 10: "What should I have for dinner?"
```

After these 10 turns, a Cloud Function will:
1. Detect conversation length reached threshold
2. Create memory shard in Firestore
3. Generate embeddings
4. Store in `/users/{userId}/personas/kai_default/memory_shards/`

---

### **Step 2: Test Memory Recall**

Now ask questions that should trigger memory:

**Test Query 1: "What do you know about my hobbies?"**

Expected behavior:
- ✅ Memory query fires
- ✅ Finds: "User loves hiking in the mountains" (similarity ~85%)
- ✅ Purple badge appears: "1 memory recalled"
- ✅ Console log: `💭 Using 1 memory contexts`
- ✅ Kai responds: "I remember you love hiking in the mountains!"

**Test Query 2: "What's my dog's name?"**

Expected behavior:
- ✅ Memory query fires
- ✅ Finds: "User has a dog named Max" (similarity ~90%)
- ✅ Purple badge appears: "1 memory recalled"
- ✅ Kai responds: "Your dog's name is Max!"

**Test Query 3: "What trips am I planning?"**

Expected behavior:
- ✅ Memory query fires
- ✅ Finds: "User planning trip to Japan" (similarity ~80%)
- ✅ Purple badge appears: "1 memory recalled"
- ✅ Kai responds: "You mentioned planning a trip to Japan!"

---

### **Step 3: Visual Confirmation**

#### ✅ **Purple Badge Appears**

Look for this in the chat:

```
┌─────────────────────────────────────┐
│  🧠 1 memory recalled                │ ← THIS!
├─────────────────────────────────────┤
│ I remember you love hiking in the   │
│ mountains!                           │
└─────────────────────────────────────┘
```

**Badge Details:**
- **Color**: Purple background with purple border
- **Icon**: Brain emoji 🧠 (`Icons.psychology`)
- **Text**: Shows count (1 memory, 2 memories, 3 memories, etc.)
- **Location**: Above Kai's message text
- **Only on Kai's messages**: Never on your messages

#### ✅ **Console Logs**

Check your IDE console or `flutter logs`:

```bash
flutter run
```

Expected output when memory is accessed:
```
💭 Using 1 memory contexts
```

Or if multiple memories:
```
💭 Using 3 memory contexts
```

---

### **Step 4: Firebase Console Verification**

1. **Open Firebase Console**: https://console.firebase.google.com
2. **Go to Firestore Database**
3. **Navigate to**: `/users/{userId}/personas/kai_default/memory_shards/`
4. **Check for shards**: Should see documents with:
   - `summary`: Text summary of conversation
   - `embedding`: Array of numbers (vector)
   - `timestamp`: When shard was created

5. **Go to Functions Logs**
6. **Filter by**: `memory-query`
7. **See logs like**:
   ```
   [memory-query] Query: "What do you know about my hobbies?"
   [memory-query] Found 5 results
   [memory-query] Returning top 5 matches
   ```

---

## 🚫 **Troubleshooting: Memory NOT Working**

### Problem 1: No Purple Badge Appears

**Possible Causes:**
1. ❌ Not enough conversations (need 10+ turns first)
2. ❌ Memory shards not created yet (check Firestore)
3. ❌ Low similarity scores (all results < 70%)
4. ❌ Cloud Functions not deployed
5. ❌ `useMemory=false` in sendMessage() call

**Solutions:**
```dart
// Check if memory is enabled in ai_service.dart
final memoryResult = await MemoryService.queryMemory(
  personaId: personaId,
  query: text,
  limit: 5,
);

// Add debug logging
if (memoryResult != null) {
  print('🔍 Memory results: ${memoryResult.results.length}');
  for (var r in memoryResult.results) {
    print('  - ${r.summary} (${r.similarity})');
  }
}
```

---

### Problem 2: Console Shows No Memory Logs

**Check:**
1. Make sure you're running with `flutter run` (not release mode)
2. Look for the `💭` emoji in logs
3. Check if Cloud Functions are deployed:
   ```powershell
   firebase functions:list
   ```

**Expected output:**
```
memory-query (us-central1)
memory-formation (us-central1)
```

---

### Problem 3: Firebase Shows No Memory Shards

**Possible Issues:**
1. Cloud Functions not deployed
2. Not enough conversations (need 10+ turns)
3. Conversations not saved to Firebase

**Check Firestore:**
```
/users/{userId}/personas/kai_default/conversations/
```

Should have at least 10 conversation documents.

**Manual Trigger** (if needed):
After 10 conversations, the memory-formation function should auto-trigger.
Check logs:
```
[memory-formation] Processing shard for kai_default
[memory-formation] Created shard with 10 conversations
```

---

## 📊 **Expected Behavior Summary**

### ✅ **When Memory Works:**

1. **Visual**: Purple badge on Kai's messages
2. **Console**: `💭 Using X memory contexts`
3. **Response**: Kai references past conversations naturally
4. **Firebase**: Memory shards in Firestore
5. **Firebase**: Query logs in Functions

### ❌ **When Memory Doesn't Work:**

1. **Visual**: No purple badge
2. **Console**: No `💭` logs
3. **Response**: Generic, no past context
4. **Firebase**: No memory shards
5. **Firebase**: No query logs

---

## 🧪 **Quick Test Script**

Use this conversation flow to test:

```
Day 1:
1. "Hi Kai, I'm John"
2. "I love pizza"
3. "My favorite movie is Inception"
4. "I work in tech"
5. "I have two cats"
6. "I'm learning Spanish"
7. "I live in Seattle"
8. "I enjoy photography"
9. "I play guitar"
10. "I'm 28 years old"

[Wait for memory shard formation - check Firestore]

Day 2:
11. "What's my name?"          → Should say "John" ✅
12. "What do I like to eat?"   → Should say "pizza" ✅
13. "How old am I?"            → Should say "28" ✅
14. "What are my hobbies?"     → Should mention photography/guitar ✅
15. "Where do I live?"         → Should say "Seattle" ✅
```

Each of these should show:
- 🟣 Purple badge with "1-2 memories recalled"
- 💭 Console log
- Kai accurately recalling the information

---

## 🔧 **Debug Mode: Enhanced Logging**

Want more detailed logs? Add this to `memory_service.dart`:

```dart
static Future<MemoryQueryResponse?> queryMemory({
  required String personaId,
  required String query,
  int limit = 5,
}) async {
  try {
    print('🔍 [MEMORY] Querying for: "$query"');
    print('🔍 [MEMORY] Persona: $personaId, Limit: $limit');
    
    final callable = _functions.httpsCallable('memory-query');
    final result = await callable.call({
      'personaId': personaId,
      'query': query,
      'limit': limit,
    });

    final response = MemoryQueryResponse.fromJson(result.data);
    print('✅ [MEMORY] Found ${response.results.length} results');
    
    for (var r in response.results) {
      print('  📝 ${r.summary}');
      print('     Similarity: ${(r.similarity * 100).toStringAsFixed(1)}%');
    }
    
    return response;
  } catch (e) {
    print('❌ [MEMORY] Query failed: $e');
    return null;
  }
}
```

This gives you complete visibility into the memory system!

---

## 🎯 **Success Checklist**

- [ ] 10+ conversations completed
- [ ] Memory shards visible in Firestore
- [ ] Cloud Functions deployed (`memory-query`, `memory-formation`)
- [ ] Purple badges appearing in chat
- [ ] Console shows `💭 Using X memory contexts`
- [ ] Kai references past conversations accurately
- [ ] Firebase Functions logs show query activity

If all checked ✅ → **Memory is working perfectly!** 🎉

---

**Need more help?** Check `MEMORY_QUICK_START.md` for detailed setup instructions.
