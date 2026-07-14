// smart_tv_service.dart
//
// Controls smart TVs over local WiFi using brand-specific WebSocket APIs.
//
// Supported brands:
//   Samsung — WebSocket port 8001 (SSL fallback: 8002)
//   LG WebOS — WebSocket port 3000
//   Sony / Philips — placeholder (extend as needed)
//
// "Turn on" caveat: WiFi control only works when the TV is in standby
// (WiFi chip stays active). A fully powered-off TV requires Wake-on-LAN,
// which is added as a best-effort attempt before the WebSocket command.

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'network_discovery_service.dart';

// How long to wait after sending a WoL packet before trying WebSocket
const _wolWarmupMs = 8000;

class SmartTVService {
  static final SmartTVService _i = SmartTVService._();
  factory SmartTVService() => _i;
  SmartTVService._();

  // ── Samsung key map ─────────────────────────────────────────────────────────
  static const _samsungKeys = <String, String>{
    'on':           'KEY_POWERON',
    'off':          'KEY_POWEROFF',
    'power':        'KEY_POWER',
    'toggle':       'KEY_POWER',
    'volume_up':    'KEY_VOLUP',
    'volume_down':  'KEY_VOLDOWN',
    'mute':         'KEY_MUTE',
    'source':       'KEY_SOURCE',
    'hdmi1':        'KEY_HDMI1',
    'hdmi2':        'KEY_HDMI2',
    'home':         'KEY_HOME',
    'back':         'KEY_RETURN',
    'menu':         'KEY_MENU',
    'up':           'KEY_UP',
    'down':         'KEY_DOWN',
    'left':         'KEY_LEFT',
    'right':        'KEY_RIGHT',
    'ok':           'KEY_ENTER',
    'select':       'KEY_ENTER',
    'play':         'KEY_PLAY',
    'pause':        'KEY_PAUSE',
    'play_pause':   'KEY_PLAY',
    'stop':         'KEY_STOP',
    'rewind':       'KEY_REWIND',
    'fast_forward': 'KEY_FF',
    'channel_up':   'KEY_CHUP',
    'channel_down': 'KEY_CHDOWN',
  };

  // ── LG WebOS URI map ────────────────────────────────────────────────────────
  static const _lgUris = <String, String>{
    'off':          'ssap://system/turnOff',
    'volume_up':    'ssap://audio/volumeUp',
    'volume_down':  'ssap://audio/volumeDown',
    'mute':         'ssap://audio/setMute',
    'source':       'ssap://tv/switchInput',
    'home':         'ssap://system.launcher/open?id=com.webos.app.home',
    'back':         'ssap://com.webos.service.ime/sendEnterKey',
    'play':         'ssap://media.controls/play',
    'pause':        'ssap://media.controls/pause',
    'stop':         'ssap://media.controls/stop',
    'rewind':       'ssap://media.controls/rewind',
    'fast_forward': 'ssap://media.controls/fastForward',
    'channel_up':   'ssap://tv/channelUp',
    'channel_down': 'ssap://tv/channelDown',
  };

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Send [action] to [deviceId] (or the first known device if null).
  ///
  /// Common actions: on, off, volume_up, volume_down, mute, source,
  ///                 home, back, play, pause, channel_up, channel_down
  Future<String> controlTV({
    required String action,
    String? deviceId,
  }) async {
    // Try cached devices first; auto-discover if cache is empty.
    var devices = await NetworkDiscoveryService().loadKnownDevices();
    if (devices.isEmpty) {
      print('📺 [TV] No cached devices — auto-scanning...');
      devices = await NetworkDiscoveryService().discoverDevices();
    }
    if (devices.isEmpty) {
      return 'No TVs found on the network. Make sure the TV is on and connected to the same WiFi, then try again.';
    }

    // Match by id or partial name
    DiscoveredDevice device;
    if (deviceId != null) {
      device = devices.firstWhere(
        (d) => d.id == deviceId ||
               d.name.toLowerCase().contains(deviceId.toLowerCase()) ||
               d.brand.toLowerCase() == deviceId.toLowerCase(),
        orElse: () => devices.first,
      );
    } else {
      device = devices.first;
    }

    print('📺 [TV] ${device.name} — action: $action');

    switch (device.brand) {
      case 'samsung':
        return await _samsung(device, action);
      case 'lg':
        return await _lg(device, action);
      default:
        // Unknown brand — try Samsung protocol as it's most common
        return await _samsung(device, action);
    }
  }

  // ── Samsung WebSocket ───────────────────────────────────────────────────────

