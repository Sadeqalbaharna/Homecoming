// AttentionSoundService
//
// Plays Kai's short attention sounds using his actual ElevenLabs voice.
// Two sounds, each generated once and cached permanently on-device:
//
//   AttentionMood.curious  → "hmm?"   (morning brief, check-in, interesting news)
//   AttentionMood.worried  → "huh?"   (event in 15 min, long gap, something urgent)
//
// On first call the clip is synthesised via ElevenLabs and stored in the app's
// support directory. Subsequent calls play the cached file instantly.

library;

import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../ai/tts_service.dart';

enum AttentionMood { curious, worried }

class AttentionSoundService {
  static final AttentionSoundService _i = AttentionSoundService._();
  factory AttentionSoundService() => _i;
  AttentionSoundService._();

  final TTSService _tts = TTSService();
  final AudioPlayer _player = AudioPlayer();

  // Text synthesised for each mood — short, natural, in-character for Kai
  static const _texts = {
    AttentionMood.curious: 'Hmm?',
    AttentionMood.worried: 'Huh?',
  };

  static const _filenames = {
    AttentionMood.curious: 'kai_attention_curious.mp3',
    AttentionMood.worried: 'kai_attention_worried.mp3',
  };

  // ── Public API ────────────────────────────────────────────────────────────

  /// Play the attention sound for [mood].
  /// Generates + caches the clip on first call; instant thereafter.
  Future<void> play(AttentionMood mood) async {
    try {
      final file = await _getOrGenerate(mood);
      if (file == null) return;
      await _player.stop();
      await _player.play(DeviceFileSource(file.path));
    } catch (e) {
      print('🔔 [AttentionSound] play failed: $e');
    }
  }

  /// Pre-warm both clips (call once on startup so first attention is instant).
  Future<void> prime() async {
    await Future.wait([
      _getOrGenerate(AttentionMood.curious),
      _getOrGenerate(AttentionMood.worried),
    ]);
    print('🔔 [AttentionSound] Both clips primed');
  }

  /// Delete cached clips (e.g. after voice change in settings).
  Future<void> clearCache() async {
    final dir = await getApplicationSupportDirectory();
    for (final name in _filenames.values) {
      final f = File('${dir.path}/$name');
      if (await f.exists()) await f.delete();
    }
    print('🔔 [AttentionSound] Cache cleared');
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<File?> _getOrGenerate(AttentionMood mood) async {
    final dir  = await getApplicationSupportDirectory();
    final file = File('${dir.path}/${_filenames[mood]}');

    if (await file.exists()) return file;

    // Generate via ElevenLabs
    final text = _texts[mood]!;
    print('🔔 [AttentionSound] Generating "$text" via ElevenLabs…');
    final Uint8List? bytes = await _tts.synthesizeTTS(text);
    if (bytes == null || bytes.isEmpty) {
      print('🔔 [AttentionSound] TTS returned null — skipping');
      return null;
    }

    await file.writeAsBytes(bytes, flush: true);
    print('🔔 [AttentionSound] Cached at ${file.path}');
    return file;
  }
}
