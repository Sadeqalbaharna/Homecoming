# Debug Button Feature - v0.7.4+43

## Overview
Added a comprehensive debug button to each chat reply that provides complete transparency into Kai's AI decision-making process.

## Commit
- **Hash**: 024127b
- **Message**: "Add debug button to show AI decision-making details (memory, personality, mood, affinity) - v0.7.4+43"
- **Date**: 2025-01-XX
- **Files Changed**: 3 files, 228 insertions(+), 7 deletions(-)

## What Was Added

### 1. Debug Data Collection (`lib/services/ai_service.dart`)
Enhanced `ChatResponse` class and `sendMessage` method to capture comprehensive debug information:

```dart
class ChatResponse {
  final String text;
  final List<int>? audioPcm;
  final Map<String, dynamic>? debugInfo;  // NEW
  
  ChatResponse(this.text, {this.audioPcm, this.debugInfo});
}
```

**Debug Info Structure**:
```dart
debugInfo = {
  'memory_query': {
    'enabled': bool,
    'query_text': String,
    'memories_found': int,
    'memories_used': int,
    'memory_details': [
      {
        'id': String,
        'summary': String,
        'similarity': double,  // 0.0 to 1.0
        'shard_ref': String,
        'included': bool,      // true if similarity > 0.5
      }
    ],
    'memory_context': String,
    'similarity_threshold': 0.5,
  },
  'personality': {
    'current': Map<String, int>,
    'mbti': String,
    'delta_requested': Map<String, int>,    // What AI wanted
    'delta_applied': Map<String, int>,      // What actually changed
    'new_values': Map<String, int>,
  },
  'mood': {
    'current': Map<String, int>,
    'delta_requested': Map<String, int>,
    'delta_applied': Map<String, int>,
    'new_values': Map<String, int>,
  },
  'affinity': {
    'current_intimacy': int,
    'current_physicality': int,
    'adapt_user': bool,
  },
  'system_prompt': String,
  'conversation_history_turns': int,
  'tags': List<String>,
  'model': String,
}
```

### 2. Debug Button Widget (`lib/widgets/debug_button.dart`)
Created a new reusable widget (243 lines):

**Features**:
- ✅ **Expandable**: Starts collapsed, expands to show full details
- ✅ **Scrollable**: Max height 400px with scroll for long content
- ✅ **Color-Coded Memory Display**:
  - 🟢 **Green**: Memories with similarity > 50% (USED in response)
  - 🔴 **Red**: Memories with similarity < 50% (FILTERED OUT)
- ✅ **Organized Sections**:
  - Memory Query
  - Personality
  - Mood
  - Affinity
  - Other (model, tags, history turns)
  - System Prompt (expandable, selectable text)
- ✅ **Cyan Theme**: Matches debug aesthetic

### 3. Mobile UI Integration (`lib/main_mobile.dart`)
Added debug button to chat bubble UI:

**State Management**:
```dart
Map<String, dynamic>? _debugInfo;  // Tracks current response debug data

// Capture on response
_debugInfo = resp.debugInfo;

// Pass to bubble
_MobileChatBubble(..., debugInfo: _debugInfo)
```

**UI Placement**:
Located after voice controls (Play/Pause buttons) in chat bubble:
```
[Play] [Pause] [🔍 Debug]
```

## How It Works

### Memory Selection Visibility
Shows exactly which memories were:
1. **Retrieved** from Cloud Functions
2. **Similarity score** for each memory (as percentage)
3. **Included or excluded** based on 50% threshold
4. **Used in response** (green badge: "USED")

**Example Display**:
```
Memory Details:
┌─────────────────────────────────────┐
│ 🟢 Similarity: 67.3% [USED]         │
│ Summary: User mentioned liking cats │
│ ID: mem_abc123                      │
│ Shard: conversations/conv1/shard0   │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ 🔴 Similarity: 42.1%                │
│ Summary: User's favorite color      │
│ ID: mem_def456                      │
│ Shard: conversations/conv2/shard1   │
└─────────────────────────────────────┘
```

### Personality/Mood Delta Tracking
Shows the difference between what AI **requested** vs what **actually happened**:

**Example**:
```
Personality:
  Current: {extraversion: 65, openness: 80, ...}
  
  Delta Requested: {extraversion: +5}  ← AI wanted this
  Delta Applied: {extraversion: +3}    ← Actually applied (clamped)
  
  New Values: {extraversion: 68, openness: 80, ...}
```

