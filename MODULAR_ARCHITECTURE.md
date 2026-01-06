# Modular Fixture Architecture - Step-by-Step Build Guide

## Overview

We've taken the monolithic `firebase_rest_listener_debug.py` (3546 lines) and refactored it into a modular, testable architecture. Each component can be developed and tested independently.

**Key Principle:** Separate concerns → Input handling, Business logic, Output control

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      SMART FIXTURE                          │
│  (e.g., DiningTableFixture, WallFixture, DoorFixture)      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐     ┌──────────────────┐             │
│  │ INPUT DRIVERS   │     │ OUTPUT DRIVERS   │             │
│  ├─────────────────┤     ├──────────────────┤             │
│  │ • Voice Input   │     │ • LED Driver     │             │
│  │ • Motion Sensor │     │ • Audio Driver   │             │
│  │ • App Commands  │     │ • Motor Driver   │             │
│  │ • Touch Buttons │     │ • Fog Machine    │             │
│  │ • Environment   │     │ • Haptic Driver  │             │
│  └────────┬────────┘     └────────┬─────────┘             │
│           │                       │                        │
│           └───────────┬───────────┘                        │
│                       ▼                                    │
│           FIXTURE.process_input()                         │
│                 (Business Logic)                          │
│           Input → Analyze → Output Commands               │
│                                                             │
└─────────────────────────────────────────────────────────────┘

Central Server (Firebase/Database)
    ├─ Fixture Registry (who is where, what hardware)
    ├─ AI Music Engine (generates YouTube queries)
    ├─ Scene Analyzer (understands D&D context)
    └─ Centralized Config
```

---

## Directory Structure

```
fixtures_v2/
├── core/                     # Core abstractions (reusable)
│   ├── __init__.py
│   ├── driver_base.py        # InputDriver, OutputDriver base classes
│   ├── fixture_base.py       # BaseFixture class
│   └── registry.py           # FixtureRegistry for central config
│
├── drivers/                  # Concrete driver implementations
│   ├── audio_driver.py       # Play music (YouTube/local)
│   ├── led_driver.py         # Control RGB LED strips
│   ├── voice_input_driver.py # Receive voice commands
│   ├── motion_sensor_driver.py (NOT YET)
│   ├── motor_driver.py       (NOT YET)
│   └── fog_machine_driver.py (NOT YET)
│
├── engines/                  # Business logic services (NOT YET)
│   ├── music_engine.py       # AI YouTube query generation
│   ├── scene_analyzer.py     # Detect D&D context
│   └── personality_engine.py # Fixture-specific AI
│
├── fixtures/                 # Concrete fixture types
│   ├── dining_table.py       # Example: Smart dining table
│   ├── wall.py               (NOT YET)
│   ├── door.py               (NOT YET)
│   └── ambient_light.py      (NOT YET)
│
└── tests/                    # Test framework & test suites
    ├── test_harness.py       # Generic testing utilities
    ├── test_step1_initialization.py
    ├── test_step2_drivers.py (NOT YET)
    ├── test_step3_fixtures.py (NOT YET)
    └── test_step4_engines.py (NOT YET)
