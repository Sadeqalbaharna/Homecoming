"""
Mobile App Integration for Intelligent Ambiance System
Add these functions to your Flutter app's Dart code for seamless voice-controlled ambiance
"""

# Flutter/Dart Integration Code for homecoming_app

flutter_integration = '''
// ============================================================================
// Add to lib/services/ambiance_service.dart
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/firebase_service.dart';

class AmbianceService {
  static const String _firebaseUrl = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app";
  static const String _personaId = "kai_persona_1";
  static const String _deviceId = "raspberry_pi_home";
  
  /// Send coordinated ambiance command (music + lighting)
  static Future<bool> setAmbiance({
    required String profile,
    required Map<String, dynamic> voiceAnalysis,
    required Map<String, dynamic> lightingConfig,
    required Map<String, dynamic> ambianceAnalysis,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final commandId = "ambiance_${timestamp}_${profile.toLowerCase()}";
      
      // Send music command
      final musicSuccess = await _sendCommand(
        commandId: "${commandId}_music",
        action: "play_mood",
        target: "music",
        data: {
          "mood": profile.toLowerCase(),
          "shuffle": false,
          "voice_analysis": voiceAnalysis,
        },
      );
      
      // Send lighting command
      final lightingSuccess = await _sendCommand(
        commandId: "${commandId}_lights", 
        action: "set_ambiance_lighting",
        target: "lights",
        data: {
          "lighting_config": lightingConfig,
          "ambiance_analysis": ambianceAnalysis,
        },
      );
      
      return musicSuccess && lightingSuccess;
      
    } catch (e) {
      print('❌ Error setting ambiance: $e');
      return false;
    }
  }
  
  /// Send individual command to Firebase
  static Future<bool> _sendCommand({
    required String commandId,
    required String action,
    required String target,
    required Map<String, dynamic> data,
  }) async {
    try {
      final commandData = {
        "action": action,
        "target": target,
        "device": _deviceId,
        "timestamp": DateTime.now().millisecondsSinceEpoch,
        ...data,
      };
      
      final url = "$_firebaseUrl/home_automation/$_personaId/commands/$commandId.json";
      
      final response = await http.put(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode(commandData),
      );
      
      return response.statusCode == 200;
      
    } catch (e) {
      print('❌ Error sending command: $e');
      return false;
    }
  }
  
  /// Predefined ambiance profiles
  static const Map<String, Map<String, dynamic>> ambianceProfiles = {
    "forest": {
      "lighting": {
        "color": "light_green",
        "brightness": 70,
        "effect": "gentle_pulse"
      },
      "analysis": {
        "profile": "Forest",
        "description": "Peaceful forest with birds chirping and leaves rustling",
        "keywords": ["forest", "nature", "trees"],
        "track": 7
      }
    },
    "ocean": {
      "lighting": {
        "color": "deep_blue", 
        "brightness": 60,
        "effect": "wave"
      },
      "analysis": {
        "profile": "Ocean",
        "description": "Calming ocean waves with seagulls and gentle breeze", 
        "keywords": ["ocean", "sea", "waves"],
        "track": 1
      }
    },
    "romantic": {
      "lighting": {
        "color": "amber",
        "brightness": 30,
        "effect": "candle_flicker"
      },
      "analysis": {
        "profile": "Romantic",
        "description": "Intimate romantic setting with soft classical music",
        "keywords": ["romantic", "intimate", "dinner"],
        "track": 6
      }
    },
    "party": {
      "lighting": {
        "color": "rainbow",
        "brightness": 90, 
        "effect": "color_cycle"
      },
      "analysis": {
        "profile": "Party",
        "description": "High-energy party atmosphere with dynamic lighting",
        "keywords": ["party", "celebration", "energetic"],
        "track": 2
      }
    },
    "focus": {
      "lighting": {
        "color": "white",
        "brightness": 80,
        "effect": "solid"
      },
      "analysis": {
        "profile": "Focus",
        "description": "Clean, bright environment for concentration and productivity",
        "keywords": ["focus", "work", "study"],
        "track": 3
      }
    },
    "sunset": {
      "lighting": {
        "color": "orange",
        "brightness": 40,
        "effect": "slow_fade"
      },
      "analysis": {
        "profile": "Sunset",
        "description": "Warm sunset colors with peaceful ambient sounds",
        "keywords": ["sunset", "evening", "warm"],
        "track": 5
      }
    }
  };
}

// ============================================================================
// Add to lib/services/kai_service.dart (enhance existing)
// ============================================================================

// Add this method to your existing KaiService class
Future<bool> processAmbianceRequest(String userInput) async {
  try {
    // Analyze user input for ambiance keywords
    final ambianceProfile = _detectAmbianceProfile(userInput);
    
    if (ambianceProfile != null) {
      print('🎭 Detected ambiance request: $ambianceProfile');
      
      // Get profile configuration
      final profileConfig = AmbianceService.ambianceProfiles[ambianceProfile];
      if (profileConfig == null) return false;
      
      // Create voice analysis data
      final voiceAnalysis = {
        "original_input": userInput,
        "matched_keywords": profileConfig["analysis"]["keywords"],
        "matched_contexts": [ambianceProfile, "ambiance"],
        "confidence": _calculateConfidence(userInput, profileConfig["analysis"]["keywords"]),
        "selected_track": profileConfig["analysis"]["track"],
      };
      
      // Set coordinated ambiance
      final success = await AmbianceService.setAmbiance(
        profile: ambianceProfile,
        voiceAnalysis: voiceAnalysis,
        lightingConfig: profileConfig["lighting"],
        ambianceAnalysis: {
          "profile": profileConfig["analysis"]["profile"],
          "description": profileConfig["analysis"]["description"],
          "confidence": voiceAnalysis["confidence"],
        },
      );
      
      if (success) {
        // Generate Kai's response about the ambiance
        final response = _generateAmbianceResponse(ambianceProfile, profileConfig);
        await _sendKaiMessage(response);
        return true;
      }
    }
    
    return false;
    
  } catch (e) {
    print('❌ Error processing ambiance request: $e');
    return false;
  }
}

String? _detectAmbianceProfile(String input) {
  final lowercaseInput = input.toLowerCase();
  
  // Check for ambiance-related keywords
  final ambianceKeywords = [
    'ambiance', 'ambience', 'mood', 'atmosphere', 'setting', 'vibe'
  ];
  
  bool hasAmbianceKeyword = ambianceKeywords.any((keyword) => 
    lowercaseInput.contains(keyword));
  
  if (!hasAmbianceKeyword) {
    // Also check for direct profile mentions
    hasAmbianceKeyword = AmbianceService.ambianceProfiles.keys.any((profile) =>
      lowercaseInput.contains(profile));
  }
  
  if (hasAmbianceKeyword) {
    // Find best matching profile
    for (final profile in AmbianceService.ambianceProfiles.keys) {
      final keywords = AmbianceService.ambianceProfiles[profile]!["analysis"]["keywords"] as List;
      
      if (keywords.any((keyword) => lowercaseInput.contains(keyword))) {
        return profile;
      }
    }
  }
  
  return null;
}

double _calculateConfidence(String input, List keywords) {
  final lowercaseInput = input.toLowerCase();
  int matches = 0;
  
  for (final keyword in keywords) {
    if (lowercaseInput.contains(keyword.toString().toLowerCase())) {
      matches++;
    }
  }
  
  return (matches / keywords.length * 0.8) + 0.2; // Base confidence of 20%
}

String _generateAmbianceResponse(String profile, Map<String, dynamic> config) {
  final responses = {
    "forest": [
      "I'm creating a peaceful forest ambiance with gentle green lighting and nature sounds. 🌲",
      "Setting up your forest environment - imagine you're surrounded by tall trees with birds singing nearby. 🕊️",
      "Forest ambiance activated! The green lights and natural sounds will help you feel connected to nature. 🌿"
    ],
    "ocean": [
      "I'm bringing the ocean to you with calming blue lights and wave sounds. 🌊", 
      "Creating your personal seaside retreat with deep blue ambiance and gentle ocean waves. 🏖️",
      "Ocean mood set! Let the blue lights and wave sounds wash your stress away. 💙"
    ],
    "romantic": [
      "Setting a romantic mood with warm amber lighting and soft classical music. 💕",
      "I'm creating an intimate atmosphere perfect for a romantic evening. 🕯️", 
      "Romantic ambiance ready! The candlelight effect and elegant music will set the perfect mood. ✨"
    ],
    "party": [
      "Party mode activated! Get ready for dynamic rainbow lights and energetic beats! 🎉",
      "I'm turning up the energy with colorful lighting and upbeat music. Let's celebrate! 💃",
      "Party ambiance set! The room is now your personal dance floor with vibrant lights and pumping music! 🎵"
    ],
    "focus": [
      "I'm optimizing your environment for maximum focus with clean white lighting and concentration music. 💡",
      "Focus mode activated! The bright, steady lighting will help you stay productive. 📚",
      "Creating the perfect work environment with clear lighting and focus-enhancing sounds. ⚡"
    ],
    "sunset": [
      "I'm painting your room with warm sunset colors and peaceful evening sounds. 🌅",
      "Sunset ambiance ready! The orange glow will help you unwind as the day transitions to night. 🧡",
      "Creating a beautiful sunset atmosphere to help you relax and reflect. 🌄"
    ]
  };
  
  final profileResponses = responses[profile];
  if (profileResponses != null && profileResponses.isNotEmpty) {
    final random = Random();
    return profileResponses[random.nextInt(profileResponses.length)];
  }
  
  return "I've set up the $profile ambiance for you with coordinated lighting and music. Enjoy! ✨";
}

// ============================================================================
// Update lib/screens/main_screen.dart (enhance existing voice processing)
// ============================================================================

// In your existing voice processing method, add this check:
Future<void> _processVoiceInput(String voiceText) async {
  try {
    // First check if this is an ambiance request
    final ambianceHandled = await KaiService.processAmbianceRequest(voiceText);
    
    if (!ambianceHandled) {
      // Continue with normal Kai processing
      await _sendToKai(voiceText);
    }
    
  } catch (e) {
    print('Error processing voice input: $e');
  }
}
'''

