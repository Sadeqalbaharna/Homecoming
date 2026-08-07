import 'package:flutter/material.dart';

/// The phone's honest continuity signal.
///
/// This reports the Messenger/Firebase line, not the laptop-only Kai Core.
/// `null` means the connection is still being established.
class KaiLineHeartbeat extends StatefulWidget {
  const KaiLineHeartbeat({
    super.key,
    required this.awake,
    this.bodyCount = 0,
    this.onTap,
  });

  final bool? awake;
  final int bodyCount;
  final VoidCallback? onTap;

  @override
  State<KaiLineHeartbeat> createState() => _KaiLineHeartbeatState();
}

class _KaiLineHeartbeatState extends State<KaiLineHeartbeat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1), weight: 12),
      TweenSequenceItem(tween: Tween(begin: 1, end: 1.30), weight: 7),
      TweenSequenceItem(tween: Tween(begin: 1.30, end: 1), weight: 8),
      TweenSequenceItem(tween: Tween(begin: 1, end: 1.18), weight: 6),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 1), weight: 9),
      TweenSequenceItem(tween: ConstantTween(1), weight: 58),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant KaiLineHeartbeat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.awake != widget.awake) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.awake == true) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final awake = widget.awake;
    final color = awake == true
        ? const Color(0xFFF5F1E8)
        : awake == null
            ? const Color(0xFFFFC247)
            : const Color(0xFFFFD0D0);
    final state = awake == true
        ? 'CORE AWAKE  ·  ${widget.bodyCount} ${widget.bodyCount == 1 ? 'BODY' : 'BODIES'}'
        : awake == null
            ? 'CHECKING CORE'
            : 'CORE ASLEEP';

    return Semantics(
      label: 'Kai $state',
      button: widget.onTap != null,
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          width: double.infinity,
          color: const Color(0xFF111111),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scale,
                child: Icon(
                  awake == false
                      ? Icons.heart_broken_rounded
                      : Icons.favorite_rounded,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'KAI  ·  $state',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
