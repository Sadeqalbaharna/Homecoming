// lib/main_desktop.dart
import 'dart:io';
import 'dart:ui'; // Size
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:window_manager/window_manager.dart';
import 'overlay_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    // --- Acrylic: handle ALL versions via dynamic calls (no compile-time sig checks) ---
    try {
      // initialize(): some versions need it, some don't
      await ((acrylic.Window) as dynamic).initialize();
    } catch (_) {}

    try {
      // Prefer new signature: setEffect(effect: ..., color: ...)
      await ((acrylic.Window) as dynamic).setEffect(
        effect: acrylic.WindowEffect.transparent,
        color: Colors.transparent,
      );
    } catch (_) {
      // Fallback to old signature: setEffect(WindowEffect effect)
      try {
        await ((acrylic.Window) as dynamic).setEffect(
          acrylic.WindowEffect.transparent,
        );
      } catch (_) {}
    }

    // --- Window tweaks (stable across 0.3.9) ---
    try {
      // 0.3.9 expects named 'style'
      await (windowManager as dynamic).setTitleBarStyle(
        style: TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
    } catch (_) {}
    try { await windowManager.setHasShadow(false); } catch (_) {}
    try { await windowManager.setAlwaysOnTop(true); } catch (_) {}
    try { await windowManager.setResizable(false); } catch (_) {}
    try { await windowManager.setSize(const Size(440, 480)); } catch (_) {}
    try { await windowManager.center(); } catch (_) {}
    try { await windowManager.show(); } catch (_) {}
    try { await windowManager.focus(); } catch (_) {}
  }

  // Round avatar content; OS frame may still be rectangular
  runApp(
    const ClipOval(
      child: OverlayApp(
        lottieFile: 'assets/avatar/kai_talk.json',
      ),
    ),
  );
}
