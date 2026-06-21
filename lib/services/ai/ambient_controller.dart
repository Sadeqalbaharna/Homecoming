// Ambient/lighting/YouTube/volume control
// Extracted from ai_service.dart — no circular imports.

import 'package:dio/dio.dart';
import '../media/ambiance_service.dart';
import '../automation/home_automation_service.dart';
import '../brain_debug_service.dart';
import '../automation/wake_on_lan_service.dart';
import '../media/dynamic_ambient_service.dart';

/// Handles all ambient environment control:
/// music (YouTube), volume, lighting, and dynamic ambient experiences.
class AmbientController {

  /// Inspect Kai's reply and trigger real-world ambiance control if relevant.
  Future<void> detectAndTriggerAmbianceFromReply(
    String reply,
    String originalInput,
    dynamic debugService,
  ) async {
    try {
      final lowerReply = reply.toLowerCase();

      final ambianceIndicators = [
        'setting up', 'creating', 'activating', 'i\'m setting', 'i\'m configuring',
        'perfect!', 'let me activate', 'let me set', 'i\'ll create',
        'ambiance', 'lighting', 'music', 'atmosphere', 'mode activated',
        'environment', 'mood', 'sounds', 'beats', 'configuring',
        'party mode', 'focus mode', 'romantic mode', 'ocean atmosphere',
        'forest ambiance', 'sunset mood', 'cozy lighting',
      ];

      final youtubeIndicators = [
        'youtube', 'from youtube', 'play song', 'play music', 'search for',
        'find and play', 'stream', 'look up', 'song called', 'track called',
        'by artist', 'music by', 'song by', 'album', 'band', 'artist',
      ];

      final volumeIndicators = [
        'volume up', 'turn up', 'louder', 'increase volume', 'raise volume',
        'volume down', 'turn down', 'quieter', 'decrease volume', 'lower volume',
        'set volume', 'volume to', 'volume at', 'make it louder', 'make it quieter',
      ];

      final lightingIndicators = [
        'red lights', 'blue lights', 'green lights', 'white lights', 'yellow lights',
        'purple lights', 'orange lights', 'amber lights', 'pink lights', 'cyan lights',
        'set lights to', 'change lights to', 'make lights', 'turn lights',
        'lighting to', 'light color', 'lights red', 'lights blue', 'lights green',
        'lights white', 'lights yellow', 'lights purple', 'lights orange',
      ];

      final bool mentionedLighting = lightingIndicators.any((i) =>
          originalInput.toLowerCase().contains(i) || lowerReply.contains(i));

      final bool mentionedAmbiance = !mentionedLighting &&
          ambianceIndicators.any((i) => lowerReply.contains(i));

      final bool mentionedYoutube = youtubeIndicators.any((i) =>
          lowerReply.contains(i) || originalInput.toLowerCase().contains(i));

      final bool mentionedVolume = volumeIndicators.any((i) =>
          originalInput.toLowerCase().contains(i) || lowerReply.contains(i));

      if (mentionedVolume) {
        print('🔊 [AMBIENT] Volume control request detected');
        await _handleVolumeControlRequest(originalInput, reply, debugService);
        return;
      }

      if (mentionedYoutube) {
        print('🎵 [AMBIENT] YouTube music request detected');
        await _handleYouTubeMusicRequest(originalInput, reply, debugService);
        return;
      }

      if (mentionedLighting) {
        print('💡 [AMBIENT] Direct lighting command detected');
        await _handleDirectLightingRequest(originalInput, reply, debugService);
        return;
      }

      if (!mentionedAmbiance) {
        print('🎭 [AMBIENT] No ambiance mention detected in reply');
        return;
      }

      debugService?.addStep(
        BrainPhase.processing,
        'Detected ambiance mention in reply - triggering actual control',
        data: {'reply_preview': reply.length > 100 ? '${reply.substring(0, 100)}...' : reply},
      );

      print('🎭 [AMBIENT] Analysing original request for ambiance trigger');

      // Try Dynamic Ambient AI System first
      print('🧠 [AMBIENT] Attempting Dynamic Ambient AI analysis...');
      final dynamicExperience = await DynamicAmbientService.generateDynamicAmbience(originalInput);

      if (dynamicExperience != null && dynamicExperience.confidence >= 0.3) {
        print('🎆 [AMBIENT] Generated dynamic experience: ${dynamicExperience.name} (confidence: ${dynamicExperience.confidence})');
        await _triggerDynamicAmbientExperience(dynamicExperience, debugService is BrainDebugService ? debugService : null);
        return;
      } else if (dynamicExperience != null) {
        print('⚠️ [AMBIENT] Dynamic experience confidence too low: ${dynamicExperience.confidence}');
      }

      // Fallback to traditional ambiance profiles
      print('🎭 [AMBIENT] Using traditional ambiance profiles...');
      final ambianceService = AmbianceService();
      final ambianceMatch = ambianceService.analyzeVoiceCommand(originalInput);

      if (ambianceMatch != null) {
        print('🎭 [AMBIENT] Triggering ${ambianceMatch.profile} ambiance (${(ambianceMatch.confidence * 100).toStringAsFixed(1)}% confidence)');

        final success = await ambianceService.setAmbiance(
          profile: ambianceMatch.profile,
          originalInput: originalInput,
          confidence: ambianceMatch.confidence,
        );

        if (success) {
          print('✅ [AMBIENT] Successfully triggered ${ambianceMatch.profile} ambiance');
          debugService?.addStep(
            BrainPhase.processing,
            'Ambiance control successful',
            data: {'profile': ambianceMatch.profile, 'confidence': ambianceMatch.confidence},
          );
        } else {
          print('❌ [AMBIENT] Failed to trigger ambiance control');
          debugService?.addStep(BrainPhase.processing, 'Ambiance control failed');
        }
      } else {
        // Infer profile from Kai's reply
        print('🎭 [AMBIENT] No direct match - inferring from reply');
        const profileMap = {
          'forest': ['forest', 'green', 'nature', 'trees'],
          'ocean': ['ocean', 'blue', 'waves', 'sea'],
          'romantic': ['romantic', 'amber', 'intimate', 'classical'],
          'party': ['party', 'rainbow', 'energetic', 'dance'],
          'focus': ['focus', 'white', 'concentration', 'productivity'],
          'sunset': ['sunset', 'orange', 'warm', 'evening'],
          'cozy': ['cozy', 'comfortable', 'relaxing'],
          'energetic': ['energetic', 'motivated', 'bright', 'upbeat'],
        };

        String? inferredProfile;
        for (final entry in profileMap.entries) {
          if (entry.value.any((kw) => lowerReply.contains(kw))) {
            inferredProfile = entry.key;
            break;
          }
        }

        if (inferredProfile != null) {
          print('🎭 [AMBIENT] Inferred profile: $inferredProfile');
          final success = await ambianceService.setAmbiance(
            profile: inferredProfile,
            originalInput: originalInput,
            confidence: 0.7,
          );
          if (success) {
            print('✅ [AMBIENT] Triggered inferred $inferredProfile ambiance');
            debugService?.addStep(
              BrainPhase.processing,
              'Inferred ambiance control successful',
              data: {'inferred_profile': inferredProfile},
            );
          }
        } else {
          print('⚠️ [AMBIENT] Could not infer specific ambiance profile from reply');
        }
      }
    } catch (e) {
      print('❌ [AMBIENT] Error in ambiance detection/triggering: $e');
      debugService?.addStep(BrainPhase.processing, 'Ambiance detection failed: $e');
    }
  }