  Future<String> _samsung(DiscoveredDevice device, String action) async {
    final isOn = action.toLowerCase() == 'on';

    // ── Wake-on-LAN for power-on ─────────────────────────────────────────────
    if (isOn) {
      if (device.macAddress != null) {
        print('⚡ [TV] Sending WoL to ${device.macAddress}');
        await NetworkDiscoveryService.sendWakeOnLan(device.macAddress!);
        // Give the TV time to boot its network stack before WebSocket
        print('⏳ [TV] Waiting ${_wolWarmupMs}ms for TV to wake...');
        await Future.delayed(Duration(milliseconds: _wolWarmupMs));
      } else {
        // No MAC — try refreshing it from ARP (TV might have been on recently)
        final mac = await NetworkDiscoveryService.macFromArp(device.ip);
        if (mac != null) {
          await NetworkDiscoveryService.sendWakeOnLan(mac);
          await Future.delayed(Duration(milliseconds: _wolWarmupMs));
        } else {
          // MAC unknown — TV is likely fully off and we can't wake it
          return 'The TV appears to be fully powered off and I don\'t have its '
              'network address to send a wake signal. '
              'Please turn it on manually once, then say "scan for TVs" so I can '
              'remember how to wake it next time.';
        }
      }
    }

    final key = _samsungKeys[action.toLowerCase()] ?? 'KEY_${action.toUpperCase()}';

    // Try WS port 8001 first, fall back to WSS 8002
    for (final config in [
      (scheme: 'ws',  port: 8001),
      (scheme: 'wss', port: 8002),
    ]) {
      final result = await _samsungSend(device.ip, config.port, config.scheme, key);
      if (result != null) {
        print('✅ [TV] Samsung $key sent via ${config.scheme}:${config.port}');
        return 'Done — ${device.name} is now ${isOn ? "on" : action}.';
      }
    }

    return isOn
        ? 'Wake signal sent but the TV didn\'t respond yet — it may need a '
          'few more seconds. Try again or check that Wake-on-LAN is enabled '
          'in the TV\'s network settings.'
        : 'Could not reach ${device.name}. '
          'Make sure the TV is in standby and on the same WiFi.';
  }

  Future<String?> _samsungSend(
      String ip, int port, String scheme, String key) async {
    // Samsung requires the app name base64-encoded in the URL
    final appName = base64.encode(utf8.encode('Kai'));
    final uri = Uri.parse(
        '$scheme://$ip:$port/api/v2/channels/samsung.remote.control?name=$appName');

    WebSocketChannel? ch;
    try {
      ch = WebSocketChannel.connect(uri);
      await ch.ready.timeout(const Duration(seconds: 3));

      ch.sink.add(jsonEncode({
        'method': 'ms.remote.control',
        'params': {
          'Cmd':          'Click',
          'DataOfCmd':    key,
          'Option':       'false',
          'TypeOfRemote': 'SendRemoteKey',
        },
      }));

      // Give the TV time to process the command
      await Future.delayed(const Duration(milliseconds: 600));
      return 'ok';
    } on TimeoutException {
      return null;
    } catch (e) {
      print('⚠️ [TV] Samsung $scheme:$port failed: $e');
      return null;
    } finally {
      await ch?.sink.close();
    }
  }

  // ── LG WebOS WebSocket ──────────────────────────────────────────────────────

  Future<String> _lg(DiscoveredDevice device, String action) async {
    final uri = _lgUris[action.toLowerCase()];
    if (uri == null) {
      // Fallback: try Samsung key mapping for unknown actions
      return 'Action "$action" is not supported for LG TVs yet.';
    }

    WebSocketChannel? ch;
    try {
      ch = WebSocketChannel.connect(
          Uri.parse('ws://${device.ip}:${device.port}'));
      await ch.ready.timeout(const Duration(seconds: 4));

      // Register with LG (required before any command)
      ch.sink.add(jsonEncode({
        'id':   'register_0',
        'type': 'register',
        'payload': {
          'forcePairing': false,
          'pairingType':  'PROMPT',
          'manifest': {
            'manifestVersion': 1,
            'appDescription':  'Kai',
            'signed': {
              'appId':    'com.homecoming.kai',
              'vendorId': 'com.homecoming',
              'localizedAppNames':   {'': 'Kai'},
              'localizedVendorNames': {'': 'Homecoming'},
              'permissions': [
                'CONTROL_POWER', 'CONTROL_AUDIO',
                'CONTROL_INPUT_TV', 'CONTROL_DISPLAY',
              ],
            },
          },
          'client-key': '',
        },
      }));

      // Wait for registration acknowledgement
      await Future.delayed(const Duration(seconds: 1));

      // Send the actual command
      ch.sink.add(jsonEncode({
        'id':   'cmd_1',
        'type': 'request',
        'uri':  uri,
      }));

      await Future.delayed(const Duration(milliseconds: 500));
      print('✅ [TV] LG command sent: $uri');
      return 'Done — ${device.name}: $action.';
    } on TimeoutException {
      return 'Could not reach ${device.name}. '
          'Make sure the TV is on and on the same WiFi.';
    } catch (e) {
      print('❌ [TV] LG command failed: $e');
      return 'LG TV command failed: $e';
    } finally {
      await ch?.sink.close();
    }
  }
}
