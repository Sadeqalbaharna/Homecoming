/// Adaptive Voice Training Service
/// Learns user's speech patterns and improves transcription accuracy over time
library;

import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class VoiceTrainingService {
  static final VoiceTrainingService _instance = VoiceTrainingService._internal();
  factory VoiceTrainingService() => _instance;
  VoiceTrainingService._internal();

  // User's personal corrections dictionary
  Map<String, String> _personalCorrections = {};
  
  // Confidence scoring history per phrase pattern
  Map<String, List<double>> _confidenceHistory = {};
  
  // User's adaptive confidence threshold
  double _userConfidenceThreshold = 0.4; // Start more permissive to fix gibberish issue
  
  // Environmental noise patterns
  Map<String, int> _noisePatterns = {};
  
  // Wake word variations learned from user
  List<String> _customWakeWords = [];
  
  // Command synonyms learned from user
  Map<String, List<String>> _commandSynonyms = {};
  
  // Voice training data for advanced recognition
  List<Map<String, dynamic>> _voiceSamples = [];
  Map<String, dynamic>? _voiceProfile;
  
  bool _isInitialized = false;

  /// Initialize the training service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _loadUserProfile();
    _isInitialized = true;
    
    print('🧠 [VoiceTraining] Initialized with ${_personalCorrections.length} corrections');
    print('🎯 [VoiceTraining] User confidence threshold: ${(_userConfidenceThreshold * 100).toInt()}%');
  }

  /// Apply learned corrections to transcription
  String applyPersonalCorrections(String rawTranscription) {
    if (!_isInitialized) return rawTranscription;
    
    String corrected = rawTranscription.toLowerCase().trim();
    int correctionCount = 0;
    
    // Apply direct word/phrase corrections
    for (final entry in _personalCorrections.entries) {
      if (corrected.contains(entry.key)) {
        corrected = corrected.replaceAll(entry.key, entry.value);
        correctionCount++;
      }
    }
    
    // Apply wake word corrections
    for (final customWakeWord in _customWakeWords) {
      if (corrected.contains(customWakeWord)) {
        // Normalize to standard wake word for processing
        corrected = corrected.replaceAll(customWakeWord, 'hey kai');
        correctionCount++;
      }
    }
    
    // Apply command synonym corrections
    for (final entry in _commandSynonyms.entries) {
      final standardCommand = entry.key;
      final synonyms = entry.value;
      
      for (final synonym in synonyms) {
        if (corrected.contains(synonym)) {
          corrected = corrected.replaceAll(synonym, standardCommand);
          correctionCount++;
        }
      }
    }
    
    if (correctionCount > 0) {
      print('✏️ [VoiceTraining] Applied $correctionCount corrections: "$rawTranscription" → "$corrected"');
    }
    
    return corrected;
  }

  /// Check if transcription meets user's personalized confidence threshold
  bool meetsUserConfidence(String text, double? whisperConfidence) {
    if (!_isInitialized) return true;
    
    // Calculate personalized confidence based on user's history
    final personalConfidence = _calculatePersonalConfidence(text, whisperConfidence);
    
    final passes = personalConfidence >= _userConfidenceThreshold;
    
    if (!passes) {
      print('🎯 [VoiceTraining] Low confidence: ${(personalConfidence * 100).toInt()}% < ${(_userConfidenceThreshold * 100).toInt()}%');
    }
    
    return passes;
  }

  /// Learn from a user correction
  Future<void> learnCorrection(String wrongTranscription, String correctText) async {
    if (!_isInitialized) await initialize();
    
    final wrongKey = wrongTranscription.toLowerCase().trim();
    final correctValue = correctText.toLowerCase().trim();
    
    // Store the correction
    _personalCorrections[wrongKey] = correctValue;
    
    print('📚 [VoiceTraining] Learned correction: "$wrongKey" → "$correctValue"');
    
    // Update confidence threshold based on this correction
    _adjustConfidenceThreshold(false); // This was a mistake, lower threshold
    
    // Save to persistent storage
    await _saveUserProfile();
  }

  /// Learn from a successful transcription
  Future<void> learnSuccess(String transcription, double? confidence) async {
    if (!_isInitialized) await initialize();
    
    // Record successful confidence score
    _recordConfidenceHistory(transcription, confidence ?? 0.8);
    
    // This was successful, potentially raise threshold
    _adjustConfidenceThreshold(true);
    
    // Save periodically
    if (Random().nextDouble() < 0.1) { // 10% chance to save
      await _saveUserProfile();
    }
  }

  /// Add custom wake word variation
  Future<void> addWakeWordVariation(String variation) async {
    if (!_isInitialized) await initialize();
    
    final normalizedVariation = variation.toLowerCase().trim();
    
    if (!_customWakeWords.contains(normalizedVariation)) {
      _customWakeWords.add(normalizedVariation);
      print('🎤 [VoiceTraining] Added wake word variation: "$normalizedVariation"');
      await _saveUserProfile();
    }
  }

  /// Add command synonym
  Future<void> addCommandSynonym(String standardCommand, String userSynonym) async {
    if (!_isInitialized) await initialize();
    
    final command = standardCommand.toLowerCase().trim();
    final synonym = userSynonym.toLowerCase().trim();
    
    if (!_commandSynonyms.containsKey(command)) {
      _commandSynonyms[command] = [];
    }
    
    if (!_commandSynonyms[command]!.contains(synonym)) {
      _commandSynonyms[command]!.add(synonym);
      print('🗣️ [VoiceTraining] Added command synonym: "$synonym" → "$command"');
      await _saveUserProfile();
    }
  }

  /// Get user's custom wake words
  List<String> getCustomWakeWords() {
    return List.from(_customWakeWords);
  }

  /// Get training statistics
  Map<String, dynamic> getTrainingStats() {
    return {
      'corrections_learned': _personalCorrections.length,
      'confidence_threshold': _userConfidenceThreshold,
      'custom_wake_words': _customWakeWords.length,
      'command_synonyms': _commandSynonyms.length,
      'confidence_samples': _confidenceHistory.values
          .map((samples) => samples.length)
          .fold(0, (a, b) => a + b),
    };
  }

  /// Add voice sample during training
  Future<void> addVoiceSample(String audioPath, String transcription, int phase, double similarity) async {
    if (!_isInitialized) await initialize();
    
    final sample = {
      'audioPath': audioPath,
      'transcription': transcription,
      'phase': phase,
      'similarity': similarity,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    
    _voiceSamples.add(sample);
    print('🎤 [VoiceTraining] Added voice sample: Phase $phase, ${(similarity * 100).toInt()}% match');
    
    // Auto-save after each sample
    await _saveUserProfile();
  }

  /// Build voice profile from collected samples
  Future<void> buildVoiceProfile() async {
    if (_voiceSamples.isEmpty) {
      print('⚠️ [VoiceTraining] No samples to build profile from');
      return;
    }
    
    // Calculate average confidence per phase
    final Map<int, List<double>> phaseConfidences = {};
    for (final sample in _voiceSamples) {
      final phase = sample['phase'] as int;
      final similarity = sample['similarity'] as double;
      
      if (!phaseConfidences.containsKey(phase)) {
        phaseConfidences[phase] = [];
      }
      phaseConfidences[phase]!.add(similarity);
    }
    
    // Build profile
    _voiceProfile = {
      'sampleCount': _voiceSamples.length,
      'phaseConfidences': phaseConfidences.map((phase, confidences) => 
        MapEntry(phase.toString(), confidences.reduce((a, b) => a + b) / confidences.length)),
      'overallConfidence': _voiceSamples
          .map((s) => s['similarity'] as double)
          .reduce((a, b) => a + b) / _voiceSamples.length,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    
    print('🧠 [VoiceTraining] Voice profile built with ${(_voiceProfile!['overallConfidence'] * 100).toInt()}% confidence');
    await _saveUserProfile();
  }

  /// Finalize training and return profile
  Future<Map<String, dynamic>> finalizeTraining() async {
    if (_voiceProfile == null) {
      await buildVoiceProfile();
    }
    
    // Update user confidence threshold based on training results
    if (_voiceProfile != null) {
      final overallConfidence = _voiceProfile!['overallConfidence'] as double;
      _userConfidenceThreshold = max(0.6, overallConfidence * 0.8);
    }
    
    await _saveUserProfile();
    
    return _voiceProfile ?? {
      'confidence': 0.5,
      'sampleCount': 0,
    };
  }

  /// Get current voice profile
  Future<Map<String, dynamic>?> getCurrentProfile() async {
    if (!_isInitialized) await initialize();
    return _voiceProfile;
  }

  /// Clear voice profile and samples
  Future<void> clearProfile() async {
    _voiceSamples.clear();
    _voiceProfile = null;
    _userConfidenceThreshold = 0.75;
    await _saveUserProfile();
    print('🔄 [VoiceTraining] Voice profile cleared');
  }

  /// Check if user voice matches trained profile
  bool matchesVoiceProfile(String transcription, double? confidence) {
    if (_voiceProfile == null) return true; // No profile yet, accept all
    
    final profileConfidence = _voiceProfile!['overallConfidence'] as double;
    final inputConfidence = confidence ?? 0.5;
    
    // Compare with some tolerance
    final confidenceDiff = (profileConfidence - inputConfidence).abs();
    final matches = confidenceDiff < 0.3; // Allow 30% variance
    
    if (!matches) {
      print('🔍 [VoiceTraining] Voice mismatch: Profile ${(profileConfidence * 100).toInt()}%, Input ${(inputConfidence * 100).toInt()}%');
    }
    
    return matches;
  }

  /// Reset all learning data
  Future<void> resetTraining() async {
    _personalCorrections.clear();
    _confidenceHistory.clear();
    _customWakeWords.clear();
    _commandSynonyms.clear();
    _voiceSamples.clear();
    _voiceProfile = null;
    _userConfidenceThreshold = 0.75;
    
    await _saveUserProfile();
    print('🔄 [VoiceTraining] Training data reset');
  }

  /// Calculate personalized confidence score
  double _calculatePersonalConfidence(String text, double? whisperConfidence) {
    double confidence = whisperConfidence ?? 0.5;
    
    // Boost confidence if this text pattern has been successful before
    final pattern = _getTextPattern(text);
    if (_confidenceHistory.containsKey(pattern)) {
      final history = _confidenceHistory[pattern]!;
      if (history.isNotEmpty) {
        final avgHistorical = history.reduce((a, b) => a + b) / history.length;
        // Weighted average: 70% Whisper, 30% historical
        confidence = (confidence * 0.7) + (avgHistorical * 0.3);
      }
    }
    
    // Boost confidence if text contains learned corrections
    for (final correction in _personalCorrections.values) {
      if (text.toLowerCase().contains(correction)) {
        confidence += 0.1; // Boost confidence for learned patterns
        break;
      }
    }
    
    // Boost confidence for custom wake words
    for (final wakeWord in _customWakeWords) {
      if (text.toLowerCase().contains(wakeWord)) {
        confidence += 0.15;
        break;
      }
    }
    
    return min(1.0, confidence); // Cap at 100%
  }

  /// Record confidence for a text pattern
  void _recordConfidenceHistory(String text, double confidence) {
    final pattern = _getTextPattern(text);
    
    if (!_confidenceHistory.containsKey(pattern)) {
      _confidenceHistory[pattern] = [];
    }
    
    _confidenceHistory[pattern]!.add(confidence);
    
    // Keep only last 10 samples per pattern
    if (_confidenceHistory[pattern]!.length > 10) {
      _confidenceHistory[pattern]!.removeAt(0);
    }
  }

  /// Get a pattern key for text (for grouping similar phrases)
  String _getTextPattern(String text) {
    final words = text.toLowerCase().trim().split(RegExp(r'\s+'));
    
    if (words.length <= 2) {
      return words.join(' ');
    }
    
    // For longer phrases, use first + last word + length
    return '${words.first}_${words.last}_${words.length}w';
  }

  /// Adjust confidence threshold based on success/failure feedback
  void _adjustConfidenceThreshold(bool wasSuccessful) {
    if (wasSuccessful) {
      // Success: potentially raise threshold (be more selective)
      _userConfidenceThreshold = min(0.95, _userConfidenceThreshold + 0.01);
    } else {
      // Failure: lower threshold (be more accepting)
      _userConfidenceThreshold = max(0.5, _userConfidenceThreshold - 0.02);
    }
  }

  /// Load user profile from persistent storage
  Future<void> _loadUserProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load corrections
      final correctionsJson = prefs.getString('voice_corrections') ?? '{}';
      _personalCorrections = Map<String, String>.from(json.decode(correctionsJson));
      
      // Load confidence threshold
      _userConfidenceThreshold = prefs.getDouble('voice_confidence_threshold') ?? 0.75;
      
      // Load custom wake words
      _customWakeWords = prefs.getStringList('custom_wake_words') ?? [];
      
      // Load command synonyms
      final synonymsJson = prefs.getString('command_synonyms') ?? '{}';
      final synonymsMap = json.decode(synonymsJson) as Map<String, dynamic>;
      _commandSynonyms = synonymsMap.map((key, value) => 
        MapEntry(key, List<String>.from(value as List)));
      
      // Load confidence history (simplified)
      final historyJson = prefs.getString('confidence_history') ?? '{}';
      final historyMap = json.decode(historyJson) as Map<String, dynamic>;
      _confidenceHistory = historyMap.map((key, value) => 
        MapEntry(key, List<double>.from(value as List)));
      
      // Load voice samples
      final samplesJson = prefs.getString('voice_samples') ?? '[]';
      _voiceSamples = List<Map<String, dynamic>>.from(json.decode(samplesJson));
      
      // Load voice profile
      final profileJson = prefs.getString('voice_profile');
      if (profileJson != null) {
        _voiceProfile = Map<String, dynamic>.from(json.decode(profileJson));
      }
      
    } catch (e) {
      print('⚠️ [VoiceTraining] Error loading profile: $e');
      // Continue with empty profile
    }
  }

  /// Save user profile to persistent storage
  Future<void> _saveUserProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Save corrections
      await prefs.setString('voice_corrections', json.encode(_personalCorrections));
      
      // Save confidence threshold
      await prefs.setDouble('voice_confidence_threshold', _userConfidenceThreshold);
      
      // Save custom wake words
      await prefs.setStringList('custom_wake_words', _customWakeWords);
      
      // Save command synonyms
      await prefs.setString('command_synonyms', json.encode(_commandSynonyms));
      
      // Save confidence history
      await prefs.setString('confidence_history', json.encode(_confidenceHistory));
      
      // Save voice samples
      await prefs.setString('voice_samples', json.encode(_voiceSamples));
      
      // Save voice profile
      if (_voiceProfile != null) {
        await prefs.setString('voice_profile', json.encode(_voiceProfile));
      }
      
    } catch (e) {
      print('❌ [VoiceTraining] Error saving profile: $e');
    }
  }
}