  Future<void> _handleYouTubeMusicRequest(
    String originalInput,
    String reply,
    dynamic debugService,
  ) async {
    try {
      print('🎵 [AMBIENT] Processing YouTube music request: "$originalInput"');
      debugService?.addStep(
        BrainPhase.processing,
        'YouTube music request detected',
        data: {
          'original_input': originalInput,
          'reply_preview': reply.length > 100 ? '${reply.substring(0, 100)}...' : reply,
        },
      );

      final searchQuery = _extractSearchQuery(originalInput);
      if (searchQuery.isEmpty) {
        print('⚠️ [AMBIENT] Could not extract search query from: "$originalInput"');
        debugService?.addStep(
          BrainPhase.processing,
          'Failed to extract YouTube search query',
          data: {'input': originalInput},
        );
        return;
      }

      print('🎵 [AMBIENT] Extracted YouTube search: "$searchQuery"');
      await HomeAutomationService().sendCommand(
        personaId: 'kai',
        deviceId: 'raspberry_pi_home',
        target: 'music',
        action: 'play_youtube',
        params: {
          'search_query': searchQuery,
          'voice_analysis': {
            'original_input': originalInput,
            'search_query': searchQuery,
            'confidence': 0.8,
          },
        },
      );

      print('✅ [AMBIENT] YouTube command sent to Pi: "$searchQuery"');
      debugService?.addStep(
        BrainPhase.processing,
        'YouTube command sent successfully',
        data: {'search_query': searchQuery, 'action': 'play_youtube'},
      );
    } catch (e) {
      print('❌ [AMBIENT] Error handling YouTube request: $e');
      debugService?.addStep(BrainPhase.processing, 'YouTube request failed: $e');
    }
  }

