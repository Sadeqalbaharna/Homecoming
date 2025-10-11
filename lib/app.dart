// lib/app.dart
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'core/constants.dart';
import 'overlay/kai_overlay.dart';

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WindowListener {
  @override
  void initState() {
    super.initState();
    _initWindow();
  }

  Future<void> _initWindow() async {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();
    await acrylic.Window.initialize();
    await acrylic.Window.setEffect(effect: acrylic.WindowEffect.transparent);

    final windowOptions = WindowOptions(
      size: const Size(kCanvasWidth, kCanvasHeight),
      minimumSize: const Size(kCanvasWidth, kCanvasHeight),
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
      alwaysOnTop: kAlwaysOnTop,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: KaiOverlay(),
    );
  }
}
