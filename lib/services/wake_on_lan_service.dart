import 'dart:io';
import 'dart:typed_data';

class WakeOnLanService {
  // Pi's MAC address (you'll need to get this)
  static const String piMacAddress = "dc:a6:32:xx:xx:xx"; // Replace with actual MAC
  static const String piIpAddress = "192.168.29.5";
  
  /// Send Wake-on-LAN magic packet to wake up the Pi
  Future<bool> wakePi() async {
    try {
      print('🌅 [WOL] Sending Wake-on-LAN packet to Pi...');
      
      // Create magic packet
      final magicPacket = _createMagicPacket(piMacAddress);
      
      // Send UDP broadcast packet on port 9
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      
      final broadcastAddress = InternetAddress('255.255.255.255');
      socket.send(magicPacket, broadcastAddress, 9);
      socket.close();
      
      print('✅ [WOL] Magic packet sent successfully');
      
      // Wait a moment, then check if Pi responds
      await Future.delayed(Duration(seconds: 5));
      return await _checkPiOnline();
      
    } catch (e) {
      print('❌ [WOL] Error sending wake packet: $e');
      return false;
    }
  }
  
  /// Create WoL magic packet
  Uint8List _createMagicPacket(String macAddress) {
    // Remove separators and convert to hex
    final cleanMac = macAddress.replaceAll(RegExp(r'[:-]'), '');
    final macBytes = <int>[];
    
    for (int i = 0; i < cleanMac.length; i += 2) {
      final hexByte = cleanMac.substring(i, i + 2);
      macBytes.add(int.parse(hexByte, radix: 16));
    }
    
    // Magic packet: 6 bytes of 0xFF + 16 repetitions of MAC address
    final packet = <int>[];
    
    // Add 6 bytes of 0xFF
    for (int i = 0; i < 6; i++) {
      packet.add(0xFF);
    }
    
    // Add MAC address 16 times
    for (int i = 0; i < 16; i++) {
      packet.addAll(macBytes);
    }
    
    return Uint8List.fromList(packet);
  }
  
  /// Check if Pi is online by testing consciousness API
  Future<bool> _checkPiOnline() async {
    try {
      final socket = await Socket.connect(piIpAddress, 5001, timeout: Duration(seconds: 3));
      socket.destroy();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Wake Pi and wait for Firebase listener to be ready
  Future<bool> wakeAndWaitForListener() async {
    print('🚀 [WOL] Starting Pi wake-up sequence...');
    
    // Check if already online
    if (await _checkPiOnline()) {
      print('✅ [WOL] Pi is already online!');
      return true;
    }
    
    // Send wake packet
    final wakeSuccess = await wakePi();
    if (!wakeSuccess) {
      print('❌ [WOL] Failed to wake Pi');
      return false;
    }
    
    // Wait for Firebase listener to start (up to 30 seconds)
    print('⏳ [WOL] Waiting for Firebase listener to start...');
    for (int i = 0; i < 30; i++) {
      await Future.delayed(Duration(seconds: 1));
      
      if (await _checkPiOnline()) {
        print('✅ [WOL] Pi and Firebase listener are ready!');
        return true;
      }
      
      if (i % 5 == 0) {
        print('⏳ [WOL] Still waiting... (${i}s)');
      }
    }
    
    print('⚠️ [WOL] Pi woke up but Firebase listener not responding');
    return false;
  }
}