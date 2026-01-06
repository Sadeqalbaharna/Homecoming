# 🎭 Interactive D&D Scenario Testing Guide

## Quick Test Matrix

Test each scene by speaking to Kai in the Homecoming app or using the command line.

### Scene Test Commands

| Scene | Say This | Effect | Expected Color | Music |
|-------|----------|--------|-----------------|-------|
| 🍺 Tavern | "Play tavern music" | Warm | Orange (255,140,0) | Medieval |
| 🌲 Forest | "Forest ambiance" | Shimmer | Green (34,139,34) | Nature |
| 🏰 Dungeon | "Spooky dungeon" | Pulse | Purple (100,50,150) | Horror |
| 👑 Castle | "Castle scene" | Steady | Gold (200,150,100) | Throne Room |
| ⚔️ Battle | "Battle stations!" | Strobe | Red (255,0,0) | Epic Combat |
| 👻 Spooky | "Make it spooky" | Pulse | Indigo (75,0,130) | Ghost |
| 👻⚓ **Ship** | "Haunted ship" | **Flicker** | **Teal (0,100,150)** | **Pirate Ghost** |

---

## 🧪 Test Scenarios

### Scenario 1: D&D Session Setup
**Context**: Starting a D&D campaign, setting the mood

```
Step 1: Say "Let's start with a tavern scene"
        → Warm orange lights
        → Medieval tavern music
        → Party gathers at the inn

Step 2: DM: "You descend into the dungeon"
        → Lights turn purple with pulse effect
        → Spooky music plays
        → Players feel on edge

Step 3: Combat starts!
        → Lights strobe red
        → Epic battle music blares
        → Adrenaline spike!

Step 4: Escape to safety
        → Green shimmer activates
        → Forest sounds
        → Relief and recovery
```

### Scenario 2: Haunted Campaign
**Context**: Testing the new haunted ship scene

```
Step 1: "We approach a ghostly ship on the horizon"
        → Dark teal lights with flicker
        → Eerie pirate ghost crew sounds
        → Tension builds

Step 2: Lights flicker mysteriously
        → Crew sees ghostly figures
        → Music intensifies

Step 3: Lights stop, ship disappears
        → Scene ends
        → Mystery lingers
```

### Scenario 3: Complete Journey
**Context**: Multi-scene story progression

```
Scene 1: Castle Throne Room
        Command: "Enter the grand castle"
        → Gold lights, steady and regal
        → Formal music plays

Scene 2: Castle Vault 
        Command: "Descend to the vault"
        → Lights fade to purple pulse
        → Mysterious dungeon sounds
        → Everyone quiet with tension

Scene 3: Treasure Room Ambush
        Command: "Combat!"
        → Red strobe lights
        → Battle music
        → Everyone excited

Scene 4: Escape Through Forest
        Command: "Run to the forest!"
        → Green shimmer
        → Peaceful nature sounds
        → Safe haven reached
```

### Scenario 4: Horror Story
**Context**: Spooky ghost story night

```
Scene 1: Haunted House Exterior
        → Spooky indigo pulse
        → Ghost sounds
        → Eerie atmosphere

Scene 2: Abandoned Ship Discovery
        → Switch to haunted ship
        → Dark teal flicker
        → Ghostly crew moans
        → Creepier than the house!

Scene 3: Escape
        → Battle red strobe (running for lives!)
        → Epic escape music
        → Victory!
```

---

## 📱 Testing with Homecoming App

### Step-by-Step

1. **Ensure Pi is Running**
   ```bash
   ssh pi@192.168.48.5
   cd /home/pi
   # Leave one of these running:
   python3 test_firebase_integration.py --test full
   # OR
   python3 test_end_to_end.py
   ```

2. **Open Homecoming App**
   - On your mobile device
   - Navigate to chat with Kai

3. **Speak Commands**
   - Natural language works
   - Try: "Play tavern music"
   - Then: "Switch to spooky"
   - Then: "Give me a haunted ship"

4. **Watch Terminal**
   - See Firebase command arrive
   - See scene detection happen
   - See music/LEDs activate

5. **Experience**
   - Listen to music on speaker
   - Watch LEDs (if available)
   - Feel the atmosphere change

---

## 🎯 Testing Checklist

### For Each Scene

- [ ] **Voice Input Works**
  - Speak command to Kai
  - App understands intent

- [ ] **Firebase Transmits**
  - See command in Firebase console
  - Command reaches Pi

- [ ] **Scene Detected**
  - Terminal shows scene name
  - Confidence level shows (0.9)

- [ ] **LED Colors Correct**
  - Expected RGB shows in terminal
  - Effect type matches

