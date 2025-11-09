# Kai Intelligent Ambiance Integration Guide

## 🎭 Complete Voice-Activated Ambiance System

This system allows Kai to understand natural language requests like "give me forest ambiance" and intelligently coordinate both music and lighting to create the perfect atmosphere.

## 🌟 Supported Ambiance Profiles

### Nature & Outdoor
- **Forest**: Green lighting + nature sounds (`forest`, `woods`, `trees`, `nature`)
- **Ocean**: Blue wave lighting + ocean sounds (`ocean`, `sea`, `beach`, `waves`)  
- **Mountain**: Purple lighting + focus music (`mountain`, `peak`, `elevation`)
- **Sunset**: Orange fade lighting + ambient music (`sunset`, `dusk`, `golden hour`)

### Indoor & Social  
- **Cozy**: Warm white pulse + relaxing music (`cozy`, `warm`, `comfortable`)
- **Party**: Rainbow cycling + energetic music (`party`, `celebration`, `dance`)
- **Romantic**: Red candle flicker + classical music (`romantic`, `love`, `intimate`)
- **Focus**: Bright white + concentration music (`focus`, `work`, `study`)

### Weather & Time
- **Rainy**: Gray-blue rain drops + contemplative music (`rain`, `storm`, `cloudy`)
- **Morning**: Yellow sunrise + energetic music (`morning`, `sunrise`, `energy`)
- **Night**: Deep blue pulse + relaxing music (`night`, `sleep`, `bedtime`)

### Seasonal
- **Spring**: Light green + cheerful music (`spring`, `fresh`, `bloom`)
- **Autumn**: Amber leaf fall + ambient music (`autumn`, `fall`, `golden`)

## 🚀 Integration Status

### ✅ Completed Components:

1. **IntelligentAmbianceSystem** (`intelligent_ambiance_system.py`)
   - Analyzes voice commands for ambiance requests
   - Matches keywords and contexts to profiles
   - Sends coordinated Firebase commands for music + lighting

2. **KaiAmbianceIntegrator** (`kai_ambiance_integrator.py`)
   - Connects Kai's conversational AI to ambiance system
   - Generates appropriate responses based on confidence
   - Handles ambiance requests separately from normal conversation

3. **Enhanced Firebase Listener** (`firebase_rest_listener_debug.py`)
   - Supports both music (`play_mood`) and lighting (`set_ambiance_lighting`) commands
   - Processes voice analysis data for intelligent track selection
   - Simulates smart lighting control (ready for hardware integration)

### 🎯 Voice Command Examples:

```
"Hey Kai, give me forest ambiance"
→ 🎵 Track 7 (nature sounds) + 💡 Green pulse lighting

"Create a romantic mood"  
→ 🎵 Track 6 (classical) + 💡 Red candle flicker

"I want to focus on work"
→ 🎵 Track 3 (focus music) + 💡 Bright white lighting

"Set up party atmosphere" 
→ 🎵 Track 2 (energetic) + 💡 Rainbow cycling lights

"Make it cozy in here"
→ 🎵 Track 1 (relaxing) + 💡 Warm white pulse
```

## 🔗 Mobile App Integration

### Step 1: Add Ambiance Check to AI Service

In your Dart AI service, before processing with normal AI:

```dart
// Add to your AI message processing pipeline
Future<String?> checkAmbianceRequest(String userMessage) async {
  // Call Python ambiance integrator
  final result = await callKaiAmbianceIntegrator(userMessage);
  
  if (result['is_ambiance_request'] && result['confidence'] > 0.6) {
    // High confidence - use Kai's suggested response
    return result['suggested_response'];
  }
  
  // Let normal AI handle it
  return null;
}
```

### Step 2: Create Python Bridge Function

```dart
// Call the Python ambiance system
Future<Map<String, dynamic>> callKaiAmbianceIntegrator(String message) async {
  try {
    // Option 1: Call Python script directly
    final result = await Process.run('python', [
      'kai_ambiance_integrator.py', 
      '--message', message
    ]);
    
    return jsonDecode(result.stdout);
    
    // Option 2: Use HTTP API (if you set up a Flask server)
    // final response = await http.post('http://localhost:5000/ambiance', 
    //   body: {'message': message});
    // return jsonDecode(response.body);
    
  } catch (e) {
    print('Ambiance integration error: $e');
    return {'is_ambiance_request': false};
  }
}
```

### Step 3: Update Voice Processing Flow

```dart
// In your voice processing pipeline
Future<void> processVoiceCommand(String transcription) async {
  // Check if this is an ambiance request first
  final ambianceResponse = await checkAmbianceRequest(transcription);
  
  if (ambianceResponse != null) {
    // Handle as ambiance request - Kai's response already generated
    _showKaiResponse(ambianceResponse);
    return;
  }
  
  // Continue with normal AI processing
  final normalResponse = await aiService.sendMessage(transcription);
  _showKaiResponse(normalResponse);
}
```

## 🏠 Pi Hardware Integration

### Current Status: 
- ✅ Music control via mpv + Bluetooth headset
- 🔄 Lighting control (simulated - ready for hardware)

### Hardware Setup Options:

#### Option 1: Smart Bulbs (Easiest)
```bash
# Control Philips Hue, LIFX, or TP-Link Kasa bulbs via WiFi
pip install phue lifxlan tplinkcloud
```

#### Option 2: LED Strips (Most Flexible)  
```bash
# Control WS2812B LED strips via GPIO
pip install rpi_ws281x adafruit-circuitpython-neopixel
```

#### Option 3: Smart Switches (Existing Lights)
```bash
# Control existing lights via smart switches
pip install tuyapy kasapy
```

## 🧪 Testing

### Test Voice Commands:
```bash
# Test the ambiance system
python intelligent_ambiance_system.py

# Test Kai integration  
python kai_ambiance_integrator.py

# Test Firebase listener (with music files)
python firebase_rest_listener_debug.py
```

### Expected Firebase Commands:

**Music Command:**
```json
{
  "action": "play_mood",
  "target": "music",
  "mood": "peaceful", 
  "voice_analysis": {
    "original_input": "Hey Kai, give me forest ambiance",
    "selected_track": 7,
    "confidence": 0.515
  }
}
```

**Lighting Command:**
```json
{
  "action": "set_ambiance_lighting",
  "target": "lights",
  "lighting_config": {
    "color": "green",
    "brightness": 60,
    "effect": "gentle_pulse"
  }
}
```

## 🎉 Final Result

When you say **"Hey Kai, give me forest ambiance"**:

1. 🎤 Voice is transcribed
2. 🧠 Kai's AI detects ambiance request  
3. 🎭 Ambiance system analyzes: "forest" → Forest profile
4. 📤 Firebase commands sent for music (Track 7) + lighting (green pulse)
5. 🎵 Pi plays nature sounds via Bluetooth headset
6. 💡 Pi sets green pulsing lights 
7. 🤖 Kai responds: "Perfect! I'm creating a forest ambiance for you..."

The system creates **coordinated atmosphere experiences** through intelligent voice understanding! 🌲✨