# Automated Bluetooth Troubleshooting System

## Overview

This system automatically detects and fixes Bluetooth speaker issues on app launch, ensuring the speaker is ready before any audio playback.

## How It Works

### Three-Level Troubleshooting Architecture

**1. On Windows/Local (auto_troubleshoot_bluetooth.py)**
- Connects to Pi over SSH
- Runs 5-stage diagnostic checks
- Applies automatic fixes
- Reports final status

**2. On Pi Startup (bluetooth_startup_check.py)**
- Runs directly on Raspberry Pi
- Executes before main app starts
- Fixes issues in real-time
- No network dependency

**3. Systemd Service (homecoming-app.service)**
- Runs on Pi boot automatically
- Ensures speaker ready at startup
- Handles boot timing (Bluetooth service startup delays)

## 5-Stage Diagnostic Checks

```
[1/5] Bluetooth Adapter
     - Check: Is adapter powered on?
     - Fix: Auto-power on if DOWN
     
[2/5] Speaker Connection
     - Check: Is TG-129C connected?
     - Fix: Auto-reconnect if disconnected
     
[3/5] PulseAudio Sink
     - Check: Does PulseAudio see Bluetooth?
     - Fix: Auto-load bluez5-discover module
     
[4/5] Volume Settings
     - Check: Is speaker unmuted?
     - Fix: Auto-unmute and set to 100%
     
[5/5] Audio Playback
     - Check: Can we play audio?
     - Test: Play test tone, user confirms
```

## Usage

### Option A: From Windows (Remote Check)
```bash
python auto_troubleshoot_bluetooth.py
```
Connects to Pi via SSH, runs full diagnostics, applies fixes

### Option B: From Pi Terminal
```bash
python3 bluetooth_startup_check.py
```
Runs directly on Pi, no network needed

### Option C: Automatic on Pi Boot
1. Copy service file to Pi:
```bash
ssh pi@192.168.48.5 << 'EOF'
sudo cp /home/pi/homecoming-app.service /etc/systemd/system/
sudo systemctl enable homecoming-app
sudo systemctl start homecoming-app
EOF
```

2. Service will automatically run on reboot

### Option D: App Launcher
```bash
python app_launcher.py
```
- Runs full Bluetooth troubleshooting
- Launches main app automatically
- Keeps app running

## Automatic Fixes Applied

| Issue | Automatic Fix |
|-------|---------------|
| Adapter DOWN | `sudo hciconfig hci0 up` |
| Speaker disconnected | `bluetoothctl connect 39:3E:58:14:40:4A` |
| Bluetooth module missing | `pactl load-module module-bluez5-discover` |
| Speaker muted | `pactl set-sink-mute ... 0` |
| Volume too low | `pactl set-sink-volume ... 100%` |

## Success Criteria

System confirms working when:
- ✅ Bluetooth adapter is UP
- ✅ Speaker shows Connected: yes
- ✅ PulseAudio sees bluez_output sink
- ✅ Test tone plays successfully
- ✅ User confirms hearing audio

## Log Output

```
======================================================================
                 BLUETOOTH SPEAKER AUTO-TROUBLESHOOTING
======================================================================

[CHECK 1/5] Bluetooth adapter status...
✅ Adapter is UP

[CHECK 2/5] Speaker connection...
✅ Speaker connected

[CHECK 3/5] PulseAudio Bluetooth sink...
✅ Bluetooth sink available

[CHECK 4/5] Volume configuration...
✅ Speaker unmuted
✅ Volume set to 100%

[CHECK 5/5] Audio playback test...
   Playing test tone (you should hear a beep)...
✅ Test tone played
   ❓ Did you hear a beep from the speaker?

======================================================================
                          DIAGNOSTIC REPORT
======================================================================

✅ No issues detected

======================================================================
            RESULT: SPEAKER READY FOR SCENE PLAYBACK
======================================================================

✅✅✅ BLUETOOTH SPEAKER CONFIRMED WORKING
```

## What Happens on Failure

If troubleshooting fails:
1. System reports which check failed
2. User is prompted with manual steps
3. App either:
   - Continues with limited functionality (audio disabled)
   - Blocks launch until manual fix (recommended)

## Integration Points

This system integrates with:
- `play_scene_with_bluetooth.py` - Scene playback handler
- `firebase_scene_executor.py` - Firebase listener
- Main app launcher - Runs before any scene playback

## Future Improvements

- [ ] Persistent logging of troubleshooting history
- [ ] Email alerts if speaker fails repeatedly
- [ ] Automatic speaker reboot if unresponsive
- [ ] Fallback to ALSA if Bluetooth unavailable
- [ ] Volume auto-adjustment based on ambient noise
