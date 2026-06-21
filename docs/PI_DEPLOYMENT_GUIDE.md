# 🚀 Raspberry Pi Deployment Guide - WS2812B Firebase Listener

## Quick Deployment

### Step 1: Update Pi IP Address
Edit `deploy-pi-listener.ps1` and change the IP address:
```powershell
[string]$PiHost = "192.168.1.XXX",  # Change to your Pi's IP
```

### Step 2: Deploy Files
```powershell
# Basic deployment
.\deploy-pi-listener.ps1

# Deploy with dependency installation
.\deploy-pi-listener.ps1 -InstallDependencies

# Test connection only
.\deploy-pi-listener.ps1 -TestOnly
```

### Step 3: Connect Hardware
Wire your WS2812B LED strips to the Pi:
- **Main Strip (150 LEDs)**: GPIO 18 (Pin 12)
- **Accent Strip (60 LEDs)**: GPIO 13 (Pin 33)  
- **Ambient Strip (30 LEDs)**: GPIO 12 (Pin 32)

### Step 4: Start the Listener
```bash
# SSH to your Pi
ssh pi@192.168.1.XXX

# Run manually for testing
python3 firebase_rest_listener_debug.py

# Or install as service for auto-start
sudo cp firebase-listener.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable firebase-listener
sudo systemctl start firebase-listener
```

## 🔧 Manual Setup (Alternative)

If the automated script doesn't work, follow these manual steps:

### 1. Copy Files to Pi
```bash
scp firebase_rest_listener_debug.py pi@192.168.1.XXX:/home/pi/
scp firebase-listener.service pi@192.168.1.XXX:/home/pi/
```

### 2. Install Dependencies on Pi
```bash
# SSH to Pi
ssh pi@192.168.1.XXX

# Update system
sudo apt update
sudo apt install -y python3-pip python3-dev build-essential mpv

# Install Python packages
pip3 install requests
sudo pip3 install rpi_ws281x

# Create music directory
mkdir -p /home/pi/music_tracks
```

### 3. Set Permissions
```bash
chmod +x firebase_rest_listener_debug.py
```

## 🎵 Music Setup

Add your music files to `/home/pi/music_tracks/`:
- `track_1.mp3` - Nature/Forest sounds
- `track_2.mp3` - Energetic/Upbeat music
- `track_3.mp3` - Focus/Concentration music
- `track_4.mp3` - Happy/Cheerful music
- `track_5.mp3` - Ambient/Background music
- `track_6.mp3` - Classical/Romantic music
- `track_7.mp3` - Ocean/Water sounds

## 🌈 LED Strip Wiring

### WS2812B Connections
```
Pi GPIO 18 (Pin 12) → Main Strip Data In    (150 LEDs)
Pi GPIO 13 (Pin 33) → Accent Strip Data In  (60 LEDs)
Pi GPIO 12 (Pin 32) → Ambient Strip Data In (30 LEDs)
Pi 5V (Pin 2/4)     → All Strips VCC (via level shifter)
Pi GND (Pin 6/9/14) → All Strips GND
```

### Power Supply
- Use external 5V power supply for LED strips (not Pi power)
- Connect Pi GND to power supply GND (common ground)
- Use 74HCT245 level shifter for 3.3V→5V data signal conversion

## 🎮 Features

### GM Kai Direct Control
Voice commands starting with "GM Kai" get priority processing:
- "GM Kai, set the lights to party mode"
- "GM Kai, turn off all lights"
- "GM Kai, play relaxing music"

### Intelligent Profile Matching
System automatically coordinates music + lighting:
- **Forest**: Green gentle pulse + nature sounds
- **Energetic**: Yellow pulse + upbeat music  
- **Focus**: White solid + concentration music
- **Romantic**: Amber flicker + classical music

### Scene Control
Quick lighting presets:
- `bright`, `dim`, `warm`, `cool`, `night`, `reading`, `relax`, `party`, `off`

### Dynamic Effects
- **Solid**: Static colors with brightness control
- **Gentle Pulse**: Breathing effect
- **Wave**: Flowing wave across strips
- **Color Cycle**: Rainbow animations
- **Candle Flicker**: Realistic candle simulation
- **Slow Fade**: Smooth color transitions

## 🔍 Troubleshooting

### Permission Issues
If LED control fails, run with sudo:
```bash
sudo python3 firebase_rest_listener_debug.py
```

### Audio Issues
Check Bluetooth device:
```bash
pactl list short sinks
# Update bluetooth_device in script if needed
```

### Service Logs
Check service status:
```bash
sudo systemctl status firebase-listener
sudo journalctl -u firebase-listener -f
```

### GPIO Conflicts
Ensure no other processes use GPIO 12, 13, 18:
```bash
sudo fuser /dev/mem
```

## 📊 System Requirements

- Raspberry Pi 3B+ or newer
- Python 3.7+
- Internet connection for Firebase
- Bluetooth for audio output
- 5V power supply for LED strips
- Level shifter for WS2812B data signals

## 🎯 Firebase Integration

The system polls:
```
https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app/home_automation/kai_persona_1/commands.json
```

Commands are processed and responses sent back to Firebase for the mobile app to display.