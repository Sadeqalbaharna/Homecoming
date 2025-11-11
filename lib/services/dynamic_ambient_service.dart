/// Dynamic Ambient AI System
/// Intelligently analyzes prompts and creates immersive lighting + video experiences

/// Dynamic Ambient AI System
/// Intelligently analyzes prompts and creates immersive lighting + video experiences
class DynamicAmbientService {
  
  /// Analyze prompt and generate dynamic ambient experience
  static Future<AmbientExperience?> generateDynamicAmbience(String prompt) async {
    try {
      print('🎭 [DYNAMIC_AMBIENT] Analyzing prompt for intelligent ambience...');
      
      // Step 1: AI Analysis of the prompt
      final analysis = await _analyzePromptIntelligently(prompt);
      if (analysis == null) return null;
      
      // Step 2: Generate dynamic lighting based on analysis
      final lighting = _generateDynamicLighting(analysis);
      
      // Step 3: Find matching YouTube content
      final videoContent = await _findMatchingVideoContent(analysis);
      
      // Step 4: Create immersive experience
      final experience = AmbientExperience(
        name: analysis.sceneName,
        description: analysis.description,
        lighting: lighting,
        videoContent: videoContent,
        confidence: analysis.confidence,
        tags: analysis.tags,
      );
      
      print('✨ [DYNAMIC_AMBIENT] Generated experience: ${experience.name}');
      return experience;
      
    } catch (e) {
      print('❌ [DYNAMIC_AMBIENT] Error generating experience: $e');
      return null;
    }
  }
  
  /// Intelligent prompt analysis using AI
  static Future<PromptAnalysis?> _analyzePromptIntelligently(String prompt) async {
    try {
      // Use ChatGPT to analyze the prompt intelligently
      // Intelligent keyword-based analysis with enhanced logic
      final analysisData = _intelligentKeywordAnalysis(prompt);
      
      return PromptAnalysis(
        sceneName: analysisData['scene_name'] ?? 'Dynamic Scene',
        description: analysisData['description'] ?? '',
        mood: analysisData['mood'] ?? 'neutral',
        setting: analysisData['setting'] ?? 'abstract',
        timeOfDay: analysisData['time_of_day'],
        weather: analysisData['weather'],
        intensity: (analysisData['intensity'] ?? 5).toDouble(),
        colors: List<String>.from(analysisData['colors'] ?? ['blue', 'purple']),
        movement: analysisData['movement'] ?? 'gentle',
        youtubeKeywords: analysisData['youtube_keywords'] ?? '',
        confidence: (analysisData['confidence'] ?? 0.7).toDouble(),
        tags: List<String>.from(analysisData['tags'] ?? []),
      );
      
    } catch (e) {
      print('❌ [DYNAMIC_AMBIENT] Error in AI analysis: $e');
      return null;
    }
  }
  
  /// Generate dynamic lighting configuration
  static DynamicLighting _generateDynamicLighting(PromptAnalysis analysis) {
    // Convert mood and setting to lighting parameters
    final baseColors = _moodToColors(analysis.mood, analysis.colors);
    final pattern = _movementToPattern(analysis.movement);
    final brightness = _intensityToBrightness(analysis.intensity);
    
    // Apply time of day and weather modifiers
    final modifiedColors = _applyEnvironmentalModifiers(
      baseColors, 
      analysis.timeOfDay, 
      analysis.weather
    );
    
    return DynamicLighting(
      primaryColor: modifiedColors[0],
      secondaryColor: modifiedColors.length > 1 ? modifiedColors[1] : modifiedColors[0],
      accentColor: modifiedColors.length > 2 ? modifiedColors[2] : modifiedColors[0],
      brightness: brightness,
      pattern: pattern,
      speed: _intensityToSpeed(analysis.intensity),
      zones: _generateZoneMapping(analysis.setting),
    );
  }
  
