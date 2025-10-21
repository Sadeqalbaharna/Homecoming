# Voice Cloning Alternatives to ElevenLabs 🎙️

## Current Situation
- **ElevenLabs**: $0.30 per 1K characters = $0.6078 for 2,026 chars
- **Feature needed**: Voice cloning (custom voice training)
- **Challenge**: Most cheap TTS services don't support voice cloning

## 🎯 Voice Cloning Services Comparison

### 1. **PlayHT** ⭐ RECOMMENDED
**Cost**: $0.048 per 1K characters (84% cheaper than ElevenLabs!)
- **Voice Cloning**: ✅ YES - High quality instant cloning
- **Quality**: Excellent, comparable to ElevenLabs
- **Free Tier**: 12,500 characters/month
- **Minimum Audio**: 30 seconds for voice cloning
- **Cloning Time**: ~2-5 minutes
- **Your Cost**: 2,026 chars × $0.048 = **$0.097** (vs $0.6078)
- **Savings**: **84% cheaper** ✅✅✅

**Pros**:
- Fast voice cloning (minutes)
- Multiple voice samples supported
- API very similar to ElevenLabs
- Generous free tier

**Cons**:
- Slightly less natural than ElevenLabs
- Requires 30 sec minimum audio

**Implementation**: Easy drop-in replacement

---

### 2. **Resemble.AI**
**Cost**: $0.006 per second (~$0.03 per 1K characters, 90% cheaper!)
- **Voice Cloning**: ✅ YES - Professional grade
- **Quality**: Excellent
- **Free Tier**: 300 seconds/month (~$1.80 worth)
- **Minimum Audio**: 3 minutes for good cloning
- **Cloning Time**: ~10-15 minutes
- **Your Cost**: 2,026 chars × $0.03 = **$0.061** (vs $0.6078)
- **Savings**: **90% cheaper** ✅✅✅✅

**Pros**:
- Best price/quality ratio
- Real-time synthesis available
- Emotion control (similar to ElevenLabs)
- Localization features

**Cons**:
- Requires more audio for cloning (3 min)
- Less known than ElevenLabs

**Implementation**: Medium effort (different API structure)

---

### 3. **Murf.AI**
**Cost**: ~$0.08 per 1K characters (73% cheaper)
- **Voice Cloning**: ✅ YES - Custom voice creation
- **Quality**: Very good
- **Free Tier**: 10 minutes of audio
- **Minimum Audio**: 2-3 minutes for cloning
- **Cloning Time**: ~24 hours
- **Your Cost**: 2,026 chars × $0.08 = **$0.162** (vs $0.6078)
- **Savings**: **73% cheaper** ✅✅

**Pros**:
- Very natural sounding
- Built-in studio features
- Multi-language support

**Cons**:
- Slower cloning (24h)
- More expensive than PlayHT/Resemble
- Primarily UI-focused (API less documented)

**Implementation**: Harder (limited API docs)

---

### 4. **Descript Overdub**
**Cost**: $0.05 per minute (~$0.10 per 1K characters, 67% cheaper)
- **Voice Cloning**: ✅ YES - Ultra-realistic
- **Quality**: Excellent (used by professionals)
- **Free Tier**: 10 hours of transcription (limited voice cloning)
- **Minimum Audio**: 10 minutes for good clone
- **Cloning Time**: ~30 minutes
- **Your Cost**: 2,026 chars × $0.10 = **$0.203** (vs $0.6078)
- **Savings**: **67% cheaper** ✅✅

**Pros**:
- Extremely realistic
- Built-in editing tools
- Great for longer content

**Cons**:
- Requires 10 min audio
- More focused on creators/podcasters
- API limited

**Implementation**: Harder (primarily UI-based)

---

### 5. **Coqui TTS** (Open Source) 🆓
**Cost**: FREE (self-hosted)
- **Voice Cloning**: ✅ YES - XTTS model supports cloning
- **Quality**: Good (not as good as ElevenLabs)
- **Free Tier**: Unlimited (you host it)
- **Minimum Audio**: 6 seconds for voice cloning!
- **Cloning Time**: Instant (real-time)
- **Your Cost**: **$0.00** (only server costs)
- **Savings**: **100% cheaper** ✅✅✅✅✅

