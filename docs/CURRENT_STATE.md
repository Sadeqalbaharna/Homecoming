# Current State (as of 2026-07-09)

This replaces the ~180 version-tagged status docs previously in `docs/`, which had
drifted significantly out of sync with the actual running system. Those are
preserved for history in `docs/archive/` — nothing was deleted, just decluttered.
This doc describes only what was directly verified against the code and git
history on 2026-07-09; it is not a roadmap or a feature list, just a snapshot of
what's actually there.

## What's actually deployed (verified via the systemd unit files)

Three services, defined in `scripts/pi/services/`:

- **`kai-listener.service`** → runs `scripts/pi/kai_wake_listener_simple.py`.
  This is the real wake-word entry point — listens for "kai" / "hey kai" /
  "okay kai" via repeated short recordings + Whisper transcription, then hands
  off to `scripts/test/session3_enhanced.py` for the actual conversation logic.
- **`firebase-listener.service`** → runs `/home/pi/firebase_rest_listener_debug.py`
  (Firebase REST listener with WS2812B LED control). Separate concern from the
  wake listener — this is the ambient/reactive LED layer, not conversation.
- **`homecoming-app.service`** → runs `scripts/bluetooth/bluetooth_startup_check.py`
  ("Homecoming D&D Ambiance App"). Bluetooth audio startup check.

The older `raspberry_pi/kai-home.service` → `kai_home_service.py` path (Nov 2025
generation) is **not** what's currently deployed — no current service references
it, and nothing in that directory has been touched since Nov 9, 2025 while active
development continued in `scripts/pi/` through June 2026. That whole generation
has been archived to `ARCHIVED_REDUNDANT/legacy_raspberry_pi_generation/`.

## The June 21, 2026 commit (`9175b90`) matters more than its size suggests

Commit message: "feat: background mode, Porcupine wake word, overlay flame,
Firebase index fix." This single commit:

- Added the entire current `scripts/pi/services/` generation (including the
  services above).
- Reintroduced wake-word listening, despite `docs/archive/README_V1_CLEAN.md`
  (Jan 20, 2026) explicitly stating wake words were cut ("too error-prone in a
  noisy tavern").
- Reintroduced `lib/services/ai/kai_consciousness_service.dart` (158 lines) —
  this is its *only* commit in git history, i.e. it was written fresh in this
  commit, not restored from the archived 210-line version at
  `ARCHIVED_REDUNDANT/off_mission_services/consciousness/kai_consciousness_service.dart`.
  It's genuinely different code, and it's actively called from `ai_service.dart`
  (`isSmartHomeRequest`, `getKaiTechnicalContext`, `generateKaiConsciousnessPrompt`).
  Despite older docs claiming consciousness was archived as "not core," it is
  currently live and load-bearing.

One loose thread from that commit worth checking before relying on it: the
message mentions "Porcupine wake word," but no Porcupine SDK usage was found in
`scripts/pi/` as of this audit. It may live in the Flutter/mobile side
(`lib/services/voice/voice_activation_service.dart`) instead, or be unfinished.
Not confirmed either way.

## What was archived in this cleanup pass (2026-07-09)

- `docs/*.md` (179 files) → `docs/archive/`. Nothing deleted, just moved. The
  two WS2812B wiring `.txt` guides were left in `docs/` since they're hardware
  reference, not dated status reports.
- 8 superseded wake-word script variants (`kai_wake_listener.py`,
  `kai_rms_wake.py`, `kai_silero_wake.py`, `kai_robust_wake.py`,
  `kai_reliable_wake.py`, `kai_final_wake.py`, `kai_diagnostic.py`,
  `WORKING_kai_v1_wake_word_chatgpt_tts_leds.py`) → `ARCHIVED_REDUNDANT/wake_word_variants/`.
  Only `kai_wake_listener_simple.py` (the one the live service actually runs)
  stayed in place.
- The entire `raspberry_pi/` directory (Nov 2025 generation, 24 files) →
  `ARCHIVED_REDUNDANT/legacy_raspberry_pi_generation/`.

A full backup of the working tree as it stood before this pass exists at
`C:\code\homecoming_app_BACKUP_20260709_working_tree.tar.gz`, plus git tag
`pre-cleanup-backup-20260709` at commit `c82537f` for anything already committed.

## Confirmed already-clean (no action needed this pass)

The Jan 20, 2026 `SECOND_REDUNDANCY_AUDIT.md` (now in `docs/archive/`) flagged
several duplicates that were checked against the current tree and are already
resolved: root-level vs `raspberry_pi/` Python script duplication, three
versions of `ChatService`, two versions of `VoiceService`, and two Android
package copies of `AudioRecordingService`. All down to one canonical copy each.

## Left alone, needs a product decision (not a cleanup call)

`lib/services/ai/kai_consciousness_service.dart` and its archived 210-line
predecessor. Both still exist. The live one is genuinely in use — this isn't
leftover clutter, it's a deliberate (if undocumented) feature. Whether it
should still be live is a product question, not something resolved here.