  Future<void> _handleVolumeControlRequest(
    String originalInput,
    String reply,
    dynamic debugService,
  ) async {
    try {
      print('🔊 [AMBIENT] Processing volume control request: "$originalInput"');
      debugService?.addStep(
        BrainPhase.processing,
        'Volume control request detected',
        data: {
          'original_input': originalInput,
          'reply_preview': reply.length > 100 ? '${reply.substring(0, 100)}...' : reply,
        },
      );

      final lowerInput = originalInput.toLowerCase();
      String action = '';
      Map<String, dynamic> params = {};

      if (lowerInput.contains('volume up') || lowerInput.contains('turn up') ||
          lowerInput.contains('louder') || lowerInput.contains('increase volume') ||
          lowerInput.contains('raise volume') || lowerInput.contains('make it louder')) {
        action = 'volume_up';
      } else if (lowerInput.contains('volume down') || lowerInput.contains('turn down') ||
                 lowerInput.contains('quieter') || lowerInput.contains('decrease volume') ||
                 lowerInput.contains('lower volume') || lowerInput.contains('make it quieter')) {
        action = 'volume_down';
      } else if (lowerInput.contains('set volume') || lowerInput.contains('volume to') ||
                 lowerInput.contains('volume at')) {
        action = 'set_volume';
        final match = RegExp(r'(?:set volume|volume to|volume at)\s+(\d+)', caseSensitive: false)
            .firstMatch(originalInput);
        params['volume'] = match != null
            ? (int.tryParse(match.group(1) ?? '50') ?? 50).clamp(0, 100)
            : 50;
      }

      if (action.isEmpty) {
        print('⚠️ [AMBIENT] Could not determine volume action from: "$originalInput"');
        return;
      }

      await HomeAutomationService().sendCommand(
        personaId: 'kai',
        deviceId: 'raspberry_pi_home',
        target: 'music',
        action: action,
        params: params,
      );

      print('✅ [AMBIENT] Volume command sent to Pi: $action ${params.isNotEmpty ? params : ''}');
      debugService?.addStep(
        BrainPhase.processing,
        'Volume command sent successfully',
        data: {'action': action, 'params': params},
      );
    } catch (e) {
      print('❌ [AMBIENT] Error handling volume request: $e');
      debugService?.addStep(BrainPhase.processing, 'Volume request failed: $e');
    }
  }