**Pros**:
- Completely free
- Open source
- Only 6 seconds of audio needed!
- Real-time synthesis
- Privacy (runs locally)

**Cons**:
- Lower quality than paid services
- Requires hosting (can use Google Colab free)
- More technical setup

**Implementation**: Complex (requires Python backend or Cloud Run)

---

### 6. **Speechify Voice Cloning**
**Cost**: $0.10 per 1K characters (67% cheaper)
- **Voice Cloning**: ✅ YES - Professional quality
- **Quality**: Very good
- **Free Tier**: Limited trial
- **Minimum Audio**: 1-2 minutes
- **Cloning Time**: ~15 minutes
- **Your Cost**: 2,026 chars × $0.10 = **$0.203** (vs $0.6078)
- **Savings**: **67% cheaper** ✅✅

**Pros**:
- Fast cloning
- Low audio requirement
- Natural sounding

**Cons**:
- Newer service
- Less proven at scale

**Implementation**: Easy (REST API)

---

## 📊 Comparison Table

| Service | Cost/1K chars | Your Cost | Savings | Quality | Cloning Time | Min Audio | Free Tier |
|---------|--------------|-----------|---------|---------|--------------|-----------|-----------|
| **ElevenLabs** (current) | $0.30 | $0.6078 | - | ⭐⭐⭐⭐⭐ | 5 min | 1 min | 10K chars |
| **PlayHT** ⭐ | $0.048 | $0.097 | 84% | ⭐⭐⭐⭐ | 5 min | 30 sec | 12.5K chars |
| **Resemble.AI** | $0.03 | $0.061 | 90% | ⭐⭐⭐⭐⭐ | 15 min | 3 min | 300 sec |
| **Murf.AI** | $0.08 | $0.162 | 73% | ⭐⭐⭐⭐ | 24 hours | 2 min | 10 min audio |
| **Descript** | $0.10 | $0.203 | 67% | ⭐⭐⭐⭐⭐ | 30 min | 10 min | 10 hours |
| **Coqui TTS** 🆓 | $0.00 | $0.00 | 100% | ⭐⭐⭐ | Instant | 6 sec | Unlimited |
| **Speechify** | $0.10 | $0.203 | 67% | ⭐⭐⭐⭐ | 15 min | 1 min | Trial |

---

## 🎯 My Recommendations

### Best Value: **PlayHT** ⭐⭐⭐⭐⭐
**Why**: 84% savings, comparable quality, easy implementation

**Implementation Plan**:
1. Sign up at https://play.ht
2. Clone Kai's voice (30 sec audio sample)
3. Replace ElevenLabs API calls with PlayHT
4. **New cost: $0.097 vs $0.6078** (saving $0.51 per session)

**Code changes**: ~2 hours
```dart
// Change from:
final url = 'https://api.elevenlabs.io/v1/text-to-speech/$voiceId';

// To:
final url = 'https://api.play.ht/api/v2/tts';
```

---

### Most Savings: **Resemble.AI** ⭐⭐⭐⭐⭐
**Why**: 90% savings, excellent quality, emotion control

**Trade-off**: Need 3 minutes of audio for cloning (vs 30 sec)

**Implementation Plan**:
1. Record 3 min of Kai's voice
2. Upload to Resemble.AI for cloning
3. Integrate API
4. **New cost: $0.061 vs $0.6078** (saving $0.55 per session)

**Code changes**: ~4 hours (different API structure)

---

### Completely Free: **Coqui TTS** 🆓
**Why**: $0.00 cost, only 6 sec audio needed, unlimited usage

**Trade-off**: Lower quality, requires hosting

**Implementation Options**:

**Option A: Cloud Run** (recommended)
- Deploy Coqui as Cloud Function
- ~$1-2/month for server costs
- Still 99% cheaper than ElevenLabs

**Option B: Google Colab Free**
- Use Colab's free GPU
- Host API endpoint on ngrok
- Completely free!

**Implementation Plan**:
1. Record 6 seconds of Kai's voice
2. Deploy Coqui to Cloud Run or Colab
3. Call API from Flutter app
4. **New cost: ~$0.00** (saving $0.61 per session)

**Code changes**: ~1 day (need Python backend)

---