  /// Find matching YouTube content
  static Future<VideoContent?> _findMatchingVideoContent(PromptAnalysis analysis) async {
    try {
      // Enhanced search terms combining multiple aspects
      final searchTerms = [
        '${analysis.youtubeKeywords} ambient',
        '${analysis.setting} ${analysis.mood} ambient video',
        '${analysis.setting} soundscape',
        '${analysis.mood} atmosphere ${analysis.timeOfDay ?? ""}',
        'cinematic ${analysis.setting} background',
      ];
      
      // Try each search term until we find good content
      for (final searchTerm in searchTerms) {
        final video = await _searchYouTubeAmbient(searchTerm.trim());
        if (video != null && video.duration > 600) { // At least 10 minutes
          return video;
        }
      }
      
      return null;
    } catch (e) {
      print('❌ [DYNAMIC_AMBIENT] Error finding video content: $e');
      return null;
    }
  }
  
  /// Search YouTube for ambient content
  static Future<VideoContent?> _searchYouTubeAmbient(String query) async {
    // This would integrate with YouTube API or use existing search
    // For now, return a structured result
    return VideoContent(
      title: 'Dynamic Ambient: $query',
      videoId: 'placeholder',
      duration: 3600, // 1 hour
      searchQuery: query,
    );
  }
  
