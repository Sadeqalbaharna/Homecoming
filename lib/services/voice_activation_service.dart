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
      
      // POST-WHISPER Layer 1: Filter obvious noise/hallucinations 
      if (!_isValidSpeechBasic(lowerTranscription)) {
        print('🔇 [VoiceActivation] Filtered obvious noise: "$lowerTranscription"');
        return;
      }
      
      // POST-WHISPER Layer 2: Intelligent voice filtering
      if (!await _isDirectUserSpeech(lowerTranscription, recordingFile)) {
        print('🎭 [VoiceActivation] Filtered indirect/ambient audio: "$lowerTranscription"');
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
        
        // Send the complete transcription including the wake word
        // This ensures Kai receives the full message including "hey kai"
        _wakeWordController?.add(lowerTranscription.trim());
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
    
    // Check if this matches the user's trained voice profile
    if (!_trainingService.matchesVoiceProfile(text, null)) {
      print('🔍 [VoiceActivation] Rejected: Voice doesn\'t match trained profile');
      return false;
    }
    
    return true;
  }

  /// Intelligent filtering to distinguish direct user speech from ambient audio
  Future<bool> _isDirectUserSpeech(String transcription, File audioFile) async {
    // Skip filtering for wake words - we want to catch all wake word attempts
    final containsWakeWord = _wakeWords.any((wakeWord) => 
      transcription.contains(wakeWord)
    );
    if (containsWakeWord) {
      return true; // Always allow wake words through
    }
    
    // Check for patterns that suggest ambient/indirect speech
    if (await _isAmbientAudio(transcription, audioFile)) {
      return false;
    }
    
    // Check for TV/media content patterns
    if (_isMediaContent(transcription)) {
      return false;
    }
    
    // Check for conversational context (if in conversation, be more permissive)
    if (_isInConversation) {
      return _isLikelyDirectResponse(transcription);
    }
    
    return true; // Allow through by default
  }

  /// Detect if audio is likely ambient/background rather than direct speech
  Future<bool> _isAmbientAudio(String transcription, File audioFile) async {
    // Get audio file size for quality assessment
    final fileSizeBytes = await audioFile.length();
    
    // Very large files might be picking up extended ambient audio
    if (fileSizeBytes > 100000) { // 100KB+ suggests longer background audio
      // Check for patterns that suggest background conversation
      final ambientPatterns = [
        'in the', 'at the', 'on the', 'from the',
        'there was', 'there is', 'there are',
        'and then', 'so then', 'after that',
        'i think', 'i believe', 'i feel',
        'you know', 'you see', 'you understand',
      ];
      
      final lowerText = transcription.toLowerCase();
      final hasAmbientPattern = ambientPatterns.any((pattern) => 
        lowerText.contains(pattern)
      );
      
      if (hasAmbientPattern) {
        return true; // Likely ambient conversation
      }
    }
    
    // Check for fragmentary speech (often from distant audio)
    final words = transcription.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length >= 4) {
      // Long transcriptions from ambient audio often have incomplete thoughts
      final hasCompleteThought = 
        transcription.contains('?') || // Question
        transcription.contains('!') || // Exclamation  
        transcription.endsWith('.') || // Statement
        transcription.contains(' and ') || // Connected thoughts
        transcription.contains(' so ') ||
        transcription.contains(' but ') ||
        transcription.contains(' because ');
        
      if (!hasCompleteThought && words.length > 6) {
        return true; // Long fragmented speech is likely ambient
      }
    }
    
    return false;
  }

  /// Detect TV, radio, or streaming media content patterns
  bool _isMediaContent(String transcription) {
    final lowerText = transcription.toLowerCase();
    
    // Common media/entertainment phrases
    final mediaPatterns = [
      // TV show patterns
      'previously on', 'next time on', 'coming up', 'stay tuned',
      'we\'ll be right back', 'after the break', 'this episode',
      
      // Movie/show dialogue patterns  
      'fade in', 'fade out', 'cut to', 'voice over',
      'interior', 'exterior', 'day', 'night',
      
      // News patterns
      'breaking news', 'this just in', 'reporting live',
      'back to you', 'more on this story', 'developing story',
      
      // Music/entertainment
      'ladies and gentlemen', 'thank you for listening',
      'don\'t forget to subscribe', 'like this video',
      'hit that notification bell', 'check out our',
      
      // Streaming/gaming
      'what\'s up guys', 'hope you enjoyed', 'let me know in the comments',
      'smash that like button', 'ring that bell',
      
      // Commercial patterns
      'call now', 'limited time offer', 'act fast',
      'but wait there\'s more', 'satisfaction guaranteed',
    ];
    
    for (final pattern in mediaPatterns) {
      if (lowerText.contains(pattern)) {
        return true;
      }
    }
    
    // Check for movie/show quotes (often start with character names)
    // Pattern: "Character: dialogue" or "Character said"
    if (RegExp(r'\b[A-Z][a-z]+\s*:\s*').hasMatch(transcription) ||
        lowerText.contains(' said ') ||
        lowerText.contains(' says ')) {
      return true;
    }
    
    return false;
  }

  /// Check if transcription is likely a direct response in conversation
  bool _isLikelyDirectResponse(String transcription) {
    final lowerText = transcription.toLowerCase();
    
    // Direct response patterns
    final responsePatterns = [
      // Affirmative responses
      'yes', 'yeah', 'yep', 'sure', 'okay', 'ok', 'alright',
      
      // Negative responses  
      'no', 'nope', 'not really', 'i don\'t think so',
      
      // Question responses
      'what', 'when', 'where', 'why', 'how', 'who',
      
      // Commands
      'stop', 'pause', 'continue', 'help', 'repeat',
      'turn on', 'turn off', 'set', 'play', 'show',
      
      // Polite conversation
      'please', 'thank you', 'thanks', 'excuse me',
      
      // Direct address (to Kai)
      'kai', 'you', 'your', 'can you', 'would you', 'will you',
    ];
    
    // If text contains any response pattern, it's likely direct
    for (final pattern in responsePatterns) {
      if (lowerText.contains(pattern)) {
        return true;
      }
    }
    
    // Short responses are more likely direct
    final wordCount = transcription.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (wordCount <= 3) {
      return true; // Short phrases are usually direct
    }
    
    return false; // Longer text without response patterns might be ambient
  }



  /// PRE-WHISPER: Advanced voice activity detection and quality analysis
  Future<bool> _hasValidAudio(String audioPath) async {
    try {
      final file = File(audioPath);
      if (!await file.exists()) return false;
      
      // Check file size - very small files are likely silence
      final fileSizeBytes = await file.length();
      const minFileSizeBytes = 2048; // 2KB minimum for voice
      const maxFileSizeBytes = 1024 * 1024; // 1MB maximum (prevent huge files)
      
      if (fileSizeBytes < minFileSizeBytes) {
        print('🔇 [VoiceActivation] Audio too small: ${fileSizeBytes} bytes');
        return false;
      }
      
      if (fileSizeBytes > maxFileSizeBytes) {
        print('⚠️ [VoiceActivation] Audio too large: ${fileSizeBytes} bytes');
        return false;
      }
      
      // Check if file has reasonable audio characteristics for voice
      // Files that are exactly the same size repeatedly might be silence
      if (await _isProbablySilence(fileSizeBytes)) {
        print('🔇 [VoiceActivation] Detected silence pattern');
        return false;
      }
      
      return true;
      
    } catch (e) {
      print('❌ [VoiceActivation] Audio validation error: $e');
      return false;
    }
  }

  /// Track recent file sizes to detect silence patterns
  final List<int> _recentFileSizes = [];
  
  /// Check if audio file is probably just silence/noise
  Future<bool> _isProbablySilence(int fileSize) async {
    _recentFileSizes.add(fileSize);
    
    // Keep only last 5 recordings for pattern analysis
    if (_recentFileSizes.length > 5) {
      _recentFileSizes.removeAt(0);
    }
    
    // If we have multiple recordings of exactly the same size, likely silence
    if (_recentFileSizes.length >= 3) {
      final uniqueSizes = _recentFileSizes.toSet();
      if (uniqueSizes.length == 1) {
        // All recordings are identical size - probably silence
        return true;
      }
      
      // Check for very similar sizes (within 100 bytes) - also likely silence
      final minSize = _recentFileSizes.reduce((a, b) => a < b ? a : b);
      final maxSize = _recentFileSizes.reduce((a, b) => a > b ? a : b);
      if (maxSize - minSize < 100) {
        return true;
      }
    }
    
    return false;
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
  
  /// Start recording audio for voice training
  Future<String?> startRecording() async {
    try {
      await _recorder.startRecording();
      print('🎤 [VoiceActivation] Training recording started');
      return 'recording_started'; // Return a placeholder path
    } catch (e) {
      print('❌ [VoiceActivation] Error starting training recording: $e');
      return null;
    }
  }

  /// Stop recording audio for voice training
  Future<String?> stopRecording() async {
    try {
      final audioFile = await _recorder.stopRecording();
      final audioPath = audioFile?.path;
      print('🛑 [VoiceActivation] Training recording stopped: $audioPath');
      return audioPath;
    } catch (e) {
      print('❌ [VoiceActivation] Error stopping training recording: $e');
      return null;
    }
  }

  /// Transcribe audio file to text for voice training
  Future<String> transcribeAudio(String audioPath) async {
    try {
      final transcription = await _voiceService.transcribeAudio(audioPath);
      print('📝 [VoiceActivation] Training transcription: "$transcription"');
      return transcription ?? '';
    } catch (e) {
      print('❌ [VoiceActivation] Error transcribing training audio: $e');
      return '';
    }
  }

  /// Reset voice training data
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