```

---

## Steps & Testing Strategy

### STEP 1: ✅ COMPLETED - Fixture Initialization & Driver Abstraction

**What we built:**
- `BaseFixture` class - all fixtures inherit this
- `InputDriver` & `OutputDriver` base classes - pluggable hardware
- `LEDDriver`, `AudioDriver`, `VoiceInputDriver` - concrete implementations
- `FixtureRegistry` - central config tracking
- `DiningTableFixture` - example implementation
- `FixtureTestHarness` - reusable test framework

**Testing:**
```bash
cd c:\code\homecoming_app
python fixtures_v2/tests/test_step1_initialization.py
```

**What it tests:**
```
✅ Fixture initialization
✅ Driver registration
✅ Output driver independence
✅ Input driver setup
✅ Config loading
```

**Expected output:**
```
TEST SUMMARY: table_1
================================================================
✅ Fixture Initialization (XXXms)
✅ Output Driver: led_main (XXXms)
✅ Output Driver: speaker_1 (XXXms)
Results: 3 passed, 0 failed, XXXms total
```

**Success criteria:** All tests pass ✅

---

### STEP 2: ⏳ READY - Test Driver Implementations

**What we're testing:**
- Can each driver activate and deactivate independently?
- Do LED effects work? (pulse, strobe, flicker, etc.)
- Does audio driver search YouTube correctly?
- Can drivers handle errors gracefully?

**Test file to create:** `test_step2_driver_features.py`

**Example test:**
```python
async def test_led_effects():
    led = LEDDriver(config)
    await led.initialize()
    
    # Test different effects
    for effect in ['pulse', 'strobe', 'flicker', 'shimmer', 'fade', 'breathe', 'warm']:
        success = await led.activate({'color': (255, 0, 0), 'effect': effect})
        assert success, f"Effect {effect} failed"
        await asyncio.sleep(1)  # Let it run for 1 second
        await led.deactivate()

async def test_audio_youtube_search():
    audio = AudioDriver(config)
    await audio.initialize()
    
    # Test with a query that should return results
    success = await audio.activate({'query': 'tavern medieval music'})
    assert success, "Audio activation failed"
    
    # Let it play for 5 seconds
    await asyncio.sleep(5)
    await audio.deactivate()
```

**Success criteria:**
- All LED effects render correctly
- Audio finds YouTube videos for various queries
- No crashes or hangs
- Proper error handling

---

### STEP 3: ⏳ READY - Test Voice Input → Output Flow

**What we're testing:**
- Can fixtures process voice input?
- Does the right output get triggered?
- Do multiple outputs coordinate correctly?

**Test file to create:** `test_step3_fixture_logic.py`

**Example test:**
```python
async def test_voice_triggers_tavern_scene():
    fixture = DiningTableFixture(config)
    await fixture.initialize()
    
    # Simulate voice input
    success = await fixture.receive_input(InputEvent(
        source="voice",
        event_type="command",
        data={"text": "let's start in a tavern"}
    ))
    
    assert success
    assert "led_main" in fixture.active_outputs
    assert "speaker_1" in fixture.active_outputs
    
    # Verify LED is orange (tavern color)
    # Verify audio query contains "tavern"
```

**Success criteria:**
- Voice input correctly triggers outputs
- Wrong inputs are rejected gracefully
- Multiple outputs activate together
- Scene detection works for all D&D scenes

---

### STEP 4: ⏳ READY - Extract Music Engine

**What we're doing:**
- Move music query generation from `_get_ambiance_music()` to a reusable engine
- Make it testable without needing YouTube/Pi
- Support multiple strategies (simple keyword maps, AI-powered, etc.)

**Create file:** `fixtures_v2/engines/music_engine.py`

**Example:**
```python
class MusicEngine:
    async def generate_query(self, scene_analysis: dict) -> str:
        """
        Input: {environment, action, mood, intensity}
        Output: "epic battle tavern music orchestral"
        """
        query_parts = []
        
        # Map scene attributes to music terms
        action_map = {
            'fireball': ['epic', 'dramatic', 'intense'],
            'healing': ['peaceful', 'serene', 'magical'],
            ...
        }
        
        environment_map = {
            'tavern': ['medieval', 'folk', 'inn'],
            'dungeon': ['dark', 'underground', 'mysterious'],
            ...
        }
        
        if scene['action'] in action_map:
            query_parts.extend(action_map[scene['action']])
        
        if scene['environment'] in environment_map:
            query_parts.extend(environment_map[scene['environment']])
        
        return ' '.join(query_parts)
```

**Test:**
```python
async def test_music_engine_tavern():
    engine = MusicEngine()
    query = await engine.generate_query({
        'environment': 'tavern',
        'action': 'none',
        'mood': 'social',
    })
    assert 'tavern' in query.lower() or 'medieval' in query.lower()
