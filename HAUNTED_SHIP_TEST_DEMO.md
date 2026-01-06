# Testing the Haunted Ship Scene - Live Demo

## 🎬 What Happens When You Say "Haunted Ship"

### Phase 1: Voice Input (Homecoming App)
```
User speaks: "Play a haunted ship atmosphere"
         ↓
App's ambiance_service.dart detects intent
         ↓
Kai AI recognizes: "haunted ship" scene
         ↓
home_automation_service.dart sends to Firebase
```

### Phase 2: Firebase Transmission
```
Firebase REST API receives command:
{
  "type": "ambiance_command",
  "voice_input": "Play a haunted ship atmosphere",
  "action": "set_ambiance",
  "timestamp": "2026-01-06T23:03:23.899Z"
}
         ↓
Command stored at:
/home_automation/kai_persona_1/commands/cmd_1767729803899
         ↓
Status: ✅ Sent successfully (500ms latency)
```

### Phase 3: Pi Reception & Processing
```
2026-01-06 23:03:25,380 - InputDriver.kai_ai_input - INFO
📡 Firebase command received

         ↓

2026-01-06 23:03:25,380 - fixtures_v2.drivers.kai_ai_input_driver
✅ D&D Scene detected: haunted ship

         ↓

2026-01-06 23:03:25,380 - Fixture.dining_table_1 - INFO
🎭 Kai AI Scene: haunted ship (confidence: 0.9)
💡 LED: (0, 100, 150) flicker
🎵 Music: haunted pirate ship ghost crew eerie ocean
```

### Phase 4: LED & Audio Activation
```
LED Driver:
  ├─ Color: (0, 100, 150) - Dark teal blue
  ├─ Effect: Flicker - Like old ship lanterns in fog
  ├─ Brightness: 140 - Dim, eerie
  └─ Status: Activated ✅

         ↓

Audio Driver:
  ├─ Search Query: "haunted pirate ship ghost crew eerie ocean"
  ├─ YouTube: Finding music...
  ├─ Download: /tmp/haunted_pirate_ship_ghost_crew_eerie_ocean.mp3
  ├─ Player: mpv (playing via Bluetooth)
  └─ Volume: 10% (testing level)
```

### Phase 5: Real-Time Output

#### Visual (LEDs)
```
🔷🔷🔷🔷🔷🔷🔷
🔷 Dark Teal Flicker 🔷  ← Like ship lanterns flickering
🔷🔷🔷🔷🔷🔷🔷

RGB: (0, 100, 150)
Effect: Flicker [Brightness 140]
     ░░░░░░░░░  (fading)
     ████████░  (brightening)
     ░░░░░░░░░  (fading)
```

#### Audio (Bluetooth Speaker)
```
🎙️ "Haunted Pirate Ship" Music
   ► ━━━━━━━━━ 0:00 / 3:42
   
   🔊 [eerie creaking sounds]
   🔊 [ghostly moans]
   🔊 [ocean waves]
   🔊 [ship timber groaning]
   🔊 [chains rattling]
   
   Playing on: TG-129C Bluetooth Speaker
   Volume: 10% (you'll hear it clearly)
   Duration: ~3-4 minutes typical
```

---

## 📊 Scene Comparison: What's Special About Haunted Ship?

| Aspect | Tavern | Forest | Dungeon | **Haunted Ship** |
|--------|--------|--------|---------|-----------------|
| **Color** | Warm Orange | Green | Purple | **Dark Teal** |
| **Brightness** | 200 (Bright) | 180 (Natural) | 100 (Dark) | **140 (Eerie)** |
| **Effect** | Warm | Shimmer | Pulse | **Flicker** |
| **Vibe** | Social/Cozy | Calm/Natural | Spooky/Dark | **Maritime/Eerie** |
| **Music** | Medieval tavern | Nature ambient | Dungeon horror | **Pirate ghost crew** |
| **Unique** | Welcoming | Peaceful | Mysterious | **Nautical + Spooky** |

---

## 🧪 Live Test Output

Here's what you'll see in the terminal when testing:

