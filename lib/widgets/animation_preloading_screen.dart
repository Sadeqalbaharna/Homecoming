/// Animation Preloading Screen Widget
/// Shows progress while loading all animation frames
library;

import 'package:flutter/material.dart';
import '../services/animation_preloader_service.dart';

class AnimationPreloadingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  
  const AnimationPreloadingScreen({
    super.key,
    required this.onComplete,
  });

  @override
  State<AnimationPreloadingScreen> createState() => _AnimationPreloadingScreenState();
}

class _AnimationPreloadingScreenState extends State<AnimationPreloadingScreen>
    with TickerProviderStateMixin {
  
  final _preloader = AnimationPreloaderService();
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  double _progress = 0.0;
  String _currentAnimation = 'Initializing...';
  bool _assetsVerified = false;
  
  @override
  void initState() {
    super.initState();
    
    // Setup pulse animation for logo
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    // Setup preloader callbacks
    _preloader.onProgressUpdate((progress, currentAnimation) {
      if (mounted) {
        setState(() {
          _progress = progress;
          _currentAnimation = currentAnimation;
        });
      }
    });
    
    _preloader.onPreloadingComplete(() {
      if (mounted) {
        // Small delay for visual completion
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            widget.onComplete();
          }
        });
      }
    });
    
    // Start preloading after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _verifyAndStartPreloading();
    });
  }
  
  Future<void> _verifyAndStartPreloading() async {
    // First verify assets exist
    setState(() {
      _currentAnimation = 'Verifying animation assets...';
    });
    
    _assetsVerified = await _preloader.verifyAnimationAssets();
    
    if (!_assetsVerified) {
      setState(() {
        _currentAnimation = 'Animation assets not found - using fallback mode';
      });
      
      // Wait a moment to show message, then continue anyway
      await Future.delayed(const Duration(seconds: 2));
      widget.onComplete();
      return;
    }
    
    // Start preloading
    await _preloader.preloadAllAnimations(context);
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _preloader.clearCallbacks();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A07), // Dark background like app
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pulsing Kai logo/avatar
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFFFE7B0).withOpacity(0.8),
                          const Color(0xFFFFE7B0).withOpacity(0.2),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.psychology_rounded, // Brain/AI icon
                      size: 60,
                      color: Color(0xFFFFE7B0),
                    ),
                  ),
                );
              },
            ),
            
            const SizedBox(height: 40),
            
            // App title
            const Text(
              'Homecoming',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFFE7B0),
                letterSpacing: 1.2,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Subtitle
            const Text(
              'Preparing Kai\'s animations...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
            
            const SizedBox(height: 60),
            
            // Progress bar container
            Container(
              width: 280,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    const Color(0xFFFFE7B0).withOpacity(0.8),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Progress text
            Text(
              _currentAnimation,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white60,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 12),
            
            // Percentage
            Text(
              '${(_progress * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFFE7B0),
              ),
            ),
            
            const SizedBox(height: 60),
            
            // Skip button (emergency fallback)
            if (_progress > 0.1 && !_preloader.isComplete)
              TextButton(
                onPressed: () {
                  _preloader.clearCallbacks();
                  widget.onComplete();
                },
                child: const Text(
                  'Skip Preloading',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}