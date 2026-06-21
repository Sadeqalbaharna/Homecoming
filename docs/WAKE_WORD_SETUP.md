# Kai V1 Wake Word Listener Setup

## Quick Start

### 1. Deploy to Pi

```powershell
# Copy listener script
scp kai_wake_listener.py pi@192.168.39.5:/home/pi/kai/

# SSH to Pi and test manually first
ssh pi@192.168.39.5
cd /home/pi/kai
python3 kai_wake_listener.py
```

Speak: "Hey Kai" or "Kai" within 3-5 feet of the USB mic.

### 2. Install System Service (Optional - Auto-start on boot)

```bash
# On Pi:
sudo cp kai-listener.service /etc/systemd/system/

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable kai-listener
sudo systemctl start kai-listener

# Check status
sudo systemctl status kai-listener

# View logs
sudo journalctl -u kai-listener -f
```

### 3. Stop Service

```bash
sudo systemctl stop kai-listener
```

---

## How It Works

```
┌─────────────────────────────────────────┐
│  Kai Wake Word Listener (always on)     │
│  Using pocketsphinx (local, offline)    │
└─────────────┬───────────────────────────┘
              │
              ├─ Listens for: "hey kai", "kai", "okay kai"
              │
              ▼
        ┌──────────────┐
        │ Wake word    │
        │ detected? ✓  │
        └──────┬───────┘
               │
               ▼
    ┌──────────────────────┐
    │ Trigger conversation │
    │ (session3_enhanced)  │
    └──────────┬───────────┘
               │
               ├─ Record → Transcribe → Log
               ├─ Read History & Personality
               ├─ ChatGPT with context
               ├─ Log response
               └─ Speak reply
               
               ▼
        Back to listening...
```

---

## Features

- ✅ Local wake word detection (no internet required)
- ✅ Works offline with pocketsphinx
- ✅ Customizable wake words
- ✅ Auto-restart on crash
- ✅ Runs as background service
- ✅ Journalctl logging for debugging

---

## Customizing Wake Words

Edit `kai_wake_listener.py` line ~30:

```python
WAKE_WORDS = ["kai", "hey kai", "okay kai", "your word here"]
```

Then restart the service:

```bash
sudo systemctl restart kai-listener
```

---

## Troubleshooting

**Issue: "No audio device"**
- Check USB mic is connected
- Run: `arecord -l`

**Issue: "pocketsphinx not found"**
- Install: `pip3 install pocketsphinx pyaudio`

**Issue: Wake word not detected**
- Speak clearly within 3-5 feet
- Check mic levels: `alsamixer -c 3`
- Test manually first before systemd service

**View live logs:**
```bash
sudo journalctl -u kai-listener -f
```

---

## Next Steps

1. Test manually: `python3 kai_wake_listener.py`
2. Say "hey kai" into the USB mic
3. Should trigger full conversation
4. If working, set up systemd service for auto-start
