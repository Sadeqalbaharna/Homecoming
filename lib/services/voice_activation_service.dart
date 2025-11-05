/// Voice Activation Service
/// Continuously listens for "Hey Kai" wake word
library;

import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_audio_recorder.dart';
import 'voice_service.dart';

/// Voice activation service for "Hey Kai" wake word detection
class VoiceActivationService {
  static final VoiceActivationService _instance = VoiceActivationService._internal();
  factory VoiceActivationService() => _instance;
  VoiceActivationService._internal();

  final NativeAudioRecorder _recorder = NativeAudioRecorder();
  final VoiceService _voiceService = VoiceService();
  
  bool _isListening = false;
  bool _isEnabled = false;
  bool _isInConversation = false; // Track if in active conversation
  bool _isPaused = false; // Pause while Kai is speaking
  DateTime? _lastPauseTime; // Track when we last paused
  Timer? _listeningTimer;
  Timer? _conversationTimer; // Timer to end conversation after silence
  Timer? _resumeBufferTimer; // Delay resume to prevent catching TTS tail
  StreamController<String>? _wakeWordController;

  // Configuration
  static const Duration _listenDuration = Duration(seconds: 3); // Listen in 3-second chunks
  static const Duration _pauseBetweenListens = Duration(milliseconds: 500);
  static const Duration _conversationTimeout = Duration(seconds: 15); // End conversation after 15s of silence
  static const Duration _resumeBufferDelay = Duration(milliseconds: 2000); // Wait 2s after TTS stops before resuming
  static const Duration _minPauseDuration = Duration(milliseconds: 500); // Minimum pause duration
  static const List<String> _wakeWords = [
    'hey kai',
    'hey kay',
    'hey key',
    'a kai',
    'okay kai',
    'ok kai',
  ];

  /// Stream of detected wake words
  Stream<String> get onWakeWordDetected {
    _wakeWordController ??= StreamController<String>.broadcast();
    return _wakeWordController!.stream;
  }

  /// Initialize voice activation
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('voice_activation_enabled') ?? false;
    
