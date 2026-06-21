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

import 'widgets/flame_avatar.dart';

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: _FlameOverlay(),
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
    // Transparent scaffold — only the flame is visible
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: FlameAvatarCompact(
          size: 64,
          urgent: _hasPending,
          onTap: _onTap,
        ),
      ),
    );
  }
}
