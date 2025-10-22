# Memory Intelligence - Quick Start Guide

## 🚀 What Changed in v0.7.4+48?

### You'll See:
1. **Memory Chips** below Kai's replies showing which memories were used
2. **Pin/Dismiss buttons** on each memory (logging only for now)
3. **Constraints** in every prompt (kg, Bahrain timezone, projects)

### You Won't See (Yet):
- Pin to facts backend (Week 2)
- Memory drawer UI (Week 2)
- Confidence indicators (Week 2)

---

## 📸 Visual Guide

### Before:
```
Kai: "I don't have information about your hobbies."

💜 2 memories recalled
```

### After:
```
Kai: "You enjoy gaming, especially Digimon!"

🧠 Used 1 memory:
┌─────────────────────────────────────┐
│ Gaming/Digimon hobby...       38%  │
│ [📌 Pin]  [✕ Dismiss]              │
└─────────────────────────────────────┘
```

---

## 🧪 How to Test

### Test 1: Memory Recall
1. Ask: "What are my hobbies?"
2. Look for memory chip with "gaming/Digimon"
3. Should show 38% similarity
4. Tap [📌 Pin] - see console log
5. Tap [✕ Dismiss] - see console log

### Test 2: Units
1. Ask: "How much do I weigh?"
2. Kai should respond in **kg** (not lbs)
3. Thanks to constraints block!

### Test 3: Projects
1. Ask: "What is Tavern?"
2. Kai should know it's a brunch content project
3. Should recall memories about Friday brunch

### Test 4: Debug Button
1. Expand debug info
2. Check `similarity_threshold: 0.35`
3. See memory_details with included: true/false
4. Compare with memory chips (only included shown)

---

## 🎯 What to Look For

### ✅ Success Indicators:
- Memory chips appear below Kai's reply
- Similarity scores shown (35-100%)
- Pin/Dismiss buttons visible and clickable
- Console logs when buttons tapped
- Kai uses kg, not lbs
- Kai knows your timezone is Bahrain

### ❌ Failure Indicators:
- No memory chips (means no memories ≥35%)
- "No debug data" text (means debugInfo null)
- Kai uses lbs instead of kg
- No project context

---

## 🐛 Troubleshooting

**Q: No memory chips showing?**
- Check debug button → memory_query → memories_used
- If 0, then no memories met 35% threshold
- Try asking about something you've talked about before

**Q: Pin/Dismiss do nothing?**
- They're logging only (backend not implemented)
- Check console for: `📌 Pin memory:` or `❌ Dismiss memory:`
- Backend coming in Week 2

**Q: Kai still uses lbs?**
- Check system prompt in debug info
- Should include "Units: Metric system (kg)"
- If missing, constraints block didn't load

---

## 📊 Golden Tests

### Run Tests:
```bash
cd c:\code\homecoming_app
flutter test test/memory_golden_test_runner.dart
```

### Expected Output:
```
🧪 Running Memory Golden Tests (v0.7.4+48)...

✅ PASS: Should recall metric unit preference
✅ PASS: Should recall timezone preference
✅ PASS: Should recall gaming hobby at 35% threshold
✅ PASS: Should match hobbies query with different phrasing
✅ PASS: Should know about Homecoming project
✅ PASS: Should know about Tavern brunch project
✅ PASS: Should know about Lionheart fitness project
✅ PASS: Should know Sadeq is the developer
❌ FAIL: Should NOT find memories for weather (negative test)
❌ FAIL: Should NOT find memories for jokes (negative test)

📊 MEMORY GOLDEN TEST SUMMARY
Version: 0.7.4+48
Total Tests: 10
✅ Passed: 8
❌ Failed: 2
📈 Pass Rate: 80.0%
```

### If Tests Fail:
1. Check Firebase connection (tests need live DB)
2. Verify memories exist for test queries
3. Check threshold values (35%, 50%, 70%)
4. Review memory_service.dart for bugs

---

## 🎨 UI Components

### Memory Chips:
- **Location:** Below Kai's reply, above Play voice
- **Color:** Purple theme (#9C27B0)
- **Size:** Max width 280px, wraps to multiple lines
- **Actions:** Pin (📌) and Dismiss (✕)

### Debug Button:
- **Location:** Below Play voice button
- **Color:** Cyan theme (#00BCD4)
- **Expandable:** Tap to show full debug info
- **Contents:** 8 sections (memory, personality, mood, etc.)

### Layout Order:
1. Kai's reply text
2. 🧠 Memory chips (if memories used)
3. ▶ Play voice (if TTS available)
4. [Debug Info ▼] (always shown)

---

## 💡 Pro Tips

### Get Better Memory Recall:
1. **Be specific:** "gaming hobby" > "interests"
2. **Use context:** "Tavern brunch" > "my project"
3. **Repeat info:** Mentioned 2-3x = stronger embedding

### Use Debug Button:
1. Check `memories_found` vs `memories_used`
2. See similarity scores for all memories
3. Green cards = used (≥35%), Red cards = filtered (<35%)
4. Copy system_prompt to see what Kai sees

### Test Golden Set:
1. Add your own test cases to `memory_golden_test.dart`
2. Run before making memory changes
3. Prevents breaking existing functionality
4. Track pass rate over time (aim for 80%+)

---

## 🔧 Developer Notes

### Adding New Test Cases:
```dart
MemoryTest(
  query: "What's my favorite food?",
  expectedKeywords: ["pizza", "italian"],
  minSimilarity: 0.5,
  description: "Should recall food preferences",
),
```

### Implementing Pin Backend:
```dart
Future<void> pinMemoryToFacts(String personaId, String memoryId) {
  // 1. Extract memory from Firestore
  // 2. Save to /memory/facts/{personaId}/{uuid()}
  // 3. Set metadata: {ttl: null, confidence: 1.0, source: 'user_pinned'}
  // 4. Show success toast
}
```

### Implementing Dismiss Backend:
```dart
Future<void> dismissMemory(String personaId, String memoryId) {
  // 1. Load memory shard
  // 2. Update metadata: {dismissed: true, dismissed_at: timestamp}
  // 3. Lower confidence by 0.3
  // 4. Optionally: exclude from future queries
}
```

---

## 📚 Related Docs

- `DEBUG_BUTTON_FINAL_v0.7.4+46.md` - Debug button implementation
- `MEMORY_THRESHOLD_35_v0.7.4+47.md` - Threshold adjustment rationale
- `MEMORY_INTELLIGENCE_WEEK1_v0.7.4+48.md` - Full technical specification
- `KAI_RESPONSE_FLOW.md` - How AI service processes messages

---

## 🎉 Next Release (Week 2)

Coming in v0.7.5:
- ✅ Pin to facts (backend + UI feedback)
- ✅ Dismiss memory (backend + confidence update)
- ✅ Memory drawer screen (view/edit all memories)
- ✅ Confidence indicators (sparklines, fade)
- ✅ Toast notifications for user actions

---

**Questions? Check the debug button or ask Kai about "memory system"!** 🧠
