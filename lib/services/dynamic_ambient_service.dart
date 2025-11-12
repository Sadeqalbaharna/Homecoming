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
        environment: analysisData['environment'] ?? 'abstract',
        atmosphere: analysisData['atmosphere'] ?? 'neutral',
        action: analysisData['action'] ?? 'none',
        ledEffect: analysisData['led_effect'] ?? 'static',
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
    // 🎨 ENHANCED LIGHTING GENERATION FOR D&D SCENARIOS
    // Use advanced scene analysis for immersive effects
    
    // Use enhanced colors from scene analysis
    final sceneColors = analysis.colors.isNotEmpty ? analysis.colors : _moodToColors(analysis.mood, []);
    
    // Use advanced LED effect patterns
    final pattern = analysis.ledEffect.isNotEmpty ? analysis.ledEffect : _movementToPattern(analysis.movement);
    
    // Enhanced brightness calculation
    final brightness = _intensityToBrightness(analysis.intensity);
    
    // Apply environmental modifiers for time/weather
    final modifiedColors = _applyEnvironmentalModifiers(
      sceneColors, 
      analysis.timeOfDay, 
      analysis.weather
    );
    
    // Generate zone mapping based on environment
    final zones = _generateZoneMapping(analysis.setting);
    
    return DynamicLighting(
      primaryColor: modifiedColors[0],
      secondaryColor: modifiedColors.length > 1 ? modifiedColors[1] : modifiedColors[0],
      accentColor: modifiedColors.length > 2 ? modifiedColors[2] : modifiedColors[0],
      brightness: brightness.round(),
      pattern: pattern,
      speed: _intensityToSpeed(analysis.intensity),
      zones: zones,
    );
  }

  /// Enhanced keyword analysis for D&D scenarios
  static Map<String, dynamic> _intelligentKeywordAnalysis(String prompt) {
    final lowerPrompt = prompt.toLowerCase();
    
    // Check for direct lighting/color commands first
    final directColorKeywords = ['blue', 'red', 'green', 'purple', 'yellow', 'orange', 'pink', 'white'];
    final lightingKeywords = ['light', 'lights', 'lighting', 'illumination', 'glow', 'brightness'];
    
    bool isDirectColorCommand = directColorKeywords.any((color) => lowerPrompt.contains(color)) &&
                               (lightingKeywords.any((light) => lowerPrompt.contains(light)) ||
                                lowerPrompt.contains('switch') || 
                                lowerPrompt.contains('change') ||
                                lowerPrompt.contains('set'));

    // D&D Environments & Locations
    final environmentKeywords = {
      'dungeon': ['dungeon', 'chamber', 'underground', 'stone walls', 'crypt', 'tomb'],
      'forest': ['forest', 'woods', 'trees', 'jungle', 'grove', 'woodland', 'canopy', 'leaves'],
      'tavern': ['tavern', 'inn', 'bar', 'pub', 'alehouse', 'common room'],
      'ship': ['ship', 'vessel', 'boat', 'deck', 'cabin', 'sailing'],
      'cave': ['cave', 'cavern', 'grotto', 'underground', 'stalactite'],
      'castle': ['castle', 'fortress', 'keep', 'tower', 'throne room'],
      'battlefield': ['battlefield', 'war zone', 'combat', 'fighting', 'battle'],
    };
    
    // Atmospheric Conditions
    final atmosphereKeywords = {
      'thunderstorm': ['thunderstorm', 'storm', 'thunder', 'lightning', 'heavy rain'],
      'fire': ['fire', 'flames', 'burning', 'inferno', 'blaze'],
      'magical_energy': ['magical energy', 'arcane', 'spell', 'enchantment'],
      'eerie': ['eerie', 'haunting', 'ghostly', 'supernatural'],
      'peaceful': ['peaceful', 'serene', 'calm', 'tranquil'],
    };
    
    // D&D Actions & Spells
    final actionKeywords = {
      'fireball': ['fireball', 'fire spell', 'flame burst'],
      'lightning': ['lightning bolt', 'shock', 'electrical'],
      'healing': ['healing', 'restore', 'cure', 'mend'],
      'combat': ['attack', 'fight', 'battle', 'strike'],
      'magic_casting': ['cast', 'spell', 'incantation', 'summon'],
    };
    
    // Mood Keywords
    final moodKeywords = {
      'spooky': ['spooky', 'scary', 'frightening', 'creepy', 'horror'],
      'epic': ['epic', 'heroic', 'legendary', 'grand', 'majestic'],
      'dramatic': ['dramatic', 'intense', 'climactic', 'powerful'],
      'magical': ['magical', 'mystical', 'enchanted', 'otherworldly'],
      'peaceful': ['peaceful', 'calm', 'serene', 'tranquil'],
    };

    // Analyze and score matches
    String detectedMood = 'neutral';
    String detectedSetting = 'abstract';
    String detectedEnvironment = 'abstract';
    String detectedAtmosphere = 'neutral';
    String detectedAction = 'none';
    String? detectedTime;
    String? detectedWeather;
    double maxMoodScore = 0.0;
    double maxSettingScore = 0.0;
    double maxEnvironmentScore = 0.0;
    double maxAtmosphereScore = 0.0;
    double maxActionScore = 0.0;

    // Find best environment match
    for (final env in environmentKeywords.keys) {
      final keywords = environmentKeywords[env]!;
      final score = keywords.where((k) => lowerPrompt.contains(k)).length / keywords.length;
      if (score > maxEnvironmentScore) {
        maxEnvironmentScore = score;
        detectedEnvironment = env;
      }
    }
    
    // Find best atmosphere match
    for (final atm in atmosphereKeywords.keys) {
      final keywords = atmosphereKeywords[atm]!;
      final score = keywords.where((k) => lowerPrompt.contains(k)).length / keywords.length;
      if (score > maxAtmosphereScore) {
        maxAtmosphereScore = score;
        detectedAtmosphere = atm;
      }
    }
    
    // Find best action match
    for (final action in actionKeywords.keys) {
      final keywords = actionKeywords[action]!;
      final score = keywords.where((k) => lowerPrompt.contains(k)).length / keywords.length;
      if (score > maxActionScore) {
        maxActionScore = score;
        detectedAction = action;
      }
    }
    
    // Find best mood match
    for (final mood in moodKeywords.keys) {
      final keywords = moodKeywords[mood]!;
      final score = keywords.where((k) => lowerPrompt.contains(k)).length / keywords.length;
      if (score > maxMoodScore) {
        maxMoodScore = score;
        detectedMood = mood;
      }
    }
    
    // Override setting with environment if better match
    if (maxEnvironmentScore > maxSettingScore) {
      detectedSetting = detectedEnvironment;
      maxSettingScore = maxEnvironmentScore;
    }

    // Advanced scene analysis
    String ledEffect = _determineLedEffect(detectedEnvironment, detectedAtmosphere, detectedAction, detectedMood);
    List<String> primaryColors = _determineSceneColors(detectedEnvironment, detectedAtmosphere, detectedAction, detectedMood);
    double intensity = _calculateSceneIntensity(detectedAtmosphere, detectedAction, lowerPrompt);
    String youtubeKeywords = _generateYoutubeKeywords(detectedEnvironment, detectedAtmosphere, detectedAction, detectedMood, detectedTime, detectedWeather);

    // Enhanced confidence calculation
    double baseConfidence = (maxMoodScore + maxSettingScore + maxEnvironmentScore + maxAtmosphereScore + maxActionScore) / 5.0;
    
    if (isDirectColorCommand) {
      baseConfidence = (baseConfidence + 0.6).clamp(0.6, 0.9);
    } else if (detectedAction != 'none' && maxActionScore > 0.3) {
      baseConfidence = (baseConfidence + 0.4).clamp(0.5, 0.9);
    } else if (detectedAtmosphere != 'neutral' && maxAtmosphereScore > 0.3) {
      baseConfidence = (baseConfidence + 0.3).clamp(0.4, 0.9);
    } else if (detectedEnvironment != 'abstract' && maxEnvironmentScore > 0.3) {
      baseConfidence = (baseConfidence + 0.2).clamp(0.4, 0.9);
    }
    
    final confidence = baseConfidence.clamp(0.3, 0.9);

    // Generate scene name
    String sceneName;
    String description;
    if (isDirectColorCommand) {
      final detectedColor = directColorKeywords.firstWhere((color) => lowerPrompt.contains(color), orElse: () => 'colorful');
      sceneName = '${detectedColor.replaceFirst(detectedColor[0], detectedColor[0].toUpperCase())} Lighting';
      description = 'Direct lighting control: $detectedColor illumination';
    } else if (detectedAction != 'none' && detectedAtmosphere != 'neutral') {
      sceneName = '${detectedAction.replaceAll('_', ' ').split(' ').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ')}: ${detectedAtmosphere.replaceFirst(detectedAtmosphere[0], detectedAtmosphere[0].toUpperCase())} ${detectedSetting.replaceFirst(detectedSetting[0], detectedSetting[0].toUpperCase())}';
      description = 'Immersive scene: $detectedAction in $detectedAtmosphere $detectedSetting with $detectedMood atmosphere';
    } else {
      sceneName = '${detectedSetting.replaceFirst(detectedSetting[0], detectedSetting[0].toUpperCase())} ${detectedMood.replaceFirst(detectedMood[0], detectedMood[0].toUpperCase())}';
      description = 'Dynamic ambient experience: $detectedMood mood in a $detectedSetting setting';
    }

    return {
      'scene_name': sceneName,
      'description': description,
      'mood': detectedMood,
      'setting': detectedSetting,
      'environment': detectedEnvironment,
      'atmosphere': detectedAtmosphere, 
      'action': detectedAction,
      'time_of_day': detectedTime,
      'weather': detectedWeather,
      'intensity': intensity,
      'colors': primaryColors,
      'led_effect': ledEffect,
      'movement': intensity > 6 ? 'dramatic' : 'gentle',
      'youtube_keywords': youtubeKeywords,
      'confidence': confidence,
      'tags': [
        detectedMood, 
        detectedSetting,
      ],
    };
  }

  // Advanced LED effect determination
  static String _determineLedEffect(String environment, String atmosphere, String action, String mood) {
    if (action == 'fireball' || atmosphere == 'fire') return 'flickering';
    if (atmosphere == 'thunderstorm' || action == 'lightning') return 'strobe';
    if (action == 'magic_casting' || atmosphere == 'magical_energy') return 'pulsing';
    if (environment == 'dungeon' && mood == 'spooky') return 'breathing';
    if (environment == 'ship' && atmosphere == 'thunderstorm') return 'wave';
    if (environment == 'forest' && mood == 'peaceful') return 'shimmer';
    if (action == 'combat') return 'pulse';
    if (action == 'healing') return 'glow';
    
    switch (mood) {
      case 'dramatic': return 'pulse';
      case 'mysterious': return 'fade';
      case 'epic': return 'wave';
      case 'spooky': return 'flicker';
      default: return 'static';
    }
  }

  // Advanced color determination
  static List<String> _determineSceneColors(String environment, String atmosphere, String action, String mood) {
    if (action == 'fireball' || atmosphere == 'fire') return ['#FF4500', '#FF6347', '#FFD700'];
    if (atmosphere == 'thunderstorm' || action == 'lightning') return ['#4B0082', '#FFFFFF', '#1E90FF'];
    if (environment == 'dungeon' && mood == 'spooky') return ['#800080', '#2F4F4F', '#000000'];
    if (environment == 'forest') return ['#228B22', '#32CD32', '#FFFF00'];
    if (action == 'magic_casting') return ['#9400D3', '#8A2BE2', '#DA70D6'];
    if (action == 'healing') return ['#FFFFFF', '#F0F8FF', '#E0FFFF'];
    
    return ['#4169E1', '#6495ED', '#87CEEB']; // Default blue
  }

  // Advanced intensity calculation
  static double _calculateSceneIntensity(String atmosphere, String action, String prompt) {
    double intensity = 5.0;
    
    if (atmosphere == 'thunderstorm' || action == 'fireball' || action == 'combat') {
      intensity = 9.0;
    } else if (atmosphere == 'fire' || action == 'magic_casting') {
      intensity = 7.5;
    } else if (action == 'healing' || atmosphere == 'peaceful') {
      intensity = 3.0;
    }
    
    if (prompt.contains('massive') || prompt.contains('overwhelming')) {
      intensity = (intensity * 1.2).clamp(1.0, 10.0);
    }
    
    return intensity;
  }

  // Generate YouTube keywords
  static String _generateYoutubeKeywords(String environment, String atmosphere, String action, String mood, String? time, String? weather) {
    List<String> keywords = [environment];
    
    if (atmosphere != 'neutral') keywords.add(atmosphere);
    
    switch (action) {
      case 'fireball': keywords.addAll(['fire crackling', 'flame']); break;
      case 'lightning': keywords.addAll(['thunder', 'storm']); break;
      case 'combat': keywords.addAll(['battle', 'epic']); break;
      case 'magic_casting': keywords.addAll(['mystical', 'ethereal']); break;
      case 'healing': keywords.addAll(['peaceful', 'restoration']); break;
    }
    
    keywords.addAll([mood, 'ambient', 'soundscape']);
    if (time != null) keywords.add(time);
    if (weather != null) keywords.add(weather);
    
    return keywords.join(' ');
  }

  // Helper methods
  static List<String> _moodToColors(String mood, List<String> suggestedColors) {
    final moodColorMap = {
      'spooky': ['#800080', '#4B0082', '#2F4F4F'],
      'epic': ['#FFD700', '#FFA500', '#FF4500'],
      'peaceful': ['#4CAF50', '#8BC34A', '#CDDC39'],
      'dramatic': ['#D32F2F', '#7B1FA2', '#FF5722'],
    };
    return moodColorMap[mood] ?? ['#4169E1', '#6495ED', '#87CEEB'];
  }

  static String _movementToPattern(String movement) {
    return movement == 'dramatic' ? 'pulse' : 'fade';
  }

  static double _intensityToBrightness(double intensity) {
    return (intensity / 10.0 * 255.0).clamp(50.0, 255.0);
  }

  static double _intensityToSpeed(double intensity) {
    return intensity / 10.0;
  }

  static List<String> _applyEnvironmentalModifiers(List<String> colors, String? timeOfDay, String? weather) {
    return colors; // Simplified for now
  }

  static Map<String, String> _generateZoneMapping(String setting) {
    return {'main': 'dynamic', 'zone1': 'dynamic', 'zone2': 'dynamic'};
  }

  // Placeholder methods for video content
  static Future<VideoContent?> _findMatchingVideoContent(PromptAnalysis analysis) async {
    return VideoContent(
      title: 'Ambient ${analysis.sceneName}',
      videoId: 'placeholder',
      duration: 3600,
      searchQuery: analysis.youtubeKeywords,
    );
  }
}

class PromptAnalysis {
  final String sceneName;
  final String description;
  final String mood;
  final String setting;
  final String environment;
  final String atmosphere; 
  final String action;
  final String ledEffect;
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
    required this.environment,
    required this.atmosphere,
    required this.action,
    required this.ledEffect,
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
  final int brightness;
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