print(flutter_integration)

# Python Integration for AI Pipeline
python_integration = '''
# ============================================================================
# Add to your existing Python AI pipeline (kai_personality.py or similar)
# ============================================================================

import requests
import json
import time
import random

class AmbianceIntegrator:
    """Integration layer for Kai's ambiance control"""
    
    def __init__(self):
        self.firebase_url = "https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app"
        self.persona_id = "kai_persona_1"
        self.device_id = "raspberry_pi_home"
    
    def should_kai_handle_ambiance(self, user_input):
        """Check if user input is requesting ambiance control"""
        ambiance_keywords = [
            'ambiance', 'ambience', 'mood', 'atmosphere', 'setting', 'vibe',
            'lighting', 'lights', 'forest', 'ocean', 'romantic', 'party',
            'sunset', 'cozy', 'focus', 'relax', 'energetic'
        ]
        
        input_lower = user_input.lower()
        return any(keyword in input_lower for keyword in ambiance_keywords)
    
    def process_kai_ambiance_request(self, user_input):
        """Process ambiance request and send to Pi"""
        try:
            # Import the intelligent ambiance system
            from intelligent_ambiance_system import analyze_voice_command, send_firebase_commands
            
            # Analyze the voice command
            result = analyze_voice_command(user_input)
            
            if result and result.get('confidence', 0) > 0.3:  # 30% confidence threshold
                # Send coordinated commands to Pi
                success = send_firebase_commands(result)
                
                if success:
                    return self._generate_kai_response(result)
                else:
                    return "I tried to set up that ambiance, but there seems to be a technical issue. Let me try again in a moment."
            else:
                return None  # Let normal Kai processing handle it
                
        except Exception as e:
            print(f"Error in ambiance processing: {e}")
            return "I'd love to help with that ambiance, but I'm having some technical difficulties right now."
    
    def _generate_kai_response(self, ambiance_result):
        """Generate appropriate Kai response for ambiance setting"""
        profile = ambiance_result.get('profile', 'Unknown')
        confidence = ambiance_result.get('confidence', 0)
        
        responses = {
            "Forest": [
                "I'm creating a peaceful forest environment for you with gentle green lighting and nature sounds. 🌲",
                "Perfect! I'm setting up a tranquil forest ambiance. You'll hear birds chirping while soft green lights create that natural atmosphere.",
                "Forest ambiance activated! The combination of green lighting and natural soundscapes will help you feel connected to nature."
            ],
            "Ocean": [
                "I'm bringing the ocean to your space with calming blue lights and wave sounds. 🌊",
                "Creating your personal seaside retreat now. The deep blue ambiance with ocean waves will be very relaxing.",
                "Ocean mood set! Let the rhythmic blue lighting and gentle wave sounds wash away your stress."
            ],
            "Romantic": [
                "I'm setting a romantic atmosphere with warm amber lighting and soft classical music. 💕",
                "Creating an intimate setting perfect for a romantic evening. The candlelight effect with elegant music will be lovely.",
                "Romantic ambiance ready! The warm glow and classical sounds create the perfect mood for intimacy."
            ],
            "Party": [
                "Party time! I'm activating dynamic rainbow lights with energetic beats. Let's celebrate! 🎉",
                "Getting the party started with colorful lighting and upbeat music. Time to dance!",
                "Party mode engaged! Your space is now a vibrant dance floor with pulsing lights and pumping music."
            ],
            "Focus": [
                "I'm optimizing your environment for maximum productivity with clean white lighting and focus music. 💡",
                "Focus mode activated! The bright, steady lighting will help keep you concentrated and alert.",
                "Creating the perfect work atmosphere with clear lighting and concentration-enhancing sounds."
            ],
            "Sunset": [
                "I'm painting your room with beautiful sunset colors and peaceful evening sounds. 🌅",
                "Sunset ambiance ready! The warm orange glow will help you unwind as day transitions to night.",
                "Creating a gorgeous sunset atmosphere to help you relax and reflect on the day."
            ]
        }
        
        profile_responses = responses.get(profile, [
            f"I've set up the {profile.lower()} ambiance with coordinated lighting and music for you.",
            f"Perfect! Your {profile.lower()} environment is ready with matching lights and sounds.",
            f"Ambiance activated! Enjoy your personalized {profile.lower()} atmosphere."
        ])
        
        # Add confidence indicator for high-confidence matches
        selected_response = random.choice(profile_responses)
        
        if confidence > 0.8:
            selected_response += " I'm very confident this matches what you wanted!"
        elif confidence > 0.6:
            selected_response += " This should be exactly what you're looking for."
        
        return selected_response

# ============================================================================
# Integration with existing Kai personality
# ============================================================================

# Add this to your main Kai processing function
def enhanced_kai_response(user_input):
    """Enhanced Kai processing with ambiance integration"""
    
    ambiance_integrator = AmbianceIntegrator()
    
    # Check if this is an ambiance request
    if ambiance_integrator.should_kai_handle_ambiance(user_input):
        ambiance_response = ambiance_integrator.process_kai_ambiance_request(user_input)
        
        if ambiance_response:
            return ambiance_response
    
    # Continue with normal Kai personality processing
    return generate_normal_kai_response(user_input)
'''

