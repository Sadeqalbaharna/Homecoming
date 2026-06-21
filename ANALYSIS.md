# Homecoming — Project Analysis

*Generated June 2026 · v0.9.0+159*

---

## What Is Homecoming?

Homecoming is a cross-platform Flutter app centred on **Kai**, a persistent AI companion that floats over your desktop or runs full-screen on mobile. The vision is an AI that *lives with you* — it remembers past conversations, has a dynamic personality, speaks back in a synthesised voice, and can control physical hardware in your home (lights, audio, Raspberry Pi).

The app is more than a chatbot. It's closer to a **home AI OS**: voice-activated, always present, with tentacles into your local network via a Raspberry Pi listener and Firebase as the connective tissue.

---

## Tech Stack

| Layer | Technology |
|---|---|
| App framework | Flutter / Dart (v0.9.0+159) |
| AI / LLM | OpenAI GPT-4o / GPT-5 |
| Speech-to-text | OpenAI Whisper (via native audio recorder) |
| Text-to-speech | ElevenLabs |
| Cloud backend | Firebase Realtime Database + Cloud Functions (Node.js) |
| Home automation | Raspberry Pi → Python listeners → Firebase commands |
| LED control | WS2812B addressable LEDs on Pi |
| Audio playback | audioplayers + YouTube stream |
| State management | Riverpod + Flutter Hooks |
| Secure storage | flutter_secure_storage |
| Overlay (desktop) | flutter_overlay_window (local fork), window_manager, flutter_acrylic |
| Voice wake word | Custom "Hey Kai" detection via NativeAudioRecorder + local NLP |

---

## Architecture Overview

```
┌─────────────────────────────────────────┐
│           Flutter App (mobile/desktop)  │
│                                         │
│  ┌─────────┐  ┌──────────┐  ┌────────┐ │
│  │ Overlay │  │  Chat UI │  │Remote  │ │
│  │  (Kai)  │  │+ Persona │  │Control │ │
│  └────┬────┘  └────┬─────┘  └───┬────┘ │
│       │            │             │      │
│  ┌────▼────────────▼─────────────▼────┐ │
│  │            AIService               │ │
│  │  (GPT · Whisper · ElevenLabs ·    │ │
│  │   Memory · Curiosity · Ambiance)   │ │
│  └─────────────────┬──────────────────┘ │
│                    │                    │
│  ┌─────────────────▼──────────────────┐ │
│  │          FirebaseService           │ │
│  └─────────────────┬──────────────────┘ │
└────────────────────┼────────────────────┘
                     │ Realtime DB
         ┌───────────▼──────────────┐
         │     Firebase Cloud       │
         │  (DB + Functions)        │
         └───────────┬──────────────┘
                     │ listens
         ┌───────────▼──────────────┐
         │    Raspberry Pi          │
         │  firebase_listener.py    │
         │  WS2812B LEDs            │
         │  Bluetooth audio         │
         │  YouTube stream          │
         └──────────────────────────┘
```

### Key Subsystems

**AIService** (`lib/services/ai_service.dart`, 3100 lines) is the brain. It handles chat, memory retrieval, curiosity generation, ambiance detection, home automation commands, and TTS — all in one monolithic class.

**VoiceActivationService** listens continuously for "Hey Kai" in 3-second audio chunks, then hands off to Whisper STT and AIService.

**KnowledgeGraphService** builds a graph of Kai's memories from Firebase, visualised in a mind-map screen.

**DynamicAmbientService** parses conversational context to pick LED scenes and YouTube ambient video content.

**HomeAutomationService** writes commands to Firebase Realtime Database; the Pi-side Python listener picks them up and executes them (lights, music, Bluetooth).

**firebase_command_listener.py** (on Raspberry Pi) is the physical-world bridge — it polls Firebase and invokes hardware routines.

---

## Strengths

- **Ambitious, original concept.** A truly ambient, always-on AI companion with physical-world integration is genuinely novel and well ahead of most side projects.
- **Full pipeline working.** Voice input → LLM → TTS → LED + audio response is proven end-to-end.
- **Firebase as an event bus** is elegant for the app ↔ Pi communication. No custom socket server needed.
- **Personality system** is well-thought-out — Big Five traits, mood valence, user affinity, and curiosity are modelled explicitly rather than just being prompts.
- **Good deployment hygiene.** GitHub Actions CI/CD, Firebase App Distribution for testers, secure key storage.
- **Extensive documentation** — 150+ markdown files show iterative, documented development.

