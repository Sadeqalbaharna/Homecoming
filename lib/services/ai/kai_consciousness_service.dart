// Kai Consciousness Service — reads Kai's self-awareness context from the
// Raspberry Pi via Firebase RTDB.  Used to give Kai accurate information
// about the smart-home hardware when the user asks about lights, music, etc.

import '../core/firebase_service.dart';

class KaiConsciousnessService {
  // Keywords that suggest the user wants to control the smart home.
  static const List<String> _smartHomeKeywords = [
    'light', 'lights', 'lamp', 'lamps', 'brightness', 'dim',
    'music', 'song', 'play', 'pause', 'stop', 'volume',
    'ambiance', 'ambience', 'mood', 'scene',
    'temperature', 'thermostat', 'fan', 'ac', 'heat',
    'raspberry', 'pi', 'strip', 'led', 'rgb', 'wled',
    'home', 'room', 'house', 'bedroom', 'living room',
    'turn on', 'turn off', 'switch', 'toggle',
  ];

  /// True if [text] looks like a smart-home / device control request.
  static bool isSmartHomeRequest(String text) {
    final lower = text.toLowerCase();
    return _smartHomeKeywords.any((kw) => lower.contains(kw));
  }

  /// Fetch Kai's current technical context from the Pi (via Firebase).
  /// Returns null if the Pi is offline or Firebase is unavailable.
  static Future<Map<String, dynamic>?> getKaiTechnicalContext(String userRequest) async {
    if (!FirebaseService.isAvailable) {
      return _buildOfflineContext(userRequest);
    }

    try {
      final piStatus = await FirebaseService.readData('kai/status');
      if (piStatus == null) {
        return _buildOfflineContext(userRequest);
      }

      final statusMap = Map<String, dynamic>.from(piStatus as Map);
      final isOnline = statusMap['online'] == true;

      if (!isOnline) {
        return _buildOfflineContext(userRequest);
      }

      // Pi is online — build full context
      final ledState = await FirebaseService.readData('kai/led_state') ?? {};
      final musicState = await FirebaseService.readData('kai/music_state') ?? {};

      return {
        'kai_technical_context': {
          'pi_status': 'online',
          'hardware_setup': {
            'led_strips': _parseLedStrips(ledState),
            'audio': _parseAudioState(musicState),
          },
          'current_state': statusMap,
        },
      };
    } catch (e) {
      print('⚠️ [KaiConsciousness] Failed to fetch Pi context: $e');
      return _buildOfflineContext(userRequest);
    }
  }

  /// Build a system prompt that gives Kai full awareness of its hardware context.
  static String generateKaiConsciousnessPrompt(
    Map<String, dynamic> kaiConsciousness,
    String userRequest,
  ) {
    final ctx = kaiConsciousness['kai_technical_context'] as Map<String, dynamic>?;
    if (ctx == null) return _buildFallbackPrompt(userRequest);

    final piStatus = ctx['pi_status'] ?? 'unknown';
    final hw = ctx['hardware_setup'] as Map<String, dynamic>? ?? {};
    final debugMessage = kaiConsciousness['debug_message'] as String?;

    final buf = StringBuffer();
    buf.writeln('You are Kai — a warm AI companion with smart-home control capabilities.');
    buf.writeln();
    buf.writeln('🤖 YOUR CURRENT HARDWARE STATUS:');
    buf.writeln('• Raspberry Pi: $piStatus');

    final ledStrips = hw['led_strips'] as List? ?? [];
    if (ledStrips.isNotEmpty) {
      buf.writeln('• LED Strips: ${ledStrips.length} strip(s) connected');
      for (final strip in ledStrips) {
        buf.writeln('  - ${strip['name'] ?? 'Strip'}: ${strip['state'] ?? 'unknown'}');
      }
    }

    final audio = hw['audio'] as Map<String, dynamic>?;
    if (audio != null) {
      buf.writeln('• Audio: ${audio['status'] ?? 'unknown'}');
      if (audio['current_track'] != null) {
        buf.writeln('  - Playing: ${audio['current_track']}');
      }
    }

    if (debugMessage != null) {
      buf.writeln();
      buf.writeln('⚠️ System note: $debugMessage');
    }

    buf.writeln();
    buf.writeln('User request: "$userRequest"');
    buf.writeln('Respond helpfully about what you can do with the smart home.');

    return buf.toString();
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  static Map<String, dynamic>? _buildOfflineContext(String userRequest) {
    return {
      'kai_technical_context': {
        'pi_status': 'offline',
        'hardware_setup': {
          'led_strips': [],
          'audio': {'status': 'unavailable'},
        },
        'current_state': {},
      },
      'debug_message':
          "I'm having trouble reaching my smart-home system right now. "
          "It might be asleep or disconnected. I can still chat, but "
          "I won't be able to control lights or music at the moment!",
    };
  }

  static String _buildFallbackPrompt(String userRequest) {
    return 'You are Kai. Your smart-home system appears to be offline. '
        'Apologize naturally and let the user know you\'ll try again soon. '
        'User said: "$userRequest"';
  }

  static List<Map<String, dynamic>> _parseLedStrips(dynamic ledState) {
    if (ledState == null) return [];
    try {
      final map = Map<String, dynamic>.from(ledState as Map);
      return map.entries.map((e) {
        final strip = Map<String, dynamic>.from(e.value as Map? ?? {});
        strip['name'] = e.key;
        return strip;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Map<String, dynamic> _parseAudioState(dynamic musicState) {
    if (musicState == null) return {'status': 'unknown'};
    try {
      return Map<String, dynamic>.from(musicState as Map);
    } catch (_) {
      return {'status': 'unknown'};
    }
  }
}
