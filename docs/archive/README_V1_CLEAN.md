# 🍻 KAI - Smart Tavern Table V1 | Clean Implementation Ready

**Date:** January 20, 2026  
**Status:** ✅ Cleaned, focused, ready to build  
**Code Reduction:** 200+ files → 30 core files (85%)  
**Dead Code Eliminated:** 17,000+ lines

---

## Start Here

### For Implementation
👉 **[KAI_TABLE_V1_QUICKSTART.md](KAI_TABLE_V1_QUICKSTART.md)**
- 5-session build plan (3 hours total)
- Hardware wiring guide
- Testing checklist
- Production deployment checklist

### For Understanding What Changed
👉 **[MISSION_ALIGNMENT_KEEP_VS_ARCHIVE.md](MISSION_ALIGNMENT_KEEP_VS_ARCHIVE.md)**
- What code remained and why
- What was archived and why
- Final file structure

### The Core Code
👉 **[kai_table_v1_core.py](kai_table_v1_core.py)**
- ~150 lines
- Record → Transcribe → ChatGPT → Speak → Log
- 100% focused on tavern table mission

---

## What Is KAI (V1)?

A **smart table** that:

1. **Detects users** - NFC card tap or physical button press
2. **Records voice** - 6-second push-to-talk (no always-on mic)
3. **Transcribes** - Sends to OpenAI Whisper API
4. **Gets context** - Fetches user profile from Firebase
5. **Asks ChatGPT** - With structured JSON output format
6. **Speaks reply** - Local TTS (espeak-ng) or ElevenLabs
7. **Triggers LEDs** - WS2812B addressable strip for visual feedback
8. **Logs everything** - Conversation history to Firebase

**For V1:** Tight, focused, prove-the-concept.

---

## What's NOT in V1 (Archived)

| Feature | Why Archived |
|---------|-------------|
| Consciousness AI / Memory neural net | Nice-to-have, not core |
| Ambiance/Scene system | Premature (needs user feedback first) |
| Smoke machine control | Phase 2+ |
| Personality delta system | Overcomplicated for push-to-talk |
| Proactive behaviors | V1 is reactive only |
| Always-on wake words | Tavern noise makes it impractical |
| Usage tracking | Premature analytics |
| Complex music selection | Not a jukebox in V1 |

Everything archived → `ARCHIVED_REDUNDANT/` (recoverable)

---

## File Structure (Post-Cleanup)

```
homecoming_app/
├── 📄 kai_table_v1_core.py              ← Main loop
├── 📄 KAI_TABLE_V1_QUICKSTART.md        ← Implementation guide
├── 📄 MISSION_ALIGNMENT_KEEP_VS_ARCHIVE.md
│
├── raspberry_pi/
│   ├── firebase_command_listener.py     ← Table state polling
│   └── bluetooth_audio_manager.py       ← Audio routing (minimal)
│
├── lib/                                 ← Dart/Flutter (if used)
│   ├── core/services/
│   │   ├── firebase_service.dart        ← Context retrieval
│   │   └── native_audio_recorder.dart   ← Audio capture
│   ├── services/
│   │   ├── voice/
│   │   │   └── voice_service.dart       ← Whisper integration
│   │   ├── media/
│   │   │   └── audio_player_service.dart ← TTS playback
│   │   └── core/
│   │       ├── firebase_service.dart
│   │       └── native_audio_recorder.dart
│
├── unified_deployment.py                ← Pi deployment automation
├── unified_firebase_listener.py         ← Table logging
├── unified_test_harness.py              ← Testing framework
│
├── ARCHIVED_REDUNDANT/
│   ├── firebase_listeners/              (4 files, 6,837 lines)
│   ├── deployment_scripts/              (9 files)
│   ├── off_mission_services/            (consciousness, tracking, etc.)
│   ├── scene_fixtures/                  (fixtures_v2/)
│   └── flutter_features_ui/             (lib/src/features/)
│
└── docs/
    ├── KAI_TABLE_V1_QUICKSTART.md       ← Implementation 5-sessions
    ├── MISSION_ALIGNMENT_KEEP_VS_ARCHIVE.md
    ├── COMPLETE_REDUNDANCY_ANALYSIS.md  ← All 3 phases
    ├── PHASE_1_COMPLETION_REPORT.md
    ├── PHASE_2_COMPLETION_REPORT.md
    └── PHASE_3_AUDIT_REPORT.md
```

---

## What Was Cleaned (All 3 Phases)

### Phase 1: Unified Core Modules ✅
- 4 core Python modules created
- 150+ duplicate scripts consolidated
- 40-50% initial code reduction

### Phase 2: Service Architecture ✅
- 25 Dart services organized into 8 categories
- 3 ChatService versions → 1 canonical
- 2 VoiceService versions → 1 canonical
- Android package unified (1 instead of 2)
- 20-25% additional reduction

### Phase 3: Mission Alignment ✅
- 4 Firebase listener variants archived (6,837 lines)
- 9 deployment scripts consolidated
- Off-mission Dart services archived (consciousness, tracking, curiosity, animation)
- Scene fixtures archived
- Flutter UI features archived
- 15-20% additional reduction

**Total:** 455-477 files → ~30 core (85% reduction)

---

## Quick Build Path (3 Hours)

| Session | What | Time |
|---------|------|------|
| 1 | Pi setup: OS, packages, audio device | 30 min |
| 2 | Firebase + ChatGPT: prove context & responses | 30 min |
| 3 | Audio loop: record → transcribe → speak | 30 min |
| 4 | Button + LEDs: GPIO + WS2812B control | 45 min |
| 5 | NFC + systemd: tap detection + auto-start | 45 min |
| **Total** | **Working V1 in a table** | **~3 hours** |