This reveals when personality changes are:
- ✅ Applied as requested
- ⚠️ Clamped due to 0-100 limits
- ❌ Not applied at all

### System Prompt Inspection
Full prompt sent to OpenAI, including:
- Personality description
- Current mood
- Memory context (retrieved memories)
- Conversation history
- User relationship info

User can **select and copy** the entire prompt for analysis.

## Use Cases

### 1. Debugging Memory Issues
**Problem**: "Why doesn't Kai remember X?"

**Solution**: Click debug button and check:
- Was memory search enabled?
- What query text was used?
- Were any memories found?
- What were the similarity scores?
- Did any memories pass the 50% threshold?

### 2. Understanding Personality Changes
**Problem**: "Why is Kai acting differently?"

**Solution**: Click debug button and check:
- What personality deltas were requested?
- Were they applied or clamped?
- What's the current personality state?
- Is MBTI affecting behavior?

### 3. Mood Tracking
**Problem**: "Why is Kai in a bad mood?"

**Solution**: Check mood section:
- Current mood values
- Recent mood changes
- What triggered the change

### 4. Testing AI Behavior
**Developer use**: Verify that:
- Memory system is working correctly
- Personality/mood changes are applied as expected
- System prompt includes correct context
- OpenAI model received proper instructions

## Visual Design

**Button Appearance** (Collapsed):
```
┌──────────────────┐
│ 🔍 Debug Info ▼ │
└──────────────────┘
```

**Button Appearance** (Expanded):
```
┌──────────────────┐
│ 🔍 Debug Info ▲ │
├──────────────────┤
│                  │
│  Memory Query    │
│  ├─ enabled: true│
│  ├─ memories: 2  │
│  └─ used: 1      │
│                  │
│  Memory Details  │
│  ┌────────────┐  │
│  │🟢 67.3%    │  │
│  │  [USED]    │  │
│  │  Summary...│  │
│  └────────────┘  │
│                  │
│  Personality     │
│  ├─ current: {...│
│  ├─ requested:{..│
│  └─ applied: {.. │
│                  │
│  [... more]      │
│                  │
└──────────────────┘
```

## Testing Checklist

### Basic Functionality
- [ ] Debug button appears next to Play/Pause in chat bubble
- [ ] Button is cyan/teal colored
- [ ] Clicking button expands/collapses debug info
- [ ] Content scrolls if longer than 400px

### Memory Section
- [ ] Shows whether memory search was enabled
- [ ] Displays query text used
- [ ] Lists all memories found
- [ ] Green background for memories > 50% similarity
- [ ] Red background for memories < 50% similarity
- [ ] Similarity percentage displayed clearly
- [ ] "USED" badge appears on included memories

### Personality Section
- [ ] Shows current personality values
- [ ] Shows MBTI type
- [ ] Displays delta_requested vs delta_applied
- [ ] Shows new personality values after change

### Mood Section
- [ ] Shows current mood values
- [ ] Displays delta_requested vs delta_applied
- [ ] Shows new mood values after change

### Affinity Section
- [ ] Shows current intimacy level
- [ ] Shows current physicality level
- [ ] Shows adapt_user flag

### System Prompt
- [ ] Expandable tile for system prompt
- [ ] Full prompt text displayed
- [ ] Text is selectable (can copy)

### Edge Cases
- [ ] Response with no memories (memory section empty/disabled)
- [ ] Response with no personality changes (deltas empty)
- [ ] Response with clamped personality (requested ≠ applied)
- [ ] Very long debug info (scrolling works)

## Technical Implementation

### Key Files Modified
1. **lib/services/ai_service.dart** (Enhanced)
   - Added `debugInfo` field to `ChatResponse`
   - Enhanced memory query to capture `memoryDetails` list
   - Built comprehensive `debugInfo` structure after AI response
   - Lines added: ~50

2. **lib/main_mobile.dart** (Enhanced)
   - Imported `DebugButton` widget
   - Added `_debugInfo` state variable
   - Captured `debugInfo` from AI response
   - Passed `debugInfo` to `_MobileChatBubble`
   - Added conditional `DebugButton` rendering
   - Lines changed: ~15

3. **lib/widgets/debug_button.dart** (NEW)
   - Full `StatefulWidget` implementation
   - 243 lines of UI code
   - Methods:
     - `_buildSection`: Organizes debug categories
     - `_buildKeyValue`: Renders key-value pairs
     - `_formatValue`: Pretty-prints maps/lists
   - Special rendering for `memory_details` with color coding

