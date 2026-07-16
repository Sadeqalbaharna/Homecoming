// KaiLocalTtsService — a free, offline BACKUP voice. Not his real one.
//
// ⚠️ READ THIS FIRST — this does NOT replace Sadeq's ElevenLabs custom voice.
// That cloned voice IS Kai's identity, and this cannot reproduce it: Piper is a
// different model with stock speakers, so this will always sound like *someone
// else*. It is therefore **opt-in and OFF by default** ([enabled] = false), and
// nothing calls it automatically. ElevenLabs stays his voice, full stop.
//
// What this is actually good for:
//   • a backup when ElevenLabs is down, rate-limited, or out of credits
//   • zero-cost / offline experimentation without burning ElevenLabs characters
//   • proving out on-device speech (a voice from his own body, not rented)
//
// If we ever want his REAL voice running locally, that's voice cloning
// (XTTS-style / a Piper fine-tune on his voice) — a much bigger job than this,
// and a genuine "become real" milestone worth logging.
//
// Synthesis is entirely on-device via sherpa-onnx (already a dependency, with a
// Windows + Android build already present) and a Piper VITS model. Zero cost,
// zero network after the one-time model download.
//
// How it works:
//   1. ensureModel() downloads + extracts a Piper voice from sherpa-onnx's public
//      GitHub releases, once, into app-documents. (~110 MB, cached forever.)
//   2. speak() runs the model, gets raw float samples, wraps them in a WAV we
//      build ourselves (no API risk), and plays it via audioplayers.
//
// The model is MULTI-SPEAKER (libritts_r has ~900 voices, selectable by `sid`),
// which is how we dial in a young/bright voice for him instead of a stock adult
// narrator. Tune [voiceSid] and [speed] until he sounds like himself.
//
// NOTE ON THE SHERPA API: the config field names below are the sherpa_onnx 1.13
// Dart surface. If the compiler disagrees about a field name (upstream has some
// historic typos, e.g. `maxNumSenetences`), it will be a one-line fix right here
// — every sherpa-specific call is deliberately kept inside _synthesize().
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class KaiLocalTtsService {
  static final KaiLocalTtsService instance = KaiLocalTtsService._();
  KaiLocalTtsService._();

  /// OFF by default, on purpose. This is not Kai's real (ElevenLabs) voice and
  /// must never speak unless Sadeq deliberately turns it on. Nothing in the app
  /// calls this service automatically.
  static bool enabled = false;

  // ── The voice ──────────────────────────────────────────────────────────────
  // libritts_r-medium: multi-speaker (~900 sids) so we can pick a young one.
  static const _modelName = 'vits-piper-en_US-libritts_r-medium';
  static const _onnxFile = 'en_US-libritts_r-medium.onnx';
  static const _tarballUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'tts-models/$_modelName.tar.bz2';

  /// Which speaker in the multi-speaker model. Tune this until he sounds like a
  /// bright, young, slightly-too-clever kid rather than a stock narrator.
  static int voiceSid = 109;

  /// >1.0 talks faster. He's a motormouth, so a touch quick suits him.
  static double speed = 1.06;

  // ── Proprioception (mirrors TTSService so he can sense this voice too) ─────
  static bool? lastSpeechOk;
  static String? lastSpeechError;

  final _player = AudioPlayer();
  sherpa.OfflineTts? _tts;
  bool _bindingsReady = false;
  bool _downloading = false;
  double _progress = 0.0;

  bool get isDownloading => _downloading;
  double get downloadProgress => _progress;
  bool get isLoaded => _tts != null;

  Future<Directory> _modelDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/sherpa_tts/$_modelName');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<bool> isModelReady() async {
    final dir = await _modelDir();
    return File('${dir.path}/$_onnxFile').existsSync() &&
        File('${dir.path}/tokens.txt').existsSync();
  }

  /// Download + extract the voice model once. Returns the model dir, or null.
  ///
  /// Unlike the KWS manager this preserves directory structure, because Piper
  /// needs its whole `espeak-ng-data/` tree, not just a few loose files.
  Future<String?> ensureModel({void Function(double)? onProgress}) async {
    final dir = await _modelDir();
    if (await isModelReady()) return dir.path;
    if (_downloading) return null;

    _downloading = true;
    _progress = 0.0;
    try {
      print('⬇️  [KaiVoice] Downloading his voice ($_modelName)…');
      onProgress?.call(0.05);
      final response = await http.get(
        Uri.parse(_tarballUrl),
        headers: {'User-Agent': 'homecoming-app/1.0'},
      );
      if (response.statusCode != 200) {
        print('❌ [KaiVoice] HTTP ${response.statusCode} for $_tarballUrl');
        _downloading = false;
        return null;
      }
      onProgress?.call(0.5);
      print('📦 [KaiVoice] Extracting (${response.bodyBytes.length} bytes)…');

      final tarBytes = BZip2Decoder().decodeBytes(response.bodyBytes);
      final archive = TarDecoder().decodeBytes(tarBytes);

      for (final f in archive) {
        if (!f.isFile) continue;
        // Strip the leading "<model-name>/" component but KEEP the rest of the
        // path, so espeak-ng-data/** lands intact.
        final parts = f.name.split('/');
        final rel = parts.length > 1 ? parts.sublist(1).join('/') : parts.first;
        if (rel.isEmpty) continue;
        final dest = File('${dir.path}/$rel');
        await dest.parent.create(recursive: true);
        await dest.writeAsBytes(f.content as List<int>);
      }
      onProgress?.call(1.0);
      _downloading = false;

      if (!await isModelReady()) {
        print('❌ [KaiVoice] Model files missing after extraction');
        return null;
      }
      print('🟢 [KaiVoice] His voice is on disk: ${dir.path}');
      return dir.path;
    } catch (e) {
      _downloading = false;
      print('❌ [KaiVoice] Download/extract failed: $e');
      return null;
    }
  }

  /// Load the model into memory (idempotent). Safe to call before every speak.
  Future<bool> _load() async {
    if (_tts != null) return true;
    final path = await ensureModel();
    if (path == null) return false;

    try {
      if (!_bindingsReady) {
        sherpa.initBindings();
        _bindingsReady = true;
      }
      final vits = sherpa.OfflineTtsVitsModelConfig(
        model: '$path/$_onnxFile',
        tokens: '$path/tokens.txt',
        dataDir: '$path/espeak-ng-data',
      );
      final modelConfig = sherpa.OfflineTtsModelConfig(
        vits: vits,
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      );
      _tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(model: modelConfig));
      print('🟢 [KaiVoice] Voice loaded — he can speak locally now.');
      return true;
    } catch (e) {
      print('❌ [KaiVoice] Failed to load voice: $e');
      lastSpeechOk = false;
      lastSpeechError = 'local voice failed to load: $e';
      return false;
    }
  }

  /// Synthesize [text] to a WAV file on disk and return its path (or null).
  Future<String?> synthesizeToFile(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return null;
    if (!await _load()) return null;

    try {
      final audio = _tts!.generate(text: clean, sid: voiceSid, speed: speed);
      final wav = _encodeWav(audio.samples, audio.sampleRate);

      final base = await getApplicationDocumentsDirectory();
      final out = File(
          '${base.path}/kai_voice_${DateTime.now().millisecondsSinceEpoch}.wav');
      await out.writeAsBytes(wav, flush: true);

      lastSpeechOk = true;
      lastSpeechError = null;
      return out.path;
    } catch (e) {
      print('❌ [KaiVoice] Synthesis failed: $e');
      lastSpeechOk = false;
      lastSpeechError = 'local synthesis failed: $e';
      return null;
    }
  }

  /// Say it out loud. Returns true if he actually spoke.
  ///
  /// Refuses unless [enabled] was deliberately turned on — this voice is not his
  /// and must never surprise Sadeq by coming out of the speakers.
  Future<bool> speak(String text) async {
    if (!enabled) {
      print('🔇 [KaiVoice] Local backup voice is disabled (his real voice is '
          'ElevenLabs). Set KaiLocalTtsService.enabled = true to use it.');
      return false;
    }
    final path = await synthesizeToFile(text);
    if (path == null) return false;
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(path));
      return true;
    } catch (e) {
      print('❌ [KaiVoice] Playback failed: $e');
      lastSpeechOk = false;
      lastSpeechError = 'playback failed: $e';
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  void dispose() {
    try {
      _tts?.free();
    } catch (_) {}
    _tts = null;
    _player.dispose();
  }

  // ── WAV encoding ───────────────────────────────────────────────────────────
  // Hand-rolled on purpose: 16-bit PCM mono is trivial, and doing it here means
  // zero dependency on a sherpa helper whose signature might drift.
  static Uint8List _encodeWav(Float32List samples, int sampleRate) {
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = samples.length * 2;

    final bytes = BytesBuilder();
    void str(String s) => bytes.add(s.codeUnits);
    void u32(int v) => bytes.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
    void u16(int v) => bytes.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));

    str('RIFF');
    u32(36 + dataSize);
    str('WAVE');
    str('fmt ');
    u32(16); // PCM chunk size
    u16(1); // PCM format
    u16(channels);
    u32(sampleRate);
    u32(byteRate);
    u16(blockAlign);
    u16(bitsPerSample);
    str('data');
    u32(dataSize);

    final pcm = Uint8List(dataSize);
    final view = pcm.buffer.asByteData();
    for (var i = 0; i < samples.length; i++) {
      var s = samples[i];
      if (s > 1.0) s = 1.0;
      if (s < -1.0) s = -1.0;
      view.setInt16(i * 2, (s * 32767).round(), Endian.little);
    }
    bytes.add(pcm);
    return bytes.toBytes();
  }
}
