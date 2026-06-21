// Animation Preloader Service
// Stub implementation — preloading is skipped; onPreloadingComplete fires immediately.

import 'package:flutter/material.dart';

class AnimationPreloaderService {
  bool _isComplete = false;
  bool get isComplete => _isComplete;

  void Function(double progress, String currentAnimation)? _onProgressUpdate;
  void Function()? _onPreloadingComplete;

  void onProgressUpdate(void Function(double progress, String currentAnimation) cb) {
    _onProgressUpdate = cb;
  }

  void onPreloadingComplete(void Function() cb) {
    _onPreloadingComplete = cb;
  }

  Future<bool> verifyAnimationAssets() async {
    return true; // Stub: assume assets exist
  }

  Future<void> preloadAllAnimations(BuildContext context) async {
    // Stub: report instant completion
    _isComplete = true;
    _onProgressUpdate?.call(1.0, 'Done');
    _onPreloadingComplete?.call();
  }

  void clearCallbacks() {
    _onProgressUpdate = null;
    _onPreloadingComplete = null;
  }
}
