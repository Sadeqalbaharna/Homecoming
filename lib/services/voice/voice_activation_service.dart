// voice_activation_service.dart
//
// Wake word detection using sherpa-onnx keyword spotting (on-device, no API key).
//
// Architecture:
//   IDLE      → mic_stream PCM16 @ 16 kHz → sherpa_onnx KeywordSpotter
//   DETECTED  → emit 'hey kai' on [onWakeWordDetected] → UI opens the bubble
//   PAUSED    → processing flag suppressed (mic stays open to avoid re-acq lag)
//
// First-run:  ~11 MB of ONNX model files are downloaded from HuggingFace and
//             cached to the app documents dir.  Subsequent launches are instant.
//
// Setup:      none.  No API keys, no .ppn files, no external accounts.

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'sherpa_model_manager.dart';
import 'voice_service.dart';
import 'voice_training_service.dart';
import '../core/native_audio_recorder.dart';

class VoiceActivationService {
  static final VoiceActivationService _instance =
      VoiceActivationService._internal();
  factory VoiceActivationService() => _instance;
  VoiceActivationService._internal();

  // ── Keyword spotter ───────────────────────────────────────────────────────
  sherpa.KeywordSpotter? _kws;
  sherpa.OnlineStream? _kwsStream;

  // ── PCM mic stream ────────────────────────────────────────────────────────
  StreamSubscription<dynamic>? _micSub;
  static const _micChannel = EventChannel('com.homecoming.app/mic_stream');

  // ── Legacy dependencies (kept for voice training screen API compat) ───────
  final NativeAudioRecorder _recorder = NativeAudioRecorder();
  final VoiceService _voiceService = VoiceService();
  final VoiceTrainingService _trainingService = VoiceTrainingService();

  // ── State ──────────────────────────────────────────────────────────────────
  bool _isEnabled = false;
  bool _isActive = false;  // mic stream + KWS running
  bool _isPaused = false;  // suppresses chunk processing (e.g. TTS playing)
  bool _kwsReady = false;  // models loaded, KWS initialised
  bool _bindingsInit = false;

  // ── Keyword config ─────────────────────────────────────────────────────────
  //
  // One keyword phrase per line; the `:score` suffix is a per-keyword
  // threshold override.  Lower = more sensitive (more false positives).
  // Several spellings improve recall across accents.
  // Tokens confirmed from tokens.txt:
  //   ▁HE=49  Y=17  ▁K=164  A=25  I=36  K=54  H=105  E=10
  // "HEY KAI" BPE tokenisation: ▁HE Y ▁K A I
  // Using ▁ (LOWER ONE EIGHTH BLOCK) — the SentencePiece word-boundary char.
  // Keywords encoded to UTF-8 bytes at init time.
  // ▁ = U+2581 LOWER ONE EIGHTH BLOCK = SentencePiece word-boundary char.
  // Built from codepoint only — no literal special char in source to avoid
  // any edit-tool encoding issues.
  static List<int> _buildKeywordsUtf8() {
    final wb = String.fromCharCode(0x2581); // ▁
    final text =
        '${wb}HE Y ${wb}K A I :0.10\n'  // HEY KAI
        '${wb}HE Y ${wb}K I :0.10\n'    // HEY KI  (accent variant)
        '${wb}HE Y ${wb}K Y :0.10\n'    // HEY KY  (accent variant)
        '${wb}K A I :0.10\n';            // KAI alone (fallback)
    print('🔑 [VAS] Keywords string: ${text.replaceAll('\n', ' | ')}');
    return utf8.encode(text);
  }

  // ── Output stream ──────────────────────────────────────────────────────────
  StreamController<String>? _wakeWordCtrl;

  Stream<String> get onWakeWordDetected {
    _wakeWordCtrl ??= StreamController<String>.broadcast();
    return _wakeWordCtrl!.stream;
  }

  // ── Public getters (API-compat with old Porcupine version) ────────────────
  bool get isEnabled => _isEnabled;
  bool get isListening => _isActive;
  bool get isInConversation => false;   // Conversation handled by main UI
  bool get isPorcupineActive => false;  // Legacy compat — always false