  /// Intelligent keyword analysis (enhanced pattern matching)
  static Map<String, dynamic> _intelligentKeywordAnalysis(String prompt) {
    final lowerPrompt = prompt.toLowerCase();
    
    // Enhanced pattern matching for different aspects
    final moodKeywords = {
      'mysterious': ['mystery', 'mysterious', 'dark', 'shadow', 'secret', 'hidden', 'unknown'],
      'energetic': ['energy', 'energetic', 'vibrant', 'active', 'dynamic', 'power', 'intense'],
      'calm': ['calm', 'peaceful', 'serene', 'quiet', 'tranquil', 'relaxed', 'gentle'],
      'dramatic': ['dramatic', 'epic', 'grand', 'powerful', 'intense', 'climax', 'tension'],
      'magical': ['magic', 'magical', 'mystical', 'enchanted', 'fantasy', 'spell', 'wizard'],
      'cyberpunk': ['cyber', 'neon', 'digital', 'tech', 'futuristic', 'matrix', 'virtual'],
      'medieval': ['medieval', 'castle', 'knight', 'dragon', 'kingdom', 'sword', 'armor'],
      'space': ['space', 'galaxy', 'star', 'cosmic', 'universe', 'planet', 'nebula'],
    };
    
    final settingKeywords = {
      'forest': ['forest', 'trees', 'woods', 'jungle', 'nature', 'leaves', 'wilderness'],
      'underwater': ['underwater', 'ocean', 'sea', 'deep', 'aquatic', 'marine', 'coral'],
      'cave': ['cave', 'cavern', 'underground', 'stone', 'crystal', 'mineral'],
      'city': ['city', 'urban', 'street', 'building', 'metropolis', 'downtown'],
      'desert': ['desert', 'sand', 'dune', 'arid', 'oasis', 'mirage'],
      'mountain': ['mountain', 'peak', 'summit', 'cliff', 'valley', 'alpine'],
    };
    
    final timeKeywords = {
      'dawn': ['dawn', 'sunrise', 'morning light', 'first light'],
      'dusk': ['dusk', 'sunset', 'twilight', 'golden hour'],
      'night': ['night', 'midnight', 'darkness', 'nocturnal'],
    };
    
    final weatherKeywords = {
      'stormy': ['storm', 'thunder', 'lightning', 'tempest', 'turbulent'],
      'rainy': ['rain', 'drizzle', 'shower', 'wet', 'precipitation'],
      'foggy': ['fog', 'mist', 'haze', 'cloudy', 'murky'],
    };
    
    // Analyze and score matches
    String detectedMood = 'neutral';
    String detectedSetting = 'abstract';
    String? detectedTime;
    String? detectedWeather;
    double maxMoodScore = 0.0;
    double maxSettingScore = 0.0;
    
    // Find best mood match
    for (final mood in moodKeywords.keys) {
      final keywords = moodKeywords[mood]!;
      final score = keywords.where((k) => lowerPrompt.contains(k)).length / keywords.length;
      if (score > maxMoodScore) {
        maxMoodScore = score;
        detectedMood = mood;
      }
    }
    
    // Find best setting match
    for (final setting in settingKeywords.keys) {
      final keywords = settingKeywords[setting]!;
      final score = keywords.where((k) => lowerPrompt.contains(k)).length / keywords.length;
      if (score > maxSettingScore) {
        maxSettingScore = score;
        detectedSetting = setting;
      }
    }
    
    // Detect time and weather
    for (final time in timeKeywords.keys) {
      if (timeKeywords[time]!.any((k) => lowerPrompt.contains(k))) {
        detectedTime = time;
        break;
      }
    }
    
    for (final weather in weatherKeywords.keys) {
      if (weatherKeywords[weather]!.any((k) => lowerPrompt.contains(k))) {
        detectedWeather = weather;
        break;
      }
    }
    
    // Calculate intensity based on keywords
    final intensityKeywords = ['intense', 'dramatic', 'powerful', 'strong', 'vibrant'];
    final subtleKeywords = ['subtle', 'gentle', 'soft', 'quiet', 'calm'];
    double intensity = 5.0; // Default
    
    if (intensityKeywords.any((k) => lowerPrompt.contains(k))) {
      intensity = 8.0;
    } else if (subtleKeywords.any((k) => lowerPrompt.contains(k))) {
      intensity = 3.0;
    }
    
    // Generate YouTube search terms
    final youtubeKeywords = '$detectedSetting $detectedMood ambient soundscape ${detectedTime ?? ""} ${detectedWeather ?? ""}';
    
    // Calculate confidence based on matches
    final confidence = ((maxMoodScore + maxSettingScore) / 2.0).clamp(0.3, 0.9);
    
    return {
      'scene_name': '${detectedSetting.replaceFirst(detectedSetting[0], detectedSetting[0].toUpperCase())} ${detectedMood.replaceFirst(detectedMood[0], detectedMood[0].toUpperCase())}',
      'description': 'Dynamic ambient experience: $detectedMood mood in a $detectedSetting setting',
      'mood': detectedMood,
      'setting': detectedSetting,
      'time_of_day': detectedTime,
      'weather': detectedWeather,
      'intensity': intensity,
      'colors': ['blue', 'purple'], // Will be enhanced by _moodToColors
      'movement': intensity > 6 ? 'dramatic' : 'gentle',
      'youtube_keywords': youtubeKeywords,
      'confidence': confidence,
      'tags': [
        detectedMood, 
        detectedSetting, 
        if (detectedTime != null) detectedTime, 
        if (detectedWeather != null) detectedWeather
      ],
    };
  }

  // Helper methods for color/lighting generation
  static List<String> _moodToColors(String mood, List<String> suggestedColors) {
    final moodColorMap = {
      'mysterious': ['#4A148C', '#7B1FA2', '#1A237E'],
      'energetic': ['#FF5722', '#FF9800', '#FFC107'],
      'calm': ['#2196F3', '#00BCD4', '#009688'],
      'dramatic': ['#D32F2F', '#7B1FA2', '#FF5722'],
      'peaceful': ['#4CAF50', '#8BC34A', '#CDDC39'],
      'dark': ['#000000', '#424242', '#616161'],
      'magical': ['#9C27B0', '#673AB7', '#3F51B5'],
      'cyberpunk': ['#E91E63', '#00BCD4', '#8BC34A'],
      'medieval': ['#8D6E63', '#FF5722', '#FFC107'],
      'space': ['#3F51B5', '#9C27B0', '#000000'],
    };
    
    return moodColorMap[mood.toLowerCase()] ?? suggestedColors;
  }
  
