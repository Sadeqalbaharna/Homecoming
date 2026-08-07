import 'package:flutter/services.dart';

import 'kai_core_client.dart';

/// Sends the real Kai Core heartbeat state to the native Windows taskbar.
///
/// Other platforms intentionally ignore this channel. Their visible heartbeat
/// belongs in their own UI until they have an enrolled connection to Kai Core.
class KaiTaskbarHeartbeat {
  KaiTaskbarHeartbeat._();

  static const MethodChannel _channel = MethodChannel('kai.homecoming/taskbar');

  static Future<void> setStatus(KaiCoreHeartbeatStatus status) async {
    try {
      await _channel.invokeMethod<void>(
        'setHeartbeatState',
        status.phase.name,
      );
    } on MissingPluginException {
      // Expected on Android/iOS and in widget tests.
    } on PlatformException {
      // Taskbar telemetry must never make the app itself unavailable.
    }
  }
}