  // ── Initialise ─────────────────────────────────────────────────────────────

  /// Call once on app start.  Resumes detection if it was enabled last session.
  Future<void> initialize() async {
    await _trainingService.initialize();

    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('voice_activation_enabled') ?? true;

    if (_isEnabled) await start();
  }

  /// Enable and start keyword detection.
  Future<bool> start() async {
    if (_isActive) return true;

    _isEnabled = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_activation_enabled', true);

    // Model download + KWS init — runs async, detection starts once ready
    _initKwsAsync();
    return true;
  }

  Future<void> _initKwsAsync() async {
    final modelDir = await SherpaModelManager().ensureModels(
      onProgress: (p) =>
          print('⬇️  [VAS] Model download ${(p * 100).toInt()}%'),
    );

    if (modelDir == null) {
      print('❌  [VAS] Could not obtain sherpa models — wake word disabled');
      return;
    }

    // Find the exact tokens we need for "HEY KAI"
    try {
      final tokensFile = '$modelDir/tokens.txt';
      final lines = await File(tokensFile).readAsLines();
      final targets = {'H','E','Y','K','A','I','▁H','▁K','▁HE','▁HEY','▁KA','▁KAI','▁KEY','▁KI','▁KY'};
      print('📋 [VAS] Searching tokens for HEY KAI:');
      for (final l in lines) {
        final token = l.split(' ').first;
        if (targets.contains(token)) print('   FOUND: $l');
      }
      print('📋 [VAS] Total tokens: ${lines.length}');
    } catch (_) {}

    // Write keywords to a UTF-8 file — bypasses FFI string-encoding issues
    final kwFile = File('$modelDir/keywords.txt');
    await kwFile.writeAsBytes(_buildKeywordsUtf8(), flush: true);
    print('📝 [VAS] Keywords file written to ${kwFile.path}');

    _buildKws(modelDir, kwFile.path);
    if (_kwsReady) await _startMicStream();
  }

  void _buildKws(String modelDir, String keywordsFilePath) {
    try {
      // Initialize native bindings once
      if (!_bindingsInit) {
        sherpa.initBindings();
        _bindingsInit = true;
      }

      final config = sherpa.KeywordSpotterConfig(
        // 'feat' and 'model' are the correct field names in sherpa_onnx 1.13.x
        feat: const sherpa.FeatureConfig(
          sampleRate: 16000,
          featureDim: 80,
        ),
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder:
                '$modelDir/encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
            decoder:
                '$modelDir/decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
            joiner:
                '$modelDir/joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
          ),
          tokens: '$modelDir/tokens.txt',
          numThreads: 2,
          provider: 'cpu',
          debug: false,          // bool in 1.13.x
          modelType: 'zipformer2',
        ),
        keywordsFile: keywordsFilePath,
        keywordsScore: 1.0,
        keywordsThreshold: 0.10,
        numTrailingBlanks: 1,
        maxActivePaths: 4,
      );

