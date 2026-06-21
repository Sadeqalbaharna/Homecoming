// Simple audio player service for playing back recorded audio

import 'package:audioplayers/audioplayers.dart';

class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  
  final AudioPlayer _player = AudioPlayer();
  String? _currentPath;
  bool _isPlaying = false;
  
  AudioPlayerService._internal() {
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
    });
  }
  
  /// Play audio file
  Future<bool> play(String filePath) async {
    try {
      print('🔊 Playing audio: $filePath');
      await _player.play(DeviceFileSource(filePath));
      _currentPath = filePath;
      return true;
    } catch (e) {
      print('❌ Failed to play audio: $e');
      return false;
    }
  }
  
  /// Stop playback
  Future<void> stop() async {
    try {
      await _player.stop();
      _isPlaying = false;
    } catch (e) {
      print('❌ Failed to stop audio: $e');
    }
  }
  
  /// Pause playback
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      print('❌ Failed to pause audio: $e');
    }
  }
  
  /// Check if currently playing
  bool get isPlaying => _isPlaying;
  
  /// Get current file path
  String? get currentPath => _currentPath;
  
  /// Dispose player
  Future<void> dispose() async {
    await _player.dispose();
  }
}
