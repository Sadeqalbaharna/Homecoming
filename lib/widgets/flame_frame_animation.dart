// flame_frame_animation.dart
//
// Cycles through assets/avatar/flame_frames/frame_XXXX.png at ~24 fps.
// Used by the sleep-mode overlay in place of the procedural blue flame.
//
// Usage:
//   FlameFrameAnimation(size: 90)
//
// The widget is intentionally lightweight — no controllers outside the
// single AnimationController that drives the frame index.

library;

import 'package:flutter/material.dart';

class FlameFrameAnimation extends StatefulWidget {
  /// Rendered width/height in logical pixels.
  final double size;

  /// When true the animation pulses brighter (pending message indicator).
  final bool urgent;

  /// Total number of frames in assets/avatar/flame_frames/.
  static const int frameCount = 121;

  /// Playback speed in frames per second.
  static const double fps = 24.0;

  const FlameFrameAnimation({
    super.key,
    this.size = 90,
    this.urgent = false,
  });

  @override
  State<FlameFrameAnimation> createState() => _FlameFrameAnimationState();
}

class _FlameFrameAnimationState extends State<FlameFrameAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds:
            (FlameFrameAnimation.frameCount / FlameFrameAnimation.fps * 1000)
                .round(),
      ),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _framePath(int index) =>
      'assets/avatar/flame_frames/frame_${index.toString().padLeft(4, '0')}.png';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        final frameIndex =
            (_ctrl.value * FlameFrameAnimation.frameCount).floor() %
                FlameFrameAnimation.frameCount;

        // Urgent: overlay a pulsing amber tint
        final urgentOpacity =
            widget.urgent ? (0.15 + 0.15 * _ctrl.value) : 0.0;

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                _framePath(frameIndex),
                width: widget.size,
                height: widget.size,
                fit: BoxFit.contain,
                // Pre-cache next frame to reduce stutter
                gaplessPlayback: true,
              ),
              if (widget.urgent)
                Opacity(
                  opacity: urgentOpacity,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
