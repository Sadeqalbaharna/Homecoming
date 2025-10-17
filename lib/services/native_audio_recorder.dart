// Native audio recorder using Android MediaRecorder via MethodChannel
// Works in overlay isolates unlike flutter_sound plugin

import 'dart:io';
import 'package:flutter/services.dart';

class NativeAudioRecorder {
  static const MethodChannel _channel = MethodChannel('com.homecoming.app/audio_recorder');
  
  String? _recordingPath;
  bool _isRecording = false;

  /// Start recording audio
  /// Returns the file path where recording will be saved
  Future<String> startRecording() async {
    try {
      print('🎤 [NativeAudioRecorder] Starting recording...');
      
      final String? filePath = await _channel.invokeMethod('startRecording');
      
      if (filePath == null) {
        throw Exception('Failed to start recording: no file path returned');
      }
      
      _recordingPath = filePath;
      _isRecording = true;
      
      print('✅ [NativeAudioRecorder] Recording started: $filePath');
      return filePath;
    } on PlatformException catch (e) {
      print('❌ [NativeAudioRecorder] Platform error: ${e.code} - ${e.message}');
      _isRecording = false;
      rethrow;
    } catch (e) {
      print('❌ [NativeAudioRecorder] Error starting recording: $e');
      _isRecording = false;
      rethrow;
    }
  }

  /// Stop recording and return the file path
  Future<File?> stopRecording() async {
    if (!_isRecording) {
      print('⚠️ [NativeAudioRecorder] Not recording, cannot stop');
      return null;
    }

    try {
      print('🎤 [NativeAudioRecorder] Stopping recording...');
      
      final String? filePath = await _channel.invokeMethod('stopRecording');
      
      _isRecording = false;
      _recordingPath = null;
      
      if (filePath == null) {
        print('⚠️ [NativeAudioRecorder] No recording file returned');
        return null;
      }
      
      final file = File(filePath);
      if (!await file.exists()) {
        print('⚠️ [NativeAudioRecorder] Recording file does not exist: $filePath');
        return null;
      }
      
      final fileSize = await file.length();
      print('✅ [NativeAudioRecorder] Recording stopped: $filePath ($fileSize bytes)');
      
      return file;
    } on PlatformException catch (e) {
      print('❌ [NativeAudioRecorder] Platform error: ${e.code} - ${e.message}');
      _isRecording = false;
      rethrow;
    } catch (e) {
      print('❌ [NativeAudioRecorder] Error stopping recording: $e');
      _isRecording = false;
      rethrow;
    }
  }

  /// Check if currently recording
  Future<bool> isRecording() async {
    try {
      final bool? recording = await _channel.invokeMethod('isRecording');
      _isRecording = recording ?? false;
      return _isRecording;
    } catch (e) {
      print('❌ [NativeAudioRecorder] Error checking recording status: $e');
      return false;
    }
  }

  /// Get the current recording file path (if recording)
  String? get currentRecordingPath => _recordingPath;
  
  /// Get whether currently recording (cached value)
  bool get isCurrentlyRecording => _isRecording;
}
