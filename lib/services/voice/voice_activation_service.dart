// voice_activation_service.dart
//
// Wake word detection using Picovoice Porcupine (on-device, zero API cost)
// + Whisper transcription ONLY during active conversation.
//
// Architecture:
//   IDLE state    → Porcupine running on-device (~1% CPU, no API calls)
//   ACTIVE state  → Porcupine paused; Whisper polls for follow-up speech
//
// Setup (one-time):
//   1. Sign up free at console.picovoice.ai
//   2. Copy your Access Key to the app's API Keys screen (key: 'picovoice')
//   3. Go to Wake Word → New Wake Word → type "Hey Kai" → train → Export
//   4. Download hey_kai_android.ppn → put in assets/models/
//   5. Run flutter pub get
//
// Fallback: if no .ppn file or no access key, Porcupine is skipped and
// wake word detection is DISABLED (cheaper than running Whisper 24/7).
// Voice activation can still be triggered manually via the mic button.

library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:porcupine_flutter/porcupine_manager.dart'; // PorcupineManager, BuiltInKeyword
import 'package:porcupine_flutter/porcupine_error.dart';   // PorcupineException
import 'package:shared_preferences/shared_preferences.dart';

import '../core/native_audio_recorder.dart';
import '../../secrets.dart';
import 'voice_service.dart';
import 'voice_training_service.dart';

enum _VasState { idle, active, paused }

class VoiceActivationService {
  static final VoiceActivationService _instance =
      VoiceActivationService._internal();
  factory VoiceActivationService() => _instance;
  VoiceActivationService._internal();

  // ── Dependencies ───────────────────────────────────────────────────────────
  final NativeAudioRecorder _recorder = NativeAudioRecorder();
  final VoiceService _voiceService = VoiceService();
  final VoiceTrainingService _trainingService = VoiceTrainingService();
  final _storage = const FlutterSecureStorage();

  // ── Porcupine ──────────────────────────────────────────────────────────────
  PorcupineManager? _porcupineManager;
  bool _porcupineAvailable = false; // true once init succeeds

  // ── State ──────────────────────────────────────────────────────────────────
  _VasState _state = _VasState.idle;
  bool _isEnabled = false;

  // ── Whisper conversation loop (runs ONLY in active state) ──────────────────
  Timer? _whisperLoopTimer;
  Timer? _conversationTimeoutTimer;
  bool _isPaused = false; // while Kai is speaking TTS

  static const Duration _listenChunk = Duration(seconds: 3);
  static const Duration _listenGap = Duration(milliseconds: 500);
  static const Duration _conversationTimeout = Duration(seconds: 15);
  static const Duration _ttsResumeDelay = Duration(milliseconds: 2000);

  // ── Wake word variants (for Whisper fallback in conversation mode) ─────────
  static const List<String> _wakeWords = [
    'hey kai', 'hey kay', 'hey key', 'a kai', 'okay kai', 'ok kai',
  ];

  // ── Output stream ──────────────────────────────────────────────────────────
  StreamController<String>? _wakeWordController;

  Stream<String> get onWakeWordDetected {
    _wakeWordController ??= StreamController<String>.broadcast();
    return _wakeWordController!.stream;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  bool get isListening => _state != _VasState.idle || _porcupineAvailable;
  bool get isEnabled => _isEnabled;
  bool get isInConversation => _state == _VasState.active;
  bool get isPorcupineActive => _porcupineAvailable;

  /// Call once on app start.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('voice_activation_enabled') ?? false;

    await _trainingService.initialize();

    if (_isEnabled) {
      await start();
    }
  }

  /// Enable wake word detection.
  Future<bool> start() async {
    if (_isEnabled && _porcupineAvailable) return true;

    final permStatus = await Permission.microphone.status;
    if (!permStatus.isGranted) {
      final granted = await _voiceService.requestPermission();
      if (!granted) {
        print('❌ [VAS] Microphone permission denied');
        return false;
      }
    }

    _isEnabled = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_activation_enabled', true);

    await _startPorcupine();
    return true;
  }

