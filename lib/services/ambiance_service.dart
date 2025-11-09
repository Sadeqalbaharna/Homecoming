/// Intelligent Ambiance Service
/// Handles coordinated music and lighting control through voice commands
/// Integrates with Kai's voice analysis for context-aware ambiance setting
library;

import 'dart:async';
import 'dart:math';
import 'home_automation_service.dart';

class AmbianceService {
  static final AmbianceService _instance = AmbianceService._internal();
  factory AmbianceService() => _instance;
  AmbianceService._internal();

  // Firebase configuration
  static const String _personaId = "kai_persona_1";
  static const String _deviceId = "raspberry_pi_home";

  /// Send coordinated ambiance command (music + lighting)
  Future<bool> setAmbiance({
    required String profile,
    required String originalInput,
    double? confidence,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final profileConfig = ambianceProfiles[profile.toLowerCase()];
      
      if (profileConfig == null) {
        print('❌ [Ambiance] Unknown profile: $profile');
        return false;
      }

      // Generate voice analysis data
      final voiceAnalysis = _createVoiceAnalysis(
        originalInput, 
        profileConfig['analysis'], 
        confidence
      );

      print('🎭 [Ambiance] Setting $profile ambiance (${(confidence ?? 0.5) * 100}% confidence)');

      // Send music command
      final musicSuccess = await HomeAutomationService().sendCommand(
        personaId: _personaId,
        deviceId: _deviceId,
        target: "music",
        action: "play_mood",
        params: {
          "mood": profile.toLowerCase(),
          "shuffle": false,
          "voice_analysis": voiceAnalysis,
        },
      );

      // Send lighting command
      final lightingSuccess = await HomeAutomationService().sendCommand(
        personaId: _personaId,
        deviceId: _deviceId,
        target: "lights",
        action: "set_ambiance_lighting",
        params: {
          "lighting_config": profileConfig['lighting'],
          "ambiance_analysis": {
            "profile": profileConfig['analysis']['profile'],
            "description": profileConfig['analysis']['description'],
            "confidence": confidence ?? 0.5,
          },
        },
      );

      final success = musicSuccess && lightingSuccess;
      
      if (success) {
        print('✅ [Ambiance] ${profileConfig['analysis']['profile']} ambiance set successfully');
      } else {
        print('❌ [Ambiance] Failed to set ambiance - Music: $musicSuccess, Lights: $lightingSuccess');
      }

      return success;

    } catch (e) {
      print('❌ [Ambiance] Error setting ambiance: $e');
      return false;
    }
  }

  /// Analyze voice input for ambiance requests
  AmbianceMatch? analyzeVoiceCommand(String input) {
    final lowercaseInput = input.toLowerCase();
    
    // Check for ambiance-related keywords
    final ambianceKeywords = [
      'ambiance', 'ambience', 'mood', 'atmosphere', 'setting', 'vibe',
      'lighting', 'lights', 'environment', 'scene'
    ];
    
    bool hasAmbianceKeyword = ambianceKeywords.any((keyword) => 
      lowercaseInput.contains(keyword));
    
    if (!hasAmbianceKeyword) {
      // Also check for direct profile mentions
      hasAmbianceKeyword = ambianceProfiles.keys.any((profile) =>
        lowercaseInput.contains(profile));
    }
    
    if (!hasAmbianceKeyword) {
      return null;
    }
    
    // Find best matching profile
    AmbianceMatch? bestMatch;
    double bestScore = 0.0;
    
    for (final entry in ambianceProfiles.entries) {
      final profile = entry.key;
      final config = entry.value;
      final keywords = List<String>.from(config['analysis']['keywords']);
      
      double score = 0.0;
      int matches = 0;
      
      // Check keyword matches
      for (final keyword in keywords) {
        if (lowercaseInput.contains(keyword)) {
          matches++;
          score += 1.0;
        }
      }
      
      // Check for partial matches
      for (final keyword in keywords) {
        for (final word in lowercaseInput.split(' ')) {
          if (word.length > 3 && keyword.contains(word)) {
            score += 0.5;
          }
        }
      }
      
      // Calculate confidence based on matches and total keywords
      final confidence = (score / keywords.length).clamp(0.0, 1.0);
      
      // Bonus for profile name match
      if (lowercaseInput.contains(profile)) {
        score += 2.0;
      }
      
      if (score > bestScore && confidence > 0.3) {
        bestScore = score;
        bestMatch = AmbianceMatch(
          profile: profile,
          confidence: confidence,
          matchedKeywords: keywords.where((k) => lowercaseInput.contains(k)).toList(),
        );
      }
    }
    
    return bestMatch;
  }

