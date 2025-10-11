// lib/main.dart
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;

import 'src/app/app.dart'; // your MaterialApp.router etc.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init window manager
  await windowManager.ensureInitialized();
  await acrylic.Window.initialize();

  const size = Size(300, 300); // avatar window size
  final screen = await windowManager.getPrimaryDisplay();
  final bounds = screen.bounds;

  // Position bottom-right with some margin
  final dx = bounds.right - size.width - 24;
  final dy = bounds.bottom - size.height - 64;

  WindowOptions opts = const WindowOptions(
    size: size,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    center: false,
    titleBarStyle: TitleBarStyle.hidden, // frameless
  );

  await windowManager.waitUntilReadyToShow(opts, () async {
    // Transparency effect
    await acrylic.Window.setEffect(
      effect: acrylic.WindowEffect.transparent,
      color: Colors.transparent,
    );
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setResizable(false);
    await windowManager.setMovable(true);
    await windowManager.setPosition(Offset(dx, dy));
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const HomecomingAppDesktopOverlay());
}

/// A tiny app that just draws the avatar, no scaffold chrome.
class HomecomingAppDesktopOverlay extends StatelessWidget {
  const HomecomingAppDesktopOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.transparent, // crucial
      ),
      home: const _OverlayRoot(),
    );
  }
}

import 'src/overlay/avatar_overlay.dart';

class _OverlayRoot extends StatefulWidget {
  const _OverlayRoot();

  @override
  State<_OverlayRoot> createState() => _OverlayRootState();
}

class _OverlayRootState extends State<_OverlayRoot> {
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The avatar (only thing visible)
        Positioned.fill(
          child: Align(
            alignment: Alignment.bottomRight,
            child: GestureDetector(
              onTap: () => setState(() => _menuOpen = !_menuOpen),
              child: const SizedBox(width: 260, height: 260, child: AvatarOverlay()),
            ),
          ),
        ),

        // Tiny popover
        if (_menuOpen)
          Positioned(
            right: 260, bottom: 36,
            child: Material(
              elevation: 12,
              color: const Color(0xF2FFFFFF),
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Item('Start recording', () { /* call voice.start() */ setState(()=>_menuOpen=false); }),
                  const Divider(height: 1),
                  _Item('Stop & send', () { /* call voice.stopAndSend() */ setState(()=>_menuOpen=false); }),
                  const Divider(height: 1),
                  _Item('Quit', () { windowManager.close(); }),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Item(this.label, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text('', style: TextStyle(fontSize: 14)),
      ).copyWith(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(label, style: const TextStyle(fontSize: 14)),
      )),
    );
  }
}
