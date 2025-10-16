// Voice Service - Speech-to-Text using OpenAI Whisper API

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'secure_storage_service.dart';

/// Configuration for voice/speech services
class VoiceConfig {
  static final _secureStorage = SecureStorageService();
  
  /// Get OpenAI API Key from secure storage
  static Future<String> getOpenAIKey() async {
    return await _secureStorage.getOpenAIKey() ?? '';
  }
  
  static const String whisperModel = 'whisper-1';
  static const String whisperLanguage = 'en'; // Can be changed to auto-detect with null
}

/// Voice service for speech-to-text using OpenAI Whisper
class VoiceService {
  final AudioRecorder _recorder = AudioRecorder();
  late final Dio _dio;
  
  bool _isRecording = false;
  String? _currentRecordingPath;
  
  VoiceService() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ));
  }
  
  /// Check if microphone permission is granted
  Future<bool> hasPermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }
  
  /// Request microphone permission
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }
  
  /// Start recording audio
  Future<bool> startRecording() async {
    try {
      // Check permission first
      if (!await hasPermission()) {
        final granted = await requestPermission();
        if (!granted) {
          print('❌ Microphone permission denied');
          return false;
        }
      }
      
      // Check if device can record
      if (!await _recorder.hasPermission()) {
        print('❌ No recording permission');
        return false;
      }
      
      // Get temporary directory for recording
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${tempDir.path}/recording_$timestamp.m4a';
      
      // Start recording
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc, // AAC format compatible with Whisper
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );
      
      _isRecording = true;
      print('🎤 Recording started: $_currentRecordingPath');
      return true;
      
    } catch (e) {
      print('❌ Failed to start recording: $e');
      _isRecording = false;
      return false;
    }
  }
  
  /// Stop recording and return the file path
  Future<String?> stopRecording() async {
    try {
      if (!_isRecording) {
        print('⚠️ Not currently recording');
        return null;
      }
      
      final path = await _recorder.stop();
      _isRecording = false;
      
      if (path != null) {
        print('✅ Recording stopped: $path');
        return path;
      } else {
        print('⚠️ Recording stopped but no file path returned');
        return _currentRecordingPath;
      }
      
    } catch (e) {
      print('❌ Failed to stop recording: $e');
      _isRecording = false;
      return null;
    }
  }
  
  /// Cancel recording without saving
  Future<void> cancelRecording() async {
    try {
      if (_isRecording) {
        await _recorder.stop();
        _isRecording = false;
        
        // Delete the recording file
        if (_currentRecordingPath != null) {
          final file = File(_currentRecordingPath!);
          if (await file.exists()) {
            await file.delete();
            print('🗑️ Recording cancelled and deleted');
          }
        }
      }
    } catch (e) {
      print('❌ Failed to cancel recording: $e');
    }
  }
  
  /// Transcribe audio file using OpenAI Whisper API
  Future<String?> transcribeAudio(String audioPath) async {
    try {
      final openaiKey = await VoiceConfig.getOpenAIKey();
      if (openaiKey.isEmpty) {
        throw Exception('OpenAI API key not configured');
      }
      
      final file = File(audioPath);
      if (!await file.exists()) {
        throw Exception('Audio file not found: $audioPath');
      }
      
      print('🎯 Transcribing audio: $audioPath');
      print('📊 File size: ${await file.length()} bytes');
      
      // Create multipart form data
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          audioPath,
          filename: 'audio.m4a',
        ),
        'model': VoiceConfig.whisperModel,
        if (VoiceConfig.whisperLanguage.isNotEmpty) 
          'language': VoiceConfig.whisperLanguage,
      });
      
      // Call Whisper API
      final response = await _dio.post(
        'https://api.openai.com/v1/audio/transcriptions',
        data: formData,
        options: Options(
          headers: {
            'Authorization': 'Bearer $openaiKey',
          },
        ),
      );
      
      if (response.statusCode == 200) {
        final transcription = response.data['text'] as String?;
        print('✅ Transcription: $transcription');
        
        // Clean up the audio file after successful transcription
        try {
          await file.delete();
          print('🗑️ Audio file deleted after transcription');
        } catch (e) {
          print('⚠️ Failed to delete audio file: $e');
        }
        
        return transcription;
      } else {
        throw Exception('Whisper API returned status ${response.statusCode}');
      }
      
    } catch (e) {
      print('❌ Transcription error: $e');
      if (e is DioException) {
        print('Response: ${e.response?.data}');
      }
      return null;
    }
  }
  
  /// Record and transcribe in one go
  /// Returns the transcribed text or null if failed
  Future<String?> recordAndTranscribe({
    Duration? maxDuration,
    void Function(bool isRecording)? onRecordingStateChanged,
  }) async {
    try {
      // Start recording
      onRecordingStateChanged?.call(true);
      final started = await startRecording();
      if (!started) {
        onRecordingStateChanged?.call(false);
        return null;
      }
      
      // Wait for max duration or manual stop
      if (maxDuration != null) {
        await Future.delayed(maxDuration);
      }
      
      // Stop recording
      final audioPath = await stopRecording();
      onRecordingStateChanged?.call(false);
      
      if (audioPath == null) {
        return null;
      }
      
      // Transcribe
      return await transcribeAudio(audioPath);
      
    } catch (e) {
      print('❌ Record and transcribe error: $e');
      onRecordingStateChanged?.call(false);
      return null;
    }
  }
  
  /// Get current recording state
  bool get isRecording => _isRecording;
  
  /// Clean up resources
  Future<void> dispose() async {
    if (_isRecording) {
      await cancelRecording();
    }
    _recorder.dispose();
  }
}