print("\\n" + "="*50)
print("PYTHON AI PIPELINE INTEGRATION")  
print("="*50)
print(python_integration)

# Create usage examples
examples = '''
# ============================================================================
# USAGE EXAMPLES FOR TESTING
# ============================================================================

Voice Commands to Test:
------------------------
1. "Kai, give me forest ambiance"
   → Green lights + nature sounds + track 7

2. "Create ocean mood" 
   → Blue lights + wave effects + track 1

3. "Set romantic atmosphere for dinner"
   → Amber lights + candle flicker + track 6

4. "I want party vibes"
   → Rainbow lights + color cycle + track 2

5. "Help me focus on work"
   → White lights + solid effect + track 3

6. "Give me sunset ambiance" 
   → Orange lights + slow fade + track 5

Expected Pi Response Logs:
--------------------------
🎭 Ambiance profile: Forest (85.0% confidence)
💡 Setting ambiance lighting: light_green at 70%
✨ Activating effect: Gentle pulsing effect
🧠 Using Kai's intelligent selection: Track 7
🎵 Playing track 7 (forest mood) via Bluetooth

Mobile App Testing:
-------------------
1. Use voice input or text chat
2. Say any ambiance command above
3. Check Firebase console for commands
4. Monitor Pi logs for coordination
5. Verify both music and lights activate

Firebase Database Structure:
----------------------------
/home_automation/kai_persona_1/
├── commands/
│   ├── ambiance_123_music/
│   └── ambiance_123_lights/
└── responses/
    ├── ambiance_123_music/
    └── ambiance_123_lights/
'''

print("\\n" + "="*50)
print("TESTING EXAMPLES") 
print("="*50)
print(examples)