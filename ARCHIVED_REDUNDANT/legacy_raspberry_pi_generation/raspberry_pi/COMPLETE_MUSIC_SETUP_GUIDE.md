# 🎵 Complete Music System Setup Guide

## Overview
This guide walks you through setting up the complete Homecoming music system with Bluetooth audio output, voice commands, and mobile app integration.

## Prerequisites
- Raspberry Pi 4 (recommended) or Pi 3B+
- Bluetooth speaker or headphones
- Homecoming mobile app installed
- Firebase project configured

## Step 1: Initial System Setup

### Update System
```bash
sudo apt update && sudo apt upgrade -y
```

### Install Required Packages
```bash
sudo apt install -y \
    sox libsox-fmt-all \
    mpg123 alsa-utils \
    python3-pygame \
    ffmpeg \
    pulseaudio-module-bluetooth \
    bluetooth bluez bluez-tools \
    espeak-ng
```

## Step 2: Bluetooth Audio Setup

### Run Bluetooth Setup Script
```bash
chmod +x bluetooth_audio_setup.sh
./bluetooth_audio_setup.sh
```

### Pair Your Bluetooth Speaker
```bash
# Start bluetoothctl
bluetoothctl

# In bluetoothctl:
scan on
# Wait for your speaker to appear, note its MAC address
pair XX:XX:XX:XX:XX:XX
trust XX:XX:XX:XX:XX:XX
connect XX:XX:XX:XX:XX:XX
exit
```

### Set as Default Audio Output
```bash
# List audio sinks
pacmd list-sinks | grep -E "(name:|device.description)"

# Set Bluetooth as default (replace with your sink name)
pacmd set-default-sink bluez_sink.XX_XX_XX_XX_XX_XX.a2dp_sink
```

## Step 3: Deploy Music Services

### Copy Music System Files
```bash
# Ensure these files are on your Pi:
cp music_player_service.py ~/homecoming/
cp bluetooth_audio_manager.py ~/homecoming/
cp voice_enabled_home_automation.py ~/homecoming/
```

### Install Python Dependencies
```bash
pip3 install --user pygame pydub firebase-admin
```

### Generate Sample Music
```bash
cd ~/homecoming
python3 -c "
from music_player_service import MusicPlayerService
mp = MusicPlayerService()
mp.generate_sample_music()
print('✅ Sample music generated')
"
```

## Step 4: Test Music System

### Basic Audio Test
```bash
# Test system audio
speaker-test -t wav -c 2

# Test Bluetooth audio
aplay /usr/share/sounds/alsa/Front_Left.wav
```

### Run Music System Tests
```bash
python3 test_music_system.py
```

### Manual Music Test
```bash
python3 -c "
from music_player_service import MusicPlayerService
mp = MusicPlayerService()

# Play a song
result = mp.play_song('electronic_beat')
print(result['message'])

# Play a mood playlist
result = mp.play_mood_playlist('energetic')
print(result['message'])
"
```

## Step 5: Voice Command Setup

### Test Voice Recognition
```bash
python3 -c "
from voice_enabled_home_automation import VoiceEnabledHomeAutomation
va = VoiceEnabledHomeAutomation()

# Test music commands
commands = [
    'Play some energetic music',
    'Play relaxing playlist', 
    'Stop the music'
]

for cmd in commands:
    result = va.handle_voice_command(cmd)
    print(f'{cmd}: {result[\"message\"]}')
"
```

## Step 6: Mobile App Integration

### Update Firebase Rules (if needed)
Ensure your Firebase database allows music commands:
```json
{
  "rules": {
    "commands": {
      ".read": true,
      ".write": true
    },
    "music": {
      ".read": true,
      ".write": true  
    }
  }
}
```

### Test Mobile Commands
From your mobile app, try:
1. Press the music button (♪)
2. Send voice commands through the app
3. Test different music moods

## Step 7: Advanced Configuration

### Auto-start Services
Create systemd service for music system:
```bash
sudo nano /etc/systemd/system/homecoming-music.service
```

Add content:
```ini
[Unit]
Description=Homecoming Music Service
After=network.target bluetooth.service

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/homecoming
ExecStart=/usr/bin/python3 voice_enabled_home_automation.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable service:
```bash
sudo systemctl enable homecoming-music.service
sudo systemctl start homecoming-music.service
```

### Audio Quality Settings
For better audio quality:
```bash
# Edit PulseAudio config
nano ~/.config/pulse/daemon.conf

# Add/modify these lines:
default-sample-format = s24le
default-sample-rate = 48000
default-sample-channels = 2
```

## Troubleshooting

### Bluetooth Issues
```bash
# Reset Bluetooth
sudo systemctl restart bluetooth
pulseaudio --kill
pulseaudio --start

# Check Bluetooth status
systemctl status bluetooth
bluetoothctl show
```

### Audio Issues
```bash
# Check audio devices
aplay -l
pacmd list-sinks

# Reset audio
pulseaudio --kill
pulseaudio --start
```

### Music Generation Issues
```bash
# Check sox installation
sox --version

# Test sox generation
sox -n -r 44100 -c 2 test_tone.wav synth 5 sine 440
aplay test_tone.wav
```

## Voice Commands Reference

### Music Commands
- "Play some energetic music"
- "Play relaxing playlist"
- "Play electronic music"
- "Play [song name]"
- "Play focused mood"
- "Stop the music"
- "Next song"
- "Previous song"

### LED Commands (with music)
- "Set lights to red and play party music"
- "Relaxing mode with blue lights"

## Mobile App Features

### Music Controls
- **Music Button (♪)**: Quick music toggle
- **Voice Commands**: Natural language music requests
- **Audio Feedback**: Pi responds with voice confirmations

### Available Moods
- **Energetic**: Upbeat electronic and rock
- **Relaxing**: Ambient and chill
- **Focused**: Minimal and concentration-friendly
- **Party**: High-energy dance music
- **Meditation**: Peaceful and calming
- **Work**: Background productivity music
- **Sleep**: Gentle lullabies

## Performance Tips

### Optimize Audio Latency
```bash
# Edit audio config
sudo nano /usr/share/alsa/alsa.conf

# Find and modify:
defaults.pcm.period_time 0
defaults.pcm.period_size 1024
```

### Free Up Memory
```bash
# Stop unnecessary services
sudo systemctl disable cups
sudo systemctl disable avahi-daemon
```

## Testing Checklist

- [ ] Bluetooth speaker pairs and connects
- [ ] System audio works through Bluetooth
- [ ] Sample music files generate successfully
- [ ] Music playback works (individual songs)
- [ ] Mood playlists function correctly
- [ ] Voice commands recognized and executed
- [ ] Mobile app music button works
- [ ] Audio feedback from Pi to mobile app
- [ ] LED integration with music commands
- [ ] Service auto-starts on boot

## Support

### Log Files
```bash
# Music service logs
journalctl -u homecoming-music.service -f

# Bluetooth logs  
journalctl -u bluetooth -f

# Audio logs
pulseaudio --log-level=debug
```

### Configuration Files
- Bluetooth: `/etc/bluetooth/main.conf`
- PulseAudio: `~/.config/pulse/`
- Music Library: `~/homecoming/music/`

---

🎵 **Your Homecoming Pi is now ready for music!** 

Test all features and enjoy your voice-controlled smart home music system.