// kai_quick_responses.dart
//
// Pre-generated short Kai voice clips stored on device.
//
// On first startup (or whenever a clip is missing), each phrase is synthesised
// via ElevenLabs in the background and written to app-documents/kai_clips/.
// Subsequent startups load instantly from disk — zero API latency.
//
// Usage:
//   await KaiQuickResponses.instance.initialize();   // call once at startup
//   await KaiQuickResponses.instance.play('yes', player);   // instant playback
//   KaiQuickResponses.instance.isReady('yes')        // false while generating

library;

import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../ai/tts_service.dart';

// ── Clip definitions ──────────────────────────────────────────────────────────
//
// Each entry: key → (displayText, elevenLabsText, stability, similarityBoost, style)
//
// stability:       lower = more expressive / varied
// similarityBoost: how closely to match the voice clone
// style:           style exaggeration (v2+ models); 0 = natural, 1 = max drama
const Map<String, _ClipSpec> _kClips = {
  // Inquisitive "yes?" — light, upward inflection
  'yes': _ClipSpec('yes?',   stability: 0.35, similarity: 0.80, style: 0.55),
  // Thoughtful "hmm?" — slightly slower, pondering
  'hmm': _ClipSpec('hmm?',   stability: 0.50, similarity: 0.75, style: 0.40),
  // Surprised/confused "huh?" — quick, sharp
  'huh': _ClipSpec('huh?',   stability: 0.28, similarity: 0.82, style: 0.70),
  // Excited "yay!" — high energy
  'yay': _ClipSpec('yay!',   stability: 0.20, similarity: 0.90, style: 0.90),
  // Deflated "oh.." — flat, trailing off
  'oh':  _ClipSpec('oh..',   stability: 0.72, similarity: 0.70, style: 0.20),
};

class _ClipSpec {
  final String text;
  final double stability;
  final double similarity;
  final double style;
  const _ClipSpec(this.text, {required this.stability, required this.similarity, required this.style});
}

// ── Service ───────────────────────────────────────────────────────────────────

class KaiQuickResponses {
  KaiQuickResponses._();
  static final instance = KaiQuickResponses._();

  final TTSService _tts = TTSService();

  // key → absolute path to cached MP3
  final Map<String, String> _paths = {};

  bool get isReady => _paths.isNotEmpty;

  /// Returns true if the named clip exists and is ready to play.
  bool hasClip(String key) => _paths.containsKey(key);

  // ── Initialise ─────────────────────────────────────────────────────────────

  /// Call once at app startup (fire-and-forget is fine).
  /// Missing clips are generated in the background; existing ones load instantly.
  Future<void> initialize() async {
    final dir = await _clipDir();

    // Load whatever is already cached
    for (final key in _kClips.keys) {
      final file = File('${dir.path}/$key.mp3');
      if (file.existsSync() && file.lengthSync() > 512) {
        _paths[key] = file.path;
        print('🎵 [QuickResponses] Loaded "$key" from cache');
      }
    }

    // Generate any missing clips in the background
    final missing = _kClips.keys.where((k) => !_paths.containsKey(k)).toList();
    if (missing.isNotEmpty) {
      print('🎙️ [QuickResponses] Generating ${missing.length} missing clip(s): $missing');
      _generateMissing(missing, dir);   // intentionally not awaited
    } else {
      print('✅ [QuickResponses] All clips ready');
    }
  }

  Future<void> _generateMissing(List<String> keys, Directory dir) async {
    for (final key in keys) {
      final spec = _kClips[key]!;
      try {
        final bytes = await _tts.synthesizeTTS(
          spec.text,
          stability:        spec.stability,
          similarityBoost:  spec.similarity,
          style:            spec.style,
        );
        if (bytes != null && bytes.isNotEmpty) {
          final file = File('${dir.path}/$key.mp3');
          await file.writeAsBytes(bytes, flush: true);
          _paths[key] = file.path;
          print('✅ [QuickResponses] Cached "$key" (${bytes.length} B)');
        } else {
          print('⚠️ [QuickResponses] Empty response for "$key"');
        }
      } catch (e) {
        print('⚠️ [QuickResponses] Failed to generate "$key": $e');
      }
    }
  }

  // ── Playback ───────────────────────────────────────────────────────────────

  /// Play the named clip through [player] and wait for it to finish.
  /// Returns immediately (no-op) if the clip isn't cached yet.
  Future<void> play(String key, AudioPlayer player) async {
    final path = _paths[key];
    if (path == null) {
      print('⚠️ [QuickResponses] Clip "$key" not ready yet — skipping');
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      _paths.remove(key);
      print('⚠️ [QuickResponses] Clip "$key" file missing — removed from cache');
      return;
    }
    await player.stop();
    await player.play(DeviceFileSource(path));
    // Wait for playback to finish (5 s safety timeout)
    await player.onPlayerComplete.first
        .timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  // ── Cache management ───────────────────────────────────────────────────────

  /// Delete all cached clips (e.g. when the ElevenLabs voice changes).
  Future<void> clearCache() async {
    final dir = await _clipDir();
    for (final key in List.of(_paths.keys)) {
      try { await File('${dir.path}/$key.mp3').delete(); } catch (_) {}
      _paths.remove(key);
    }
    print('🗑️ [QuickResponses] Cache cleared');
  }

  Future<Directory> _clipDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/kai_clips');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
}
