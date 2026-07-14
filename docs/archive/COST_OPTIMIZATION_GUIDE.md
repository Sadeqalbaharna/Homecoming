# Cost Optimization Guide 💰

## Current Cost Breakdown (from your stats)
- **Total**: $0.6219 per session
- **ElevenLabs TTS**: $0.6078 (97.7%) ← **PRIMARY TARGET**
- **OpenAI API**: $0.0136 (2.2%)
- **Firebase**: $0.0005¢ (0.1%)
- **Cloud Functions**: $0.0000¢ (0.0%)

## 🎯 Priority 1: Reduce TTS Costs (97.7% of spending)

### Option A: Use Cheaper TTS Alternatives
**Savings: 80-100%**

1. **Google Cloud TTS** (WaveNet voices)
   - Cost: $0.000016 per character (94% cheaper!)
   - Quality: Very good, natural sounding
   - Your current: 2,026 chars × $0.0003 = $0.6078
   - With Google: 2,026 chars × $0.000016 = $0.0324 ✅ **94% savings**

2. **Azure TTS** (Neural voices)
   - Cost: $0.000016 per character
   - Quality: Excellent, comparable to ElevenLabs
   - Same savings as Google

3. **Android Native TTS** (FREE!)
   - Cost: $0.00
   - Quality: Decent on modern devices
   - Implementation: Use `flutter_tts` package
   - ✅ **100% savings on TTS**

### Option B: Cache TTS Audio
**Savings: 50-90%**

```dart
// Add to lib/services/tts_cache_service.dart
class TTSCacheService {
  static final Map<String, String> _cache = {};
  static const int maxCacheSize = 100;
  
  static String? getCached(String text) {
    return _cache[text];
  }
  
  static void setCached(String text, String audioPath) {
    if (_cache.length >= maxCacheSize) {
      _cache.remove(_cache.keys.first); // Remove oldest
    }
    _cache[text] = audioPath;
  }
}
```

Benefits:
- Common phrases only synthesized once
- "Hello!", "How are you?", etc. cached
- Estimated savings: 50-70% on repeated messages

### Option C: TTS Toggle Switch
**Savings: User controlled**

Add a setting to enable/disable TTS:
- When off: Use text-only responses (FREE)
- When on: Use ElevenLabs (current cost)
- Let users choose based on their budget

### Option D: Use Shorter TTS Responses
**Savings: 30-50%**

Modify system prompt to prefer concise responses:
```
"Keep responses under 50 words unless explicitly asked for detail."
```

Your current: 2,026 chars / 20 messages = 101 chars per message
Optimized: ~50 chars per message = **50% TTS savings**

## 🎯 Priority 2: Optimize OpenAI Costs (2.2% of spending)

### Option A: Use GPT-4o-mini More Aggressively
**Savings: 90% on API calls**

Current prices:
- gpt-4o: $2.50/$10.00 per 1M tokens
- gpt-4o-mini: $0.15/$0.60 per 1M tokens (94% cheaper!)

Strategy:
```dart
// Use gpt-4o-mini for:
- Simple conversations
- Personality updates
- Casual chat
- Context < 4K tokens

// Reserve gpt-4o for:
- Complex reasoning
- Long context (>8K tokens)
- Creative tasks
- Memory synthesis
```

### Option B: Reduce Token Usage
**Savings: 20-40%**

1. **Shorter system prompts**
   - Current: ~500 tokens
   - Optimized: ~200 tokens
   - Savings: 300 tokens per call

2. **Limit conversation history**
   ```dart
   // Keep only last 10 messages instead of all
   final recentHistory = chatHistory.take(10).toList();
   ```

3. **Use embeddings cache**
   - Don't re-embed same text
   - Cache commonly used embeddings

### Option C: Batch API (50% cheaper)
OpenAI Batch API is 50% cheaper but has 24h delay.
Good for:
- Memory processing (not time-sensitive)
- Fact extraction from old conversations
- Embedding generation for archives

## 🎯 Priority 3: Firebase Optimization (0.1% of spending)

Already very cheap, but you can:

1. **Batch writes**
   ```dart
   // Instead of 10 individual writes:
   await db.set('turn1', data1);
   await db.set('turn2', data2);
   // ... 10 writes
   
   // Use batch:
   await db.update({
     'turn1': data1,
     'turn2': data2,
     // ... all at once
   }); // 1 write operation
   ```

2. **Read from cache**
   ```dart
   // Use local cache for personality data
   // Only sync to Firebase every 5 updates
   ```

