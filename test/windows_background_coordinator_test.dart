import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('closing the Windows room hides it without killing Central Kai', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(source, contains('case WM_CLOSE:'));
    expect(source, contains('coordinator_worker_ && !quitting_'));
    expect(source, contains('ShowWindow(hwnd, SW_HIDE)'));
    expect(source, contains('kKaiTrayMessage'));
    expect(source, contains('Quit Kai completely'));
    expect(source, contains('PaintTrayHeartbeat(icon)'));
  });

  test('Windows sign-in starts the coordinator hidden', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();

    expect(source, contains('Kai Homecoming'));
    expect(source, contains('CurrentVersion\\\\Run'));
    expect(source, contains('--coordinator-worker --background'));
    expect(source, contains('if (coordinator_worker)'));
    expect(source, contains('coordinator_worker);'));
  });

  test('Windows runner restarts Kai after abnormal coordinator exit', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();

    expect(source, contains('StartKaiWatchdog()'));
    expect(source, contains('--watchdog'));
    expect(source, contains('WaitForSingleObject(watched, INFINITE)'));
    expect(source, contains('if (exit_code == EXIT_SUCCESS)'));
    expect(source, contains('--coordinator-worker --background --recovered'));
  });

  test('tray opens a separate desktop room instead of revealing the worker',
      () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(source, contains('void FlutterWindow::LaunchDesktopRoom()'));
    expect(source, contains('if (coordinator_worker_)'));
    expect(source, contains('LaunchDesktopRoom();'));
  });

  test('only one central coordinator can own the queue', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();

    expect(source, contains('KaiHomecomingCentralCoordinator'));
    expect(source, contains('ERROR_ALREADY_EXISTS'));
  });
}
