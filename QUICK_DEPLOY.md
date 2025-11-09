# Quick Manual Deployment to Raspberry Pi

## Step 1: Update your Pi's IP address
Replace `192.168.1.XXX` with your actual Pi IP in the commands below.

## Step 2: Copy the main file to Pi
```powershell
scp firebase_rest_listener_debug.py pi@192.168.1.XXX:/home/pi/
scp firebase-listener.service pi@192.168.1.XXX:/home/pi/
```

## Step 3: SSH to Pi and install dependencies
```bash
# Connect to Pi
ssh pi@192.168.1.XXX

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
python3 -m py_compile firebase_rest_listener_debug.py
```

## Step 4: Test run
```bash
# Run manually first to test
python3 firebase_rest_listener_debug.py

# If it works, set up as service
sudo cp firebase-listener.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable firebase-listener
sudo systemctl start firebase-listener
sudo systemctl status firebase-listener
```

## Step 5: Check logs
```bash
# View service logs
sudo journalctl -u firebase-listener -f

# Or run manually to see output
python3 firebase_rest_listener_debug.py
```

## 🌈 WS2812B Hardware Setup
Wire your LED strips to these GPIO pins:
- **Main Strip**: GPIO 18 (Pin 12) - 150 LEDs
- **Accent Strip**: GPIO 13 (Pin 33) - 60 LEDs  
- **Ambient Strip**: GPIO 12 (Pin 32) - 30 LEDs

Connect 5V power and GND to external power supply (not Pi power).
Use level shifter for 3.3V to 5V data signal conversion.

## 🎵 Add Music Files
Copy your music tracks to `/home/pi/music_tracks/`:
- track_1.mp3 (Nature/Forest)
- track_2.mp3 (Energetic/Upbeat)
- track_3.mp3 (Focus/Concentration)
- track_4.mp3 (Happy/Cheerful)
- track_5.mp3 (Ambient/Background)
- track_6.mp3 (Classical/Romantic)
- track_7.mp3 (Ocean/Water)

## 🎮 Test Voice Commands
Once running, test through your Homecoming app:
- "Play relaxing music" → Nature sounds + green lighting
- "GM Kai, set party mode" → Upbeat music + rainbow effects
- "Set the lights to reading" → White solid lighting
- "Turn off all lights" → All LED strips off