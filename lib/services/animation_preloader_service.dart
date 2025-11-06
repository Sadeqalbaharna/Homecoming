/// Animation Preloader Service
/// Preloads all animation frames to prevent first-time flicker
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class AnimationPreloaderService {
  static final AnimationPreloaderService _instance = AnimationPreloaderService._internal();
  factory AnimationPreloaderService() => _instance;
  AnimationPreloaderService._internal();

  // Preloading state
  bool _isPreloading = false;
  bool _preloadingComplete = false;
  double _progress = 0.0;
  String _currentAnimation = '';
  
  // Progress callbacks
  final List<Function(double progress, String currentAnimation)> _progressCallbacks = [];
  final List<Function()> _completionCallbacks = [];
  
  // Getters
  bool get isPreloading => _isPreloading;
  bool get isComplete => _preloadingComplete;
  double get progress => _progress;
  String get currentAnimation => _currentAnimation;
  
  /// Add progress callback
  void onProgressUpdate(Function(double progress, String currentAnimation) callback) {
    _progressCallbacks.add(callback);
  }
  
  /// Add completion callback
  void onPreloadingComplete(Function() callback) {
    _completionCallbacks.add(callback);
  }
  
  /// Remove all callbacks
  void clearCallbacks() {
    _progressCallbacks.clear();
    _completionCallbacks.clear();
  }
  
  /// Preload all animation frames
  Future<void> preloadAllAnimations(BuildContext context) async {
    if (_isPreloading || _preloadingComplete) return;
    
    _isPreloading = true;
    _progress = 0.0;
    _notifyProgressUpdate();
    
    try {
      // Define all animations with their frame counts and directories
      final animations = [
        ('Idle Animation', 121, 'assets/avatar/idle_frames/'),
        ('Attention Animation', 121, 'assets/avatar/attention_frames/'),
        ('Thinking Animation', 241, 'assets/avatar/thinking_frames/'),
        ('Speaking Animation', 121, 'assets/avatar/speaking_frames/'),
      ];
      
      int totalFrames = animations.fold(0, (sum, anim) => sum + anim.$2);
      int loadedFrames = 0;
      
      for (final (animName, frameCount, frameDir) in animations) {
        _currentAnimation = animName;
        _notifyProgressUpdate();
        
        // Load frames in batches to avoid memory spikes
        const batchSize = 10;
        for (int batchStart = 0; batchStart < frameCount; batchStart += batchSize) {
          final batchEnd = (batchStart + batchSize).clamp(0, frameCount);
          
          // Load batch of frames concurrently
          final futures = <Future<void>>[];
          for (int i = batchStart; i < batchEnd; i++) {
            final framePath = '${frameDir}frame_${i.toString().padLeft(4, '0')}.png';
            futures.add(_preloadFrame(context, framePath));
          }
          
          // Wait for batch to complete
          await Future.wait(futures);
          
          // Update progress
          loadedFrames += (batchEnd - batchStart);
          _progress = loadedFrames / totalFrames;
          _notifyProgressUpdate();
          
          // Small delay to prevent UI blocking
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }
      
      // Mark as complete
      _preloadingComplete = true;
      _isPreloading = false;
      _progress = 1.0;
      _currentAnimation = 'Complete!';
      _notifyProgressUpdate();
      _notifyCompletion();
      
    } catch (e) {
      print('🚨 Animation preloading error: $e');
      _isPreloading = false;
      // Continue anyway - better to have some frames than none
    }
  }
  
  /// Preload a single frame
  Future<void> _preloadFrame(BuildContext context, String framePath) async {
    try {
      // Check if asset exists first
      await rootBundle.load(framePath);
      
      // Precache the image
      await precacheImage(AssetImage(framePath), context);
    } catch (e) {
      // Frame doesn't exist - this is expected for some animations
      // Just skip silently
    }
  }
  
  /// Notify progress callbacks
  void _notifyProgressUpdate() {
    for (final callback in _progressCallbacks) {
      try {
        callback(_progress, _currentAnimation);
      } catch (e) {
        print('🚨 Progress callback error: $e');
      }
    }
  }
  
  /// Notify completion callbacks
  void _notifyCompletion() {
    for (final callback in _completionCallbacks) {
      try {
        callback();
      } catch (e) {
        print('🚨 Completion callback error: $e');
      }
    }
  }
  
  /// Force reset (for debugging)
  void reset() {
    _isPreloading = false;
    _preloadingComplete = false;
    _progress = 0.0;
    _currentAnimation = '';
  }
  
  /// Quick preload check - verify some key frames exist
  Future<bool> verifyAnimationAssets() async {
    try {
      final testFrames = [
        'assets/avatar/idle_frames/frame_0000.png',
        'assets/avatar/attention_frames/frame_0000.png',
        'assets/avatar/thinking_frames/frame_0000.png',
        'assets/avatar/speaking_frames/frame_0000.png',
      ];
      
      for (final frame in testFrames) {
        await rootBundle.load(frame);
      }
      
      return true;
    } catch (e) {
      print('🚨 Animation assets verification failed: $e');
      return false;
    }
  }
}