# Bluetooth Audio Setup for Homecoming Pi 🔵🎵

This guide sets up Bluetooth audio output on your Raspberry Pi so you can hear Kai's voice responses from your mobile app commands!

## 🚀 Quick Setup

### 1. Run the Setup Script
```bash
# On your Raspberry Pi
cd /home/pi/homecoming_pi
chmod +x bluetooth_audio_setup.sh
sudo ./bluetooth_audio_setup.sh
```

### 2. Reboot and Pair
```bash
sudo reboot

# After reboot, make Pi discoverable
bluetoothctl
> discoverable on
> pairable on
> scan on
```

### 3. Pair Your Device
- On your phone/speaker: Search for "Homecoming-Pi" 
- Pair and connect
- The Pi will automatically connect audio

### 4. Test Audio
```bash
python3 test_bluetooth_audio.py
```

## 🎵 What You Get

### Voice Responses for Commands
When you use the mobile app to control lights, you'll hear:
- **"Turn on lights"** → *"Turning on the lights for you!"*
- **"Set rainbow effect"** → *"Rainbow mode activated! Enjoy the beautiful colors."*
- **"Set mood to relaxing"** → *"Setting relaxing mood. Dimming lights to a warm glow."*

### Available Voice Commands
- **Lights**: "Turn on/off lights", "Set to red/blue/green", "Rainbow effect"
- **Moods**: "Set mood to relaxing/energetic/romantic/party/focus"
- **Info**: "What time is it?", "Tell me a joke"
- **Weather**: "What's the weather?" (placeholder response)

## 📱 Mobile App Integration

### Current Mobile Features
Your mobile app already has:
- **Lights Button**: Tests LED toggle with success/failure messages
- **Training Button**: Voice training with Kai
- **Chat**: Send messages to Kai

### Enhanced Features with Bluetooth Audio
Once Bluetooth is setup, these features get voice responses:
- LED controls play confirmation sounds
- Voice training gives audio feedback
- Kai can speak responses instead of just text

## 🧪 Testing Capabilities

### 1. Basic Audio Test
```bash
cd /home/pi/homecoming_pi
python3 bluetooth_audio_manager.py test
```

### 2. Voice Command Simulation
```bash
python3 test_bluetooth_audio.py
```

### 3. Interactive Testing
```bash
python3 voice_enabled_home_automation.py
```

### 4. Mobile App Testing
1. Open Homecoming mobile app
2. Tap "Lights" button
3. Should hear: *"I've adjusted the lighting for you"*
4. Try voice training - should hear instructions
5. Send chat messages - Kai responds via audio

## 🎛️ Advanced Features

### LED + Audio Commands
```python
# Example: Party mode with voice
automation = VoiceEnabledHomeAutomation()
result = automation.handle_mood_command("party")
# LED strip: Flashing colors
# Audio: "Party mode activated! Let's get this party started!"
```

### Custom Responses
Edit `voice_enabled_home_automation.py` to customize what Kai says:
```python
self.responses = {
    'light_on': [
        "Your custom response here!",
        "Another response option",
    ]
}
```

## 🔧 Troubleshooting

### Bluetooth Not Working
```bash
# Restart Bluetooth service
sudo systemctl restart bluetooth

# Check status
sudo systemctl status bluetooth

# Manual pairing
bluetoothctl
> scan on
> pair XX:XX:XX:XX:XX:XX
> connect XX:XX:XX:XX:XX:XX
```

### Audio Not Playing
```bash
# Check audio devices
pulseaudio --check -v

# Test speaker
speaker-test -t sine -f 1000 -l 1

# Check Bluetooth audio sink
pactl list short sinks | grep bluez
```

### Service Issues
```bash
# Check logs
journalctl -u bluetooth-audio.service -f

# Restart service
sudo systemctl restart bluetooth-audio.service
```

## 🎯 What to Test from Mobile App

1. **LED Controls** (should hear confirmations):
   - Tap "Lights" button
   - Should hear: *"I've adjusted the lighting for you"*

2. **Voice Training** (should hear instructions):
   - Tap "Training" button  
   - Should hear: *"Read the phrase shown in the gold box"*

3. **Chat Messages** (should hear responses):
   - Send "Hey Kai, what time is it?"
   - Should hear the time spoken via Bluetooth

4. **Advanced Commands** (via chat):
   - "Turn on rainbow lights"
   - "Set mood to relaxing" 
   - "Tell me a joke"

## 🔮 Next Steps

Once working, you can:
- Add more voice responses
- Create custom light shows with narration
- Build voice-controlled home automation scenes
- Add background music playback
- Create interactive voice games

Your Pi is now a full voice-enabled smart home hub! 🏠🎵