## 💡 Hybrid Strategy (BEST APPROACH)

Use **PlayHT + Coqui TTS**:

1. **Default**: Coqui TTS (FREE)
   - For most messages
   - Good enough quality
   - Zero cost

2. **Premium mode**: PlayHT ($0.048/1K chars)
   - When user enables "HD Voice"
   - For important messages
   - Special moments

3. **Fallback**: Android Native TTS
   - If both fail
   - Network issues

**Estimated cost with this strategy**:
- 80% of messages: Coqui (FREE)
- 20% of messages: PlayHT ($0.019)
- **Total: $0.019 vs $0.6078** (saving **97%**) ✅✅✅✅✅

---

## 🚀 Quickest Win: **PlayHT** (2 hours implementation)

Here's what I'll do:

### Step 1: Sign up for PlayHT
```
1. Go to https://play.ht
2. Create account
3. Get API key
4. Clone voice (upload 30 sec audio)
```

### Step 2: Replace ElevenLabs with PlayHT
```dart
// lib/services/ai_service.dart

// OLD:
final response = await http.post(
  Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/$voiceId'),
  headers: {
    'xi-api-key': apiKey,
    'Content-Type': 'application/json',
  },
  body: jsonEncode({
    'text': text,
    'model_id': 'eleven_monolingual_v1',
  }),
);

// NEW:
final response = await http.post(
  Uri.parse('https://api.play.ht/api/v2/tts'),
  headers: {
    'AUTHORIZATION': 'Bearer $apiKey',
    'X-USER-ID': userId,
    'Content-Type': 'application/json',
  },
  body: jsonEncode({
    'text': text,
    'voice': clonedVoiceId, // Your cloned voice
    'quality': 'premium',
    'output_format': 'mp3',
  }),
);
```

### Step 3: Test
- Verify voice quality matches Kai
- Check latency
- Confirm cost tracking works

**Result**: Save **$0.51 per session** (84% reduction)

---

## 📈 Cost Projection

### Current (20 API calls, 2,026 chars):
```
ElevenLabs: $0.6078
Total:      $0.6078
```

### With PlayHT (84% savings):
```
PlayHT:     $0.097
Total:      $0.097 ✅
```

### With Resemble.AI (90% savings):
```
Resemble:   $0.061
Total:      $0.061 ✅✅
```

### With Coqui TTS (100% savings):
```
Coqui:      $0.00
Server:     ~$0.05/month (Cloud Run)
Total:      ~$0.00 ✅✅✅
```

### With Hybrid (PlayHT + Coqui):
```
Coqui:      $0.00 (80% of calls)
PlayHT:     $0.019 (20% of calls)
Total:      $0.019 ✅✅✅✅
```

---

## ✅ Action Items

**Want me to implement PlayHT right now?**

I can:
1. Update `ai_service.dart` to use PlayHT API
2. Add voice cloning instructions
3. Keep ElevenLabs as fallback option
4. Update cost tracking

**Time**: 2 hours
**Savings**: 84% ($0.51 per session)

**OR want to go with the FREE option (Coqui)?**

I can:
1. Set up Coqui Cloud Run deployment
2. Add voice cloning (just need 6 sec audio!)
3. Integrate with Flutter app
4. Keep PlayHT as premium option

**Time**: 1 day
**Savings**: 97%+ (virtually free)

---

## 🎁 Bonus: Voice Sample Recording

For any service, you'll need to record Kai's voice. Here's how:

**What to record**:
- 30 seconds - 3 minutes (depending on service)
- Clear audio, no background noise
- Natural speech, various emotions
- Sample script: "Hello! I'm Kai, your AI companion. I'm here to chat, help you think, and keep you company. How are you feeling today? I'd love to hear what's on your mind. Whether you want to talk about something serious or just have fun, I'm all ears!"

**Recording tips**:
- Use phone mic or better
- Quiet room
- Natural pace
- Include emotions (happy, thoughtful, caring)

---

**What do you want to do?**
1. Switch to **PlayHT** (quick, 84% savings)
2. Try **Coqui TTS** (free, 100% savings)
3. Use **Hybrid approach** (best of both worlds)
4. Research **Resemble.AI** (best quality/price)

Let me know and I'll start implementing! 🚀
