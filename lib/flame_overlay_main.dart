// flame_overlay_main.dart
//
// Overlay entry point for Kai's background mode flame.
// Android calls this via FlutterOverlayWindow when showOverlay() fires.
//
// The overlay is sized to the flame itself (~90×120 dp) so there's no
// transparent dead zone — the entire overlay window IS the flame.
// Draggable, snaps to the nearest screen edge, tapping sends 'expand'
// back to the main app via the overlay message channel.

library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'widgets/flame_frame_animation.dart';

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  // Do NOT use MaterialApp — it renders an opaque background that hides the flame.
  // Use a bare transparent widget tree instead.
  runApp(const Directionality(
    textDirection: TextDirection.ltr,
    child: _FlameOverlay(),
  ));
}

class _FlameOverlay extends StatefulWidget {
  const _FlameOverlay();
  @override
  State<_FlameOverlay> createState() => _FlameOverlayState();
}

class _FlameOverlayState extends State<_FlameOverlay> {
  bool _hasPending = false;
  StreamSubscription? _dataSub;

  @override
  void initState() {
    super.initState();
    // Listen for data pushed from main app (e.g. pending badge update)
    _dataSub = FlutterOverlayWindow.overlayListener.listen((data) {
      if (data is Map && data['pending'] == true) {
        setState(() => _hasPending = true);
      } else if (data is Map && data['pending'] == false) {
        setState(() => _hasPending = false);
      }
    });
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    super.dispose();
  }

  Future<void> _onTap() async {
    // Tell the main app to expand
    await FlutterOverlayWindow.shareData({'action': 'expand'});
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    // No Scaffold or Material — just the animation on a fully transparent canvas.
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: _onTap,
        child: FlameFrameAnimation(
          size: 90,
          urgent: _hasPending,
        ),
      ),
    );
  }
}
