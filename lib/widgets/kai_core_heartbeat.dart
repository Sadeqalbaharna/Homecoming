import 'package:flutter/material.dart';

import '../services/core/kai_core_client.dart';

/// A small, literal heartbeat for the persistent Kai Core.
///
/// The animation only runs while the sidecar is confirmed healthy. Amber means
/// a recent heartbeat was missed; a still red broken heart means the core is
/// offline. This makes the animation operational telemetry, not decoration.
class KaiCoreHeartbeat extends StatefulWidget {
  const KaiCoreHeartbeat({
    super.key,
    required this.status,
    this.bodyCount = 0,
    this.onTap,
  });

  final KaiCoreHeartbeatStatus status;
  final int bodyCount;
  final VoidCallback? onTap;

  @override
  State<KaiCoreHeartbeat> createState() => _KaiCoreHeartbeatState();
}

class _KaiCoreHeartbeatState extends State<KaiCoreHeartbeat>
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
  void didUpdateWidget(covariant KaiCoreHeartbeat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status.phase != widget.status.phase) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.status.phase == KaiCoreHeartbeatPhase.healthy) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = widget.status.phase;
    final healthy = phase == KaiCoreHeartbeatPhase.healthy;
    final reconnecting = phase == KaiCoreHeartbeatPhase.reconnecting;
    final connecting = phase == KaiCoreHeartbeatPhase.connecting;
    final color = healthy
        ? const Color(0xFF35E6D3)
        : (reconnecting || connecting)
            ? const Color(0xFFFFB74D)
            : const Color(0xFFFF5B6E);
    final label = switch (phase) {
      KaiCoreHeartbeatPhase.connecting => 'KAI CORE · CHECKING',
      KaiCoreHeartbeatPhase.healthy =>
        'KAI CORE · AWAKE · ${widget.bodyCount} ${widget.bodyCount == 1 ? 'BODY' : 'BODIES'}',
      KaiCoreHeartbeatPhase.reconnecting => 'KAI CORE · UNVERIFIED',
      KaiCoreHeartbeatPhase.offline => 'KAI CORE · ASLEEP',
    };
    final lastBeat = widget.status.lastSuccessAt;
    final tooltip = lastBeat == null
        ? label
        : '$label\nLast heartbeat: ${lastBeat.toLocal()}';

    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: label,
        button: widget.onTap != null,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.38)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _scale,
                  child: Icon(
                    phase == KaiCoreHeartbeatPhase.offline
                        ? Icons.heart_broken_rounded
                        : Icons.favorite_rounded,
                    size: 13,
                    color: color,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  healthy
                      ? 'CORE AWAKE · ${widget.bodyCount}'
                      : phase == KaiCoreHeartbeatPhase.offline
                          ? 'CORE ASLEEP'
                          : 'CHECKING',
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
