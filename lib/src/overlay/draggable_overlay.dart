import 'package:flutter/material.dart';

/// Wrap any child (e.g., AvatarOverlay) to make it draggable.
/// - Keeps the widget within screen bounds
/// - Remembers position while the screen stays mounted
/// - Optional edge‑snap
class DraggableOverlay extends StatefulWidget {
  const DraggableOverlay({
    super.key,
    required this.child,
    this.size = const Size(180, 180),
    this.initialAlignment = const Alignment(0.8, 0.8), // bottom-rightish
    this.snapToEdges = true,
    this.margin = const EdgeInsets.all(12),
  });

  final Widget child;
  final Size size;
  final Alignment initialAlignment;
  final bool snapToEdges;
  final EdgeInsets margin;

  @override
  State<DraggableOverlay> createState() => _DraggableOverlayState();
}

class _DraggableOverlayState extends State<DraggableOverlay> {
  late Offset _posPx; // position in pixels (top-left)
  Size? _screen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screen ??= MediaQuery.sizeOf(context);
    // First-time compute from alignment
    _posPx = _fromAlignment(widget.initialAlignment, _screen!, widget.size, widget.margin);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // Clamp if screen changed (rotation / resize)
    _posPx = _clamp(_posPx, screen, widget.size, widget.margin);

    return Positioned(
      left: _posPx.dx,
      top: _posPx.dy,
      width: widget.size.width,
      height: widget.size.height,
      child: _DragHandle(
        onUpdate: (delta) {
          setState(() {
            _posPx = _clamp(_posPx + delta, screen, widget.size, widget.margin);
          });
        },
        onEnd: () {
          if (!widget.snapToEdges) return;
          setState(() {
            _posPx = _snapToNearestEdge(_posPx, screen, widget.size, widget.margin);
          });
        },
        child: IgnorePointer(
          ignoring: false, // allow gestures inside (tap/long-press for voice)
          child: widget.child,
        ),
      ),
    );
  }

  static Offset _fromAlignment(
    Alignment a,
    Size screen,
    Size child,
    EdgeInsets margin,
  ) {
    final usable = Size(
      screen.width - margin.horizontal - child.width,
      screen.height - margin.vertical - child.height,
    );
    final x = margin.left + (usable.width / 2) * (a.x + 1);
    final y = margin.top + (usable.height / 2) * (a.y + 1);
    return Offset(x, y);
  }

  static Offset _clamp(Offset p, Size screen, Size child, EdgeInsets m) {
    final minX = m.left;
    final minY = m.top;
    final maxX = screen.width - m.right - child.width;
    final maxY = screen.height - m.bottom - child.height;
    return Offset(
      p.dx.clamp(minX, maxX),
      p.dy.clamp(minY, maxY),
    );
  }

  static Offset _snapToNearestEdge(Offset p, Size screen, Size child, EdgeInsets m) {
    final left = m.left;
    final right = screen.width - m.right - child.width;
    final top = m.top;
    final bottom = screen.height - m.bottom - child.height;

    // Distances to edges
    final dLeft = (p.dx - left).abs();
    final dRight = (right - p.dx).abs();
    final dTop = (p.dy - top).abs();
    final dBottom = (bottom - p.dy).abs();

    // Snap horizontally to nearest side, keep y clamped
    if (dLeft < dRight && dLeft < dTop && dLeft < dBottom) {
      return Offset(left, p.dy);
    } else if (dRight < dLeft && dRight < dTop && dRight < dBottom) {
      return Offset(right, p.dy);
    } else if (dTop < dBottom) {
      return Offset(p.dx, top);
    } else {
      return Offset(p.dx, bottom);
    }
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({
    required this.child,
    required this.onUpdate,
    required this.onEnd,
  });

  final Widget child;
  final void Function(Offset delta) onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Listener( // keeps desktop dragging smooth
      onPointerMove: (e) => onUpdate(e.delta),
      onPointerUp: (_) => onEnd(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => onUpdate(d.delta),
        onPanEnd: (_) => onEnd(),
        child: child,
      ),
    );
  }
}
