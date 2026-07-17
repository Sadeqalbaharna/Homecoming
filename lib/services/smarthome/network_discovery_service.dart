// network_discovery_service.dart
//
// Discovers smart TVs on the local WiFi network using two strategies:
//   1. SSDP (UPnP M-SEARCH multicast) — fast, TVs announce themselves
//   2. Port probe fallback — scans subnet for known TV ports
//
// Discovered devices are saved to Firebase /devices/tvs so Kai remembers
// them between sessions without re-scanning every time.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../core/kai_db.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class DiscoveredDevice {
  final String id;      // e.g. "samsung_192.168.1.5"
  final String name;    // e.g. "Samsung TV (192.168.1.5)"
  final String brand;   // "samsung" | "lg" | "sony" | "philips" | "unknown"
  final String ip;
  final int port;
  final String? macAddress; // for Wake-on-LAN (future use)

  DiscoveredDevice({
    required this.id,
    required this.name,
    required this.brand,
    required this.ip,
    required this.port,
    this.macAddress,
  });

  Map<String, dynamic> toMap() => {
    'id':    id,
    'name':  name,
    'brand': brand,
    'ip':    ip,
    'port':  port,
    if (macAddress != null) 'macAddress': macAddress,
  };

  factory DiscoveredDevice.fromMap(Map<dynamic, dynamic> m) => DiscoveredDevice(
    id:         m['id']    as String,
    name:       m['name']  as String,
    brand:      m['brand'] as String,
    ip:         m['ip']    as String,
    port:       (m['port'] as num).toInt(),
    macAddress: m['macAddress'] as String?,
  );

  @override
  String toString() => '$name ($brand @ $ip:$port)';
}

// ── Service ───────────────────────────────────────────────────────────────────

class NetworkDiscoveryService {
  static final NetworkDiscoveryService _i = NetworkDiscoveryService._();
  factory NetworkDiscoveryService() => _i;
  NetworkDiscoveryService._();

  static const _ssdpAddress = '239.255.255.250';
  static const _ssdpPort    = 1900;

  // Known TV ports → brand
  static const _tvPorts = <int, String>{
    8001: 'samsung',
    8002: 'samsung',
    3000: 'lg',
    1925: 'philips',
    52235: 'sony',
  };

  static const _ssdpMessage =
      'M-SEARCH * HTTP/1.1\r\n'
      'HOST: 239.255.255.250:1900\r\n'
      'MAN: "ssdp:discover"\r\n'
      'MX: 3\r\n'
      'ST: ssdp:all\r\n'
      '\r\n';

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Scan the local network for smart TVs.
  /// Returns found devices and persists them to Firebase.
  Future<List<DiscoveredDevice>> discoverDevices({
    void Function(DiscoveredDevice)? onFound,
  }) async {
    final found = <String, DiscoveredDevice>{}; // keyed by IP to deduplicate

    // ── Strategy 1: SSDP ────────────────────────────────────────────────────
    print('📡 [Discovery] Starting SSDP scan...');
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, 0,
        reuseAddress: true,
      );

      final data = utf8.encode(_ssdpMessage);
      socket.send(data, InternetAddress(_ssdpAddress), _ssdpPort);

