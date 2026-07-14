# Homecoming App - Complete Auto-Startup System

## Overview

The app now has **three-stage automatic startup**:
1. **Pi Auto-Discovery** - Finds Pi on network without manual IP entry
2. **Bluetooth Auto-Troubleshoot** - Fixes issues automatically
3. **App Launch** - Starts only after speaker confirmed working

## Files Created

### Core Startup Files
- **`homecoming_startup.py`** - Master startup script (run this to start app)
- **`discover_pi.py`** - Auto-finds Pi using 4 methods
- **`auto_troubleshoot_bluetooth.py`** - Auto-fixes Bluetooth issues
- **`bluetooth_startup_check.py`** - Pi-native startup check

### Deployment
- **`deploy_auto_troubleshoot.py`** - Deploy to Pi
- **`homecoming-app.service`** - Systemd service for Pi boot

## How It Works

### Startup Sequence

```
1. Run: python homecoming_startup.py
            ↓
2. STEP 1: Discover Pi
   - Try common hostnames (raspberrypi.local, homecoming.local, etc)
   - Use arp-scan if available
   - Use nmap if available  
   - Test known IP addresses
            ↓
3. STEP 2: Bluetooth Troubleshooting
   - Check adapter is UP (fix if DOWN)
   - Check speaker connected (reconnect if needed)
   - Check PulseAudio sink exists (load if missing)
   - Check volume unmuted (unmute if needed)
   - Test audio playback (play test tone)
            ↓
4. ✅ App Launches
   - All systems confirmed working
   - Ready for D&D scenes
```

## Pi Discovery Methods (In Order)

### Method 1: Hostname Resolution
- Tries: `raspberrypi`, `raspberrypi.local`, `homecoming`, `homecoming.local`, `kai`, `kai.local`
- Fastest if Pi has proper mDNS setup
- Works on same WiFi network

### Method 2: ARP Scanning
- Uses `arp-scan -l` to find Broadcom/Raspberry devices
- Requires arp-scan tool
- Fast, reliable on local network

### Method 3: NMAP Scanning
- Scans for open SSH port (22)
- Requires nmap tool
- More thorough but slower

### Method 4: Ping Sweep
- Tests known IPs in parallel
- Falls back to hardcoded FALLBACK_IPS
- Always works if Pi is at known IP

## Auto-Fixes Applied

| Issue | Fix |
|-------|-----|
| Adapter DOWN | `sudo hciconfig hci0 up` |
| Speaker disconnected | `bluetoothctl connect 39:3E:58:14:40:4A` |
| Bluetooth module missing | `pactl load-module module-bluez5-discover` |
| Speaker muted | `pactl set-sink-mute ... 0` |
| Volume too low | `pactl set-sink-volume ... 100%` |

## Usage

### Option 1: Direct Launch (Recommended)
```bash
python homecoming_startup.py
```

Output:
```
======================================================================
                        HOMECOMING - D&D AMBIANCE APP
======================================================================

📍 STEP 1: Discovering Raspberry Pi...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Pi found at: 192.168.48.5

🔧 STEP 2: Running Bluetooth troubleshooting...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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
✅ Test tone played

======================================================================
✅ STARTUP COMPLETE - APP READY
======================================================================

🎭 Homecoming app is ready!
📍 Pi: 192.168.48.5
🎵 Bluetooth: Ready

Listening for D&D scene commands...
```

### Option 2: Just Discovery
```bash
python discover_pi.py
```

Returns Pi IP or error

### Option 3: Just Troubleshooting
```bash
python auto_troubleshoot_bluetooth.py
```

(Requires Pi IP - will auto-discover)

## Customization

### Change Speaker MAC
Edit files and replace:
```python
SPEAKER_MAC = "39:3E:58:14:40:4A"
```

### Add Known Pi IPs
Edit `discover_pi.py`:
```python
FALLBACK_IPS = [
    "192.168.48.5",     # Your Pi's IP
    "192.168.1.100",    # Alternative IP
    # ... add more
]
```

### Add Hostnames
Edit `discover_pi.py`:
```python
COMMON_HOSTNAMES = [
    "raspberrypi",
    "my-pi-name",  # Add custom name
    # ... add more
]
```

## Troubleshooting Discovery

If discovery fails, check:

1. **Is Pi powered on?**
   ```bash
   ping 192.168.48.5  # Try known IP
   ```

2. **Is Pi on same network?**
   ```bash
   ipconfig  # Check your network
   ```

3. **Can you SSH manually?**
   ```bash
   ssh pi@192.168.48.5
   ```

4. **Check router for connected devices**
   - Log into router admin
   - Look for "Raspberry Pi" in device list
   - Note its IP

5. **Update FALLBACK_IPS**
   - Edit `discover_pi.py`
   - Add your Pi's IP
   - Run discovery again

## Integration Points

This system integrates automatically with:
- `auto_troubleshoot_bluetooth.py` → Full diagnostics
- `bluetooth_startup_check.py` → Pi-side startup
- `play_pirate_fixed.py` → Scene playback
- Firebase integration → Scene execution
- Main app → D&D scene commands

## What Happens on Failure

If any step fails:

1. **Discovery fails** → App exits with instructions
2. **Troubleshooting fails** → Logs issues, continues
3. **Speaker test fails** → Warns user, suggests manual steps

App will only fully launch after **all checks pass**.

## Deployment to Pi

When Pi is online:
```bash
python deploy_auto_troubleshoot.py
```

This:
- Uploads all scripts to Pi
- Installs systemd service
- Runs at boot automatically
- Tests the system

## Performance

- **Discovery**: 30-60 seconds (depending on network)
- **Troubleshooting**: 20-30 seconds
- **Total startup**: ~2 minutes on first boot

Subsequent launches are faster if Pi is already known.

## Future Enhancements

- [ ] Save discovered Pi IP for faster future launches
- [ ] Persistent troubleshooting history/logging
- [ ] Auto-update Pi scripts from cloud
- [ ] Fallback to ALSA if Bluetooth unavailable
- [ ] Voice feedback during startup
- [ ] Web dashboard for startup monitoring