```

---

### STEP 5: ⏳ READY - Create More Fixture Types

**What we're doing:**
- Create `WallFixture` - only has LED strips (ambient lighting)
- Create `DoorFixture` - has motor + light
- Demonstrate that fixtures are truly modular

**Create files:**
- `fixtures_v2/fixtures/wall.py`
- `fixtures_v2/fixtures/door.py`

**Example (WallFixture):**
```python
class WallFixture(BaseFixture):
    async def initialize(self):
        # Only create LED driver (no audio, no voice input)
        # Can listen to voice via app or Firebase
        
    async def process_input(self, event: InputEvent):
        # "Tavern" scene comes in → wall lights up orange
        # Input from app/Firebase, not local voice
```

---

### STEP 6: ⏳ READY - Server-Side Config & Registry

**What we're doing:**
- Create `fixtures_config.json` - describes all fixtures
- Pi queries server on startup: "Who am I?"
- Server returns: "You're table_1 with LED+Audio"
- Fixture dynamically loads only the drivers it needs

**Config file:**
```json
{
  "fixtures": [
    {
      "fixture_id": "table_1",
      "fixture_type": "dining_table",
      "location": "dining_area",
      "pi_ip": "192.168.48.5",
      "output_drivers": [
        {"driver_id": "led_main", "driver_type": "led", "gpio_pin": 18, "count": 300},
        {"driver_id": "speaker_1", "driver_type": "audio", "sink": "bluez_output.39_3E_58_14_40_4A.1"}
      ],
      "input_drivers": [
        {"driver_id": "voice_input", "driver_type": "voice"}
      ]
    },
    {
      "fixture_id": "wall_tavern",
      "fixture_type": "wall",
      "location": "bar_area",
      "pi_ip": "192.168.48.6",
      "output_drivers": [
        {"driver_id": "led_strip", "driver_type": "led", "gpio_pin": 18, "count": 600}
      ],
      "input_drivers": []
    }
  ]
}
```

**Test:**
```python
registry = FixtureRegistry("fixtures_config.json")
table_1 = registry.get("table_1")
assert table_1.output_drivers[0]['driver_type'] == 'led'
```

---

## Running Tests in Sequence

```bash
# STEP 1: Test the foundation (drivers work)
python fixtures_v2/tests/test_step1_initialization.py

# STEP 2: Test individual drivers (after you create it)
python fixtures_v2/tests/test_step2_driver_features.py

# STEP 3: Test fixture logic (after you create it)
python fixtures_v2/tests/test_step3_fixture_logic.py

# STEP 4: Test music engine (after you extract it)
python fixtures_v2/tests/test_step4_music_engine.py

# Full suite (after all steps complete)
python -m pytest fixtures_v2/tests/ -v
```

---

## Comparison: Old vs New

### Old System (firebase_rest_listener_debug.py)
```
3546 lines in 1 file
├─ LED control (hardcoded to GPIO 18)
├─ YouTube music (embedded in listener)
├─ Firebase polling (always listening)
├─ D&D scene analysis (in listener)
└─ Everything depends on everything

Problems:
❌ Can't test music generation without Pi
❌ Can't add new fixture types without copy-pasting
❌ Can't run multiple fixtures independently
❌ Single point of failure
```

### New System (fixtures_v2/)
```
Multiple focused files
├─ drivers/
│  ├─ led_driver.py    (100 lines, reusable)
│  ├─ audio_driver.py  (200 lines, testable)
│  └─ voice_input_driver.py (50 lines, simple)
├─ fixtures/
│  └─ dining_table.py  (150 lines, logic only)
├─ engines/
│  └─ music_engine.py  (100 lines, testable)
└─ tests/
   └─ test_*.py        (comprehensive testing)

