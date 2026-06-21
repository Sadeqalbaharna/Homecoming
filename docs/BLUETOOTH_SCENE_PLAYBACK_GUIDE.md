# 🎧 Bluetooth Speaker & Scene Playback Testing Guide

## Quick Start

### 1. Check Bluetooth Speaker Connection
```bash
python test_bluetooth_tg129c.py
```

This will:
- ✅ Verify TG-129C speaker is paired and connected
- ✅ Check PulseAudio sink configuration
- ✅ Verify mpv and yt-dlp are installed
- ⚠️ Confirm volume is capped at 20% for public safety

### 2. Test Scene Playback

**Available Scenes:**
- `haunted_mansion` - Spooky ghostly atmosphere
- `dungeon` - Dark underground chamber
- `forest` - Mystical ancient forest
- `tavern` - Cozy medieval tavern
- `battle` - Intense epic battle music

**Play a scene:**
```bash
python test_modular_scene_playback.py haunted_mansion
```

Or with custom YouTube query:
```bash
python test_modular_scene_playback.py "relaxing meditation music"
```

## How It Works - Modular Architecture

```
┌─────────────────────────────────────────┐
│  Scene Playback Request                 │
│  (haunted_mansion)                      │
└──────────────┬──────────────────────────┘
               │
       ┌───────┴────────┐
       │                │
       ▼                ▼
┌──────────────┐  ┌──────────────┐
│ AudioDriver  │  │  LEDDriver   │
│              │  │              │
│ • YouTube    │  │ • RGB Colors │
│ • Streaming  │  │ • Effects    │
│ • mpv/yt-dlp │  │ • GPIO 18    │
└──────────────┘  └──────────────┘
       │                │
       └───────┬────────┘
               │
       ┌───────▼────────┐
       │ FixtureBase    │
       │ (Orchestrate)  │
       └────────────────┘
```

## Volume Safety

**⚠️ IMPORTANT:**
- Volume is **capped at 20% maximum** for public use
- This prevents hearing damage and disturbs fewer people around you
- The AudioDriver enforces this limit in [fixtures_v2/drivers/audio_driver.py](fixtures_v2/drivers/audio_driver.py#L162-L169)

```python
# Enforce maximum 20% volume for safety in public spaces
mpv_volume = min(mpv_volume, 20)
```

## Bluetooth Device Info

**TG-129C Speaker:**
- MAC Address: `39:3E:58:14:40:4A`
- Expected sink: `bluez_output.39_3E_58_14_40_4A.1`
- Model: Portable Bluetooth Speaker

## Troubleshooting

### Speaker not detected?
```bash
# List paired Bluetooth devices
bluetoothctl paired-devices

# Show detailed device info
bluetoothctl info 39:3E:58:14:40:4A

# Connect manually if needed
bluetoothctl connect 39:3E:58:14:40:4A
```

### No audio output?
```bash
# Check PulseAudio sinks
pactl list sinks

# Set Bluetooth as default sink
pactl set-default-sink bluez_output.39_3E_58_14_40_4A.1

# Test with a simple beep
speaker-test -t sine -f 1000
```

### Install missing tools
```bash
# Install mpv for audio playback
sudo apt-get install mpv

# Install yt-dlp for YouTube streaming
sudo apt-get install yt-dlp

# Or use pip for yt-dlp
pip3 install yt-dlp
```

## Testing Flow

1. **Check connection:**
   ```bash
   python test_bluetooth_tg129c.py
   ```
   Expected: All checks pass ✅

2. **Play a test scene:**
   ```bash
   python test_modular_scene_playback.py haunted_mansion
   ```
   Expected: Audio plays at 20% volume through speaker

3. **Monitor in logs:**
   - Look for "TG-129C Bluetooth speaker detected"
   - Confirm "Volume: 20% (capped at 20% max)"
   - Watch for "Stream URL obtained" (instant, no download)

## Architecture Benefits

✅ **Modular Design:**
- Each driver is independent
- Easy to test individually
- Can extend without breaking existing code

✅ **Async/Await:**
- Non-blocking audio operations
- Can run multiple scenes simultaneously
- Responsive UI

✅ **Safety First:**
- Volume always capped at safe levels
- Bluetooth validation before playback
- Graceful error handling

## Files

- [test_bluetooth_tg129c.py](test_bluetooth_tg129c.py) - Connection testing
- [test_modular_scene_playback.py](test_modular_scene_playback.py) - Scene playback
- [fixtures_v2/drivers/audio_driver.py](fixtures_v2/drivers/audio_driver.py) - Audio streaming
- [fixtures_v2/drivers/led_driver.py](fixtures_v2/drivers/led_driver.py) - LED lighting
- [fixtures_v2/core/fixture_base.py](fixtures_v2/core/fixture_base.py) - Orchestration

---

**Remember:** Always test at low volume first, especially in public spaces! 🔊
