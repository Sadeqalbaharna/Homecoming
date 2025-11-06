/// Voice Activation Service
/// Continuously listens for "Hey Kai" wake word
library;

import 'dart:async';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_audio_recorder.dart';
import 'voice_service.dart';
import 'voice_training_service.dart';

/// Voice activation service for "Hey Kai" wake word detection
class VoiceActivationService {
  static final VoiceActivationService _instance = VoiceActivationService._internal();
  factory VoiceActivationService() => _instance;
  VoiceActivationService._internal();

  final NativeAudioRecorder _recorder = NativeAudioRecorder();
  final VoiceService _voiceService = VoiceService();
  final VoiceTrainingService _trainingService = VoiceTrainingService();
  
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
  static const List<String> _defaultWakeWords = [
    'hey kai',
    'hey kay',
    'hey key',
    'a kai',
    'okay kai',
    'ok kai',
  ];
  
  List<String> _wakeWords = [..._defaultWakeWords];

  /// Stream of detected wake words
  Stream<String> get onWakeWordDetected {
    _wakeWordController ??= StreamController<String>.broadcast();
    return _wakeWordController!.stream;
  }

  /// Initialize voice activation
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('voice_activation_enabled') ?? false;
    
    // Initialize voice training service
    await _trainingService.initialize();
    
    // Add custom wake words from training
    final customWakeWords = _trainingService.getCustomWakeWords();
    _wakeWords.addAll(customWakeWords);
    
    if (customWakeWords.isNotEmpty) {
      print('🎤 [VoiceActivation] Loaded ${customWakeWords.length} custom wake words');
    }
    
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
      
      // PRE-WHISPER: Check if audio file has enough content to transcribe
      if (!await _hasValidAudio(recordingFile.path)) {
        print('🔇 [VoiceActivation] Audio too short/quiet - skipping Whisper');
        return;
      }
      
      // Transcribe the chunk
      final rawTranscription = await _voiceService.transcribeAudio(recordingFile.path);
      
      if (rawTranscription == null || rawTranscription.isEmpty) {
        // No speech detected - if in conversation, this counts as silence
        return;
      }
      
      // ADAPTIVE LAYER: Apply learned corrections
      final correctedTranscription = _trainingService.applyPersonalCorrections(rawTranscription);
      final lowerTranscription = correctedTranscription.toLowerCase().trim();
      
      // POST-WHISPER Layer 1: Filter obvious noise/hallucinations (REDUCED FILTERING)
      if (!_isValidSpeechBasic(lowerTranscription)) {
        print('🔇 [VoiceActivation] Filtered obvious noise: "$lowerTranscription"');
        return;
      }
      
      // TEMPORARILY DISABLED - Too aggressive filtering
      // POST-WHISPER Layer 2: Semantic validation - does this make sense?
      // if (!_makesSemanticsense(lowerTranscription)) {
      //   print('🧠 [VoiceActivation] Filtered nonsense/gibberish: "$lowerTranscription"');
      //   // Learn that this pattern should be rejected
      //   await _trainingService.learnSuccess(lowerTranscription, 0.0);
      //   return;
      // }
      
      // TEMPORARILY DISABLED - Confidence filtering too strict
      // CONFIDENCE LAYER: Check personalized confidence threshold
      // if (!_trainingService.meetsUserConfidence(lowerTranscription, null)) {
      //   print('🎯 [VoiceActivation] Below user confidence threshold: "$lowerTranscription"');
      //   return;
      // }
      
      print('🎤 [VoiceActivation] Heard: "$lowerTranscription"');
      