### Dependencies
- Flutter Material Design
- Existing `AIService` class
- No new packages required

## Known Limitations

### Current Scope
- ✅ Available in **mobile UI** (main_mobile.dart)
- ❌ NOT yet in **desktop overlay** (main_overlay.dart)
- ✅ Shows data for **AI responses only**
- ❌ No data for **user messages** (not applicable)

### Future Enhancements
1. **Add to Desktop Overlay**: Same debug button in overlay UI
2. **Export Debug Data**: Button to copy full JSON
3. **Debug History**: Save debug logs for multiple messages
4. **Visual Charts**: Graph personality/mood changes over time
5. **Memory Timeline**: Show when memories were created/used
6. **Prompt Comparison**: Compare prompts across different responses

## Version History
- **v0.7.4+42**: Fixed memory threshold (60% → 50%)
- **v0.7.4+43**: Added debug button feature ← **YOU ARE HERE**

## Next Steps
1. ✅ Code complete and committed (024127b)
2. ⏳ GitHub Action building v0.7.4+43
3. ⏳ Test on mobile device after build
4. ⏳ Add to desktop overlay UI (optional)
5. ⏳ User feedback and refinements

## Troubleshooting

### Debug Button Not Showing
**Possible Causes**:
- AI response didn't include `debugInfo` (check AI service logs)
- State variable `_debugInfo` is null
- Widget not imported in main_mobile.dart

**Solution**: Check logs for "debugInfo: {...}" in AI response

### Memory Section Empty
**Possible Causes**:
- Memory search disabled (check settings)
- No memories matched query
- Cloud Function error (check Firebase logs)

**Solution**: Click debug button to see `enabled: false` or `memories_found: 0`

### Similarity Scores Seem Wrong
**Possible Causes**:
- Embedding model changed
- Query text not optimal
- Memories too old/irrelevant

**Solution**: Debug button shows exact scores - review memory summaries

### Personality Changes Not Applied
**Possible Causes**:
- Clamped to 0-100 range (check `delta_applied`)
- AI didn't request changes (check `delta_requested`)
- Personality locking enabled (not implemented yet)

**Solution**: Compare `delta_requested` vs `delta_applied` in debug

## Developer Notes

### Code Quality
- ✅ No breaking changes to existing code
- ✅ Optional `debugInfo` field (backwards compatible)
- ✅ Clean separation of concerns (widget in separate file)
- ✅ Follows Flutter best practices

### Performance
- ✅ Debug data only collected when AI responds
- ✅ No performance impact when debug button not used
- ✅ Scrollable container prevents UI overflow
- ✅ Lazy rendering (only visible when expanded)

### Maintainability
- ✅ Well-documented code
- ✅ Reusable widget (can add to desktop overlay)
- ✅ Easy to extend (add new debug sections)
- ✅ Clear naming conventions

## User Documentation

### How to Use Debug Button

1. **Send a message** to Kai
2. **Wait for response** to appear in chat bubble
3. **Look for debug button** (🔍) next to Play/Pause buttons
4. **Click to expand** and see AI decision details
5. **Review sections** to understand response:
   - **Green memories** = used in response
   - **Red memories** = found but not used
   - **Personality/Mood** = how Kai's state changed
   - **System Prompt** = exact prompt sent to AI
6. **Click again** to collapse

### Interpreting the Data

**Memory Similarity Scores**:
- **80-100%**: Very relevant (strong match)
- **50-79%**: Relevant (will be used)
- **0-49%**: Not relevant enough (filtered out)

**Personality Delta**:
- **Requested**: What AI wanted to change
- **Applied**: What actually changed
- If different, personality was clamped to 0-100 range

**System Prompt**:
- Shows exactly what OpenAI saw
- Includes: personality, mood, memories, history
- Can copy for analysis

## Conclusion

The debug button provides **complete transparency** into Kai's AI decision-making process. Users can now see:
- ✅ Which memories were selected and why
- ✅ How personality/mood influenced the response
- ✅ What context was provided to the AI
- ✅ Why certain memories were included/excluded

This enables:
- 🔍 **Debugging**: Find issues with memory/personality
- 📊 **Analysis**: Understand AI behavior patterns
- 🎯 **Optimization**: Fine-tune thresholds and prompts
- 🤝 **Transparency**: Build user trust through visibility

**Status**: Feature complete, ready for testing! 🎉