- [ ] **Music Starts**
  - Search query shows in terminal
  - YouTube download begins
  - Music plays on speaker

- [ ] **Audio Plays**
  - Hear music on Bluetooth
  - Volume is appropriate (10%)
  - Duration is expected (3-20 min)

### Scene-Specific Tests

#### Tavern ✅
- [ ] Color: Orange/warm
- [ ] Effect: Steady glow
- [ ] Music: Medieval tavern sounds
- [ ] Feel: Cozy, social

#### Forest ✅
- [ ] Color: Green
- [ ] Effect: Shimmer (wave)
- [ ] Music: Nature ambient
- [ ] Feel: Peaceful, calm

#### Dungeon ✅
- [ ] Color: Purple
- [ ] Effect: Pulse (breathing)
- [ ] Music: Spooky horror
- [ ] Feel: Creepy, mysterious

#### Castle ✅
- [ ] Color: Gold
- [ ] Effect: Steady bright
- [ ] Music: Throne room
- [ ] Feel: Grand, majestic

#### Battle ✅
- [ ] Color: Red
- [ ] Effect: Strobe (flashing)
- [ ] Music: Epic combat
- [ ] Feel: High energy

#### Spooky ✅
- [ ] Color: Indigo
- [ ] Effect: Pulse (eerie)
- [ ] Music: Ghost sounds
- [ ] Feel: Terrifying

#### Haunted Ship ✅
- [ ] Color: Teal blue
- [ ] Effect: Flicker (lanterns)
- [ ] Music: Pirate ghosts
- [ ] Feel: Maritime eerie

---

## 🔧 Troubleshooting

### Music Doesn't Play
```bash
# Check speaker is connected
pactl list sinks | grep bluez

# Check mpv is installed
mpv --version

# Test directly on Pi
pactl set-sink-volume bluez_output.39_3E_58_14_40_4A.1 50%
timeout 10 mpv --audio-device='pulse/bluez_output.39_3E_58_14_40_4A.1' /tmp/tavern.mp3
```

### Scene Not Detected
```bash
# Check the prompt in terminal
# Make sure scene keyword is in prompt
# "tavern" in "Play tavern music" → DETECTED ✅
# "music" without scene → NOT DETECTED ✗

# Try exact scene names:
- tavern
- forest
- dungeon
- castle
- battle
- spooky
- haunted ship
```

### Firebase Command Not Received
```bash
# Check Firebase connection
curl -X GET https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app/home_automation/kai_persona_1/commands.json

# If it works, app will see it
# If error, check internet on both devices
```

### LED Not Lighting (GPIO)
```bash
# Need sudo for GPIO access
sudo python3 test_firebase_integration.py --test ship

# Or run as background service with sudo
```

---

## 📊 Testing Results Format

After each test, record:

```
Scene: Haunted Ship
Date: 2026-01-06
Time: 23:03

✅ Firebase: Sent successfully (cmd_1767729803899)
✅ Scene Detection: haunted ship (confidence 0.9)
✅ LED Colors: (0, 100, 150) - Correct ✓
✅ Effect: Flicker - Correct ✓
✅ Music Query: "haunted pirate ship..." - Correct ✓
✅ Audio: Played for 20 seconds
✅ Bluetooth: TG-129C working

Notes: Perfect! Eerie atmosphere achieved.
```

---

## 🎮 Advanced Testing

### Test Custom Prompts
```python
# In test_firebase_integration.py, change:
command_id = firebase_client.send_dnd_ambiance("your custom prompt")

# Will use custom music search
# If no scene match, uses prompt as music query
```

### Test Edge Cases
```
- Very long prompt: "Give me a very spooky haunted ship"
- Multiple scenes: "Tavern then haunted ship" → detects first
- No scene match: "Play music" → uses custom search
- Misspelling: "havnted ship" → no match, custom search
- Abbreviation: "ship" → "haunted ship" not matched
```

### Test Rapid Switching
```
Command 1: Tavern
Wait 5s
Command 2: Haunted Ship
Wait 5s
Command 3: Battle

Observe: Does music stop/start smoothly?
         Do LEDs transition smoothly?
```

---

## ✨ Summary

You can now:

1. **Test via App**: Speak to Kai naturally
2. **Test via CLI**: Run command line tests
3. **Test Any Scenario**: Create your own D&D story
4. **Add Custom Scenes**: Easy to extend
5. **Monitor Everything**: See it all in the terminal

The complete system is:
- ✅ Deployed on Pi
- ✅ Firebase integrated
- ✅ Bluetooth tested
- ✅ 7 scenes working
- ✅ Ready for production

**Time to have fun with it!** 🎉
