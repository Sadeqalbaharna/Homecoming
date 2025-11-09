// Simple test for ambiance detection patterns
void main() {
  // Test phrases that should trigger ambiance
  final testPhrases = [
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
    "play something calming",
    "I want nature sounds",
    "set forest lighting",
    "ocean atmosphere please"
  ];
  
  print('🧪 Testing Ambiance Keyword Detection');
  print('=' * 50);
  
  // Ambiance profiles from the service
  final ambianceProfiles = {
    "forest": ["forest", "nature", "trees", "woods", "natural"],
    "ocean": ["ocean", "sea", "waves", "beach", "water"], 
    "romantic": ["romantic", "intimate", "dinner", "love", "couple"],
    "party": ["party", "celebration", "energetic", "dance", "fun"],
    "focus": ["focus", "work", "study", "concentrate", "productivity"],
    "sunset": ["sunset", "evening", "warm", "golden", "dusk"],
    "cozy": ["cozy", "comfortable", "relaxing", "warm", "home"],
    "energetic": ["energetic", "motivated", "active", "bright", "upbeat"]
  };
  
  // Ambiance keywords
  final ambianceKeywords = [
    'ambiance', 'ambience', 'mood', 'atmosphere', 'setting', 'vibe',
    'lighting', 'lights', 'environment', 'scene'
  ];
  
  for (final phrase in testPhrases) {
    final lowercasePhrase = phrase.toLowerCase();
    
    // Check for ambiance keywords
    bool hasAmbianceKeyword = ambianceKeywords.any((keyword) => 
      lowercasePhrase.contains(keyword));
    
    // Check for profile keywords  
    bool hasProfileKeyword = false;
    String? matchedProfile;
    List<String> matchedKeywords = [];
    
    for (final entry in ambianceProfiles.entries) {
      final profile = entry.key;
      final keywords = entry.value;
      
      for (final keyword in keywords) {
        if (lowercasePhrase.contains(keyword)) {
          hasProfileKeyword = true;
          matchedProfile = profile;
          matchedKeywords.add(keyword);
          break;
        }
      }
      
      if (hasProfileKeyword) break;
    }
    
    // Also check for direct profile mentions
    if (!hasAmbianceKeyword && !hasProfileKeyword) {
      for (final profile in ambianceProfiles.keys) {
        if (lowercasePhrase.contains(profile)) {
          hasAmbianceKeyword = true;
          matchedProfile = profile;
          break;
        }
      }
    }
    
    if (hasAmbianceKeyword || hasProfileKeyword) {
      print('✅ "$phrase"');
      if (matchedProfile != null) {
        print('   → Profile: $matchedProfile');
        if (matchedKeywords.isNotEmpty) {
          print('   → Keywords: ${matchedKeywords.join(", ")}');
        }
      } else {
        print('   → Has ambiance keyword but no specific profile');
      }
      print('');
    } else {
      print('❌ "$phrase" → No ambiance detected');
      print('');
    }
  }
  
  print('🎭 Expected Behavior:');
  print('   - "Kai, play some relaxing music" should NOT match (no ambiance keywords)');
  print('   - "I want forest ambiance" should match → forest profile');
  print('   - "give me ocean vibes" should match → ocean profile');
  print('   - The issue might be that simple music requests don\'t have ambiance keywords!');
}