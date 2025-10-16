import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

void main() {
  runApp(const TestApp());
}

class TestApp extends StatelessWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.blue,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  color: Colors.white,
                  child: const Text(
                    'Kai Test App\nIf you see this,\nthe app is running!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    // Request overlay permission if needed
                    final hasPermission = await FlutterOverlayWindow.isPermissionGranted();
                    if (!hasPermission) {
                      await FlutterOverlayWindow.requestPermission();
                    }
                    
                    // Show overlay
                    await FlutterOverlayWindow.showOverlay(
                      height: 200,
                      width: 200,
                      alignment: OverlayAlignment.center,
                      overlayTitle: "Kai",
                      overlayContent: '',
                    );
                  },
                  child: const Text('Show Overlay'),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Version: Test Build',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
