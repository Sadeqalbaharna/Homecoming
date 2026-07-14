# TTS Service Migration Guide 🔄

## Current Status
- **Active Service**: ElevenLabs
- **Cost**: $0.30 per 1K characters
- **Implementation**: `lib/services/ai_service.dart` - `synthesizeTTS()` method
- **Voice ID**: Stored in `elevenlabsVoiceId` constant

## Migration Strategy

### ✅ Design Principles
The TTS integration is designed to be **service-agnostic**:

1. **Single point of integration**: All TTS calls go through `AIService.synthesizeTTS()`
2. **Abstracted implementation**: Change only the API endpoint, not the app logic
3. **Fallback support**: Can add multiple providers with failover
4. **Cost tracking**: Already integrated with `UsageTrackingService`

### 🔄 When to Migrate
Migrate to a different TTS service when:
- ✅ You need to reduce costs (84-100% savings available)
- ✅ You want to try different voice quality
- ✅ Free tier limitations become an issue
- ✅ You need specific features (emotion control, faster synthesis, etc.)

### ⏱️ Migration Effort
**Time required**: 2-4 hours depending on service

**Changes needed**:
1. Update API endpoint in `synthesizeTTS()` method
2. Adjust request format (headers + body)
3. Update voice ID to new service's cloned voice
4. Update cost tracking rates
5. Test audio quality

**Files to modify**:
- `lib/services/ai_service.dart` (~20 lines)
- `lib/services/usage_tracking_service.dart` (~2 lines)

### 📋 Quick Migration Checklist

**Before migration**:
- [ ] Clone Kai's voice on new service
- [ ] Get API key for new service
- [ ] Test voice quality in their playground
- [ ] Note voice ID from cloning process

**During migration** (20 minutes):
- [ ] Update API endpoint URL
- [ ] Update headers (authentication format)
- [ ] Update request body format
- [ ] Update response parsing
- [ ] Update cost rate in usage tracking

**After migration** (1 hour):
- [ ] Test synthesis with sample text
- [ ] Verify audio plays correctly
- [ ] Check cost tracking accuracy
- [ ] Compare voice quality to ElevenLabs
- [ ] Deploy and test on device

### 🎯 Service Swap Templates

#### PlayHT (84% cheaper)
```dart
// In synthesizeTTS() method:
final response = await http.post(
  Uri.parse('https://api.play.ht/api/v2/tts'),
  headers: {
    'AUTHORIZATION': 'Bearer $playhTApiKey',
    'X-USER-ID': playhTUserId,
    'Content-Type': 'application/json',
  },
  body: jsonEncode({
    'text': text,
    'voice': playhTVoiceId, // Your cloned voice
    'quality': 'premium',
    'output_format': 'mp3',
  }),
);

// In usage_tracking_service.dart:
costPerUnit: 0.048, // vs 0.30 for ElevenLabs
```

#### Resemble.AI (90% cheaper)
```dart
// In synthesizeTTS() method:
final response = await http.post(
  Uri.parse('https://app.resemble.ai/api/v2/projects/$projectId/clips'),
  headers: {
    'Authorization': 'Token $resembleApiKey',
    'Content-Type': 'application/json',
  },
  body: jsonEncode({
    'body': text,
    'voice_uuid': resembleVoiceId, // Your cloned voice
    'is_async': false,
  }),
);

// In usage_tracking_service.dart:
costPerUnit: 0.03, // vs 0.30 for ElevenLabs
```

#### Coqui TTS (100% free)
```dart
// In synthesizeTTS() method:
final response = await http.post(
  Uri.parse('https://YOUR_CLOUD_RUN_URL/tts'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'text': text,
    'speaker_wav': 'kai_voice.wav', // Your 6-sec sample
  }),
);

// In usage_tracking_service.dart:
costPerUnit: 0.0, // FREE!
```

### 🔐 API Key Management
Store new API keys in Firebase:
```
elevenlabs_key → playht_key (or resemble_key, etc.)
elevenlabs_voice_id → playht_voice_id
```

No app code changes needed - just update Firestore values!

### 📊 A/B Testing Strategy
Can run both services simultaneously:

```dart
Future<Uint8List> synthesizeTTS(String text, {bool useHD = false}) async {
  if (useHD) {
    // Use ElevenLabs for premium quality
    return _synthesizeElevenLabs(text);
  } else {
    // Use cheaper alternative for normal quality
    return _synthesizePlayHT(text);
  }
}
```

### 🎁 Benefits of Waiting
**Why it's smart to migrate later**:
1. ✅ **Current focus on features** - Don't get distracted by optimization
2. ✅ **More data** - See actual usage patterns first
3. ✅ **Test ElevenLabs quality** - Establish baseline for comparison
4. ✅ **Free tier** - ElevenLabs gives 10K chars/month free
5. ✅ **Market changes** - Prices drop, new services emerge

**When you're ready to migrate**:
- Come back to `VOICE_CLONING_ALTERNATIVES.md`
- Pick your service
- Run the migration checklist
- 2-4 hours and you're done!

### 💰 Cost Impact Timeline
**Current usage** (20 API calls, 2,026 chars):
- First month: ~$0.60 (under free tier? Check your plan)
- Growth to 100 calls: ~$3.00/session
- Growth to 1000 calls: ~$30.00/session

**When to migrate**:
- If exceeding $5-10/month → Consider PlayHT (84% savings)
- If exceeding $50/month → Strongly consider Coqui (100% savings)
- If need emotion control → Consider Resemble.AI (90% savings + features)

### 📝 Migration Decision Tree
```
Are costs becoming an issue?
├─ No → Stay with ElevenLabs ✅
└─ Yes
   ├─ Need best quality? → PlayHT (84% savings, easy migration)
   ├─ Need best price? → Coqui (100% savings, harder migration)
   └─ Need emotion control? → Resemble.AI (90% savings, medium migration)
```

## 🚀 Bottom Line
**You're absolutely right to focus on features first!**

TTS migration is:
- ✅ Easy to do later (2-4 hours)
- ✅ Won't break anything (just change API)
- ✅ Can be tested safely (A/B approach)
- ✅ Can be done anytime (no urgency)

**For now**:
- Keep building features
- Track costs in UsageStatsScreen
- Revisit when costs exceed comfort level

**This doc will be here when you're ready!** 📖

---

*Last updated: October 21, 2025*
*Current TTS: ElevenLabs*
*Migration templates ready for: PlayHT, Resemble.AI, Coqui TTS*