```bash
$ python3 test_firebase_integration.py --test ship

╔════════════════════════════════════════════════════════════════════════════╗
║                  FIREBASE INTEGRATION TEST SUITE                           ║
║           Homecoming App → Firebase → Pi → Bluetooth Speaker               ║
╚════════════════════════════════════════════════════════════════════════════╝

2026-01-06 23:03:23,541 - Fixture.dining_table_1 - INFO
🎭 Initializing dining_table fixture...

2026-01-06 23:03:23,541 - InputDriver.voice_input - INFO
🎤 Voice input driver started

2026-01-06 23:03:23,899 - OutputDriver.speaker_1 - INFO
✅ mpv found: mpv

2026-01-06 23:03:23,899 - Fixture.dining_table_1 - INFO
✅ dining_table_1 ready!

════════════════════════════════════════════════════════════════════════════
                        👻⚓ HAUNTED SHIP SCENE
      Eerie pirate ghost ship with creepy ocean sounds
════════════════════════════════════════════════════════════════════════════

2026-01-06 23:03:23,899 - __main__ - INFO
📡 Sending haunted ship command...
   Voice input: 'haunted ship'

2026-01-06 23:03:23,899 - __main__ - INFO
📡 Sending to Firebase: https://homecoming-74f73-default-rtdb.europe-west1...

2026-01-06 23:03:24,377 - __main__ - INFO
✅ Firebase command sent successfully
   Command ID: cmd_1767729803899
   Voice Input: haunted ship

2026-01-06 23:03:24,378 - __main__ - INFO
⏳ Processing haunted ship ambiance...

2026-01-06 23:03:25,380 - __main__ - INFO
🎭 Fixture processing scene interpretation...

2026-01-06 23:03:25,380 - fixtures_v2.drivers.kai_ai_input_driver - INFO
✅ D&D Scene detected: haunted ship

2026-01-06 23:03:25,380 - Fixture.dining_table_1 - INFO
🎭 Kai AI Scene: haunted ship (confidence: 0.9)
💡 LED: (0, 100, 150) flicker
🎵 Music: haunted pirate ship ghost crew eerie ocean

2026-01-06 23:03:25,380 - __main__ - INFO
⚡ Executing 2 commands:
   ✓ led_main: activate
   ✓ speaker_1: activate (download & play)

════════════════════════════════════════════════════════════════════════════
  👻 Eerie ghost crew sounds...
  💡 LEDs showing dark blue ocean colors...
  ⚓ Creaking ship timber sounds...
════════════════════════════════════════════════════════════════════════════

2026-01-06 23:03:25,380 - __main__ - INFO
📻 Listening for 20 seconds...

  [████████████████████░░░░] 90%
  
2026-01-06 23:03:45,380 - __main__ - INFO
⏹️  Stopping haunted ship ambiance...

════════════════════════════════════════════════════════════════════════════
                     HAUNTED SHIP TEST COMPLETE
════════════════════════════════════════════════════════════════════════════

✅ WHAT YOU SHOULD HAVE HEARD/SEEN:
   1. Eerie pirate ghost ship music started playing
   2. Dark blue LEDs (0, 100, 150) lit up with flicker effect
   3. Music featured creepy ocean/ghost sounds
   4. Bluetooth speaker played for ~20 seconds

🎭 SCENE DETAILS:
   Color: Dark teal blue (0, 100, 150)
   Effect: Flicker (like candles on a ghost ship)
   Music: Haunted pirate ship with ghost crew sounds
   Brightness: 140 (dimmer for spooky effect)

✨ This is a brand new D&D scene just added!
```

---

## 🎯 Why Haunted Ship?

The haunted ship scene uniquely combines:

1. **Maritime Theme**: Specific to ocean/ship scenarios
   - Not just "spooky" (dungeon), but spooky + nautical
   - Adds thematic depth to D&D campaigns

2. **Distinctive Color**: Dark teal (0, 100, 150)
   - Different from dungeon purple (100, 50, 150)
   - Suggests water/ocean environment
   - Eerie but recognizable as nautical

3. **Unique Effect**: Flicker
   - Like ship's lanterns in fog
   - More organic than strobe (battle) or pulse (dungeon)
   - Suggests unstable/ghostly lighting

4. **Layered Atmosphere**: Ghost crew + pirate ship
   - Combines multiple horror elements
   - Creates a specific, memorable scene
   - Different from generic "spooky"

---

## 🚀 Quick Start

To experience the haunted ship scene:

### Option 1: Command Line Test (Immediate)
```bash
ssh pi@192.168.48.5
cd /home/pi
python3 test_firebase_integration.py --test ship
# Listen for 20 seconds of eerie pirate music!
```

### Option 2: Real App Test (Full Experience)
1. Open Homecoming app on mobile
2. Say: "Play a haunted ship scene"
3. Watch Pi respond with lights and sounds
4. Tell your D&D friends about the cool atmosphere!

### Option 3: All Scenes Test
```bash
python3 test_firebase_integration.py --test full
# Tests all 7 scenes in sequence:
# 1. Tavern (warm orange)
# 2. Forest (green shimmer)
# 3. Dungeon (purple pulse)
# + 4 more including haunted ship!
```

---

## ✨ The Cool Part

When you say "haunted ship" to Kai in the Homecoming app:
- **It actually works** ✅
- **Lights up with ocean blue** ✅
- **Plays eerie ghost ship music** ✅
- **All in real-time** ✅
- **From anywhere** (Firebase handles it) ✅

This is the full magic of the system working together!

---

## 📈 What's Next?

You can easily add more scenes:

```python
# In kai_ai_input_driver.py, add:
'underwater palace': {
    'music_query': 'ethereal underwater ambient palace music',
    'lighting': {'color': (0, 255, 200), 'effect': 'shimmer', 'brightness': 190},
    'confidence': 0.9,
},
```

That's it! The system handles the rest. 🪄
