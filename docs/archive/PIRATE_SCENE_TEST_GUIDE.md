# Pirate Ship Scene Test - End-to-End Pipeline

## What's Happening

This test validates the complete scene pipeline:

```
1. Pirate Ship Scene JSON (local file)
   ↓
2. Send to Firebase (send_pirate_scene.py)
   ↓
3. Firebase stores scene with status="pending"
   ↓
4. Pi listener watches Firebase (firebase_scene_executor.py on Pi)
   ↓
5. Pi detects new "pending" scene
   ↓
6. Pi executes:
   • 🔊 YouTube audio search & playback on Bluetooth speaker at 20% volume
   • 💡 LED wave animation (blue/dark blue ocean colors)
   • 📊 Updates Firebase status: pending → executing → completed
   ↓
7. Mobile app sees status updates in real-time
   ↓
8. Listen to Bluetooth speaker for pirate ship sea shanty! 🏴‍☠️
```

## Files Involved

### Windows/Local Files
- **pirate_ship_scene.json** - Scene definition with audio query, LED colors, duration
- **send_pirate_scene.py** - Script to upload scene to Firebase and monitor execution

### Raspberry Pi Files
- **firebase_scene_executor.py** - Listener that watches Firebase and executes scenes
- **fixtures_v2/drivers/audio_driver.py** - Handles YouTube audio streaming
- **fixtures_v2/drivers/led_driver.py** - Handles LED animations
- **fixtures_v2/core/driver_base.py** - Base driver framework

## Pre-requisites

✅ **Already Done:**
- Pi connected to TG-129C Bluetooth speaker
- fixtures_v2/ deployed to Pi
- SSH key authentication configured
- Firebase project accessible

## Step-by-Step Test

### Step 1: Deploy Scene Executor to Pi
```bash
python3 deploy_scene_executor.py
```
This will:
- Connect to Pi via SSH
- Upload firebase_scene_executor.py
- Start the listener (runs indefinitely, watching Firebase)

Keep this running in a separate terminal.

### Step 2: Send Pirate Scene to Firebase
```bash
python3 send_pirate_scene.py
```
This will:
- Load pirate_ship_scene.json
- Send to Firebase under `scene_prompts/scene_20260107_143022_pirate_ship`
- Set status="pending"
- Wait for Pi to execute (polls Firebase for status changes)
- Show real-time updates:
  - ⏳ Status: PENDING
  - ✅ Status: EXECUTING (when Pi picks it up)
  - ✅ Status: COMPLETED (when scene finishes)

### Step 3: Listen for Audio

**Expected Output on Bluetooth Speaker:**
- Pirate ship sea shanty music at 20% volume
- 🔊 Audio query: "pirate ship sea shanty D&D ambiance music"

**Expected LED Behavior:**
- Wave animation with ocean colors (dark blue/deep blue)
- Speed: Medium (0.5x)
- Brightness: 180/255

**Expected Duration:**
- Scene runs for 300 seconds (5 minutes)
- Then stops and updates Firebase to status="completed"

## Monitoring

### Option 1: Monitor via Firebase Console
Visit: https://console.firebase.google.com/u/0/project/homecoming-kai/firestore/data/scene_prompts

Watch the status field change in real-time:
```
execution.status: pending → executing → completed
execution.started_at: [timestamp]
execution.completed_at: [timestamp]
```

### Option 2: Watch Pi Terminal
If you SSH into the Pi, you should see logging from firebase_scene_executor.py:
```
2026-01-07 14:30:22 - root - INFO - 🎭 EXECUTING SCENE: PIRATE SHIP ADVENTURE
   📖 Scene Type: tavern
   🎭 Mood: epic
   📝 A swashbuckling pirate ship on the high seas...
   
   🔊 Starting audio: 'pirate ship sea shanty D&D ambiance music'
   💡 Setting up lighting: wave
   ✅ Audio playback started
   ✅ Lighting animation started
   ⏱️ Scene running for 300 seconds...
   ✅ SCENE COMPLETED
```

## Troubleshooting

### Issue: Firebase connection fails
- Check: WIFI is connected on Pi
- Check: Firebase project ID is correct in code
- Fix: Update FIREBASE_PROJECT_ID if changed

### Issue: Audio doesn't play
- Check: TG-129C speaker is paired and connected
  ```bash
  ssh pi@192.168.48.5
  bluetoothctl show
  pactl list short sinks  # Look for bluez_output device
  ```
- Check: YouTube search query returns valid stream
  ```bash
  yt-dlp -f "best[ext=m4a]/best" --no-warnings -O "%(url)s" ytsearch1:"pirate ship sea shanty D&D ambiance music" | head -1
  ```

### Issue: LEDs don't light up
- This is non-blocking - audio will still play even if LEDs fail
- Check: GPIO 18 is accessible and WS2812B library is installed
  ```bash
  ssh pi@192.168.48.5
  python3 -c "from rpi_ws281x import PixelStrip; print('✅ WS2812B available')"
  ```

### Issue: Pi listener not detecting scene
- Check: Is deploy_scene_executor.py still running?
- Check: Does firebase_scene_executor.py show startup message in terminal?
- Check: Firebase status is actually "pending" in console

## Scene JSON Structure (Pirate Ship)

```json
{
  "scene": {
    "name": "Pirate Ship Adventure",
    "type": "tavern",
    "mood": "epic",
    "intensity": 0.75,
    "duration_seconds": 300
  },
  "audio": {
    "query": "pirate ship sea shanty D&D ambiance music",
    "volume_percent": 20,
    "loop": true
  },
  "lighting": {
    "animation": "wave",
    "colors": [
      {"r": 0, "g": 51, "b": 102},      # Deep ocean blue
      {"r": 0, "g": 102, "b": 153},    # Medium blue
      {"r": 25, "g": 25, "b": 51}      # Dark blue
    ],
    "speed": 0.5,
    "brightness": 180
  }
}
```

## Expected Timeline

1. **T+0s**: Send scene to Firebase
2. **T+2s**: Pi detects pending scene
3. **T+4s**: Pi searches YouTube for stream URL (instant)
4. **T+5s**: mpv starts playing audio on Bluetooth
5. **T+6s**: LED wave animation starts
6. **T+7s**: Firebase status updates to "executing"
7. **T+7s to T+307s**: Audio and lights continue
8. **T+307s**: Scene duration expires
9. **T+308s**: Firebase status updates to "completed"
10. **T+308s**: Audio stops, lights stop

## Next Steps After This Test

If this works, we've validated:
✅ Firebase → Pi communication
✅ Scene JSON schema
✅ Audio playback on Bluetooth
✅ LED animation system
✅ Status tracking

Then we can:
1. Hook up ChatGPT to generate scene JSON from voice commands
2. Integrate mobile voice capture to trigger the pipeline
3. Build the complete end-to-end system

---

## Quick Command Reference

```bash
# Deploy listener to Pi
python3 deploy_scene_executor.py

# Send scene in separate terminal
python3 send_pirate_scene.py

# Monitor Firebase (web console)
open https://console.firebase.google.com/u/0/project/homecoming-kai/firestore/data/scene_prompts

# Check Pi audio device
ssh pi@192.168.48.5
pactl list short sinks

# Stop listener on Pi
# Ctrl+C in the deploy terminal or SSH kill -9 [PID]
```
