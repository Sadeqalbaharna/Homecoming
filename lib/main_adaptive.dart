// main.dart - Platform adaptive entry point
import 'package:flutter/foundation.dart';
import 'dart:io';

// Import both versions
import 'main_mobile.dart' as mobile;
import 'main.dart' as desktop show main;

Future<void> main() async {
  // Detect platform and run appropriate version
  if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
    // Run mobile version for web, Android, and iOS
    await mobile.main();
  } else {
    // Run desktop version for Windows, macOS, Linux
    await desktop.main();
  }
}