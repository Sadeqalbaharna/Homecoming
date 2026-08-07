import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/core/kai_global_presence_service.dart';

/// A literal view of Kai's currently leased bodies around the central core.
///
/// Nothing here is inferred: a body appears only while its registry lease is
/// live. The center beats only while the coordinator lease is verified.
class KaiBodyConstellation extends StatefulWidget {
  const KaiBodyConstellation({
    super.key,
    required this.awake,
    required this.bodies,
    this.compact = false,
  });

  final bool awake;
  final List<KaiGlobalBody> bodies;
  final bool compact;

  @override
  State<KaiBodyConstellation> createState() => _KaiBodyConstellationState();
}

class _KaiBodyConstellationState extends State<KaiBodyConstellation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant KaiBodyConstellation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.awake != widget.awake) _syncPulse();
  }

  void _syncPulse() {
    if (widget.awake) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bodies = widget.bodies.take(widget.compact ? 4 : 8).toList();
    final height = widget.compact ? 38.0 : 50.0;
    return Semantics(
      label: widget.awake
          ? 'Central Kai awake in ${widget.bodies.length} bodies'
          : 'Central Kai asleep',
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                final scale = widget.awake ? 0.92 + (_pulse.value * 0.13) : 0.9;
                return Transform.scale(
                  scale: scale,
                  child: Icon(
                    widget.awake ? Icons.favorite : Icons.favorite_border,
                    key: const ValueKey('kai-central-heart'),
                    size: widget.compact ? 17 : 21,
                    color: widget.awake
                        ? const Color(0xFF2CE8FF)
                        : const Color(0xFF53616D),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: bodies.isEmpty
                  ? Text(
                      widget.awake
                          ? 'CORE AWAKE · NO BODY ONLINE'
                          : 'CORE ASLEEP',
                      style: TextStyle(
                        color: widget.awake
                            ? const Color(0xFF7FAFBA)
                            : const Color(0xFF65717A),
                        fontFamily: 'monospace',
                        fontSize: widget.compact ? 9 : 10,
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: bodies.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, index) => _BodyChip(
                        body: bodies[index],
                        compact: widget.compact,
                      ),
                    ),
            ),
            if (widget.bodies.length > bodies.length)
              Text(
                '+${widget.bodies.length - bodies.length}',
                style: const TextStyle(
                  color: Color(0xFF6CDCEB),
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BodyChip extends StatelessWidget {
  const _BodyChip({required this.body, required this.compact});

  final KaiGlobalBody body;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final active = const {'listening', 'thinking', 'speaking', 'working'}
        .contains(body.status.toLowerCase());
    final color = active
        ? const Color(0xFFFFAD42)
        : body.foreground
            ? const Color(0xFF2CE8FF)
            : const Color(0xFF7894A4);
    final label = body.surface.toUpperCase();
    final status = body.status.toUpperCase();
    return Tooltip(
      message:
          '$label · $status${body.gogglesOn ? ' · GOGGLES ON' : ' · FRIEND'}',
      child: Container(
        key: ValueKey('kai-body-${body.bodyId}'),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 9,
          vertical: compact ? 4 : 5,
        ),
        decoration: BoxDecoration(
          color: color.withOpacity(0.09),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: body.gogglesOn ? -math.pi / 14 : 0,
              child: Icon(
                _iconFor(body.surface),
                size: compact ? 11 : 13,
                color: color,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              compact ? label : '$label · $status',
              style: TextStyle(
                color: color,
                fontFamily: 'monospace',
                fontSize: compact ? 8 : 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String surface) => switch (surface.toLowerCase()) {
        'messenger' || 'mobile' => Icons.phone_android,
        'vr' => Icons.view_in_ar,
        'ar' => Icons.center_focus_strong,
        _ => Icons.desktop_windows_outlined,
      };
}
