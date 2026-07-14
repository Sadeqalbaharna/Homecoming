# 🚀 Pi Boot & Music System Deployment Checklist

## 📡 **Once Your Pi Connects to WiFi:**

### **Step 1: Initial System Check**
```bash
# SSH into your Pi
ssh pi@[your-pi-ip]

# Update system
sudo apt update && sudo apt upgrade -y

# Check system status
echo "✅ Pi is online and ready!"
```

### **Step 2: Deploy Homecoming Music Files**
```bash
# Create homecoming directory
mkdir -p ~/homecoming_pi/{music,logs,playlists}

# Upload the music system files (from your computer):
# - music_player_service.py
# - bluetooth_audio_manager.py  
# - voice_enabled_home_automation.py
# - bluetooth_audio_setup.sh
# - test_music_system.py

# Make scripts executable
chmod +x ~/homecoming_pi/bluetooth_audio_setup.sh
chmod +x ~/homecoming_pi/test_music_system.py
```

### **Step 3: Quick Bluetooth Audio Setup**
```bash
cd ~/homecoming_pi

# Run the automated Bluetooth setup
./bluetooth_audio_setup.sh

# This will install:
# - PulseAudio with Bluetooth support
# - Sox audio processing
# - Python audio libraries
# - TTS (espeak-ng)
```

### **Step 4: Generate Music Library**  
```bash
# Generate all 7 music tracks
python3 -c "
from music_player_service import MusicPlayerService
mp = MusicPlayerService()
mp.generate_sample_music()
print('🎵 All 7 tracks generated!')
"

# Verify files created
ls -la ~/homecoming_pi/music/
```

### **Step 5: Pair Bluetooth Speaker**
```bash
# Start Bluetooth pairing
bluetoothctl

# In bluetoothctl interface:
scan on
# Wait to see your speaker, then:
pair XX:XX:XX:XX:XX:XX
trust XX:XX:XX:XX:XX:XX  
connect XX:XX:XX:XX:XX:XX
exit

# Set as default audio output
pacmd set-default-sink bluez_sink.XX_XX_XX_XX_XX_XX.a2dp_sink
```

### **Step 6: Test Audio System**
```bash
# Test system audio
speaker-test -t wav -c 2

# Test Bluetooth audio  
aplay /usr/share/sounds/alsa/Front_Left.wav

# Test TTS
espeak-ng "Hello! Pi audio system is ready!"
```

### **Step 7: Test Music System**
```bash
# Run comprehensive music tests
python3 test_music_system.py

# Manual music test
python3 -c "
from music_player_service import MusicPlayerService
mp = MusicPlayerService()

# Play a song
result = mp.play_song('electronic_beat')
print('🎵 Playing:', result['message'])
"
```

### **Step 8: Start Voice Automation**
```bash
# Test voice automation with music
python3 voice_enabled_home_automation.py

# Try voice commands:
# - 'Play some energetic music'
# - 'Play relaxing playlist'
# - 'Stop the music'
```

### **Step 9: Mobile App Testing**
1. **Open your Homecoming mobile app**
2. **Tap the ♪ Music button** 
3. **Browse the 7 songs + 7 moods**
4. **Test specific song playback**
5. **Test mood playlists**
6. **Verify audio feedback from Pi**

---

## 🎵 **Quick Test Commands:**

### **Generate All Music (One Command):**
```bash
python3 -c "from music_player_service import MusicPlayerService; MusicPlayerService().generate_sample_music()"
```

### **Test Specific Features:**
```bash
# Play electronic beat
python3 -c "from music_player_service import MusicPlayerService; print(MusicPlayerService().play_song('electronic_beat'))"

# Play energetic mood
python3 -c "from music_player_service import MusicPlayerService; print(MusicPlayerService().play_mood_playlist('energetic'))"

# Stop music
python3 -c "from music_player_service import MusicPlayerService; print(MusicPlayerService().stop_music())"
```

### **Interactive Music Shell:**
```bash
python3 test_music_system.py
# Then use commands: play energetic, stop, next, list, quit
```

---

## 🔧 **Troubleshooting:**

### **Bluetooth Issues:**
```bash
sudo systemctl restart bluetooth
pulseaudio --kill && pulseaudio --start
bluetoothctl show
```

### **Audio Issues:**
```bash
aplay -l  # List audio devices
pacmd list-sinks  # List audio sinks
pulseaudio --kill && pulseaudio --start  # Restart audio
```

### **Music Generation Issues:**
```bash
sox --version  # Check sox installation
sudo apt install sox libsox-fmt-all  # Reinstall if needed
```

---

## 📱 **Mobile App Features Ready:**
- ✅ **Music Selection Dialog** with 7 songs + 7 moods
- ✅ **Music Status Widget** with quick controls
- ✅ **Voice Feedback** from Pi responses
- ✅ **Bluetooth Audio** integration
- ✅ **Real-time Controls** (play, stop, next, shuffle)

**🎵 Your complete music ecosystem is ready to deploy! 🔊✨**

Just run through this checklist once your Pi connects to WiFi and you'll have a fully functional music system!