      final done = Completer<void>();
      Timer(const Duration(seconds: 4), () {
        if (!done.isCompleted) done.complete();
      });

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket.receive();
        if (dg == null) return;
        final text = utf8.decode(dg.data, allowMalformed: true);
        final sourceIp = dg.address.address;
        _parseSSDP(text, sourceIp).then((device) {
          if (device != null && !found.containsKey(device.ip)) {
            found[device.ip] = device;
            print('📺 [Discovery] SSDP found: $device');
            onFound?.call(device);
          }
        });
      });

      await done.future;
      socket.close();
    } catch (e) {
      print('⚠️ [Discovery] SSDP failed ($e) — will try port scan');
    }

    // ── Strategy 2: port probe fallback ─────────────────────────────────────
    if (found.isEmpty) {
      print('🔍 [Discovery] No SSDP responses — scanning subnet...');
      final probed = await _portScan(onFound: (d) {
        if (!found.containsKey(d.ip)) {
          found[d.ip] = d;
          onFound?.call(d);
        }
      });
      for (final d in probed) {
        found.putIfAbsent(d.ip, () => d);
      }
    }

    final devices = found.values.toList();
    print('✅ [Discovery] Found ${devices.length} device(s)');

    // Persist to Firebase
    if (devices.isNotEmpty) {
      try {
        final ref = KaiDb.instance.ref('devices/tvs');
        final map = {for (final d in devices) d.id: d.toMap()};
        await ref.set(map);
        print('💾 [Discovery] Saved to Firebase');
      } catch (e) {
        print('⚠️ [Discovery] Firebase save failed: $e');
      }
    }

    return devices;
  }

  /// Load previously discovered devices from Firebase (no network scan).
  Future<List<DiscoveredDevice>> loadKnownDevices() async {
    try {
      final snap = await KaiDb.instance.ref('devices/tvs').get();
      if (!snap.exists || snap.value == null) return [];
      final map = snap.value as Map<dynamic, dynamic>;
      return map.values
          .map((v) => DiscoveredDevice.fromMap(v as Map<dynamic, dynamic>))
          .toList();
    } catch (e) {
      print('⚠️ [Discovery] loadKnownDevices failed: $e');
      return [];
    }
  }

  // ── SSDP parsing ────────────────────────────────────────────────────────────

  Future<DiscoveredDevice?> _parseSSDP(String response, String sourceIp) async {
    // Only process M-SEARCH responses and NOTIFY announcements
    if (!response.contains('HTTP/1.1 200') &&
        !response.toUpperCase().contains('NOTIFY')) return null;

    // Extract IP from LOCATION header (more reliable than source address)
    final locMatch = RegExp(r'LOCATION:\s*https?://([^:/\s]+)', caseSensitive: false)
        .firstMatch(response);
    final ip = locMatch?.group(1) ?? sourceIp;

    // Extract brand from SERVER header
    final srvMatch = RegExp(r'SERVER:\s*([^\r\n]+)', caseSensitive: false)
        .firstMatch(response);
    final server = (srvMatch?.group(1) ?? '').toLowerCase();

    // Extract device type from ST / NT header
    final stMatch = RegExp(r'(?:ST|NT):\s*([^\r\n]+)', caseSensitive: false)
        .firstMatch(response);
    final st = (stMatch?.group(1) ?? '').toLowerCase();

    // Determine brand
    String brand;
    int port;
    if (server.contains('samsung') || st.contains('samsung')) {
      brand = 'samsung'; port = 8001;
    } else if (server.contains('lg') || server.contains('webos') ||
               st.contains('lg')) {
      brand = 'lg'; port = 3000;
    } else if (server.contains('sony') || st.contains('sony')) {
      brand = 'sony'; port = 52235;
    } else if (server.contains('philips') || st.contains('philips')) {
      brand = 'philips'; port = 1925;
    } else {
      // Check if it looks like a TV at all
      final isTV = response.toLowerCase().let((r) =>
          r.contains('tv') || r.contains('dial') ||
          r.contains('mediarenderer') || r.contains('remotecontrol'));
      if (!isTV) return null;
      brand = 'unknown'; port = 8001;
    }

    final mac = await macFromArp(ip);
    final safeId = ip.replaceAll('.', '_');
    return DiscoveredDevice(
      id:         '${brand}_$safeId',
      name:       '${_brandLabel(brand)} TV ($ip)',
      brand:      brand,
      ip:         ip,
      port:       port,
      macAddress: mac,
    );
  }

  // ── Port scan ────────────────────────────────────────────────────────────────

  Future<List<DiscoveredDevice>> _portScan({
    void Function(DiscoveredDevice)? onFound,
  }) async {
    // Determine local subnet
    String? subnet;
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            subnet = '${parts[0]}.${parts[1]}.${parts[2]}.';
            break;
          }
        }
        if (subnet != null) break;
      }
    } catch (_) {}

    if (subnet == null) {
      print('⚠️ [Discovery] Cannot determine subnet for port scan');
      return [];
    }

    print('🔍 [Discovery] Probing $subnet 1-254 on TV ports...');
    final results = <DiscoveredDevice>[];
    final futures = <Future>[];

    for (int host = 1; host <= 254; host++) {
      final ip = '$subnet$host';
      for (final entry in _tvPorts.entries) {
        futures.add(
          _probePort(ip, entry.key, entry.value).then((d) {
            if (d != null) {
              results.add(d);
              onFound?.call(d);
            }
          }).catchError((_) {}),
        );
      }
    }

    await Future.wait(futures);
    return results;
  }

  Future<DiscoveredDevice?> _probePort(String ip, int port, String brand) async {
    try {
      final sock = await Socket.connect(
        ip, port,
        timeout: const Duration(milliseconds: 250),
      );
      sock.destroy();
      print('📺 [Discovery] Port hit: $ip:$port ($brand)');
      final mac = await macFromArp(ip);
      final safeId = ip.replaceAll('.', '_');
      return DiscoveredDevice(
        id:         '${brand}_$safeId',
        name:       '${_brandLabel(brand)} TV ($ip)',
        brand:      brand,
        ip:         ip,
        port:       port,
        macAddress: mac,
      );
    } catch (_) {
      return null;
    }
  }

  /// Read the kernel ARP table to get a MAC address for [ip].
  /// Works on Android without any special permissions.
  static Future<String?> macFromArp(String ip) async {
    try {
      final arp = await File('/proc/net/arp').readAsString();
      for (final line in arp.split('\n').skip(1)) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 4 && parts[0] == ip) {
          final mac = parts[3];
          if (mac != '00:00:00:00:00:00' && mac.contains(':')) {
            print('🔍 [ARP] $ip → $mac');
            return mac;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Send a Wake-on-LAN magic packet to [macAddress] on the broadcast network.
  static Future<void> sendWakeOnLan(String macAddress) async {
    try {
      final mac = macAddress
          .split(macAddress.contains(':') ? ':' : '-')
          .map((h) => int.parse(h, radix: 16))
          .toList();
      if (mac.length != 6) return;

      // Magic packet: 6×0xFF + MAC repeated 16 times = 102 bytes
      final packet = Uint8List(102);
      for (int i = 0; i < 6; i++) packet[i] = 0xFF;
      for (int rep = 0; rep < 16; rep++) {
        for (int b = 0; b < 6; b++) {
          packet[6 + rep * 6 + b] = mac[b];
        }
      }

      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send(packet, InternetAddress('255.255.255.255'), 9);
      socket.send(packet, InternetAddress('255.255.255.255'), 7); // some TVs use port 7
      socket.close();
      print('⚡ [WoL] Magic packet sent to $macAddress');
    } catch (e) {
      print('⚠️ [WoL] Failed: $e');
    }
  }

  String _brandLabel(String brand) {
    const labels = {
      'samsung': 'Samsung',
      'lg':      'LG',
      'sony':    'Sony',
      'philips': 'Philips',
    };
    return labels[brand] ?? 'Smart';
  }
}

// Small utility extension
extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}