---

## Issues & Technical Debt

### 1. Massive monolith in AIService
`lib/services/ai_service.dart` is **3,100 lines** — the single largest file and the biggest architectural risk. Everything from prompt construction to TTS playback to ambiance detection lives here. A bug anywhere cascades everywhere.

### 2. Duplicate service files
Multiple versions of the same service exist side by side:
- `services/ai_service.dart` AND `services/ai/ai_service.dart` (identical, 3101 lines each)
- `services/voice_activation_service.dart` AND `services/voice/voice_activation_service.dart`
- `services/voice_training_service.dart` AND `services/voice/voice_training_service.dart`
- `services/wake_on_lan_service.dart` AND `services/automation/wake_on_lan_service.dart`
- `services/dynamic_ambient_service.dart` AND `services/media/dynamic_ambient_service.dart`

The refactor to a modular structure was started but not completed — both the old flat files and the new `services/voice/`, `services/ai/`, `services/automation/` directories exist simultaneously.

### 3. Root-level clutter
162 Python scripts, 150+ markdown docs, screenshots, test logs, and deployment scripts all live at the project root. There is no `scripts/`, `docs/`, or `tools/` directory to separate concerns. This makes navigation increasingly difficult.

### 4. Active branch divergence
The current branch is `refactor/modular-fixtures`, not `main`. The modular refactor is in progress but uncommitted to main — work is potentially scattered across branches.

### 5. Local fork of flutter_overlay_window
The project vendors a modified `packages/flutter_overlay_window` for click-through support. This is valid but increases maintenance burden and means upstream fixes won't be picked up automatically.

### 6. No test coverage
There are many `test_*.py` files for the Pi side but essentially no Flutter unit or widget tests (the `test/` folder exists but appears empty). At 16,000+ lines of Dart, there's substantial logic with no safety net.

### 7. Raspberry Pi scripts are not versioned coherently
There are 30+ Python scripts at the root (many one-off experiments), and a `raspberry_pi/` folder with the canonical service files. It's unclear which scripts are current vs abandoned. Several appear to be debug/one-off scripts that were never cleaned up.

### 8. main.dart is a 60KB monolith too
The main entry point contains most of the UI widget tree inline. At this size it's effectively a second monolith alongside AIService.

---

## Suggested Priorities

### Short-term (clean the workspace)
1. **Delete or archive duplicate service files.** Pick the `services/ai/`, `services/voice/`, etc. structure and remove the flat-level duplicates.
2. **Move root-level scripts** to `scripts/pi/`, `scripts/deploy/`, `scripts/debug/`.
3. **Move markdown docs** to `docs/` (or archive them — most are dated build notes).
4. **Merge the `refactor/modular-fixtures` branch** into main once conflicts are clear.

### Medium-term (architecture)
5. **Break up AIService.** Extract at minimum: `MemoryService`, `PersonalityService`, `AmbianceService`, `TTSService`, `ChatService`. Each should be injectable and independently testable.
6. **Break up main.dart.** Extract the overlay widget, the expanded chat panel, and the avatar animation system into separate widget files.
7. **Add Flutter tests.** Start with AIService prompt-building logic and the personality mutation functions — they're pure functions and easy to test.

### Longer-term (product)
8. **Consider moving to Claude API.** GPT-4o is solid, but Claude's longer context window and system prompt adherence may suit Kai's personality system better.
9. **Kai's memory needs a retrieval strategy.** Right now the knowledge graph is rebuilt from all Firebase data. As history grows this will become slow and expensive — semantic search (embeddings) or a local vector store would help.
10. **Formalise the Pi ↔ app protocol.** The Firebase command schema is ad-hoc. A typed schema (even just a Dart class + Python dataclass pair) would prevent the silent failures that plague the Bluetooth/audio debug scripts.

---

## Summary

Homecoming is a genuinely interesting, feature-rich project with a clear vision. The core loop — speak to Kai, Kai responds with voice and personality, hardware responds in the room — works. The codebase has accumulated significant structural debt through rapid, exploratory development: duplicated files, a monolithic AIService, and a root directory full of one-off scripts. The single highest-leverage action is completing the modular refactor that was already started, which would make every other improvement easier.