See [KAI_TABLE_V1_QUICKSTART.md](KAI_TABLE_V1_QUICKSTART.md) for exact commands.

---

## Hardware Bill of Materials (V1)

| Component | Cost | Notes |
|-----------|------|-------|
| Raspberry Pi 5 | $70 | Or Pi 4 if available |
| Official PSU | $15 | Don't cheap out |
| microSD 128GB | $15 | Fast class |
| USB microphone | $25 | Directional if possible |
| USB speaker | $15 | Small, loud |
| WS2812B LED strip | $10 | 30 LEDs, 5V |
| Level shifter | $3 | 3.3V → 5V |
| 5V PSU (LEDs) | $10 | Separate from Pi |
| Fuse + wiring | $5 | Safety |
| **Total** | **~$170** | Functional V1 |

---

## Core Mission (Non-Negotiable for V1)

✅ **What's In:**
- Tap NFC or press button → triggers cycle
- 6-second push-to-talk voice recording
- Whisper transcription (API)
- Firebase context fetch (user profile)
- ChatGPT JSON-structured responses
- Local TTS playback (espeak-ng)
- LED visual feedback (white pulse while thinking, blue when speaking)
- Firebase logging (all conversations)

❌ **What's NOT:**
- Always-on listening (taverns are loud)
- Wake words (too error-prone in noisy environment)
- Consciousness / memory neural net
- Complex personality system
- Proactive messages
- Music playback
- Scene management
- Multi-table coordination

This is intentional. V1 proves the core concept. Everything else is Phase 2+.

---

## Deployment

### Local Testing
```bash
python3 kai_table_v1_core.py
# Calls run_cycle() for testing
```

### Pi Production
```bash
# Copy all files to /home/pi/kai/
# Create Firebase service account JSON
# Set OPENAI_API_KEY environment variable
# Enable systemd service

sudo systemctl start kai-table
sudo systemctl status kai-table
```

---

## Documentation Map

| Document | Purpose |
|----------|---------|
| [KAI_TABLE_V1_QUICKSTART.md](KAI_TABLE_V1_QUICKSTART.md) | **START HERE** - 5-session implementation guide |
| [MISSION_ALIGNMENT_KEEP_VS_ARCHIVE.md](MISSION_ALIGNMENT_KEEP_VS_ARCHIVE.md) | What stayed/archived + why |
| [kai_table_v1_core.py](kai_table_v1_core.py) | The actual code (~150 lines) |
| [COMPLETE_REDUNDANCY_ANALYSIS.md](COMPLETE_REDUNDANCY_ANALYSIS.md) | Full 3-phase audit details |
| [PHASE_1_COMPLETION_REPORT.md](PHASE_1_COMPLETION_REPORT.md) | Unified modules created |
| [PHASE_2_COMPLETION_REPORT.md](PHASE_2_COMPLETION_REPORT.md) | Services organized |
| [PHASE_3_AUDIT_REPORT.md](PHASE_3_AUDIT_REPORT.md) | Hidden redundancies discovered |

---

## Philosophy

The original **Homecoming** project tried to build everything at once:
- Consciousness AI
- Music selection & streaming
- Ambiance scene management
- Complex personality system
- Home automation
- Usage tracking
- Multi-user profiles

That's a **platform**, not a **product**.

For a **tavern table**, you need the minimum viable set:
- Button or NFC trigger
- Voice input (push-to-talk)
- ChatGPT responses
- LED feedback
- Simple logging

**This is that minimum.** Build it. Test it with real users. Get feedback.

Then Phase 2, 3, 4, ... based on what actually matters to users.

---

## What's Next (After V1 Works)

### Phase 2: Multi-Table Network
- Coordinator Pi listening to 4+ tables
- Shared context (staff can see what's happening)
- Analytics dashboard

### Phase 3: Short-Term Memory
- Last 5 conversations cached
- "Same cozy blue glow and the usual?" personalization
- Mood detection from tone

### Phase 4: Proactive Behaviors
- "It's been 30 minutes" check-ins
- Staff alert if user requests help
- Ambient music loops

### Phase 5: Full Ambiance
- Background music (jazz, ambient, tavern bustle)
- Synchronized lighting themes
- Table-to-table communication (staff messaging)

But **first**: prove V1 works in the real world.

---

## Success Criteria (V1)

✅ **Building It**
- [ ] Pi setup (audio, packages, network)
- [ ] Firebase connection (read/write working)
- [ ] ChatGPT integration (JSON responses)
- [ ] Audio loop (record → transcribe → speak)
- [ ] Button trigger working
- [ ] LED feedback visible
- [ ] NFC card detection working
- [ ] Logs saving to Firebase

✅ **Testing It**
- [ ] 10 consecutive conversations without crash
- [ ] Audio quality acceptable in quiet room
- [ ] Response latency < 8 seconds
- [ ] LED colors match expected mood
- [ ] Firebase stores 100+ logs reliably

✅ **In a Real Table**
- [ ] Mount all hardware safely
- [ ] Service hatch accessible
- [ ] Cables protected
- [ ] No water damage risk
- [ ] User can tap NFC and talk naturally
- [ ] Response feels like a real conversation

---

## Questions?

This is a **complete, focused, mission-aligned** codebase ready for V1.

Everything not needed for the tavern table is archived (but recoverable).

Start with [KAI_TABLE_V1_QUICKSTART.md](KAI_TABLE_V1_QUICKSTART.md) and build.

Good luck! 🍻

