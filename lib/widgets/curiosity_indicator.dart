import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../services/ai/curiosity_service.dart';

/// Floating curiosity indicator that shows when Kai has a question
/// Shows an animated question mark that pulses and glows
class CuriosityIndicator extends StatefulWidget {
  final CuriosityQuestion question;
  final VoidCallback onTap;
  final Duration displayDuration;

  const CuriosityIndicator({
    super.key,
    required this.question,
    required this.onTap,
    this.displayDuration = const Duration(seconds: 8),
  });

  @override
  State<CuriosityIndicator> createState() => _CuriosityIndicatorState();
}

class _CuriosityIndicatorState extends State<CuriosityIndicator>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _glowController;
  late AnimationController _bounceController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _bounceAnimation;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();

    // Pulse animation (scale)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    // Glow animation (opacity)
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _glowController.repeat(reverse: true);

    // Bounce animation (slight vertical movement)
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _bounceAnimation = Tween<double>(begin: 0, end: 8).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );
    _bounceController.repeat(reverse: true);

    // Auto-dismiss after displayDuration
    Future.delayed(widget.displayDuration, () {
      if (mounted && !_dismissed) {
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _glowController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (!_dismissed) {
      setState(() => _dismissed = true);
      Future.delayed(const Duration(milliseconds: 300), () {
        // Indicator will be removed by parent
      });
    }
  }

  void _handleTap() {
    _dismiss();
    widget.onTap();
  }

  Color _getPriorityColor() {
    final priority = widget.question.priority;
    if (priority >= 9) {
      return Colors.amber; // High priority (emotional)
    } else if (priority >= 7) {
      return Colors.blue; // Medium priority
    } else {
      return Colors.purple; // Low priority
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) {
      return const SizedBox.shrink();
    }

    final color = _getPriorityColor();

    return AnimatedBuilder(
      animation: Listenable.merge([
        _pulseController,
        _glowController,
        _bounceController,
      ]),
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -_bounceAnimation.value),
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: GestureDetector(
              onTap: _handleTap,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.7),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(_glowAnimation.value),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                  border: Border.all(
                    color: color.withOpacity(0.8),
                    width: 2,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer glow ring
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.withOpacity(_glowAnimation.value * 0.5),
                          width: 1,
                        ),
                      ),
                    ),
                    // Question mark
                    Icon(
                      Icons.question_mark_rounded,
                      size: 40,
                      color: color,
                    ),
                    // Sparkle effect (rotating)
                    Transform.rotate(
                      angle: _pulseController.value * 2 * math.pi,
                      child: Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Overlay manager to show curiosity indicator
class CuriosityOverlay {
  static OverlayEntry? _currentOverlay;

  /// Show curiosity indicator
  static void show({
    required BuildContext context,
    required CuriosityQuestion question,
    required VoidCallback onTap,
    Alignment alignment = Alignment.topRight,
    EdgeInsets padding = const EdgeInsets.all(20),
  }) {
    // Remove any existing indicator
    dismiss();

    _currentOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: alignment == Alignment.topRight || alignment == Alignment.topLeft
            ? padding.top
            : null,
        bottom:
            alignment == Alignment.bottomRight || alignment == Alignment.bottomLeft
                ? padding.bottom
                : null,
        left: alignment == Alignment.topLeft || alignment == Alignment.bottomLeft
            ? padding.left
            : null,
        right: alignment == Alignment.topRight || alignment == Alignment.bottomRight
            ? padding.right
            : null,
        child: SafeArea(
          child: Material(
            color: Colors.transparent,
            child: CuriosityIndicator(
              question: question,
              onTap: () {
                dismiss();
                onTap();
              },
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_currentOverlay!);

    // Auto-dismiss after 8 seconds
    Future.delayed(const Duration(seconds: 8), dismiss);
  }

  /// Dismiss the current indicator
  static void dismiss() {
    _currentOverlay?.remove();
    _currentOverlay = null;
  }
}