  /// Generate Kai's response for ambiance setting
  String generateKaiResponse(String profile, double confidence) {
    final config = ambianceProfiles[profile.toLowerCase()];
    if (config == null) return "I've set up a custom ambiance for you.";
    
    final responses = _getResponsesForProfile(profile);
    final selectedResponse = responses[Random().nextInt(responses.length)];
    
    // Add confidence indicator for high-confidence matches
    String response = selectedResponse;
    if (confidence > 0.8) {
      response += " I'm very confident this matches what you wanted!";
    } else if (confidence > 0.6) {
      response += " This should be exactly what you're looking for.";
    }
    
    return response;
  }

  /// Create voice analysis data for Firebase
  Map<String, dynamic> _createVoiceAnalysis(
    String originalInput, 
    Map<String, dynamic> analysisConfig,
    double? confidence,
  ) {
    final keywords = List<String>.from(analysisConfig['keywords']);
    final matchedKeywords = keywords.where((k) => 
      originalInput.toLowerCase().contains(k)).toList();
    
    return {
      "original_input": originalInput,
      "matched_keywords": matchedKeywords,
      "matched_contexts": [analysisConfig['profile'].toString().toLowerCase(), "ambiance"],
      "confidence": confidence ?? _calculateConfidence(originalInput, keywords),
      "selected_track": analysisConfig['track'],
    };
  }

  /// Calculate confidence score
  double _calculateConfidence(String input, List<String> keywords) {
    final lowercaseInput = input.toLowerCase();
    int matches = 0;
    
    for (final keyword in keywords) {
      if (lowercaseInput.contains(keyword)) {
        matches++;
      }
    }
    
    return ((matches / keywords.length) * 0.8 + 0.2).clamp(0.0, 1.0);
  }

  /// Get response templates for profile
  List<String> _getResponsesForProfile(String profile) {
    final responses = {
      "forest": [
        "I'm creating a peaceful forest environment for you with gentle green lighting and nature sounds. 🌲",
        "Perfect! I'm setting up a tranquil forest ambiance. You'll hear birds chirping while soft green lights create that natural atmosphere.",
        "Forest ambiance activated! The combination of green lighting and natural soundscapes will help you feel connected to nature."
      ],
      "ocean": [
        "I'm bringing the ocean to your space with calming blue lights and wave sounds. 🌊",
        "Creating your personal seaside retreat now. The deep blue ambiance with ocean waves will be very relaxing.",
        "Ocean mood set! Let the rhythmic blue lighting and gentle wave sounds wash away your stress."
      ],
      "romantic": [
        "I'm setting a romantic atmosphere with warm amber lighting and soft classical music. 💕",
        "Creating an intimate setting perfect for a romantic evening. The candlelight effect with elegant music will be lovely.",
        "Romantic ambiance ready! The warm glow and classical sounds create the perfect mood for intimacy."
      ],
      "party": [
        "Party time! I'm activating dynamic rainbow lights with energetic beats. Let's celebrate! 🎉",
        "Getting the party started with colorful lighting and upbeat music. Time to dance!",
        "Party mode engaged! Your space is now a vibrant dance floor with pulsing lights and pumping music."
      ],
      "focus": [
        "I'm optimizing your environment for maximum productivity with clean white lighting and focus music. 💡",
        "Focus mode activated! The bright, steady lighting will help keep you concentrated and alert.",
        "Creating the perfect work atmosphere with clear lighting and concentration-enhancing sounds."
      ],
      "sunset": [
        "I'm painting your room with beautiful sunset colors and peaceful evening sounds. 🌅",
        "Sunset ambiance ready! The warm orange glow will help you unwind as day transitions to night.",
        "Creating a gorgeous sunset atmosphere to help you relax and reflect on the day."
      ],
      "cozy": [
        "I'm setting up a cozy atmosphere with warm lighting and comfortable background sounds. 🏠",
        "Creating that perfect cozy feeling with soft amber lights and gentle ambient music.",
        "Cozy mode activated! Your space now feels like a warm hug with perfect lighting and sounds."
      ],
      "energetic": [
        "I'm energizing your space with bright lighting and motivating music! ⚡",
        "Energy mode on! Bright lights and upbeat sounds to help you power through anything.",
        "Energetic ambiance set! Ready to tackle whatever comes your way with this motivating atmosphere."
      ]
    };
    
    return responses[profile.toLowerCase()] ?? [
      "I've set up the $profile ambiance with coordinated lighting and music for you.",
      "Perfect! Your $profile environment is ready with matching lights and sounds.",
      "Ambiance activated! Enjoy your personalized $profile atmosphere."
    ];
  }

