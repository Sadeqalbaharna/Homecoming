# ✅ KAI V1 Pi Setup - Session 1 Complete

**Date:** January 20, 2026  
**Pi IP:** 192.168.39.5  
**Status:** Ready for Session 2

---

## What's Installed on Pi

### System Software
✅ Python 3.13.5  
✅ alsa-utils (audio recording)  
✅ espeak-ng (text-to-speech)  
✅ git  

### Python Packages
✅ firebase-admin (database)  
✅ openai (ChatGPT + Whisper)  

### V1 Core Files
✅ `/home/pi/kai/kai_table_v1_core.py` (150 lines - main loop)  
✅ `/home/pi/kai/unified_firebase_listener.py` (logging)  
✅ `/home/pi/kai/unified_deployment.py` (deployment utils)  

---

## Hardware Verified

### USB Audio Device
✅ **PDX417 USB Audio**
- Card: 1
- Device: 0
- Driver: plughw:1,0
- Tested: 3-second recording = 517KB ✓

### Recording Verified
```bash
arecord -D plughw:1,0 -f cd -t wav -d 3 /home/pi/kai/test.wav
# Result: SUCCESS (517KB file created)
```

### Text-to-Speech Verified
```bash
espeak-ng "Hello, tavern table is ready" -s 150
# Result: SUCCESS (audio output works)
```

---

## Next: Session 2 Setup

**Firebase Integration:**
1. Download service account JSON from Firebase Console
   - Go: https://console.firebase.google.com/
   - Project settings → Service Accounts → Generate new private key
   - Save as: `/home/pi/kai/firebase_service_account.json`

2. Update environment variable
   ```bash
   export OPENAI_API_KEY="sk-proj-..."  # Your key from GitHub
   ```

3. Test Firebase + ChatGPT connection
   ```bash
   ssh pi@192.168.39.5
   cd /home/pi/kai
   python3 kai_table_v1_core.py
   ```

**Expected output:**
```
🍻 KAI - SMART TAVERN TABLE (V1)
=========================================
✓ Firebase initialized
Ready. Press button or tap NFC to start conversation.

🎙️ Listening (6 seconds)...
🔆 LED: listening #ffffff
[Waits for input]
```

---

## Session 2 Commands (Exact)

```bash
# SSH into Pi
ssh pi@192.168.39.5

# Copy Firebase service account (if not already there)
# scp ~/firebase_service_account.json pi@192.168.39.5:/home/pi/kai/

# Set API key
export OPENAI_API_KEY="sk-proj-dne6ocEl_T-YDpjmy_X-8s5..."

# Run V1 core
cd /home/pi/kai
python3 kai_table_v1_core.py

# Press Ctrl+C to exit
```

---

## Audio Device Configuration

**Current setup:**
- USB Microphone: `plughw:1,0` (card 1, device 0)
- Speakers: 3.5mm headphone jack (default)

**If you need to use different device:**
Edit `kai_table_v1_core.py` line ~45:
```python
"-D", "plughw:1,0",  # Change "1,0" if needed
```

To find device number:
```bash
arecord -l  # Shows all devices
```

---

## Summary

| Task | Status |
|------|--------|
| Pi OS setup | ✅ Complete |
| Python packages | ✅ Complete |
| Audio recording | ✅ Tested |
| Text-to-speech | ✅ Tested |
| V1 core deployed | ✅ Complete |
| Firebase ready | ⏳ Waiting for key |
| ChatGPT ready | ✅ (API key set) |

**Ready to proceed?** Follow Session 2 commands above.

