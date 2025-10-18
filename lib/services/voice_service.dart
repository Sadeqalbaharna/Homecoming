// Voice Service - Speech-to-Text using OpenAI Whisper API

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:permission_handler/permission_handler.dart';
import 'secure_storage_service.dart';
import 'native_audio_recorder.dart';

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
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  
  final NativeAudioRecorder _recorder = NativeAudioRecorder();
  late final Dio _dio;
  
  bool _isRecording = false;
  
  VoiceService._internal() {
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
      print('🎤 [VoiceService] Starting recording...');
      
      // Check permission status
      final permStatus = await Permission.microphone.status;
      print('🎤 [VoiceService] Microphone permission status: $permStatus');
      
      if (!permStatus.isGranted) {
        print('🎤 [VoiceService] Requesting microphone permission...');
        final granted = await requestPermission();
        print('🎤 [VoiceService] Permission request result: $granted');
        if (!granted) {
          print('❌ [VoiceService] Microphone permission denied');
          return false;
        }
      }
      
      // Start recording with native recorder
      await _recorder.startRecording();
      _isRecording = true;
      
      print('✅ [VoiceService] Recording started successfully');
      return true;
      
    } catch (e, stackTrace) {
      print('❌ [VoiceService] Failed to start recording: $e');
      print('Stack trace: $stackTrace');
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
      
      final recordingFile = await _recorder.stopRecording();
      _isRecording = false;
      
      if (recordingFile != null && await recordingFile.exists()) {
        final filePath = recordingFile.path;
        print('✅ Recording stopped: $filePath');
        return filePath;
      } else {
        print('⚠️ Recording stopped but no file');
        return null;
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
        final recordingFile = await _recorder.stopRecording();
        _isRecording = false;
        
        // Delete the recording file
        if (recordingFile != null && await recordingFile.exists()) {
          await recordingFile.delete();
          print('🗑️ Recording cancelled and deleted');
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
      print('🔑 API Key retrieved: ${openaiKey.isEmpty ? "EMPTY" : "Present (${openaiKey.length} chars)"}');
      
      if (openaiKey.isEmpty) {
        throw Exception('OpenAI API key not configured');
      }
      
      final file = File(audioPath);
      if (!await file.exists()) {
        throw Exception('Audio file not found: $audioPath');
      }
      
      print('🎯 Transcribing audio: $audioPath');
      print('📊 File size: ${await file.length()} bytes');
      print('🌐 Testing internet connectivity...');
      
      // Test internet connectivity first
      try {
        await _dio.get('https://www.google.com', options: Options(
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
        ));
        print('✅ Internet connection OK');
      } catch (e) {
        print('❌ No internet connection: $e');
        throw Exception('No internet connection. Please connect to WiFi or mobile data.');
      }
      
      // Create multipart form data with correct MIME type for m4a
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          audioPath,
          filename: 'audio.m4a',
          contentType: MediaType('audio', 'mp4'),
        ),
        'model': VoiceConfig.whisperModel,
        if (VoiceConfig.whisperLanguage.isNotEmpty) 
          'language': VoiceConfig.whisperLanguage,
      });
      
      print('📤 Sending request to Whisper API...');
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
    // Native recorder doesn't need cleanup
  }
}
