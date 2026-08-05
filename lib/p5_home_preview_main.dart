// A window onto the P5 home. Runs alone, wired to nothing.
//
//   flutter run -d windows -t lib/p5_home_preview_main.dart
//   flutter run -d <phone> -t lib/p5_home_preview_main.dart
//
// See the cascade slam in, the avatar breathe, and — tap any bar — the diagonal
// comic-panel wipe cut to a placeholder and back. No Firebase, no keys, starts
// in a second. Change a tilt or a stagger in kai_p5_home.dart, hot reload, look.
//
// Same reason the chat has a preview: a layout you can only judge by launching
// the whole app and signing in is a layout nobody iterates on.
library;

import 'package:flutter/material.dart';

import 'screens/kai_p5_home.dart';
import 'widgets/kai_p5_chat.dart';

void main() => runApp(const _P5HomePreviewApp());

class _P5HomePreviewApp extends StatelessWidget {
  const _P5HomePreviewApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Kai — home preview',
        debugShowCheckedModeBanner: false,
        // Every menu item opens a placeholder so the WIPE can be felt without
        // the real screens. In main_mobile these `open:` builders become the
        // actual destinations (KaiP5ChatScreen, Brain3DScreen, …).
        home: KaiP5Home(
          statusLine: 'focused. mildly suspicious of the concept of sleep.',
          items: [
            for (final m in kKaiMenu)
              P5MenuItem(
                id: m.id,
                label: m.label,
                glyph: m.glyph,
                open: () => _Placeholder(title: m.label),
              ),
          ],
        ),
      );
}

/// What the wipe reveals in the preview — a red panel that names the screen and
/// lets you sweep back. Stands in for the real destination.
class _Placeholder extends StatelessWidget {
  final String title;
  const _Placeholder({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: P5Background(
        child: SafeArea(
          child: Center(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Transform.rotate(
                angle: -0.03,
                child: Container(
                  color: P5Palette.ink,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: P5Palette.paper,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'tap to sweep back',
                        style: TextStyle(
                          color: P5Palette.kaiAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
