// The comic-panel wipe. A hard diagonal edge sweeps the new screen across the
// old one, instead of Flutter's default slide.
//
// This is the single move that makes a menu feel like Persona and not like a
// settings app: navigation is a cut, not a drawer. It's a PageRouteBuilder, so
// any push can use it — MESSAGES, MIND, JOURNAL all sweep the same way, and the
// reverse sweeps back.
//
// No package, no shader. A ClipPath whose clipper reveals everything to the left
// of a slanted line, and the line's x-position is driven by the route's
// animation. At t=0 the line is off the left edge (nothing shown); at t=1 it's
// off the right (fully shown).
library;

import 'package:flutter/material.dart';

class P5WipeRoute<T> extends PageRouteBuilder<T> {
  P5WipeRoute({required Widget page, this.slant = 120})
      : super(
          transitionDuration: const Duration(milliseconds: 420),
          reverseTransitionDuration: const Duration(milliseconds: 340),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, animation, __, child) {
            // Snap in, ease out — a cut wants to feel decisive, not floaty.
            final t = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return AnimatedBuilder(
              animation: t,
              builder: (_, __) => ClipPath(
                clipper: _DiagonalReveal(t.value, slant),
                child: child,
              ),
            );
          },
        );

  /// How far the leading edge leans. 0 = a vertical wipe; higher = a sharper
  /// diagonal. 120 reads as a comic panel without being a gimmick.
  final double slant;
}

class _DiagonalReveal extends CustomClipper<Path> {
  _DiagonalReveal(this.progress, this.slant);

  final double progress; // 0..1
  final double slant;

  @override
  Path getClip(Size size) {
    // The leading edge travels from off the left (-slant) to off the right
    // (width + slant). Everything to its left is revealed. The edge is a
    // straight diagonal: its top x leads, its bottom x trails by `slant`.
    final travel = size.width + slant * 2;
    final edgeTop = -slant + travel * progress;
    final edgeBottom = edgeTop - slant;

    return Path()
      ..moveTo(0, 0)
      ..lineTo(edgeTop, 0)
      ..lineTo(edgeBottom, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_DiagonalReveal old) => old.progress != progress;
}
