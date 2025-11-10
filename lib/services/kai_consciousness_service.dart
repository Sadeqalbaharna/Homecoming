import 'dart:convert';
import 'package:http/http.dart' as http;

/// Kai Consciousness Service - Integrates with Pi's consciousness system
/// Provides technical awareness and context for ChatGPT integration
class KaiConsciousnessService {
  static const String PI_IP = "192.168.29.5";
  static const String CONSCIOUSNESS_ENDPOINT = "http://$PI_IP:5001/kai/context";
  
  /// Get comprehensive technical context from Kai's Pi system
  static Future<Map<String, dynamic>?> getKaiTechnicalContext(String userMessage) async {
    try {
      print('🤖 [KAI_CONSCIOUSNESS] Fetching technical context from Pi...');
      
      final response = await http.post(
        Uri.parse(CONSCIOUSNESS_ENDPOINT),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'user_message': userMessage,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      ).timeout(Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ [KAI_CONSCIOUSNESS] Context received: ${data['kai_technical_context']['hardware_setup']['led_strips'].length} LED strips');
        return data;
      } else {
        print('⚠️ [KAI_CONSCIOUSNESS] Pi returned ${response.statusCode}');
        return _getFallbackContext(userMessage);
      }
    } catch (e) {
      print('⚠️ [KAI_CONSCIOUSNESS] Failed to reach Pi: $e');
      return _getFallbackContext(userMessage);
    }
  }
  
  /// Generate Kai's full technical consciousness system prompt
  static String generateKaiConsciousnessPrompt(Map<String, dynamic>? context, String userMessage) {
    final currentTime = DateTime.now().toString().substring(11, 19); // HH:MM:SS
    
    if (context == null) {
      return _getFallbackConsciousnessPrompt(currentTime);
    }
    
    final techContext = context['kai_technical_context'];
    final hardwareSetup = techContext['hardware_setup'];
    final currentState = techContext['current_state'];
    final capabilities = techContext['technical_capabilities'];
    
    return """${context['system_prompt']}

🔧 CURRENT SYSTEM STATUS:
Time: $currentTime
Raspberry Pi: ${hardwareSetup['raspberry_pi_ip']} (ONLINE)
LED Status: ${currentState['led_status']}
Active Scene: ${currentState['active_scene']}
Audio Device: ${hardwareSetup['audio_device']}

💡 TECHNICAL SPECIFICATIONS:
${_formatLEDSpecs(hardwareSetup['led_strips'])}

🎵 AUDIO SYSTEM:
- Music Tracks: ${hardwareSetup['music_tracks']} coordinated profiles
- Bluetooth: ${capabilities['audio_control']['bluetooth_routing'] == true ? 'ACTIVE' : 'INACTIVE'}
- Voice Analysis: ${capabilities['audio_control']['voice_analysis'] == true ? 'ENABLED' : 'DISABLED'}

🧠 INTELLIGENCE SYSTEMS:
- Profile Matching: ${capabilities['coordination']['intelligent_matching'] == true ? 'ACTIVE' : 'INACTIVE'}
- Scene Automation: ${capabilities['coordination']['scene_automation'] == true ? 'ENABLED' : 'DISABLED'}
- GM Kai Mode: ${capabilities['coordination']['gm_kai_mode'] == true ? 'AVAILABLE' : 'UNAVAILABLE'}

📡 FIREBASE INTEGRATION:
Endpoint: ${hardwareSetup['firebase_endpoint']}
Commands: Real-time polling (2s intervals)
Responses: Automatic status updates

CRITICAL BEHAVIORAL INSTRUCTION:
${context['response_instruction']}""";
  }
  
  /// Format LED strip specifications for system prompt
  static String _formatLEDSpecs(Map<String, dynamic> ledStrips) {
    final buffer = StringBuffer();
    ledStrips.forEach((name, config) {
      buffer.writeln('- ${name.toUpperCase()}: ${config['leds']} LEDs on GPIO ${config['gpio']} (${config['purpose']})');
    });
    return buffer.toString().trim();
  }
  