    if (_isEnabled) {
      await start();
    }
  }

  /// Start continuous listening for wake word
  Future<bool> start() async {
    if (_isListening) {
      print('🎤 [VoiceActivation] Already listening');
      return true;
    }

    // Check microphone permission
    final permStatus = await Permission.microphone.status;
    if (!permStatus.isGranted) {
      print('🎤 [VoiceActivation] Requesting microphone permission...');
      final granted = await _voiceService.requestPermission();
      if (!granted) {
        print('❌ [VoiceActivation] Microphone permission denied');
        return false;
      }
    }

    _isListening = true;
    _isEnabled = true;
    
    // Save state
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_activation_enabled', true);
    
    print('✅ [VoiceActivation] Started listening for "Hey Kai"');
    
    // Start the listening loop
    _startListeningLoop();
    
    return true;
  }

  /// Stop continuous listening
  Future<void> stop() async {
    if (!_isListening) return;
    
    _isListening = false;
    _isEnabled = false;
    _listeningTimer?.cancel();
    _conversationTimer?.cancel();
    _isInConversation = false;
    
    // Save state
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_activation_enabled', false);
    
    print('🛑 [VoiceActivation] Stopped listening');
  }

  /// Main listening loop
  void _startListeningLoop() {
    if (!_isListening) return;
    
    _listeningTimer?.cancel();
    _listeningTimer = Timer.periodic(_listenDuration + _pauseBetweenListens, (_) async {
      if (!_isListening) {
        _listeningTimer?.cancel();
        return;
      }
      
      await _listenForWakeWord();
    });
    
    // Start first listen immediately
    _listenForWakeWord();
  }

  /// Listen for a single chunk and check for wake word OR conversation input
  Future<void> _listenForWakeWord() async {
    if (!_isListening || _isPaused) return; // Skip if paused
    
    try {
      // Record a short audio chunk
      await _recorder.startRecording();
      await Future.delayed(_listenDuration);
      final recordingFile = await _recorder.stopRecording();
      
      if (recordingFile == null || !await recordingFile.exists()) {
        print('⚠️ [VoiceActivation] No recording file');
        return;
      }
      
      // Transcribe the chunk
      final transcription = await _voiceService.transcribeAudio(recordingFile.path);
      
      if (transcription == null || transcription.isEmpty) {
        // No speech detected - if in conversation, this counts as silence
        return;
      }
      
      final lowerTranscription = transcription.toLowerCase().trim();
      print('🎤 [VoiceActivation] Heard: "$lowerTranscription"');
      
      // If we're in conversation mode, any speech continues the conversation
      if (_isInConversation) {
        print('💬 [VoiceActivation] Conversation continues: "$lowerTranscription"');
        
        // Reset conversation timer
        _resetConversationTimer();
        
        // Send the message
        _wakeWordController?.add(lowerTranscription);
        
        return;
      }
      
      // Not in conversation - check for wake word
      final wakeWordDetected = _wakeWords.any((wakeWord) => 
        lowerTranscription.contains(wakeWord)
      );
      
      if (wakeWordDetected) {
        print('🎯 [VoiceActivation] WAKE WORD DETECTED!');
        
        // Enter conversation mode
        _enterConversationMode();
        
        // Extract any text after the wake word
        String? followUpText;
        for (final wakeWord in _wakeWords) {
          final index = lowerTranscription.indexOf(wakeWord);
          if (index >= 0) {
            final afterWakeWord = lowerTranscription
                .substring(index + wakeWord.length)
                .trim();
            if (afterWakeWord.isNotEmpty) {
              followUpText = afterWakeWord;
              break;
            }
          }
        }
        
        // Notify listeners
        _wakeWordController?.add(followUpText ?? '');
      }
      
    } catch (e) {
      print('❌ [VoiceActivation] Error during listen cycle: $e');
      // Continue listening despite errors
    }
  }

  /// Enter conversation mode - keep listening for follow-up without wake word
  void _enterConversationMode() {
    if (_isInConversation) return;
    
    _isInConversation = true;
    print('🗣️ [VoiceActivation] Entered conversation mode');
    
    // Start conversation timer
    _resetConversationTimer();
  }

  /// Reset conversation timer (called when user speaks)
  void _resetConversationTimer() {
    _conversationTimer?.cancel();
    _conversationTimer = Timer(_conversationTimeout, () {
      _exitConversationMode();
    });
  }

  /// Exit conversation mode - return to wake word only
  void _exitConversationMode() {
    if (!_isInConversation) return;
    
    _isInConversation = false;
    _conversationTimer?.cancel();
    print('💤 [VoiceActivation] Exited conversation mode (idle timeout)');
  }

  /// Manually end conversation (can be called when user closes interaction)
  void endConversation() {
    _exitConversationMode();
  }

  /// Enable/disable voice activation
  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      await start();
    } else {
      await stop();
    }
  }

  /// Check if currently listening
  bool get isListening => _isListening;
  
  /// Check if enabled (persisted setting)
  bool get isEnabled => _isEnabled;
  
  /// Check if in active conversation mode
  bool get isInConversation => _isInConversation;

  /// Pause listening temporarily (e.g., while Kai is speaking)
  void pause() {
    if (_isPaused) return;
    
    _isPaused = true;
    _lastPauseTime = DateTime.now();
    
    // Cancel any pending resume
    _resumeBufferTimer?.cancel();
    
    print('⏸️ [VoiceActivation] Paused listening (Kai speaking)');
  }

  /// Resume listening after pause with buffer delay
  void resume() {
    if (!_isPaused) return;
    
    final now = DateTime.now();
    
    // Calculate how long we've been paused
    final pauseDuration = _lastPauseTime != null 
        ? now.difference(_lastPauseTime!)
        : Duration.zero;
    
    // If we paused very recently, enforce minimum pause duration
    if (pauseDuration < _minPauseDuration) {
      print('⏱️ [VoiceActivation] Pause too short (${pauseDuration.inMilliseconds}ms), waiting ${_minPauseDuration.inMilliseconds}ms total');
      _resumeBufferTimer?.cancel();
      _resumeBufferTimer = Timer(_minPauseDuration - pauseDuration, _actuallyResume);
      return;
    }
    
    // Add buffer delay before resuming to avoid catching TTS tail/echo
    print('⏱️ [VoiceActivation] Scheduling resume in ${_resumeBufferDelay.inMilliseconds}ms (buffer delay)');
    _resumeBufferTimer?.cancel();
    _resumeBufferTimer = Timer(_resumeBufferDelay, _actuallyResume);
  }
  
  /// Actually resume listening (called after buffer delay)
  void _actuallyResume() {
    if (!_isPaused) return;
    
    _isPaused = false;
    _resumeBufferTimer = null;
    
    // Calculate total pause time
    if (_lastPauseTime != null) {
      final totalPauseDuration = DateTime.now().difference(_lastPauseTime!);
      print('▶️ [VoiceActivation] Resumed listening (paused for ${totalPauseDuration.inMilliseconds}ms)');
    } else {
      print('▶️ [VoiceActivation] Resumed listening');
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    _resumeBufferTimer?.cancel();
    await stop();
    await _wakeWordController?.close();
  }
}
