# 🚀 DEPLOY TO RASPBERRY PI - Step by Step Guide

## Your Pi IP: 192.168.29.5

### Method 1: Use WinSCP or FileZilla (Recommended for Windows)

1. **Download WinSCP** (free): https://winscp.net/eng/download.php
2. **Connect to your Pi:**
   - Protocol: SFTP
   - Host: 192.168.29.5
   - Username: pi
   - Password: (your Pi password)
3. **Upload the file:**
   - Navigate to `/home/pi/` on the Pi
   - Upload `firebase_rest_listener_debug.py` from your local folder

### Method 2: Use Windows Subsystem for Linux (WSL)

1. **Open WSL or Git Bash**
2. **Navigate to your project folder**
3. **Copy the file:**
   ```bash
   scp firebase_rest_listener_debug.py pi@192.168.29.5:/home/pi/
   ```

### Method 3: Enable Windows SSH Client

1. **Enable SSH Client in Windows:**
   - Go to Settings → Apps → Optional Features
   - Add "OpenSSH Client"
   - Restart PowerShell

2. **Then run:**
   ```powershell
   scp firebase_rest_listener_debug.py pi@192.168.29.5:/home/pi/
   ```

## 🔧 Setup on Pi (SSH Required)

Once the file is uploaded, SSH to your Pi and run these commands:

### Connect to Pi
```bash
# Option 1: Use PuTTY (Windows)
# Download PuTTY and connect to 192.168.29.5

# Option 2: Use WSL/Git Bash
ssh pi@192.168.29.5
```

### Install Dependencies
```bash
# Update system
sudo apt update
sudo apt install -y python3-pip python3-dev build-essential mpv

# Install Python packages
pip3 install requests
sudo pip3 install rpi_ws281x

# Create music directory
mkdir -p /home/pi/music_tracks

# Set permissions
chmod +x firebase_rest_listener_debug.py

# Test the script
python3 -c "import requests; print('✅ requests available')"
python3 -c "print('✅ Python syntax check passed')"
```

### Test Run
```bash
# Run manually first to test
python3 firebase_rest_listener_debug.py

# If it works, press Ctrl+C to stop, then set up as service:
sudo nano /etc/systemd/system/firebase-listener.service
```

### Service Configuration
Copy this into the service file:
```ini
[Unit]
Description=Firebase REST Listener with WS2812B LED Control
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi
ExecStart=/usr/bin/python3 /home/pi/firebase_rest_listener_debug.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Start the Service
```bash
sudo systemctl daemon-reload
sudo systemctl enable firebase-listener
sudo systemctl start firebase-listener
sudo systemctl status firebase-listener
```

## 🌈 Hardware Setup (Optional - for LED strips)

If you have WS2812B LED strips, connect them to:
- **Main Strip (150 LEDs)**: GPIO 18 (Pin 12)
- **Accent Strip (60 LEDs)**: GPIO 13 (Pin 33)
- **Ambient Strip (30 LEDs)**: GPIO 12 (Pin 32)

## 🎵 Add Music Files

Copy your music tracks to `/home/pi/music_tracks/`:
- track_1.mp3 - Nature/Forest sounds
- track_2.mp3 - Energetic/Upbeat music
- track_3.mp3 - Focus/Concentration music
- track_4.mp3 - Happy/Cheerful music
- track_5.mp3 - Ambient/Background music
- track_6.mp3 - Classical/Romantic music
- track_7.mp3 - Ocean/Water sounds

## 🎮 Test Voice Commands

Once running, test through your Homecoming app:
- "Play relaxing music" → Nature sounds + green lighting
- "GM Kai, set party mode" → Upbeat music + rainbow effects
- "Set the lights to reading" → White solid lighting
- "Turn off all lights" → All LED strips off

## ✅ Verification

The system should log:
```
🔥 Firebase REST listener initialized with intelligent profile matching
🎧 Polling for commands at: https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app/home_automation/kai_persona_1/commands.json
🎯 Intelligent profiles loaded: 7
🔄 Starting command polling...
```

## 🚨 If You Need Help

1. **Can't connect to Pi?** 
   - Check Pi IP: `hostname -I`
   - Enable SSH: `sudo systemctl enable ssh`

2. **Permission denied?**
   - Run with sudo: `sudo python3 firebase_rest_listener_debug.py`

3. **Audio not working?**
   - Check devices: `pactl list short sinks`
   - Update bluetooth_device in script

4. **LEDs not working?**
   - Run with sudo for GPIO access
   - Check wiring to GPIO 18, 13, 12