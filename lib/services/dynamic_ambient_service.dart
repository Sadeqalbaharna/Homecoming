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
    final zones = _generateAdvancedZoneMapping(analysis.environment, analysis.atmosphere, analysis.action);
    
    return DynamicLighting(
      primaryColor: modifiedColors[0],
      secondaryColor: modifiedColors.length > 1 ? modifiedColors[1] : modifiedColors[0],
      accentColor: modifiedColors.length > 2 ? modifiedColors[2] : modifiedColors[0],
      brightness: brightness,
      pattern: pattern,
      speed: _intensityToSpeed(analysis.intensity),
      zones: zones,
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
    
    // 🎭 ENHANCED D&D/NARRATIVE SCENE ANALYSIS
    // Comprehensive scene detection for immersive roleplay
    
    // D&D Environments & Locations
    final environmentKeywords = {
      'dungeon': ['dungeon', 'dungeon room', 'chamber', 'underground', 'stone walls', 'crypt', 'tomb', 'labyrinth', 'maze'],
      'forest': ['forest', 'woods', 'trees', 'jungle', 'grove', 'woodland', 'canopy', 'leaves', 'branches', 'wilderness'],
      'tavern': ['tavern', 'inn', 'bar', 'pub', 'alehouse', 'common room', 'hearth', 'fireplace'],
      'ship': ['ship', 'vessel', 'boat', 'deck', 'cabin', 'sailing', 'ocean voyage', 'nautical'],
      'cave': ['cave', 'cavern', 'grotto', 'underground', 'stalactite', 'crystal cave', 'mineral'],
      'castle': ['castle', 'fortress', 'keep', 'tower', 'throne room', 'great hall', 'courtyard'],
      'battlefield': ['battlefield', 'war zone', 'combat', 'fighting', 'battle', 'skirmish'],
      'magical_realm': ['magical realm', 'enchanted', 'fey realm', 'otherworld', 'mystical plane'],
      'swamp': ['swamp', 'marsh', 'bog', 'wetland', 'murky water', 'mist'],
      'mountain': ['mountain', 'peak', 'summit', 'cliff', 'alpine', 'rocky'],
      'desert': ['desert', 'sand dunes', 'oasis', 'arid', 'wasteland'],
      'city': ['city', 'town', 'village', 'streets', 'marketplace', 'urban'],
    };
    
    // Atmospheric Conditions & Weather
    final atmosphereKeywords = {
      'thunderstorm': ['thunderstorm', 'storm', 'thunder', 'lightning', 'heavy rain', 'tempest', 'electrical storm'],
      'foggy': ['fog', 'mist', 'haze', 'cloudy', 'murky', 'shrouded', 'veiled'],
      'fire': ['fire', 'flames', 'burning', 'inferno', 'blaze', 'conflagration', 'ember', 'smoke'],
      'magical_energy': ['magical energy', 'arcane', 'spell', 'enchantment', 'mystical aura', 'otherworldly'],
      'eerie': ['eerie', 'haunting', 'ghostly', 'spectral', 'supernatural', 'chilling'],
      'peaceful': ['peaceful', 'serene', 'calm', 'tranquil', 'gentle', 'soothing'],
      'tense': ['tense', 'suspenseful', 'ominous', 'foreboding', 'threatening'],
      'chaotic': ['chaotic', 'frenzied', 'wild', 'turbulent', 'explosive'],
    };
    
    // D&D Actions & Spells
    final actionKeywords = {
      'fireball': ['fireball', 'fire spell', 'flame burst', 'fire magic'],
      'lightning': ['lightning bolt', 'shock', 'electrical', 'thunder spell'],
      'healing': ['healing', 'restore', 'cure', 'mend', 'recovery'],
      'stealth': ['stealth', 'sneak', 'hide', 'invisible', 'shadow'],
      'combat': ['attack', 'fight', 'battle', 'strike', 'combat', 'weapon'],
      'exploration': ['enter', 'approach', 'discover', 'find', 'explore'],
      'magic_casting': ['cast', 'spell', 'incantation', 'summon', 'conjure'],
    };
    
    // Mood & Emotional Atmosphere
    final moodKeywords = {
      'spooky': ['spooky', 'scary', 'frightening', 'creepy', 'horror', 'terrifying', 'sinister'],
      'mysterious': ['mysterious', 'enigmatic', 'cryptic', 'puzzling', 'secretive'],
      'epic': ['epic', 'heroic', 'legendary', 'grand', 'majestic', 'triumphant'],
      'dramatic': ['dramatic', 'intense', 'climactic', 'powerful', 'overwhelming'],
      'magical': ['magical', 'mystical', 'enchanted', 'otherworldly', 'supernatural'],
      'dark': ['dark', 'grim', 'shadow', 'noir', 'brooding', 'somber'],
      'bright': ['bright', 'radiant', 'luminous', 'gleaming', 'brilliant'],
      'cozy': ['cozy', 'warm', 'comfortable', 'intimate', 'welcoming'],
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
    
    // Check for direct lighting/color commands first
    final directColorKeywords = ['blue', 'red', 'green', 'purple', 'yellow', 'orange', 'pink', 'white'];
    final lightingKeywords = ['light', 'lights', 'lighting', 'illumination', 'glow', 'brightness'];
    
    bool isDirectColorCommand = directColorKeywords.any((color) => lowerPrompt.contains(color)) &&
                               (lightingKeywords.any((light) => lowerPrompt.contains(light)) ||
                                lowerPrompt.contains('switch') || 
                                lowerPrompt.contains('change') ||
                                lowerPrompt.contains('set'));
    
    // Analyze and score matches
    String detectedMood = 'neutral';
    String detectedSetting = 'abstract';
    String? detectedTime;
    String? detectedWeather;
    double maxMoodScore = 0.0;
    double maxSettingScore = 0.0;
    
    // 🎯 ENHANCED ANALYSIS: Multi-layered scene detection
    
    // Analyze Environment/Location
    String detectedEnvironment = 'abstract';
    double maxEnvironmentScore = 0.0;
    for (final env in environmentKeywords.keys) {
      final keywords = environmentKeywords[env]!;
      final score = keywords.where((k) => lowerPrompt.contains(k)).length / keywords.length;
      if (score > maxEnvironmentScore) {
        maxEnvironmentScore = score;
        detectedEnvironment = env;
      }
    }
    
    // Analyze Atmosphere/Weather
    String detectedAtmosphere = 'neutral';
    double maxAtmosphereScore = 0.0;
    for (final atm in atmosphereKeywords.keys) {
      final keywords = atmosphereKeywords[atm]!;
      final score = keywords.where((k) => lowerPrompt.contains(k)).length / keywords.length;
      if (score > maxAtmosphereScore) {
        maxAtmosphereScore = score;
        detectedAtmosphere = atm;
      }
    }
    
    // Analyze Actions/Spells
    String detectedAction = 'none';
    double maxActionScore = 0.0;
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
    
    // 🎨 ADVANCED SCENE ANALYSIS
    String ledEffect = _determineLedEffect(detectedEnvironment, detectedAtmosphere, detectedAction, detectedMood);
    List<String> primaryColors = _determineSceneColors(detectedEnvironment, detectedAtmosphere, detectedAction, detectedMood);
    double intensity = _calculateSceneIntensity(detectedAtmosphere, detectedAction, lowerPrompt);
    
    // Generate enhanced YouTube search terms
    String youtubeKeywords = _generateYoutubeKeywords(detectedEnvironment, detectedAtmosphere, detectedAction, detectedMood, detectedTime, detectedWeather);
    
    // 🎯 ENHANCED CONFIDENCE CALCULATION
    // Multi-factor confidence based on scene complexity
    double baseConfidence = (maxMoodScore + maxSettingScore + maxEnvironmentScore + maxAtmosphereScore + maxActionScore) / 5.0;
    
    // Boost for specific scenarios
    if (isDirectColorCommand) {
      baseConfidence = (baseConfidence + 0.6).clamp(0.6, 0.9); // Direct color commands
    } else if (detectedAction != 'none' && maxActionScore > 0.3) {
      baseConfidence = (baseConfidence + 0.4).clamp(0.5, 0.9); // D&D action scenarios
    } else if (detectedAtmosphere != 'neutral' && maxAtmosphereScore > 0.3) {
      baseConfidence = (baseConfidence + 0.3).clamp(0.4, 0.9); // Strong atmospheric scenarios
    } else if (detectedEnvironment != 'abstract' && maxEnvironmentScore > 0.3) {
      baseConfidence = (baseConfidence + 0.2).clamp(0.4, 0.9); // Clear environment detection
    }
    
    final confidence = baseConfidence.clamp(0.3, 0.9);
    
    // Generate scene name (enhanced for D&D scenarios)
    String sceneName;
    String description;
    if (isDirectColorCommand) {
      final detectedColor = directColorKeywords.firstWhere((color) => lowerPrompt.contains(color), orElse: () => 'colorful');
      sceneName = '${detectedColor.replaceFirst(detectedColor[0], detectedColor[0].toUpperCase())} Lighting';
      description = 'Direct lighting control: $detectedColor illumination';
    } else if (detectedAction != 'none' && detectedAtmosphere != 'neutral') {
      // D&D/Narrative scenarios
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

  /// 🎨 ADVANCED LED EFFECT DETERMINATION  
  /// Maps narrative scenarios to specific LED patterns
  static String _determineLedEffect(String environment, String atmosphere, String action, String mood) {
    // Fire/Flame Effects
    if (action == 'fireball' || atmosphere == 'fire' || action.contains('fire')) {
      return 'flickering'; // Realistic fire flickering
    }
    
    // Lightning/Thunder Effects  
    if (atmosphere == 'thunderstorm' || action == 'lightning' || action.contains('lightning')) {
      return 'strobe'; // Lightning flash pattern
    }
    
    // Magic/Spell Effects
    if (action == 'magic_casting' || atmosphere == 'magical_energy' || mood == 'magical') {
      return 'pulsing'; // Rhythmic magical pulsing
    }
    
    // Dungeon/Spooky Effects
    if (environment == 'dungeon' && mood == 'spooky') {
      return 'breathing'; // Slow ominous breathing pattern
    }
    
    // Ocean/Water Effects
    if (environment == 'ship' && atmosphere == 'thunderstorm') {
      return 'wave'; // Rolling wave pattern with storm intensity
    }
    
    // Forest/Nature Effects
    if (environment == 'forest' && mood == 'peaceful') {
      return 'shimmer'; // Gentle light filtering through leaves
    }
    
    // Combat/Action Effects
    if (action == 'combat' || environment == 'battlefield') {
      return 'pulse'; // Intense battle rhythm
    }
    
    // Healing/Recovery Effects
    if (action == 'healing') {
      return 'glow'; // Gentle healing glow
    }
    
    // Default based on mood
    switch (mood) {
      case 'dramatic': return 'pulse';
      case 'mysterious': return 'fade';
      case 'epic': return 'wave';
      case 'spooky': return 'flicker';
      default: return 'static'; // Steady light
    }
  }
  
  /// 🌈 ADVANCED COLOR DETERMINATION  
  /// Maps scenarios to immersive color palettes
  static List<String> _determineSceneColors(String environment, String atmosphere, String action, String mood) {
    // Fire/Flame Scenarios
    if (action == 'fireball' || atmosphere == 'fire') {
      return ['#FF4500', '#FF6347', '#FFD700']; // Orange, red, yellow flames
    }
    
    // Lightning/Storm Scenarios
    if (atmosphere == 'thunderstorm' || action == 'lightning') {
      return ['#4B0082', '#FFFFFF', '#1E90FF']; // Deep purple, white flash, electric blue
    }
    
    // Dungeon/Spooky Scenarios
    if (environment == 'dungeon' && mood == 'spooky') {
      return ['#800080', '#2F4F4F', '#000000']; // Dark purple, dark gray, black
    }
    
    // Forest/Nature Scenarios
    if (environment == 'forest') {
      if (mood == 'peaceful') {
        return ['#228B22', '#32CD32', '#FFFF00']; // Forest green, lime, sunlight yellow
      } else {
        return ['#006400', '#2E8B57', '#8FBC8F']; // Dark green variations
      }
    }
    
    // Ocean/Ship Scenarios
    if (environment == 'ship' || environment.contains('ocean')) {
      if (atmosphere == 'thunderstorm') {
        return ['#191970', '#000080', '#708090']; // Midnight blue, navy, slate gray
      } else {
        return ['#0000FF', '#00CED1', '#87CEEB']; // Blue, turquoise, sky blue
      }
    }
    
    // Magic/Mystical Scenarios
    if (action == 'magic_casting' || atmosphere == 'magical_energy') {
      return ['#9400D3', '#8A2BE2', '#DA70D6']; // Violet, blue violet, orchid
    }
    
    // Healing Scenarios
    if (action == 'healing') {
      return ['#FFFFFF', '#F0F8FF', '#E0FFFF']; // Pure white, alice blue, light cyan
    }
    
    // Tavern/Cozy Scenarios  
    if (environment == 'tavern' || mood == 'cozy') {
      return ['#FF8C00', '#DAA520', '#B8860B']; // Dark orange, goldenrod, dark goldenrod
    }
    
    // Default mood-based colors
    switch (mood) {
      case 'spooky': return ['#800080', '#4B0082', '#2F4F4F'];
      case 'epic': return ['#FFD700', '#FFA500', '#FF4500'];
      case 'mysterious': return ['#483D8B', '#2F4F4F', '#696969'];
      case 'magical': return ['#9400D3', '#8A2BE2', '#DA70D6'];
      case 'dark': return ['#000000', '#2F4F4F', '#696969'];
      case 'bright': return ['#FFFFFF', '#FFFF00', '#FFD700'];
      default: return ['#4169E1', '#6495ED', '#87CEEB']; // Default blue palette
    }
  }
  
  /// ⚡ ADVANCED INTENSITY CALCULATION
  /// Maps narrative intensity to LED brightness/speed
  static double _calculateSceneIntensity(String atmosphere, String action, String prompt) {
    double intensity = 5.0; // Base intensity
    
    // High intensity scenarios
    if (atmosphere == 'thunderstorm' || action == 'fireball' || action == 'combat') {
      intensity = 9.0;
    }
    // Medium-high intensity
    else if (atmosphere == 'fire' || action == 'magic_casting' || atmosphere == 'chaotic') {
      intensity = 7.5;
    }
    // Medium intensity  
    else if (atmosphere == 'tense' || action == 'exploration') {
      intensity = 6.0;
    }
    // Low intensity
    else if (atmosphere == 'peaceful' || action == 'healing') {
      intensity = 3.0;
    }
    
    // Boost based on intensity keywords
    if (prompt.contains('massive') || prompt.contains('overwhelming')) {
      intensity = (intensity * 1.2).clamp(1.0, 10.0);
    }
    if (prompt.contains('gentle') || prompt.contains('subtle')) {
      intensity = (intensity * 0.7).clamp(1.0, 10.0);
    }
    
    return intensity;
  }
  
  /// 🎵 ENHANCED YOUTUBE SEARCH GENERATION
  /// Creates targeted search terms for narrative scenarios
  static String _generateYoutubeKeywords(String environment, String atmosphere, String action, String mood, String? time, String? weather) {
    List<String> keywords = [];
    
    // Core environment
    keywords.add(environment);
    
    // Atmospheric conditions
    if (atmosphere != 'neutral') {
      keywords.add(atmosphere);
    }
    
    // Specific action-based sounds
    switch (action) {
      case 'fireball':
        keywords.addAll(['fire crackling', 'flame', 'burning']);
        break;
      case 'lightning':
        keywords.addAll(['thunder', 'storm', 'rain']);
        break;
      case 'combat':
        keywords.addAll(['battle', 'tension', 'epic']);
        break;
      case 'magic_casting':
        keywords.addAll(['mystical', 'ethereal', 'magical']);
        break;
      case 'healing':
        keywords.addAll(['peaceful', 'restoration', 'calm']);
        break;
    }
    
    // Mood enhancement
    keywords.add(mood);
    
    // Time and weather context
    if (time != null) keywords.add(time);
    if (weather != null) keywords.add(weather);
    
    // Add base terms
    keywords.addAll(['ambient', 'soundscape', 'atmosphere', 'background']);
    
    return keywords.join(' ');
  }

  /// 🎯 ADVANCED ZONE MAPPING FOR D&D SCENARIOS
  static Map<String, String> _generateAdvancedZoneMapping(String environment, String atmosphere, String action) {
    // Special mappings for D&D scenarios
    if (environment == 'dungeon' && atmosphere == 'spooky') {
      return {'main': 'dungeon_shadows', 'zone1': 'torch_flicker', 'zone2': 'eerie_glow'};
    }
    if (action == 'fireball') {
      return {'main': 'fire_explosion', 'zone1': 'flame_spread', 'zone2': 'ember_glow'};
    }
    if (environment == 'ship' && atmosphere == 'thunderstorm') {
      return {'main': 'storm_chaos', 'zone1': 'lightning_flash', 'zone2': 'wave_crash'};
    }
    if (environment == 'forest') {
      return {'main': 'canopy_filter', 'zone1': 'leaf_shimmer', 'zone2': 'forest_depth'};
    }
    
    // Default mapping
    return {'main': 'dynamic', 'zone1': 'dynamic', 'zone2': 'dynamic'};
  }
}

/// Data classes for the dynamic ambient system
class PromptAnalysis {
  final String sceneName;
  final String description;
  final String mood;
  final String setting;
  // 🎭 ENHANCED D&D FIELDS
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
    
    // Ocean/Water Effects
    if (environment == 'ship' && atmosphere == 'thunderstorm') {
      return 'wave'; // Rolling wave pattern with storm intensity
    }
    
    // Forest/Nature Effects
    if (environment == 'forest' && mood == 'peaceful') {
      return 'shimmer'; // Gentle light filtering through leaves
    }
    
    // Combat/Action Effects
    if (action == 'combat' || environment == 'battlefield') {
      return 'pulse'; // Intense battle rhythm
    }
    
    // Healing/Recovery Effects
    if (action == 'healing') {
      return 'glow'; // Gentle healing glow
    }
    
    // Default based on mood
    switch (mood) {
      case 'dramatic': return 'pulse';
      case 'mysterious': return 'fade';
      case 'epic': return 'wave';
      case 'spooky': return 'flicker';
      default: return 'static'; // Steady light
    }
  }
  
  /// 🌈 ADVANCED COLOR DETERMINATION  
  /// Maps scenarios to immersive color palettes
  static List<String> _determineSceneColors(String environment, String atmosphere, String action, String mood) {
    // Fire/Flame Scenarios
    if (action == 'fireball' || atmosphere == 'fire') {
      return ['#FF4500', '#FF6347', '#FFD700']; // Orange, red, yellow flames
    }
    
    // Lightning/Storm Scenarios
    if (atmosphere == 'thunderstorm' || action == 'lightning') {
      return ['#4B0082', '#FFFFFF', '#1E90FF']; // Deep purple, white flash, electric blue
    }
    
    // Dungeon/Spooky Scenarios
    if (environment == 'dungeon' && mood == 'spooky') {
      return ['#800080', '#2F4F4F', '#000000']; // Dark purple, dark gray, black
    }
    
    // Forest/Nature Scenarios
    if (environment == 'forest') {
      if (mood == 'peaceful') {
        return ['#228B22', '#32CD32', '#FFFF00']; // Forest green, lime, sunlight yellow
      } else {
        return ['#006400', '#2E8B57', '#8FBC8F']; // Dark green variations
      }
    }
    
    // Ocean/Ship Scenarios
    if (environment == 'ship' || environment.contains('ocean')) {
      if (atmosphere == 'thunderstorm') {
        return ['#191970', '#000080', '#708090']; // Midnight blue, navy, slate gray
      } else {
        return ['#0000FF', '#00CED1', '#87CEEB']; // Blue, turquoise, sky blue
      }
    }
    
    // Magic/Mystical Scenarios
    if (action == 'magic_casting' || atmosphere == 'magical_energy') {
      return ['#9400D3', '#8A2BE2', '#DA70D6']; // Violet, blue violet, orchid
    }
    
    // Healing Scenarios
    if (action == 'healing') {
      return ['#FFFFFF', '#F0F8FF', '#E0FFFF']; // Pure white, alice blue, light cyan
    }
    
    // Tavern/Cozy Scenarios  
    if (environment == 'tavern' || mood == 'cozy') {
      return ['#FF8C00', '#DAA520', '#B8860B']; // Dark orange, goldenrod, dark goldenrod
    }
    
    // Default mood-based colors
    switch (mood) {
      case 'spooky': return ['#800080', '#4B0082', '#2F4F4F'];
      case 'epic': return ['#FFD700', '#FFA500', '#FF4500'];
      case 'mysterious': return ['#483D8B', '#2F4F4F', '#696969'];
      case 'magical': return ['#9400D3', '#8A2BE2', '#DA70D6'];
      case 'dark': return ['#000000', '#2F4F4F', '#696969'];
      case 'bright': return ['#FFFFFF', '#FFFF00', '#FFD700'];
      default: return ['#4169E1', '#6495ED', '#87CEEB']; // Default blue palette
    }
  }
  
  /// ⚡ ADVANCED INTENSITY CALCULATION
  /// Maps narrative intensity to LED brightness/speed
  static double _calculateSceneIntensity(String atmosphere, String action, String prompt) {
    double intensity = 5.0; // Base intensity
    
    // High intensity scenarios
    if (atmosphere == 'thunderstorm' || action == 'fireball' || action == 'combat') {
      intensity = 9.0;
    }
    // Medium-high intensity
    else if (atmosphere == 'fire' || action == 'magic_casting' || atmosphere == 'chaotic') {
      intensity = 7.5;
    }
    // Medium intensity  
    else if (atmosphere == 'tense' || action == 'exploration') {
      intensity = 6.0;
    }
    // Low intensity
    else if (atmosphere == 'peaceful' || action == 'healing') {
      intensity = 3.0;
    }
    
    // Boost based on intensity keywords
    if (prompt.contains('massive') || prompt.contains('overwhelming')) {
      intensity = (intensity * 1.2).clamp(1.0, 10.0);
    }
    if (prompt.contains('gentle') || prompt.contains('subtle')) {
      intensity = (intensity * 0.7).clamp(1.0, 10.0);
    }
    
    return intensity;
  }
  
  /// 🎵 ENHANCED YOUTUBE SEARCH GENERATION
  /// Creates targeted search terms for narrative scenarios
  static String _generateYoutubeKeywords(String environment, String atmosphere, String action, String mood, String? time, String? weather) {
    List<String> keywords = [];
    
    // Core environment
    keywords.add(environment);
    
    // Atmospheric conditions
    if (atmosphere != 'neutral') {
      keywords.add(atmosphere);
    }
    
    // Specific action-based sounds
    switch (action) {
      case 'fireball':
        keywords.addAll(['fire crackling', 'flame', 'burning']);
        break;
      case 'lightning':
        keywords.addAll(['thunder', 'storm', 'rain']);
        break;
      case 'combat':
        keywords.addAll(['battle', 'tension', 'epic']);
        break;
      case 'magic_casting':
        keywords.addAll(['mystical', 'ethereal', 'magical']);
        break;
      case 'healing':
        keywords.addAll(['peaceful', 'restoration', 'calm']);
        break;
    }
    
    // Mood enhancement
    keywords.add(mood);
    
    // Time and weather context
    if (time != null) keywords.add(time);
    if (weather != null) keywords.add(weather);
    
    // Add base terms
    keywords.addAll(['ambient', 'soundscape', 'atmosphere', 'background']);
    
    return keywords.join(' ');
  }
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