## 🎯 Priority 4: Cloud Functions (0.0% of spending)
Already optimized! No action needed.

## 📊 Recommended Implementation Plan

### Phase 1: Quick Wins (Immediate - 1 day)
**Target: 50% cost reduction**

1. ✅ **Add TTS toggle** - Let users disable voice
   - Effort: 1 hour
   - Savings: Up to 97.7% (user controlled)

2. ✅ **Switch to gpt-4o-mini by default**
   - Effort: 30 minutes
   - Savings: 90% on OpenAI API calls (2% of total)

3. ✅ **Cache common TTS phrases**
   - Effort: 2 hours
   - Savings: 30-50% on TTS

**Total Phase 1 Savings: ~$0.30 per session (48%)**

### Phase 2: Medium Impact (1-3 days)
**Target: 80% cost reduction**

4. ✅ **Implement Google Cloud TTS**
   - Effort: 4 hours
   - Savings: 94% on TTS (94% of total costs)

5. ✅ **Optimize prompts for brevity**
   - Effort: 2 hours
   - Savings: 20-30% on both APIs

6. ✅ **Add conversation history limit**
   - Effort: 1 hour
   - Savings: 10-20% on OpenAI

**Total Phase 2 Savings: ~$0.50 per session (80%)**

### Phase 3: Maximum Optimization (1 week)
**Target: 95% cost reduction**

7. ✅ **Android Native TTS fallback**
   - Effort: 1 day
   - Savings: 100% on TTS (when enabled)

8. ✅ **Implement OpenAI Batch API**
   - Effort: 2 days
   - Savings: 50% on non-realtime tasks

9. ✅ **Advanced caching system**
   - Effort: 2 days
   - Savings: 40-60% overall

**Total Phase 3 Savings: ~$0.59 per session (95%)**

## 💡 Cost Comparison Examples

### Current Usage (20 API calls, 2,026 TTS chars):
```
ElevenLabs:  $0.6078
OpenAI:      $0.0136
Firebase:    $0.0005
Total:       $0.6219
```

### After Phase 1 (Toggle + Mini + Cache):
```
ElevenLabs:  $0.3039 (50% cached)
OpenAI:      $0.0014 (gpt-4o-mini)
Firebase:    $0.0005
Total:       $0.3058 (51% savings) ✅
```

### After Phase 2 (Google TTS + Optimization):
```
Google TTS:  $0.0324 (94% cheaper)
OpenAI:      $0.0010 (mini + shorter prompts)
Firebase:    $0.0003 (batched)
Total:       $0.0337 (95% savings) ✅✅✅
```

### After Phase 3 (Native TTS + Batch):
```
Native TTS:  $0.0000 (FREE)
OpenAI:      $0.0007 (batch API)
Firebase:    $0.0003
Total:       $0.0010 (99.8% savings) ✅✅✅✅
```

## 🎯 My Recommendation: Start with Phase 1

**Implement these 3 changes NOW:**

1. **TTS Toggle Switch**
   - Add checkbox in settings: "Enable voice responses"
   - Default: OFF
   - User can turn on when they want to hear Kai's voice
   - Instant 97.7% savings when disabled

2. **Switch to gpt-4o-mini**
   - Change default model from `gpt-4o` to `gpt-4o-mini`
   - Keep gpt-4o for complex tasks only
   - 90% savings on API calls

3. **TTS Cache**
   - Cache last 50 TTS responses
   - Reuse audio for repeated messages
   - 30-50% savings on TTS

**Total time: 3-4 hours**
**Total savings: ~50% immediately**
**New cost: ~$0.31 per session**

Would you like me to implement these Phase 1 optimizations now? I can:
1. Add the TTS toggle switch
2. Switch to gpt-4o-mini by default
3. Implement TTS caching

Just say "yes" and I'll get started! 🚀

---

## 📈 Monitoring Costs

After implementing optimizations, track with:
```dart
// Already implemented in UsageStatsScreen!
- Current Session costs
- Lifetime costs
- Cost per service breakdown
- Tokens/Characters used
```

## 🎁 Bonus: Free Tier Limits

Most services have free tiers:
- **OpenAI**: $5 free credit for new users
- **Google Cloud TTS**: 4M chars/month free
- **Azure TTS**: 500K chars/month free
- **Firebase**: 100K reads, 20K writes/day free

**Your current usage would fit in Google Cloud TTS free tier!** 🎉

---

**Questions?** Let me know which phase you want to implement!
