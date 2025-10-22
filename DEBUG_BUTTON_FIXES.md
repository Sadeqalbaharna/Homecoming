# Debug Button Build Fixes - v0.7.4+43

## Build Errors Fixed

### Error 1: Missing `debugInfo` parameter in `_MobileChatBubble` widget
**Error Message**:
```
lib/main_mobile.dart:979:27: Error: The getter 'debugInfo' isn't defined for the class '_MobileChatBubble'.
```

**Fix (Commit 5504cdb)**:
- Added `final Map<String, dynamic>? debugInfo;` field to `_MobileChatBubble` class
- Added `this.debugInfo,` to constructor as optional parameter
- Added `debugInfo: _debugInfo,` when instantiating the widget

**Files Modified**: `lib/main_mobile.dart`

---

### Error 2: Missing `_debugInfo` state variable in `_MobileKaiState`
**Error Message**:
```
lib/main_mobile.dart:647:32: Error: The getter '_debugInfo' isn't defined for the class '_MobileKaiState'.
```

**Fix (Commit 9e9c4bf)**:
- Added `Map<String, dynamic>? _debugInfo;` state variable to `_MobileKaiState` class
- Added `_debugInfo = resp.debugInfo;` to capture debug info from AI response
- Added `debugInfo` field to `ChatResponse` class in ai_service.dart
- Built comprehensive `debugInfo` structure before returning ChatResponse

**Files Modified**: 
- `lib/main_mobile.dart`
- `lib/services/ai_service.dart`

---

## Changes Summary

### `lib/main_mobile.dart`
1. **Added state variable** (line ~150):
   ```dart
   Map<String, dynamic>? _debugInfo; // NEW: Track debug info from AI response
   ```

2. **Capture debug info from response** (line ~336):
   ```dart
   setState(() {
     _reply = resp.reply.isEmpty ? "(no reply)" : resp.reply;
     _memoriesUsed = resp.memoriesUsed;
     _debugInfo = resp.debugInfo; // NEW: Track debug info
   });
   ```

3. **Pass to widget** (line ~648):
   ```dart
   _MobileChatBubble(
     // ... other parameters
     debugInfo: _debugInfo, // NEW: Pass debug info
   )
   ```

4. **Added widget parameter** (line ~735):
   ```dart
   class _MobileChatBubble extends StatelessWidget {
     // ... other fields
     final Map<String, dynamic>? debugInfo; // NEW: Debug information
     
     const _MobileChatBubble({
       // ... other parameters
       this.debugInfo, // NEW: Optional debug info
     });
   }
   ```

### `lib/services/ai_service.dart`
1. **Added field to ChatResponse class** (line ~88):
   ```dart
   class ChatResponse {
     // ... other fields
     final Map<String, dynamic>? debugInfo; // NEW: Debug information
     
     ChatResponse({
       // ... other parameters
       this.debugInfo, // NEW: Optional debug info
     });
   }
   ```

2. **Capture memoryResult for debugging** (line ~459):
   ```dart
   dynamic memoryResult; // Capture for debug info
   if (useMemory) {
     memoryResult = await MemoryService.queryMemory(...);
     // ... rest of memory logic
   }
   ```

3. **Build comprehensive debugInfo structure** (line ~569-617):
   ```dart
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
         'included': r.similarity > 0.5,
       }).toList() ?? [],
       'memory_context': memoryContext,
       'similarity_threshold': 0.5,
     },
     'personality': {
       'current': personality,
       'mbti': mbti,
       'delta_requested': personalityDelta,
       'delta_applied': Map.fromEntries(
         actualDeltas.entries.where((e) => 
           PersonalityTraits.personality.contains(e.key))
       ),
       'new_values': newPersonality,
     },
     'mood': {
       'current': mood,
       'delta_requested': moodDelta,
       'delta_applied': Map.fromEntries(
         actualDeltas.entries.where((e) => 
           PersonalityTraits.mood.contains(e.key))
       ),
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
   ```

4. **Pass debugInfo to ChatResponse** (line ~619):
   ```dart
   return ChatResponse(
     // ... other parameters
     debugInfo: debugInfo, // NEW: Pass debug info
   );
   ```

---

## Debug Info Structure

The `debugInfo` map contains the following sections:

### 1. Memory Query
- `enabled`: Whether memory search was active
- `query_text`: The user's input text used for memory search
- `memories_found`: Total number of memories retrieved
- `memories_used`: Number of memories that passed the threshold
- `memory_details`: Array of detailed memory info:
  - `id`: Memory document ID
  - `summary`: Memory summary text
  - `similarity`: Cosine similarity score (0.0 to 1.0)
  - `shard_ref`: Firestore reference to the shard
  - `included`: Boolean indicating if similarity > 0.5
- `memory_context`: Full memory context string sent to AI
- `similarity_threshold`: The threshold value (0.5)

### 2. Personality
- `current`: Current personality values before response
- `mbti`: Current MBTI type
- `delta_requested`: What deltas the AI wanted to apply
- `delta_applied`: What deltas were actually applied (after clamping)
- `new_values`: New personality values after response

### 3. Mood
- `current`: Current mood values before response
- `delta_requested`: What mood deltas the AI wanted
- `delta_applied`: What mood deltas were actually applied
- `new_values`: New mood values after response

### 4. Affinity
- `current_intimacy`: Current intimacy level
- `current_physicality`: Current physicality level
- `adapt_user`: Whether user adaptation is enabled

### 5. Other
- `system_prompt`: Full system prompt sent to OpenAI
- `conversation_history_turns`: Number of turns in conversation history
- `tags`: Tags extracted from the response
- `model`: OpenAI model used (e.g., 'gpt-4o')

---

## Commits

1. **024127b** - "Add debug button to show AI decision-making details (memory, personality, mood, affinity) - v0.7.4+43"
   - Initial debug button implementation
   - Created DebugButton widget

2. **5504cdb** - "Fix: Add missing debugInfo parameter to _MobileChatBubble widget"
   - Fixed first build error
   - Added debugInfo parameter to widget

3. **9e9c4bf** - "Fix: Add debugInfo field to ChatResponse and build comprehensive debug data"
   - Fixed second build error
   - Added _debugInfo state variable
   - Implemented complete debugInfo structure in AI service
   - Captured memoryResult for debug details

---

## Testing Status

✅ **Code complete** - All fixes committed
⏳ **Build in progress** - GitHub Actions building v0.7.4+43
⏳ **Testing pending** - Waiting for build to complete

---

## What's Next

1. **Wait for build** to complete on GitHub Actions
2. **Install from Firebase App Distribution**
3. **Test debug button**:
   - Send a message to Kai
   - Click debug button (🔍)
   - Verify all sections display correctly:
     - Memory query with green/red color coding
     - Personality deltas (requested vs applied)
     - Mood deltas
     - Affinity levels
     - System prompt
4. **Verify edge cases**:
   - Response with no memories
   - Response with high similarity memories (>80%)
   - Response with low similarity memories (<50%)
   - Personality deltas that get clamped

---

## Files Changed

- `lib/main_mobile.dart`: +5 insertions, -2 deletions
- `lib/services/ai_service.dart`: +49 insertions, -16 deletions
- `lib/widgets/debug_button.dart`: +243 insertions (new file)
- `pubspec.yaml`: version bump to 0.7.4+43

**Total**: 3 commits, 297 insertions, 18 deletions

---

## Date
October 22, 2025