Benefits:
✅ Test drivers without Pi
✅ Test music logic without YouTube
✅ Create new fixtures by combining existing drivers
✅ Each component is independent
✅ Easy to understand & modify
```

---

## Common Questions

**Q: Do I need to deploy this to the Pi now?**
A: No! Test it locally first. All the tests can run on Windows:
- LED effects render in simulation mode (no hardware needed)
- Audio driver tests can mock YouTube search
- Voice input is just a queue

**Q: How do I switch from old system to new?**
A: Gradually:
1. Keep old `firebase_rest_listener_debug.py` running (it works!)
2. Deploy new fixture code to a test Pi
3. Run both in parallel while you migrate
4. Once confident, switch to new system
5. Keep old system as fallback

**Q: What if a driver needs permissions (GPIO, PulseAudio)?**
A: The test mode simulates everything. When you deploy to Pi:
- LED: Runs as-is or with `sudo`
- Audio: PulseAudio already configured on Pi
- Each driver handles its own permissions

**Q: How do I add a new fixture type?**
A: 3 steps:
```python
# 1. Create fixture class
class MyFixture(BaseFixture):
    async def initialize(self):
        # Create only the drivers you need
        self.output_drivers['led'] = LEDDriver(config)
    
    async def process_input(self, event):
        # Your logic here
        return [OutputCommand(...)]

# 2. Create test
async def test_my_fixture():
    fixture = MyFixture(config)
    await fixture.initialize()
    # Test it
    
# 3. Register in config
# Add entry to fixtures_config.json
```

---

## Next Actions

1. **Run Step 1 test** to make sure foundation works
2. **Create Step 2 test** for driver features
3. **Create Step 3 test** for voice→output flow
4. **Extract music engine** to separate module
5. **Create WallFixture** to prove modularity
6. **Deploy to Pi** and test end-to-end

Each step should be committed to git:
```bash
git add fixtures_v2/
git commit -m "STEP N: Description of what was added and tested"
```

---

## Success Criteria for Each Step

| Step | Criteria | Test File |
|------|----------|-----------|
| 1 | Fixtures initialize, drivers register | test_step1_initialization.py |
| 2 | Individual drivers work correctly | test_step2_driver_features.py |
| 3 | Voice input → outputs activate | test_step3_fixture_logic.py |
| 4 | Music engine generates queries | test_step4_music_engine.py |
| 5 | Multiple fixture types work | test_step5_multiple_fixtures.py |
| 6 | Server config works | test_step6_registry.py |

---

## Git Workflow

```bash
# Current state: main branch with working system
git log --oneline
# 3b91b86 BACKUP: Working AI music system v0.8.3+140

# New branch for refactoring
git checkout refactor/modular-fixtures

# After each step, commit and tag
git commit -m "STEP N: Description"
git tag "v2.0.stepN"

# Keep both branches alive
# main = production ready (old system)
# refactor/modular-fixtures = work in progress (new system)
```

---

## File Structure Summary

```
✅ fixtures_v2/core/
   ✅ __init__.py
   ✅ driver_base.py       (InputDriver, OutputDriver)
   ✅ fixture_base.py      (BaseFixture)
   ✅ registry.py          (FixtureRegistry)

✅ fixtures_v2/drivers/
   ✅ led_driver.py
   ✅ audio_driver.py
   ✅ voice_input_driver.py

✅ fixtures_v2/fixtures/
   ✅ dining_table.py

✅ fixtures_v2/engines/
   (NOT YET - ready for Step 4)

✅ fixtures_v2/tests/
   ✅ test_harness.py
   ✅ test_step1_initialization.py
   
📄 This file: MODULAR_ARCHITECTURE.md
```

---

## Questions? 

The goal is to build something **testable**, **maintainable**, and **scalable**.

Each step should:
1. ✅ Add code
2. ✅ Have tests
3. ✅ Be committed to git
4. ✅ Show that it works

Let me know when you're ready to run the first test!