      // Positional constructor in 1.13.x — NOT a named 'config:' argument
      _kws = sherpa.KeywordSpotter(config);
      _kwsStream = _kws!.createStream();
      _kwsReady = true;
      print('🟢  [VAS] Sherpa keyword spotter ready');
    } catch (e) {
      print('❌  [VAS] Failed to initialise KeywordSpotter: $e');
      _kwsReady = false;
    }
  }

  Future<void> _startMicStream() async {
    if (_isActive) return;

    try {
      _isActive = true;
      _micSub = _micChannel
          .receiveBroadcastStream()
          .listen(
            (data) => _onAudioChunk(data as List<int>),
            onError: (e) => print('❌  [VAS] Mic stream error: $e'),
            cancelOnError: false,
          );

      print('🎙️  [VAS] Mic stream started — listening for "Hey Kai"');
    } catch (e) {
      print('❌  [VAS] Could not start mic stream: $e');
      _isActive = false;
    }
  }

  // ── Audio chunk processing ─────────────────────────────────────────────────

  int _chunkCount = 0;

  void _onAudioChunk(List<int> pcmBytes) {
    if (_isPaused || !_kwsReady || _kws == null || _kwsStream == null) return;

    _chunkCount++;
    if (_chunkCount % 100 == 0) {
      print('🎙️  [VAS] Alive — $_chunkCount chunks processed, kwsReady=$_kwsReady');
    }

    // mic_stream delivers raw PCM16 LE bytes; convert to Float32 [-1.0, 1.0]
    final count = pcmBytes.length ~/ 2;
    if (count == 0) return;

    final samples = Float32List(count);
    for (int i = 0; i < count; i++) {
      final lo = pcmBytes[i * 2] & 0xFF;
      final hi = pcmBytes[i * 2 + 1] & 0xFF;
      final s16 = (hi << 8 | lo).toSigned(16);
      samples[i] = s16 / 32768.0;
    }

    _kwsStream!.acceptWaveform(samples: samples, sampleRate: 16000);

    // Decode while the stream has enough context
    while (_kws!.isReady(_kwsStream!)) {
      _kws!.decode(_kwsStream!);
    }

    final result = _kws!.getResult(_kwsStream!);
    if (result.keyword.trim().isNotEmpty) {
      print('🎯  [VAS] Wake word: "${result.keyword}"');

      // Reset the stream so the same keyword can fire again
      _kws!.reset(_kwsStream!);

      _wakeWordCtrl?.add('hey kai');
    }
  }

  // ── Stop / pause / resume ──────────────────────────────────────────────────

  /// Fully disable and tear down detection.
  Future<void> stop() async {
    _isEnabled = false;
    await _stopMicStream();
    _freeKws();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_activation_enabled', false);
    print('🛑  [VAS] Stopped');
  }

  /// Pause detection and RELEASE the microphone so the recorder can use it.
  /// Cancels the EventChannel subscription → triggers onCancel in Kotlin →
  /// AudioRecord.stop() + release().  Call before starting any recording.
  Future<void> pause() async {
    if (_isPaused) return;
    _isPaused = true;
    await _stopMicStream();   // release AudioRecord so NativeAudioRecorder can open mic
    print('⏸  [VAS] Paused (mic released)');
  }

  /// Re-acquire the mic and resume detection after a short echo-decay buffer.
  void resume() {
    if (!_isPaused) return;
    _isPaused = false;        // clear flag immediately so _startMicStream proceeds
    Future.delayed(const Duration(milliseconds: 1500), () async {
      if (_isPaused) return;  // a second pause() arrived before the delay elapsed
      if (_kwsReady && !_isActive) await _startMicStream();
      print('▶  [VAS] Resumed');
    });
  }

  /// Called when user closes chat — no-op in sherpa version.
  void endConversation() {}

  Future<void> _stopMicStream() async {
    await _micSub?.cancel();
    _micSub = null;
    _isActive = false;
    // Native AudioRecord is released when the EventChannel stream is cancelled
  }

  void _freeKws() {
    try { _kwsStream?.free(); } catch (_) {}
    try { _kws?.free(); } catch (_) {}
    _kwsStream = null;
    _kws = null;
    _kwsReady = false;
  }

  // ── Voice training passthrough (API compat) ───────────────────────────────

  Future<void> teachCorrection(String wrong, String correct) =>
      _trainingService.learnCorrection(wrong, correct);

  Future<void> addWakeWordVariation(String variation) =>
      _trainingService.addWakeWordVariation(variation);

  Future<void> addCommandSynonym(String cmd, String synonym) =>
      _trainingService.addCommandSynonym(cmd, synonym);

  Map<String, dynamic> getTrainingStats() =>
      _trainingService.getTrainingStats();

  // Legacy recording API used by the voice training screen
  Future<String?> startRecording() async {
    try { await _recorder.startRecording(); return 'recording_started'; }
    catch (_) { return null; }
  }

  Future<String?> stopRecording() async {
    try { final f = await _recorder.stopRecording(); return f?.path; }
    catch (_) { return null; }
  }

  Future<String> transcribeAudio(String path) async =>
      await _voiceService.transcribeAudio(path) ?? '';

  Future<void> resetVoiceTraining() => _trainingService.resetTraining();

  // ── Cleanup ────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _stopMicStream();
    _freeKws();
    await _wakeWordCtrl?.close();
  }
}
