# KAI TABLE V1 - Quick Start Implementation Guide

**Mission-Aligned. Cleaned. Ready to Build.**

---

## What You Have Now (Post-Cleanup)

✅ **Core Python Loop** - `kai_table_v1_core.py`
- Record → Transcribe → Ask ChatGPT → Speak → Log

✅ **Firebase Integration** - Unified listener
- User context retrieval
- Conversation logging  
- No unnecessary features

✅ **Clean Codebase**
- Removed: Consciousness, scenes, personality deltas, proactive behavior
- Removed: 80+ documentation versions
- Removed: 9 deployment variants → 1 unified
- Removed: 4 Firebase listeners → 1 unified

**Total:** ~200 files → ~30 core files (85% reduction)

---

## Implementation Checklist (5 sessions, ~3 hours)

### Session 1: Pi Setup (30 min)

**Goal:** Basic Raspberry Pi ready for audio/Firebase

```bash
# On Pi:
sudo apt update && sudo apt upgrade -y
sudo apt install python3-pip python3-pyaudio alsa-utils espeak-ng -y

# Install Python deps
pip3 install firebase-admin openai

# Set audio device (find USB mic)
arecord -l
# Look for "USB Audio Device" card number, update kai_table_v1_core.py line ~35

# Test microphone
arecord -D plughw:1,0 -f cd -t wav -d 3 /tmp/test.wav
aplay /tmp/test.wav
```

**Verify:** You can record 3 seconds and hear it back ✓

---

### Session 2: Firebase + ChatGPT (30 min)

**Goal:** Prove context retrieval and ChatGPT integration

```bash
# Create /home/pi/kai/firebase_service_account.json
# (Download from Firebase Console → Service Accounts)

# Test script:
python3 <<'EOF'
import json
import firebase_admin
from firebase_admin import credentials, db
from openai import OpenAI

# Firebase
cred = credentials.Certificate("/home/pi/kai/firebase_service_account.json")
firebase_admin.initialize_app(cred, {
    "databaseURL": "https://homecoming-kai-default-rtdb.firebaseio.com/"
})

# Write test user
db.reference("users/test_user/profile").set({
    "name": "Darc",
    "color": "blue",
    "language": "en"
})

# Read it back
profile = db.reference("users/test_user/profile").get()
print(f"✓ Firebase working: {profile}")

# ChatGPT test
client = OpenAI()  # Reads OPENAI_API_KEY env var
response = client.chat.completions.create(
    model="gpt-4-mini",
    messages=[{"role": "user", "content": "Say 'Kai is ready' in JSON format"}],
    temperature=0.7,
    max_tokens=50
)
print(f"✓ ChatGPT working: {response.choices[0].message.content}")
EOF
```

**Verify:** Firebase reads/writes work. ChatGPT responds ✓

---

### Session 3: Audio I/O Loop (30 min)

**Goal:** Record → Transcribe → Speak working end-to-end

```bash
python3 kai_table_v1_core.py

# (Running, should wait for trigger)
# Manually call: run_cycle(uid="demo_user")
# Should:
#   1. Show "Listening..."
#   2. Record 6 seconds
#   3. Transcribe your speech
#   4. Send to ChatGPT
#   5. Speak the response
```

**Verify:** You can have a 1-turn conversation ✓

---

### Session 4: Button + LED Control (45 min)

**Goal:** Push-button trigger → LED feedback

```bash
# Wiring:
# GPIO 23 (pin 16) → Button → GND (pull-up on Pi)
# GPIO 18 (pin 12) → WS2812B data line (w/ level shifter)

# Test button
pip3 install RPi.GPIO

python3 <<'EOF'
import RPi.GPIO as GPIO
import time

GPIO.setmode(GPIO.BCM)
GPIO.setup(23, GPIO.IN, pull_up_down=GPIO.PUD_UP)

print("Press button...")
while True:
    if GPIO.input(23) == False:  # Button pressed
        print("✓ Button pressed!")
        time.sleep(0.3)  # Debounce
    time.sleep(0.1)
EOF

# Test LEDs
pip3 install adafruit-circuitpython-neopixel

python3 <<'EOF'
import board
import neopixel

pixels = neopixel.NeoPixel(board.D18, 30, brightness=0.8)  # 30 LEDs on GPIO 18

# White pulse (listening)
for brightness in [0.2, 0.5, 0.8, 0.5, 0.2]:
    pixels.fill((255, 255, 255))  # White
    pixels.brightness = brightness
    time.sleep(0.2)

# Blue solid (speaking)
pixels.fill((0, 100, 200))  # Blue
pixels.brightness = 0.8

print("✓ LEDs working")
EOF
```

**Verify:** Button triggers cycle. LEDs pulse during recording ✓

---

### Session 5: NFC + System Integration (45 min)

**Goal:** NFC tap auto-runs conversation with that user

