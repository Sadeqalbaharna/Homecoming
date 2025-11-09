import 'lib/services/ambiance_service.dart';

void main() {
  final ambianceService = AmbianceService();
  
  // Test various inputs that should trigger ambiance
  final testInputs = [
    "Kai, play some relaxing music",
    "I want forest ambiance", 
    "give me ocean vibes",
    "set romantic mood",
    "play relaxing track",
    "can you play music for focus",
    "I need some energetic music",
    "set the lights to cozy mode",
    "give me some peaceful music",
    "play track 1",
  ];
  
  print('🧪 Testing Ambiance Detection');
  print('=' * 50);
  
  for (final input in testInputs) {
    final match = ambianceService.analyzeVoiceCommand(input);
    
    if (match != null) {
      print('✅ "$input"');
      print('   → Profile: ${match.profile}');
      print('   → Confidence: ${(match.confidence * 100).toStringAsFixed(1)}%');
      print('   → Keywords: ${match.matchedKeywords.join(", ")}');
      print('');
    } else {
      print('❌ "$input" → No ambiance detected');
      print('');
    }
  }
  
  print('🎭 Available Profiles:');
  for (final profile in AmbianceService.ambianceProfiles.keys) {
    final keywords = AmbianceService.ambianceProfiles[profile]!['analysis']['keywords'];
    print('   $profile: ${keywords.join(", ")}');
  }
}