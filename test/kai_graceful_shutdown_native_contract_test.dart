import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native lifecycle bridge acknowledges before posting normal tray quit',
      () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final success = source.indexOf('result->Success();');
    final post = source.indexOf(
      'PostMessageW(GetHandle(), kKaiGracefulQuitMessage',
      success,
    );
    final handler = source.indexOf('case kKaiGracefulQuitMessage:');
    final quit = source.indexOf('QuitFromTray();', handler);

    expect(source, contains('"kai.homecoming/lifecycle"'));
    expect(source, contains('call.method_name() != "quitCoordinator"'));
    expect(success, greaterThanOrEqualTo(0));
    expect(post, greaterThan(success));
    expect(handler, greaterThan(post));
    expect(quit, greaterThan(handler));
    expect(source, contains('if (coordinator_worker_ && !quitting_)'));
  });

  test('ordinary coordinator WM_CLOSE still hides rather than exits', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final close = source.indexOf('case WM_CLOSE:');
    final tray = source.indexOf('case kKaiTrayMessage:', close);
    final branch = source.substring(close, tray);

    expect(branch, contains('coordinator_worker_ && !quitting_'));
    expect(branch, contains('ShowWindow(hwnd, SW_HIDE)'));
    expect(branch, isNot(contains('QuitFromTray')));
  });

  test('watchdog treats the shared normal exit path as deliberate', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();
    expect(source, contains('if (exit_code == EXIT_SUCCESS)'));
    expect(source, contains('return EXIT_SUCCESS;'));
    expect(source, contains('--coordinator-worker --background --recovered'));
  });

  test('headless coordinator does not register the crashing audio plugin', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final coordinator = source.indexOf('void RegisterCoordinatorPlugins(');
    final namespaceEnd = source.indexOf('}  // namespace', coordinator);
    final coordinatorPlugins = source.substring(coordinator, namespaceEnd);
    final selection = source.indexOf('if (coordinator_worker_) {');

    expect(coordinator, greaterThanOrEqualTo(0));
    expect(coordinatorPlugins, isNot(contains('AudioplayersWindowsPlugin')));
    expect(selection, greaterThan(namespaceEnd));
    expect(
      source.substring(selection, source.indexOf('SetChildContent', selection)),
      contains('RegisterCoordinatorPlugins'),
    );
    expect(source, contains('RegisterPlugins(flutter_controller_->engine())'));
  });
}