  /// Disable all detection.
  Future<void> stop() async {
    _isEnabled = false;
    _state = _VasState.idle;

    await _stopPorcupine();
    _stopWhisperLoop();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_activation_enabled', false);

    print('🛑 [VAS] Stopped');
  }

  /// Pause while Kai is speaking TTS (prevents self-echo).
  void pause() {
    if (_isPaused) return;
    _isPaused = true;
    _porcupineManager?.stop().catchError((_) {});
    print('⏸ [VAS] Paused (TTS playing)');
  }

  /// Resume after TTS finishes, with a 2-second echo buffer.
  void resume() {
    if (!_isPaused) return;
    Future.delayed(_ttsResumeDelay, () {
      if (!_isPaused) return;
      _isPaused = false;
      if (_isEnabled && _state == _VasState.idle) {
        _porcupineManager?.start().catchError((_) {});
      }
      print('▶ [VAS] Resumed');
    });
  }

  /// Called when user closes chat — exit conversation mode.
  void endConversation() {
    _exitConversationMode();
  }

  // ── Porcupine init ─────────────────────────────────────────────────────────

  Future<void> _startPorcupine() async {
    try {
      const _kBuiltIn = kPicovoiceKey;
      final stored = await _storage.read(key: 'picovoice') ?? '';
      final accessKey = stored.isNotEmpty ? stored : _kBuiltIn;
      if (accessKey.isEmpty) {
        print('⚠️ [VAS] No Picovoice access key — wake word disabled. '
            'Add key in API Keys screen.');
        return;
      }

      // Try to load custom "Hey Kai" .ppn model
      final ppnPath = await _extractPpnAsset();

      if (ppnPath == null) {
        print('⚠️ [VAS] No .ppn model found — wake word disabled.\n'
            '  1. Go to console.picovoice.ai → Wake Word → train "Hey Kai"\n'
            '  2. Export for Android → save as assets/models/hey_kai_android.ppn\n'
            '  3. flutter pub get && flutter run');
        return;
      }

      _porcupineManager = await PorcupineManager.fromKeywordPaths(
        accessKey,
        [ppnPath],
        _onWakeWordDetected,
        errorCallback: _onPorcupineError,
      );
      print('🟢 [VAS] Porcupine ready with custom "Hey Kai" model');

      await _porcupineManager!.start();
      _porcupineAvailable = true;
      _state = _VasState.idle;
    } on PorcupineException catch (e) {
      print('❌ [VAS] Porcupine init failed: $e');
      _porcupineAvailable = false;
    } catch (e) {
      print('❌ [VAS] Porcupine unexpected error: $e');
      _porcupineAvailable = false;
    }
  }

  Future<void> _stopPorcupine() async {
    try {
      await _porcupineManager?.stop();
      await _porcupineManager?.delete();
    } catch (_) {}
    _porcupineManager = null;
    _porcupineAvailable = false;
  }

  /// Extract .ppn from Flutter assets to a temp file Porcupine can read.
  /// Returns null if asset doesn't exist yet.
  Future<String?> _extractPpnAsset() async {
    final assetName = Platform.isAndroid
        ? 'assets/models/hey_kai_android.ppn'
        : 'assets/models/hey_kai_ios.ppn';

    try {
      final data = await rootBundle.load(assetName);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/hey_kai.ppn');
      await file.writeAsBytes(data.buffer.asUint8List());
      return file.path;
    } catch (_) {
      return null; // Asset not yet added
    }
  }

  // ── Porcupine callbacks ────────────────────────────────────────────────────

  void _onWakeWordDetected(int keywordIndex) {
    if (_isPaused) return;
    print('🎯 [VAS] Wake word detected! Entering conversation mode.');
    _enterConversationMode();
    // Emit the wake word so the UI can react immediately
    _wakeWordController?.add('hey kai');
  }

  void _onPorcupineError(PorcupineException e) {
    print('❌ [VAS] Porcupine runtime error: $e');
  }

  // ── Conversation mode (Whisper loop) ──────────────────────────────────────