  static String _movementToPattern(String movement) {
    final patternMap = {
      'static': 'solid',
      'gentle': 'breathe',
      'pulsing': 'pulse',
      'dramatic': 'strobe',
      'chaotic': 'random',
    };
    
    return patternMap[movement.toLowerCase()] ?? 'breathe';
  }
  
  static double _intensityToBrightness(double intensity) {
    return (intensity / 10.0).clamp(0.1, 1.0);
  }
  
  static double _intensityToSpeed(double intensity) {
    return (intensity / 5.0).clamp(0.5, 2.0);
  }
  
  static List<String> _applyEnvironmentalModifiers(
    List<String> colors, String? timeOfDay, String? weather) {
    // Apply time of day modifiers
    if (timeOfDay != null) {
      switch (timeOfDay.toLowerCase()) {
        case 'dawn':
          return ['#FF7043', '#FFC107', '#FFEB3B']; // Orange/yellow
        case 'dusk':
          return ['#FF5722', '#9C27B0', '#673AB7']; // Red/purple
        case 'night':
          return colors.map((c) => _darkenColor(c)).toList();
      }
    }
    
    // Apply weather modifiers  
    if (weather != null) {
      switch (weather.toLowerCase()) {
        case 'stormy':
          return ['#424242', '#9E9E9E', '#607D8B']; // Dark grays
        case 'rainy':
          return ['#2196F3', '#607D8B', '#90A4AE']; // Blues/grays
        case 'foggy':
          return colors.map((c) => _softenColor(c)).toList();
      }
    }
    
    return colors;
  }
  
  static String _darkenColor(String color) {
    // Simple darkening logic (would use proper color manipulation)
    return color; // Placeholder
  }
  
  static String _softenColor(String color) {
    // Simple softening logic
    return color; // Placeholder
  }
  
  static Map<String, String> _generateZoneMapping(String setting) {
    // Map different zones based on setting
    final zoneMap = {
      'forest': {
        'main': 'green_canopy',
        'accent': 'filtered_sunlight',
        'background': 'deep_shadows'
      },
      'space': {
        'main': 'star_field',
        'accent': 'nebula_colors', 
        'background': 'void_black'
      },
      'underwater': {
        'main': 'ocean_blue',
        'accent': 'bioluminescent',
        'background': 'deep_current'
      },
    };
    
    return zoneMap[setting.toLowerCase()] ?? {'main': 'dynamic', 'accent': 'dynamic'};
  }
}

/// Data classes for the dynamic ambient system
class PromptAnalysis {
  final String sceneName;
  final String description;
  final String mood;
  final String setting;
  final String? timeOfDay;
  final String? weather;
  final double intensity;
  final List<String> colors;
  final String movement;
  final String youtubeKeywords;
  final double confidence;
  final List<String> tags;
  
  PromptAnalysis({
    required this.sceneName,
    required this.description,
    required this.mood,
    required this.setting,
    this.timeOfDay,
    this.weather,
    required this.intensity,
    required this.colors,
    required this.movement,
    required this.youtubeKeywords,
    required this.confidence,
    required this.tags,
  });
}

class DynamicLighting {
  final String primaryColor;
  final String secondaryColor;
  final String accentColor;
  final double brightness;
  final String pattern;
  final double speed;
  final Map<String, String> zones;
  
  DynamicLighting({
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.brightness,
    required this.pattern,
    required this.speed,
    required this.zones,
  });
}

class VideoContent {
  final String title;
  final String videoId;
  final int duration;
  final String searchQuery;
  
  VideoContent({
    required this.title,
    required this.videoId,
    required this.duration,
    required this.searchQuery,
  });
}

class AmbientExperience {
  final String name;
  final String description;
  final DynamicLighting lighting;
  final VideoContent? videoContent;
  final double confidence;
  final List<String> tags;
  
  AmbientExperience({
    required this.name,
    required this.description,
    required this.lighting,
    this.videoContent,
    required this.confidence,
    required this.tags,
  });
}