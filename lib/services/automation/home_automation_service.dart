/// Home Automation Service
/// Kai's interface to control smart home devices via Firebase
library;

import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../core/firebase_service.dart';

class HomeAutomationService {
  static final HomeAutomationService _instance = HomeAutomationService._internal();
  factory HomeAutomationService() => _instance;
  HomeAutomationService._internal();

  /// Send command to home device
  Future<bool> sendCommand({
    required String personaId,
    required String deviceId,
    required String target,
    required String action,
    Map<String, dynamic>? params,
  }) async {
    if (!FirebaseService.isAvailable) {
      print('❌ [HomeAuto] Firebase not available');
      return false;
    }

    try {
      final commandId = 'cmd_${DateTime.now().millisecondsSinceEpoch}';
      final commandRef = FirebaseDatabase.instance
          .ref('home_automation/$personaId/commands/$commandId');

      final commandData = {
        'device': deviceId,
        'target': target,
        'action': action,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        if (params != null) ...params,
      };

      await commandRef.set(commandData);
      print('✅ [HomeAuto] Command sent: $action on $target');

      // Wait for response (with timeout)
      final response = await _waitForResponse(personaId, commandId);
      
      return response;
    } catch (e) {
      print('❌ [HomeAuto] Failed to send command: $e');
      return false;
    }
  }

  /// Wait for command response from device
  Future<bool> _waitForResponse(String personaId, String commandId) async {
    try {
      final responseRef = FirebaseDatabase.instance
          .ref('home_automation/$personaId/responses/$commandId');

      // Wait up to 10 seconds for response
      final completer = Completer<bool>();
      Timer? timeout;

      final subscription = responseRef.onValue.listen((event) {
        if (event.snapshot.exists) {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          final success = data['success'] as bool? ?? false;
          
          if (success) {
            print('✅ [HomeAuto] Command succeeded: ${data['message']}');
          } else {
            print('❌ [HomeAuto] Command failed: ${data['error']}');
          }
          
          if (!completer.isCompleted) {
            completer.complete(success);
          }
        }
      });

      timeout = Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          print('⏱️ [HomeAuto] Command timeout');
          completer.complete(false);
        }
      });

      final result = await completer.future;
      
      // Cleanup
      await subscription.cancel();
      timeout.cancel();
      
      // Delete response
      try {
        await responseRef.remove();
      } catch (e) {
        // Ignore cleanup errors
      }

      return result;
    } catch (e) {
      print('❌ [HomeAuto] Error waiting for response: $e');
      return false;
    }
  }

  /// Get device status
  Future<DeviceStatus?> getDeviceStatus({
    required String personaId,
    required String deviceId,
  }) async {
    if (!FirebaseService.isAvailable) return null;

    try {
      final statusRef = FirebaseDatabase.instance
          .ref('home_automation/$personaId/status/$deviceId');

      final snapshot = await statusRef.get();

      if (!snapshot.exists) {
        print('⚠️ [HomeAuto] Device not found: $deviceId');
        return null;
      }

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      return DeviceStatus.fromMap(data);
    } catch (e) {
      print('❌ [HomeAuto] Failed to get status: $e');
      return null;
    }
  }

  /// List all devices for a persona
  Future<List<DeviceStatus>> listDevices(String personaId) async {
    if (!FirebaseService.isAvailable) return [];

    try {
      final statusRef = FirebaseDatabase.instance
          .ref('home_automation/$personaId/status');

      final snapshot = await statusRef.get();

      if (!snapshot.exists) {
        return [];
      }

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final devices = <DeviceStatus>[];

      for (final entry in data.entries) {
        try {
          final deviceData = Map<String, dynamic>.from(entry.value as Map);
          devices.add(DeviceStatus.fromMap(deviceData));
        } catch (e) {
          print('⚠️ [HomeAuto] Failed to parse device: ${entry.key}');
        }
      }

      return devices;
    } catch (e) {
      print('❌ [HomeAuto] Failed to list devices: $e');
      return [];
    }
  }

  /// Listen to device status changes
  Stream<DeviceStatus> watchDevice({
    required String personaId,
    required String deviceId,
  }) {
    final controller = StreamController<DeviceStatus>.broadcast();

    if (!FirebaseService.isAvailable) {
      controller.close();
      return controller.stream;
    }

    try {
      final statusRef = FirebaseDatabase.instance
          .ref('home_automation/$personaId/status/$deviceId');

      final subscription = statusRef.onValue.listen((event) {
        if (event.snapshot.exists) {
          try {
            final data = Map<String, dynamic>.from(event.snapshot.value as Map);
            final status = DeviceStatus.fromMap(data);
            controller.add(status);
          } catch (e) {
            print('❌ [HomeAuto] Failed to parse status update: $e');
          }
        }
      });

      controller.onCancel = () {
        subscription.cancel();
      };
    } catch (e) {
      print('❌ [HomeAuto] Failed to watch device: $e');
      controller.close();
    }

    return controller.stream;
  }

  /// Helper methods for common actions
  Future<bool> turnOn(String personaId, String deviceId, String target) {
    return sendCommand(
      personaId: personaId,
      deviceId: deviceId,
      target: target,
      action: 'turn_on',
    );
  }

  Future<bool> turnOff(String personaId, String deviceId, String target) {
    return sendCommand(
      personaId: personaId,
      deviceId: deviceId,
      target: target,
      action: 'turn_off',
    );
  }

  Future<bool> toggle(String personaId, String deviceId, String target) {
    return sendCommand(
      personaId: personaId,
      deviceId: deviceId,
      target: target,
      action: 'toggle',
    );
  }

  Future<bool> blink(String personaId, String deviceId, String target, {int duration = 3}) {
    return sendCommand(
      personaId: personaId,
      deviceId: deviceId,
      target: target,
      action: 'blink',
      params: {'duration': duration},
    );
  }
}

/// Device status model
class DeviceStatus {
  final String deviceId;
  final String deviceName;
  final bool online;
  final DateTime lastUpdated;
  final Map<String, DeviceState> devices;

  DeviceStatus({
    required this.deviceId,
    required this.deviceName,
    required this.online,
    required this.lastUpdated,
    required this.devices,
  });

  factory DeviceStatus.fromMap(Map<String, dynamic> map) {
    final devicesMap = map['devices'] as Map<String, dynamic>? ?? {};
    final devices = <String, DeviceState>{};

    for (final entry in devicesMap.entries) {
      try {
        final deviceData = Map<String, dynamic>.from(entry.value as Map);
        devices[entry.key] = DeviceState(
          name: deviceData['name'] as String? ?? entry.key,
          state: deviceData['state'] as String? ?? 'unknown',
        );
      } catch (e) {
        // Skip invalid device
      }
    }

    return DeviceStatus(
      deviceId: map['device_id'] as String? ?? 'unknown',
      deviceName: map['device_name'] as String? ?? 'Unknown Device',
      online: map['online'] as bool? ?? false,
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(
        map['last_updated'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
      devices: devices,
    );
  }

  bool get isOnline => online && 
      DateTime.now().difference(lastUpdated).inMinutes < 5;
}

/// Individual device state
class DeviceState {
  final String name;
  final String state; // 'on', 'off', 'unknown'

  DeviceState({
    required this.name,
    required this.state,
  });

  bool get isOn => state == 'on';
  bool get isOff => state == 'off';
}