  /// Predefined ambiance profiles with coordinated lighting and music
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
        "keywords": ["forest", "nature", "trees", "woods", "natural"],
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
        "keywords": ["ocean", "sea", "waves", "beach", "water"],
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
        "keywords": ["romantic", "intimate", "dinner", "love", "couple"],
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
        "keywords": ["party", "celebration", "energetic", "dance", "fun"],
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
        "keywords": ["focus", "work", "study", "concentrate", "productivity"],
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
        "keywords": ["sunset", "evening", "warm", "golden", "dusk"],
        "track": 5
      }
    },
    "cozy": {
      "lighting": {
        "color": "warm_white",
        "brightness": 50,
        "effect": "solid"
      },
      "analysis": {
        "profile": "Cozy",
        "description": "Warm and comfortable atmosphere for relaxation",
        "keywords": ["cozy", "comfortable", "relaxing", "warm", "home"],
        "track": 1
      }
    },
    "energetic": {
      "lighting": {
        "color": "yellow",
        "brightness": 85,
        "effect": "gentle_pulse"
      },
      "analysis": {
        "profile": "Energetic",
        "description": "Bright and motivating environment to boost energy",
        "keywords": ["energetic", "motivated", "active", "bright", "upbeat"],
        "track": 2
      }
    }
  };

  /// Quick access methods for common ambiances
  Future<bool> setForestAmbiance(String originalInput) => 
    setAmbiance(profile: "forest", originalInput: originalInput);

  Future<bool> setOceanAmbiance(String originalInput) => 
    setAmbiance(profile: "ocean", originalInput: originalInput);

  Future<bool> setRomanticAmbiance(String originalInput) => 
    setAmbiance(profile: "romantic", originalInput: originalInput);

  Future<bool> setPartyAmbiance(String originalInput) => 
    setAmbiance(profile: "party", originalInput: originalInput);

  Future<bool> setFocusAmbiance(String originalInput) => 
    setAmbiance(profile: "focus", originalInput: originalInput);

  /// Stop all ambiance (music and lights)
  Future<bool> stopAmbiance() async {
    try {
      // Stop music
      final musicStopped = await HomeAutomationService().sendCommand(
        personaId: _personaId,
        deviceId: _deviceId,
        target: "music",
        action: "stop_music",
      );

      // Turn off ambiance lighting (reset to default)
      final lightingStopped = await HomeAutomationService().sendCommand(
        personaId: _personaId,
        deviceId: _deviceId,
        target: "lights",
        action: "set_ambiance_lighting",
        params: {
          "lighting_config": {
            "color": "warm_white",
            "brightness": 50,
            "effect": "solid"
          },
          "ambiance_analysis": {
            "profile": "Default",
            "description": "Reset to default lighting",
            "confidence": 1.0,
          },
        },
      );

      print('🛑 [Ambiance] Stopped - Music: $musicStopped, Lights: $lightingStopped');
      return musicStopped && lightingStopped;

    } catch (e) {
      print('❌ [Ambiance] Error stopping ambiance: $e');
      return false;
    }
  }
}

/// Ambiance analysis result
class AmbianceMatch {
  final String profile;
  final double confidence;
  final List<String> matchedKeywords;

  AmbianceMatch({
    required this.profile,
    required this.confidence,
    required this.matchedKeywords,
  });

  @override
  String toString() => 'AmbianceMatch(profile: $profile, confidence: ${(confidence * 100).toStringAsFixed(1)}%)';
}