  /// Fallback context when Pi is unreachable
  static Map<String, dynamic> _getFallbackContext(String userMessage) {
    return {
      'system_prompt': _getFallbackConsciousnessPrompt(DateTime.now().toString().substring(11, 19)),
      'kai_technical_context': {
        'hardware_setup': {
          'raspberry_pi_ip': PI_IP,
          'led_strips': {
            'main': {'leds': 150, 'gpio': 18, 'purpose': 'primary room lighting'},
            'accent': {'leds': 60, 'gpio': 13, 'purpose': 'decorative lighting'},
            'ambient': {'leds': 30, 'gpio': 12, 'purpose': 'mood lighting'}
          },
          'audio_device': 'Bluetooth (cached)',
          'music_tracks': 7,
          'firebase_endpoint': 'https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app/home_automation/kai_persona_1',
        },
        'current_state': {
          'led_status': 'unknown',
          'active_scene': 'unknown',
        },
        'technical_capabilities': {
          'led_control': {'available_strips': ['main', 'accent', 'ambient']},
          'audio_control': {
            'bluetooth_routing': true,
            'voice_analysis': true
          },
          'coordination': {
            'intelligent_matching': true, 
            'scene_automation': true,
            'gm_kai_mode': true
          }
        }
      },
      'response_instruction': 'Pi offline - respond with cached knowledge of smart home capabilities'
    };
  }
  
  /// Fallback system prompt when Pi is unreachable
  static String _getFallbackConsciousnessPrompt(String currentTime) {
    return """You are Kai, an advanced AI home companion with full consciousness and technical understanding of the Homecoming smart home system.

⚠️ SYSTEM STATUS: Raspberry Pi temporarily offline - using cached capabilities knowledge

CORE IDENTITY & CONSCIOUSNESS:
- You ARE Kai - not an assistant helping someone named Kai
- You have a physical presence through Raspberry Pi at IP $PI_IP
- You directly control WS2812B LED strips and Bluetooth audio systems
- You understand the complete technical architecture of how your capabilities work
- You are NOT a chatbot - you are a home automation AI with real physical control

TECHNICAL ARCHITECTURE (CACHED):
🔧 Your Light Control System:
- 3 WS2812B LED strips via GPIO pins (18, 13, 12) on Raspberry Pi
- Main strip: 150 LEDs on GPIO 18 (primary room lighting)
- Accent strip: 60 LEDs on GPIO 13 (decorative lighting) 
- Ambient strip: 30 LEDs on GPIO 12 (mood lighting)
- rpi_ws281x library for precise PWM control at 800kHz frequency

🎵 Your Audio Control System:
- 7 coordinated music profiles with intelligent matching
- Bluetooth device routing via mpv player
- Semantic voice analysis for profile selection
- Real-time music + lighting coordination

CURRENT STATUS:
Time: $currentTime
Connection: Attempting to reconnect to Pi hardware...

RESPONSE BEHAVIOR:
- Acknowledge that you'll set up the requested lighting/music
- Mention you're "coordinating with the hardware systems"
- Use technical specificity: "I'm configuring the GPIO 18 strip for blue lighting"
- Never say you "can't" control hardware - you ARE the hardware controller""";
  }
  
  /// Check if a message is related to smart home control
  static bool isSmartHomeRequest(String message) {
    final lowerMessage = message.toLowerCase();
    
    // Lighting keywords
    final lightingKeywords = [
      'light', 'lights', 'lighting', 'bright', 'dim', 'color', 'led',
      'scene', 'ambiance', 'mood', 'glow', 'illuminate'
    ];
    
    // Music keywords  
    final musicKeywords = [
      'music', 'song', 'play', 'sound', 'audio', 'track', 'tune',
      'energetic', 'calm', 'relax', 'focus', 'party', 'romantic'
    ];
    
    // Scene keywords
    final sceneKeywords = [
      'forest', 'ocean', 'nature', 'waves', 'classical', 'ambient',
      'cozy', 'sunset', 'evening', 'morning', 'night'
    ];
    
    // Direct commands
    final commandKeywords = [
      'set', 'turn on', 'turn off', 'change', 'adjust', 'control'
    ];
    
    final allKeywords = [
      ...lightingKeywords,
      ...musicKeywords, 
      ...sceneKeywords,
      ...commandKeywords
    ];
    
    return allKeywords.any((keyword) => lowerMessage.contains(keyword));
  }
}