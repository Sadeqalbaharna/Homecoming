# Kai AI Integration Architecture

## Overview
The homecoming app (Dart/Flutter) has a full AI system that understands natural language and generates intelligent music/lighting commands. We're now integrating this with the Pi's modular fixture system.

## Complete Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│ HOMECOMING APP (Dart/Flutter) - Running on Mobile/Desktop               │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    User speaks to Kai: "Play some tavern music"
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ lib/services/ai_service.dart                                             │
│ - Sends voice text to OpenAI/ChatGPT API                                 │
│ - Gets intelligent response with personality/mood delta                  │
│ - Returns tags like "music", "relaxing", "tavern"                       │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ lib/services/ambiance_service.dart                                       │
│ - Analyzes response for D&D/ambiance keywords                            │
│ - Detects scene: "tavern" → music_mood = "tavern"                       │
│ - Generates lighting config: warm orange colors                          │
│ - Sets confidence level based on AI response                             │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ lib/services/home_automation_service.dart                                │
│ - Sends command to Firebase Database                                     │
│ - Command format:                                                         │
│   {                                                                       │
│     "device": "raspberry_pi_home",                                       │
│     "target": "ambiance",                                                │
│     "action": "dnd_ambiance",                                            │
│     "prompt": "tavern music",                                            │
│     "include_music": true,                                               │
│     "include_smoke": false,                                              │
│     "timestamp": 1234567890                                              │
│   }                                                                       │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    Firebase Realtime Database (Cloud)
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ RASPBERRY PI - fixtures_v2                                               │
│ Receives command from Firebase                                           │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ fixtures_v2/drivers/kai_ai_input_driver.py (NEW)                        │
│ - Listens to Firebase for ambiance commands                              │
│ - Interprets "tavern music" → music search + lighting                    │
│ - Creates InputEvent with analyzed data                                  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ fixtures_v2/fixtures/dining_table.py                                     │
│ - Receives InputEvent from KaiAIInputDriver                              │
│ - process_input() creates OutputCommands for:                            │
│   1. LED driver with lighting config (color, effect, brightness)         │
│   2. Audio driver with music_query ("tavern music")                      │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                        ┌──────────┴──────────┐
                        │                     │
                        ▼                     ▼
┌──────────────────────────────┐  ┌──────────────────────────────┐
│ fixtures_v2/drivers/led_...  │  │ fixtures_v2/drivers/audio..  │
│ - Set LED color to warm      │  │ - Search YouTube for prompt  │
│   orange (255, 140, 0)       │  │ - Download tavern music MP3  │
│ - Apply "warm" effect        │  │ - Play via mpv on Bluetooth  │
│ - Brightness 200             │  │   speaker                     │
└──────────────────────────────┘  └──────────────────────────────┘
                        │                     │
                        ▼                     ▼
                   ┌─────────────────────────────┐
                   │  HOME RESULT                │
                   │  🔆 Warm LED lighting       │
                   │  🎵 Tavern music playing    │
                   └─────────────────────────────┘
```

## What Makes This Intelligent

### 1. **Natural Language Understanding (Homecoming App)**
   - Kai the AI parses: "Play some tavern music"
   - Uses ChatGPT to understand context and intent
   - Detects D&D/fantasy themes
   - Generates personality response with mood delta

### 2. **Scene Detection (ambiance_service.dart)**
   - Keywords: "tavern", "dungeon", "forest", "castle", "battle", "spooky"
   - Each scene has predefined:
     - Music search prompt
     - Lighting color (RGB)
     - Lighting effect (warm, pulse, shimmer, etc.)
     - Confidence level

### 3. **Command Execution (Pi Fixture)**
   - KaiAIInputDriver receives Firebase command
   - KaiCommandInterpreter analyzes the scene
   - Routes to appropriate drivers:
     - Audio driver: Downloads and plays music
     - LED driver: Sets color/effect/brightness
   - Both activate simultaneously

## Firebase Command Schema

```json
{
  "home_automation": {
    "kai_persona_1": {
      "commands": {
        "cmd_1704568789": {
          "device": "raspberry_pi_home",
          "target": "ambiance",
          "action": "dnd_ambiance",
          "prompt": "tavern music",
          "include_music": true,
          "include_smoke": false,
          "timestamp": 1704568789
        }
      },
      "responses": {
        "cmd_1704568789": {
          "success": true,
          "message": "Tavern ambiance activated",
          "devices": ["led_main", "speaker_1"]
        }
      }
    }
  }
}
```

## Scene Mapping (Hardcoded in kai_ai_input_driver.py)

| Scene | Music Query | LED Color | Effect | Brightness |
|-------|-------------|-----------|--------|------------|
| tavern | medieval tavern music ambience | (255, 140, 0) | warm | 200 |
| dungeon | dark spooky dungeon ambience | (100, 50, 150) | pulse | 100 |
| forest | peaceful forest nature ambient | (34, 139, 34) | shimmer | 180 |
| castle | medieval castle throne room | (200, 150, 100) | steady | 220 |
| battle | epic battle combat music | (255, 0, 0) | strobe | 255 |
| spooky | creepy ghost spooky horror | (75, 0, 130) | pulse | 80 |

## Usage

### For Testing (Without Homecoming App)
```python
# test_kai_integration.py
from fixtures_v2.fixtures.dining_table import DiningTableFixture
from fixtures_v2.core.fixture_base import InputEvent

# Create fixture
fixture = DiningTableFixture(...)

# Simulate Kai's "tavern music" command
input_event = InputEvent(
    source="kai_ai",
    event_type="dnd_ambiance",
    data={
        "prompt": "tavern music",
        "confidence": 0.9
    }
)

# Process and execute
commands = await fixture.process_input(input_event)
for cmd in commands:
    await fixture.execute_output(cmd)
```

### For Real Integration (With Homecoming App)
1. User speaks to Kai app: "Play tavern music"
2. Kai analyzes and detects "tavern" scene
3. Sends Firebase command
4. KaiAIInputDriver listens and receives it
5. Fixture automatically activates LEDs and music

## Next Steps

1. ✅ Create KaiAIInputDriver (done)
2. ⏳ Update DiningTableFixture to support KaiAIInputDriver
3. ⏳ Set up Firebase credentials on Pi
4. ⏳ Test end-to-end with homecoming app
5. ⏳ Add more D&D scenes as needed

## Configuration Required

On Pi, you need:
1. Firebase credentials (JSON service account)
2. Firebase database URL
3. Persona ID matching homecoming app
4. Device ID matching what app sends

See: `FIREBASE_SETUP.md` for key generation

