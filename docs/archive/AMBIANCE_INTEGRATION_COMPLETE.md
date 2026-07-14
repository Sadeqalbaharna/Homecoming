# 🎭 Intelligent Ambiance System Integration Guide

## ✅ What's Ready

1. **Enhanced Firebase Listener** (`firebase_rest_listener_debug.py`)
   - Supports both music and intelligent lighting commands
   - 12 coordinated ambiance profiles
   - Voice analysis integration

2. **Mobile App Services** 
   - `AmbianceService` - Core ambiance coordination
   - `AI Service` - Enhanced with ambiance detection
   - `HomeAutomationService` - Already working

3. **Test Interface**
   - `AmbianceTestScreen` - Complete testing UI
   - `AmbianceControlWidget` - Quick test controls

## 🚀 Integration Steps

### Step 1: Add Test Screen to Your App

Add this to your main app navigation (probably in `lib/main.dart`):

```dart
// Import the test screen
import 'screens/ambiance_test_screen.dart';

// Add a way to navigate to it, for example:
// In your main app, add a FloatingActionButton or menu item:

FloatingActionButton(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AmbianceTestScreen()),
    );
  },
  child: const Icon(Icons.lightbulb),
  tooltip: 'Test Ambiance System',
)
```

### Step 2: Test the System

1. **Make sure your Pi listener is running:**
   ```bash
   cd /home/pi
   python3 firebase_rest_listener_debug.py
   ```

2. **Open the test screen in your app**

3. **Try voice commands like:**
   - "Kai, give me forest ambiance"
   - "Create ocean mood" 
   - "Set romantic atmosphere"
   - "I need to focus"

### Step 3: Integration with Existing Voice Pipeline

Your existing voice processing should automatically detect ambiance requests now because:

1. **AI Service Enhanced**: `ai_service.dart` now includes ambiance detection
2. **Automatic Bypass**: Ambiance requests bypass full AI processing for speed
3. **Natural Responses**: Kai responds naturally about the ambiance being set

### Step 4: Voice Integration Example

If you want to manually integrate with your existing voice system:

```dart
import 'services/ambiance_service.dart';

// In your voice processing method:
Future<void> processVoiceInput(String voiceText) async {
  final ambianceService = AmbianceService();
  
  // Check if this is an ambiance request
  final ambianceMatch = ambianceService.analyzeVoiceCommand(voiceText);
  
  if (ambianceMatch != null) {
    // Handle ambiance request
    final success = await ambianceService.setAmbiance(
      profile: ambianceMatch.profile,
      originalInput: voiceText,
      confidence: ambianceMatch.confidence,
    );
    
    if (success) {
      final response = ambianceService.generateKaiResponse(
        ambianceMatch.profile, 
        ambianceMatch.confidence
      );
      
      // Display Kai's response
      showKaiResponse(response);
      return; // Don't process further
    }
  }
  
  // Continue with normal AI processing
  final aiResponse = await aiService.sendMessage(text: voiceText, personaId: 'kai_persona_1');
  showKaiResponse(aiResponse.reply);
}
```

## 🎯 Expected Behavior

When working correctly:

1. **User says**: "Kai, give me forest ambiance"
2. **App detects**: Forest profile (85% confidence)
3. **Firebase commands sent**: 
   - Music: `play_mood` → track 7 (nature sounds)
   - Lights: `set_ambiance_lighting` → green + gentle pulse
4. **Pi responds**: Coordinated music and lighting
5. **Kai says**: Natural response about forest ambiance

## 📱 Quick Test

The easiest way to test:

1. Open `AmbianceTestScreen` in your app
2. Use the quick test buttons (🌲 Forest, 🌊 Ocean, etc.)
3. Check Pi logs for coordination
4. Try talking to Kai directly with ambiance requests

## 🔧 Troubleshooting

- **No response**: Check Pi listener is running and connected to internet
- **Music only**: Check lighting config in ambiance profiles  
- **No Firebase commands**: Check device ID matches ("raspberry_pi_home")
- **AI not detecting**: Check confidence threshold (default 30%)

## 🎉 Success Indicators

✅ Pi logs show coordinated music + lighting commands  
✅ Kai responds naturally about ambiance  
✅ Voice commands work from both test screen and normal chat  
✅ Multiple ambiance profiles working (forest, ocean, romantic, etc.)  
✅ Stop ambiance resets to default lighting  

The system is ready to test! Start with the test screen to verify everything works, then integrate into your main voice pipeline.