  void _enterConversationMode() {
    if (_state == _VasState.active) return;
    _state = _VasState.active;

    // Porcupine doesn't need to run while we're actively capturing Whisper
    _porcupineManager?.stop().catchError((_) {});

    _startWhisperLoop();
    _resetConversationTimeout();
    print('🗣 [VAS] Conversation mode — Whisper active');
  }

  void _exitConversationMode() {
    if (_state != _VasState.active) return;
    _state = _VasState.idle;

    _stopWhisperLoop();
    _conversationTimeoutTimer?.cancel();

    // Resume Porcupine
    if (_isEnabled && _porcupineAvailable && !_isPaused) {
      _porcupineManager?.start().catchError((_) {});
    }
    print('💤 [VAS] Conversation ended — Porcupine resumed');
  }

  void _startWhisperLoop() {
    _stopWhisperLoop();
    _whisperLoopTimer = Timer.periodic(
      _listenChunk + _listenGap,
      (_) => _captureAndTranscribe(),
    );
    // First chunk immediately
    _captureAndTranscribe();
  }

  void _stopWhisperLoop() {
    _whisperLoopTimer?.cancel();
    _whisperLoopTimer = null;
  }

  void _resetConversationTimeout() {
    _conversationTimeoutTimer?.cancel();
    _conversationTimeoutTimer =
        Timer(_conversationTimeout, _exitConversationMode);
  }

  Future<void> _captureAndTranscribe() async {
    if (_state != _VasState.active || _isPaused) return;

    try {
      await _recorder.startRecording();
      await Future.delayed(_listenChunk);
      final file = await _recorder.stopRecording();

      if (file == null || !await file.exists()) return;

      // Skip tiny/silent files
      final size = await file.length();
      if (size < 2048 || size > 1024 * 1024) return;

      final raw = await _voiceService.transcribeAudio(file.path);
      if (raw == null || raw.trim().isEmpty) return;

      final corrected = _trainingService.applyPersonalCorrections(raw);
      final lower = corrected.toLowerCase().trim();

      // Basic noise filter
      if (!_isValidSpeech(lower)) return;

      print('🎤 [VAS] Transcribed: "$lower"');

      // Reset timeout since user spoke
      _resetConversationTimeout();

      _wakeWordController?.add(lower);
    } catch (e) {
      print('❌ [VAS] Whisper capture error: $e');
    }
  }

  bool _isValidSpeech(String text) {
    if (text.length < 2) return false;
    const noise = ['silence', '[music]', '[silence]', '(music)', '...'];
    final clean = text.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    if (noise.any((n) => clean == n.replaceAll(RegExp(r'[^\w\s]'), ''))) {
      return false;
    }
    if (!_trainingService.matchesVoiceProfile(text, null)) return false;
    return true;
  }

  // ── Voice training passthrough ─────────────────────────────────────────────

  Future<void> teachCorrection(String wrong, String correct) async {
    await _trainingService.learnCorrection(wrong, correct);
  }

  Future<void> addWakeWordVariation(String variation) async {
    await _trainingService.addWakeWordVariation(variation);
  }

  Future<void> addCommandSynonym(String cmd, String synonym) async {
    await _trainingService.addCommandSynonym(cmd, synonym);
  }

  Map<String, dynamic> getTrainingStats() => _trainingService.getTrainingStats();

  // Legacy recording API (used by voice training screen)
  Future<String?> startRecording() async {
    try {
      await _recorder.startRecording();
      return 'recording_started';
    } catch (e) {
      return null;
    }
  }

  Future<String?> stopRecording() async {
    try {
      final f = await _recorder.stopRecording();
      return f?.path;
    } catch (e) {
      return null;
    }
  }

  Future<String> transcribeAudio(String path) async {
    return await _voiceService.transcribeAudio(path) ?? '';
  }

  Future<void> resetVoiceTraining() async {
    await _trainingService.resetTraining();
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    _stopWhisperLoop();
    _conversationTimeoutTimer?.cancel();
    await _stopPorcupine();
    await _wakeWordController?.close();
  }
}