  Future<void> _handleDirectLightingRequest(
    String originalInput,
    String reply,
    dynamic debugService,
  ) async {
    try {
      print('💡 [AMBIENT] Processing direct lighting request: "$originalInput"');
      debugService?.addStep(
        BrainPhase.processing,
        'Direct lighting command detected',
        data: {
          'original_input': originalInput,
          'reply_preview': reply.length > 100 ? '${reply.substring(0, 100)}...' : reply,
        },
      );

      final lowerInput = originalInput.toLowerCase();
      const colorMap = {
        'red': 'red', 'blue': 'blue', 'green': 'green', 'white': 'white',
        'yellow': 'yellow', 'purple': 'purple', 'orange': 'orange', 'amber': 'amber',
        'pink': 'pink', 'cyan': 'cyan', 'magenta': 'magenta',
        'warm white': 'warm_white', 'warm_white': 'warm_white',
        'light green': 'light_green', 'light_green': 'light_green',
      };

      String? detectedColor;
      for (final entry in colorMap.entries) {
        if (lowerInput.contains(entry.key)) {
          detectedColor = entry.value;
          break;
        }
      }

      if (detectedColor == null) {
        print('⚠️ [AMBIENT] No color detected in lighting request');
        return;
      }

      print('🎨 [AMBIENT] Detected color: $detectedColor');
      await HomeAutomationService().sendCommand(
        personaId: 'kai',
        deviceId: 'raspberry_pi_home',
        target: 'lights',
        action: 'set_lighting',
        params: {
          'color': detectedColor,
          'brightness': 70,
          'effect': 'solid',
          'zones': ['all'],
        },
      );

      print('✅ [AMBIENT] Lighting command sent to Pi: $detectedColor lights');
      debugService?.addStep(
        BrainPhase.processing,
        'Lighting command sent successfully',
        data: {'color': detectedColor, 'action': 'set_lighting'},
      );
    } catch (e) {
      print('❌ [AMBIENT] Error handling lighting request: $e');
      debugService?.addStep(BrainPhase.processing, 'Lighting request failed: $e');
    }
  }