      // If we're in conversation mode, any speech continues the conversation
      if (_isInConversation) {
        print('💬 [VoiceActivation] Conversation continues: "$lowerTranscription"');
        
        // Learn successful transcription
        await _trainingService.learnSuccess(lowerTranscription, 0.9);
        
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
        
        // Learn successful wake word detection
        await _trainingService.learnSuccess(lowerTranscription, 1.0);
        
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

  /// Basic speech validation - only filter obvious noise
  bool _isValidSpeechBasic(String text) {
    // Must have minimum length (at least 2 characters)
    if (text.length < 2) {
      return false;
    }
    
    // Only filter very obvious noise patterns
    final obviousNoisePatterns = [
      'silence',
      '[music]',
      '[silence]',
      '(music)',
      '(silence)',
      '[applause]',
      '(applause)',
      '...',
    ];
    
    // Check if text is exactly an obvious noise pattern
    final cleanText = text.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    for (final pattern in obviousNoisePatterns) {
      final cleanPattern = pattern.replaceAll(RegExp(r'[^\w\s]'), '').trim();
      if (cleanText.toLowerCase() == cleanPattern.toLowerCase()) {
        return false;
      }
    }
    
    return true;
  }

  /// Validate if transcription is actual speech vs noise/silence (ORIGINAL - MORE AGGRESSIVE)
  bool _isValidSpeech(String text) {
    // Must have minimum length (at least 2 characters)
    if (text.length < 2) {
      return false;
    }
    
    // Filter Whisper hallucinations - common phrases it generates from silence
    final hallucinationPatterns = [
      // Common silence artifacts
      'you',
      'thank you',
      'thank you for watching',
      'thanks for watching',
      'thanks',
      'bye',
      'goodbye',
      
      // Video/stream closings (Whisper trained on YouTube)
      'see you next time',
      'see you later',
      'see you soon',
      'until next time',
      'catch you later',
      'take care',
      
      // Subscription prompts (YouTube training data)
      'subscribe',
      'like and subscribe',
      'hit the like button',
      'smash that like button',
      'leave a comment',
      
      // Music/audio detection
      'music',
      'silence',
      '[music]',
      '[silence]',
      '(music)',
      '(silence)',
      '[applause]',
      '(applause)',
      
      // Filler sounds
      'uh',
      'um',
      'hmm',
      'mhm',
      'mm',
      'huh',
      'ah',
      'oh',
      'er',
      
      // Empty/meaningless
      '...',
      'okay',
      'alright',
      'right',
      'yeah',
      'yep',
      'nope',
      'well',
      'so',
      'and',
      'but',
      'the',
      'a',
      'i',
    ];
    
    // Check if text is exactly a hallucination pattern (case insensitive, with/without punctuation)
    final cleanText = text.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    for (final pattern in hallucinationPatterns) {
      final cleanPattern = pattern.replaceAll(RegExp(r'[^\w\s]'), '').trim();
      if (cleanText.toLowerCase() == cleanPattern.toLowerCase()) {
        return false;
      }
    }
    
    // Check if text CONTAINS common hallucination phrases (not just equals)
    final lowerText = text.toLowerCase();
    final containsHallucination = [
      'thank you for watching',
      'thanks for watching',
      'like and subscribe',
      'hit the like button',
      'smash that',
      'see you next time',
      'until next time',
    ];
    
    for (final phrase in containsHallucination) {
      if (lowerText.contains(phrase)) {
        return false;
      }
    }
    
    // Check if text is ONLY punctuation or whitespace
    if (cleanText.isEmpty) {
      return false;
    }
    
    // Must contain at least one alphabetic character
    if (!text.contains(RegExp(r'[a-zA-Z]'))) {
      return false;
    }
    
    // If very short (2-4 chars), must be a real word attempt
    if (cleanText.length <= 4) {
      // Allow common short words that indicate actual speech
      final validShortWords = ['hi', 'hey', 'kai', 'yes', 'no', 'stop', 'go', 'help', 'what', 'why', 'how', 'who', 'when'];
      final hasValidWord = validShortWords.any((word) => cleanText.toLowerCase().contains(word));
      if (!hasValidWord) {
        return false;
      }
    }
    
    // Require minimum word count for very generic text
    final wordCount = cleanText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (wordCount < 2 && cleanText.length < 8) {
      // Single short words are likely noise unless they're wake word related
      if (!cleanText.toLowerCase().contains('kai')) {
        return false;
      }
    }
    
    return true;
  }

  /// PRE-WHISPER: Check if audio file has sufficient content to transcribe
  Future<bool> _hasValidAudio(String audioPath) async {
    try {
      final file = File(audioPath);
      if (!await file.exists()) return false;
      
      // Check file size - very small files are likely silence
      final fileSizeBytes = await file.length();
      const minFileSizeBytes = 1024; // 1KB minimum
      
      if (fileSizeBytes < minFileSizeBytes) {
        return false;
      }
      
      // For now, just use file size. Could add actual audio analysis later
      return true;
      
    } catch (e) {
      return false;
    }
  }

  /// POST-WHISPER: Semantic validation - does this text make sense?
  bool _makesSemanticsense(String text) {
    final cleanText = text.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    
    // Must have reasonable length
    if (cleanText.length < 2) return false;
    
    // Check for common Whisper artifacts that slip through
    final nonsensePatterns = [
      // Repeated characters/sounds
      RegExp(r'^(.)\1{3,}$'), // aaaaa, mmmmm, etc
      RegExp(r'^(..)\1{2,}$'), // lalala, hahaha, etc
      
      // Random letter combinations
      RegExp(r'^[bcdfghjklmnpqrstvwxyz]{3,}$'), // consonant clusters
      RegExp(r'^[aeiou]{3,}$'), // vowel clusters
      
      // Single syllable repeated
      RegExp(r'^(\w{1,3})\s\1\s\1'), // "la la la", "no no no"
      
      // Very fragmented speech
      RegExp(r'^\w\s\w\s\w'), // "a b c", "i o u"
    ];
    
    for (final pattern in nonsensePatterns) {
      if (pattern.hasMatch(cleanText.toLowerCase())) {
        return false;
      }
    }
    
    // Check word patterns - real speech has varied word lengths
    final words = cleanText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    
    if (words.isEmpty) return false;
    
    // Single word validation
    if (words.length == 1) {
      final word = words[0].toLowerCase();
      
      // Very short single words are suspicious unless they're commands
      if (word.length <= 2) {
        final validShortWords = ['hi', 'no', 'go', 'ok', 'on', 'up'];
        return validShortWords.contains(word) || word.contains('kai');
      }
      
      // Very long single "words" are usually gibberish
      if (word.length > 20) {
        return false;
      }
      
      // Check if it's a real word pattern (has vowels and consonants)
      final hasVowels = word.contains(RegExp(r'[aeiou]'));
      final hasConsonants = word.contains(RegExp(r'[bcdfghjklmnpqrstvwxyz]'));
      
      if (!hasVowels || !hasConsonants) {
        return false;
      }
    }
    
    // Multiple words validation
    if (words.length > 1) {
      // Check for excessive repetition
      final uniqueWords = words.toSet();
      if (uniqueWords.length == 1 && words.length > 2) {
        // Same word repeated 3+ times is usually noise
        return false;
      }
      
      // Very short words in sequence are suspicious
      final avgWordLength = words.map((w) => w.length).reduce((a, b) => a + b) / words.length;
      if (avgWordLength < 2.0 && words.length > 3) {
        return false;
      }
    }
    
    // Check for common sense patterns
    // Real speech usually has function words (the, a, is, to, etc.)
    if (cleanText.length > 15 && words.length > 3) {
      final functionWords = ['the', 'a', 'an', 'to', 'of', 'and', 'or', 'but', 'in', 'on', 'at', 'is', 'are', 'was', 'were', 'i', 'you', 'he', 'she', 'it', 'we', 'they'];
      final hasFunctionWords = words.any((word) => functionWords.contains(word.toLowerCase()));
      
      // Long sentences without function words are often gibberish
      if (!hasFunctionWords && !cleanText.toLowerCase().contains('kai')) {
        return false;
      }
    }
    
    return true;
  }

  // Voice Training Interface Methods
  
  /// Teach a correction for a misheard transcription
  Future<void> teachCorrection(String wrongTranscription, String correctTranscription) async {
    await _trainingService.learnCorrection(wrongTranscription, correctTranscription);
  }
  
  /// Add a custom wake word variation
  Future<void> addWakeWordVariation(String variation) async {
    await _trainingService.addWakeWordVariation(variation);
    // Update local wake words list
    if (!_wakeWords.contains(variation.toLowerCase())) {
      _wakeWords.add(variation.toLowerCase());
    }
  }
  
  /// Add a command synonym
  Future<void> addCommandSynonym(String standardCommand, String userSynonym) async {
    await _trainingService.addCommandSynonym(standardCommand, userSynonym);
  }
  
  /// Get training statistics
  Map<String, dynamic> getTrainingStats() {
    return _trainingService.getTrainingStats();
  }
  
  /// Reset all training data
  Future<void> resetVoiceTraining() async {
    await _trainingService.resetTraining();
    // Reset to original wake words
    _wakeWords = List.from(_originalWakeWords);
  }
  
  // Store original wake words for reset
  static const List<String> _originalWakeWords = [
    'hey kai',
    'hey kay',
    'hey key',
    'a kai',
    'okay kai',
    'ok kai',
  ];

  /// Clean up resources
  Future<void> dispose() async {
    _resumeBufferTimer?.cancel();
    await stop();
    await _wakeWordController?.close();
  }
}
