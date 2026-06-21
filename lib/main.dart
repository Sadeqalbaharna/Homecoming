// main.dart — canonical entry point for Kai.
// All app logic lives in main_mobile.dart.
// The Windows overlay is preserved (disabled) at lib/overlay/kai_overlay_disabled.dart.

import 'main_mobile.dart' as app;
// Registers the overlayMain() entry point used by FlutterOverlayWindow
// for the background-mode flame overlay. Must be imported here so the
// Dart VM includes it in the build (tree-shaking would otherwise drop it).
import 'flame_overlay_main.dart'; // ignore: unused_import

Future<void> main() => app.main();