  String _extractSearchQuery(String input) {
    final patterns = [
      RegExp(r'play\s+(.+?)(?:\s+by\s+(.+?))?(?:\s+from\s+youtube)?(?:\s+on\s+youtube)?$', caseSensitive: false),
      RegExp(r'(?:find|search|look up)\s+(.+?)(?:\s+on\s+youtube)?$', caseSensitive: false),
      RegExp(r'(?:song|track|music)\s+called\s+(.+?)(?:\s+by\s+(.+?))?$', caseSensitive: false),
      RegExp(r'(.+?)\s+by\s+(.+?)(?:\s+from\s+youtube)?$', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(input);
      if (match != null) {
        final song = match.group(1)?.trim() ?? '';
        final artist = match.group(2)?.trim() ?? '';
        if (song.isNotEmpty) {
          return artist.isNotEmpty ? '$song by $artist' : song;
        }
      }
    }

    return input
        .replaceAll(RegExp(r'\b(hey\s+kai,?\s*|play\s+|from\s+youtube\s+|on\s+youtube\s+)', caseSensitive: false), '')
        .trim()
        .isNotEmpty
        ? input
            .replaceAll(RegExp(r'\b(hey\s+kai,?\s*|play\s+|from\s+youtube\s+|on\s+youtube\s+)', caseSensitive: false), '')
            .trim()
        : input;
  }

  Future<void> _triggerDynamicAmbientExperience(
    AmbientExperience experience,
    BrainDebugService? debugService,
  ) async {
    try {
      print('🎆 [DYNAMIC_AMBIENT] Triggering experience: ${experience.name}');
      debugService?.addStep(
        BrainPhase.processing,
        'Triggering dynamic ambient experience',
        data: {
          'experience_name': experience.name,
          'confidence': experience.confidence,
          'has_video': experience.videoContent != null,
          'lighting_pattern': experience.lighting.pattern,
        },
      );

      await _applyDynamicLighting(experience.lighting);

      if (experience.videoContent != null) {
        await _startAmbientVideo(experience.videoContent!);
      }

      print('✅ [DYNAMIC_AMBIENT] Experience activated successfully');
    } catch (e) {
      print('❌ [DYNAMIC_AMBIENT] Error triggering experience: $e');
      debugService?.addStep(
        BrainPhase.processing,
        'Dynamic ambient experience failed',
        data: {'error': e.toString()},
      );
    }
  }

  Future<void> _applyDynamicLighting(DynamicLighting lighting) async {
    try {
      final dio = Dio();
      final prompt = _generateAmbientPrompt(lighting);

      final response = await dio.post(
        'http://192.168.227.5:5001/command',
        data: {'command': 'dynamic_ambient', 'prompt': prompt},
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200) {
        print('🎨 [DYNAMIC_AMBIENT] Applied via HTTP POST: $prompt');
        print('✅ Pi Response: ${response.data}');
      } else {
        print('❌ Pi HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [DYNAMIC_AMBIENT] HTTP command failed: $e — trying Firebase fallback');
      try {
        await HomeAutomationService().sendCommand(
          personaId: 'kai',
          deviceId: 'led_strip_main',
          target: 'lighting',
          action: 'dynamic_ambient',
          params: {
            'type': 'dynamic_lighting',
            'primary_color': lighting.primaryColor,
            'secondary_color': lighting.secondaryColor,
            'accent_color': lighting.accentColor,
            'brightness': lighting.brightness,
            'pattern': lighting.pattern,
            'speed': lighting.speed,
            'zones': lighting.zones,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        );
        print('🔄 [DYNAMIC_AMBIENT] Fallback to Firebase completed');
      } catch (fallbackError) {
        print('❌ Firebase fallback also failed: $fallbackError');
      }
    }
  }

  String _generateAmbientPrompt(DynamicLighting lighting) {
    String basePrompt;
    switch (lighting.primaryColor.toLowerCase()) {
      case '#00ff00':
      case 'green':
      case 'light_green':
        basePrompt = lighting.pattern == 'gentle_pulse'
            ? 'mysterious forest atmosphere with gentle breathing lights'
            : 'peaceful forest environment';
        break;
      case '#ff6500':
      case 'orange':
      case 'amber':
        basePrompt = lighting.pattern == 'candle_flicker'
            ? 'cozy fireplace with flickering flames'
            : 'warm fireplace evening';
        break;
      case '#0066cc':
      case 'blue':
      case 'deep_blue':
        basePrompt = lighting.pattern == 'wave'
            ? 'ocean waves with flowing movement'
            : 'peaceful ocean atmosphere';
        break;
      case '#800080':
      case 'purple':
      case 'indigo':
        basePrompt = 'mystical evening with purple ambiance';
        break;
      case '#ffff00':
      case 'yellow':
      case 'warm_white':
        basePrompt = 'warm sunlit afternoon atmosphere';
        break;
      default:
        basePrompt = 'ambient lighting atmosphere';
    }

    switch (lighting.pattern.toLowerCase()) {
      case 'color_cycle':
      case 'rainbow':
        basePrompt += ' with rainbow color transitions';
        break;
      case 'lightning':
        basePrompt += ' with dramatic lightning effects';
        break;
      case 'aurora':
        basePrompt += ' with northern lights effect';
        break;
      case 'rain_drops':
        basePrompt += ' with rain drop patterns';
        break;
    }

    return basePrompt;
  }

  Future<void> _startAmbientVideo(VideoContent video) async {
    try {
      final dio = Dio();
      final response = await dio.post(
        'http://192.168.227.5:5001/command',
        data: {
          'command': 'play_ambient_video',
          'query': video.searchQuery,
          'title': video.title,
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200) {
        print('🎵 [DYNAMIC_AMBIENT] Started ambient video via HTTP: ${video.title}');
        print('✅ Pi Audio Response: ${response.data}');
      } else {
        print('❌ Pi Audio HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [DYNAMIC_AMBIENT] Audio HTTP command failed: $e — trying Firebase fallback');
      try {
        await HomeAutomationService().sendCommand(
          personaId: 'kai',
          deviceId: 'pi_audio_system',
          target: 'audio',
          action: 'play_ambient_video',
          params: {
            'type': 'youtube_ambient',
            'video_title': video.title,
            'search_query': video.searchQuery,
            'duration': video.duration,
            'volume': 0.3,
            'loop': true,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        );
        print('🔄 [DYNAMIC_AMBIENT] Audio fallback to Firebase completed');
      } catch (fallbackError) {
        print('❌ Audio Firebase fallback also failed: $fallbackError');
      }
    }
  }

  /// Attempt to wake up Pi in the background via Wake-on-LAN.
  void attemptPiWakeUp() {
    WakeOnLanService().wakeAndWaitForListener().then((success) {
      if (success) {
        print('✅ [AMBIENT] Pi successfully awakened via Wake-on-LAN');
      } else {
        print('⚠️ [AMBIENT] Wake-on-LAN attempt failed or Pi not responding');
      }
    }).catchError((e) {
      print('❌ [AMBIENT] Wake-on-LAN background task error: $e');
    });
  }
}