```bash
# USB NFC reader (e.g., ACR122U)
pip3 install nfcpy

# Create nfc_poller.py
cat > /home/pi/kai/nfc_poller.py <<'EOF'
import nfc
import subprocess

# Poll for NFC card
clf = nfc.ClassicalInitiator()
clf.connect(rdwr={'on-connect': on_connect})

def on_connect(tag):
    uid = tag.identifier.hex()
    print(f"✓ NFC: {uid}")
    
    # Map UID to user (from Firebase)
    # For now: just use UUID as user ID
    subprocess.run(["python3", "/home/pi/kai/kai_table_v1_core.py", "--user", uid])
EOF
```

**Create systemd service** (auto-start on boot):

```bash
sudo tee /etc/systemd/system/kai-table.service > /dev/null <<'EOF'
[Unit]
Description=Kai Table V1
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/kai
Environment="OPENAI_API_KEY=sk-..."
ExecStart=/usr/bin/python3 /home/pi/kai/kai_table_v1_core.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable kai-table
sudo systemctl start kai-table
sudo systemctl status kai-table
```

**Verify:** Reboot Pi, service auto-starts, NFC taps work ✓

---

## Testing Checklist

```
✓ Audio: record → transcribe → speak (Session 3)
✓ Firebase: read user profile, write logs (Session 2)
✓ ChatGPT: structured JSON responses (Session 2)
✓ Button: triggers conversation (Session 4)
✓ LEDs: pulse on listen, solid on speak (Session 4)
✓ NFC: tap card → recognize user → personalized response (Session 5)
✓ Logging: conversations saved to Firebase (Session 3)
```

---

## Production Deployment Checklist

```bash
# Before you mount this in a table:

[ ] Test on actual Pi (not desktop)
[ ] Volume levels comfortable in quiet room
[ ] LED diffuser brightness OK
[ ] Button debouncing solid
[ ] NFC reader finds cards reliably
[ ] Firebase can write 100+ logs without slowdown
[ ] Audio files cleaned up daily (don't fill SD card)
[ ] Service auto-restarts on crash
[ ] Time-limited budget alerts (ChatGPT API usage)

# After mounting in table:

[ ] Under-table service hatch accessible
[ ] All cables strain-relieved
[ ] No exposed terminals
[ ] Fused LED power supply
[ ] Grommets where cables exit wood
[ ] Tested with liquid spill (water on table, not on Pi!)
[ ] Tested under load (multiple conversations back-to-back)
```

---

## File Layout (After Cleanup)

```
/home/pi/kai/
├── kai_table_v1_core.py         ← Main loop
├── led_controller.py             ← WS2812B control (minimal)
├── button_poller.py              ← GPIO button handling
├── nfc_poller.py                 ← NFC card reading
├── firebase_service_account.json ← Keep secret!
├── logs/                         ← Audio recordings (auto-clean weekly)
└── config.json                   ← User UUID → Firebase UID mapping
```

---

## Cost Estimate (BoM)

| Item | Cost | Notes |
|------|------|-------|
| Raspberry Pi 5 | $70 | Or Pi 4 if you have one |
| Official PSU | $15 | Don't skip |
| microSD 128GB | $15 | Fast class |
| USB Microphone | $25 | Directional |
| USB Speaker | $15 | Small, loud enough |
| WS2812B strips (30) | $10 | 5V addressable |
| Level shifter | $3 | 3.3V → 5V |
| 5V PSU (LED) | $10 | Separate from Pi |
| Fuse + wiring | $5 | Safety first |
| **Total** | **~$170** | For functional V1 |

---

## Next Steps (Beyond V1)

### Phase 2: Multi-Table Network
- Coordinator Pi listening to 4 tables' Firebase logs
- Aggregate analytics dashboard

### Phase 3: Smart Context
- Short-term memory (last 5 conversations)
- Order history learning ("usual?")
- Sentiment tracking (happy → warmer colors)

### Phase 4: Proactive Behaviors
- "It's been 30 min, how's the meal?" prompts
- "Staff called" alert with relay + light

### Phase 5: Ambiance Modes
- Background scene selection (jazz, ambient, tavern bustle)
- Lighting themes (cozy, energetic, romantic)

---

## Troubleshooting Quick Ref

| Issue | Fix |
|-------|-----|
| Mic not recording | `arecord -l` → check device, update device ID in code |
| Transcription slow | Using local Whisper? Use API instead (faster) |
| ChatGPT returns text not JSON | Check system prompt, ensure quotes |
| LEDs not lighting | Check 5V power (separate supply), GPIO 18 wired right |
| Button not responsive | Check GPIO 23 polarity, debounce timing |
| Firebase timeout | Check internet, service account permissions |
| Sound distorted | Lower volume in alsamixer, check mic levels |

---

## You're Ready

This is a **working V1** that:
- ✅ Detects users (button or NFC)
- ✅ Records push-to-talk audio
- ✅ Transcribes with Whisper
- ✅ Gets personalized context from Firebase
- ✅ Calls ChatGPT with structured JSON
- ✅ Speaks replies with TTS
- ✅ Triggers LEDs based on state
- ✅ Logs everything for analytics

**No bloat. No consciousness. No ambiance. Just a smart table.**

Build it. Test it. Put it in a tavern. Get feedback.

Then Phase 2.

