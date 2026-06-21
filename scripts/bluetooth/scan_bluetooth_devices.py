#!/usr/bin/env python3
"""
Bluetooth Device Scanner - Find and pair available devices
"""

import paramiko
import logging
import sys
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_USER = "pi"

def run_remote_command(client, cmd):
    """Run command on remote Pi"""
    stdin, stdout, stderr = client.exec_command(cmd)
    out = stdout.read().decode('utf-8', errors='ignore').strip()
    err = stderr.read().decode('utf-8', errors='ignore').strip()
    return out, err, stdout.channel.recv_exit_status()

def scan_bluetooth_devices(pi_ip):
    """Scan for available Bluetooth devices"""
    try:
        logger.info(f"\n📱 SCANNING BLUETOOTH DEVICES on {pi_ip}\n")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        # Scan for devices
        logger.info("🔍 Scanning for Bluetooth devices...")
        logger.info("   (Turn on your device if not already on)")
        
        out, _, _ = run_remote_command(client, "bluetoothctl scan on &")
        time.sleep(5)  # Let it scan
        run_remote_command(client, "killall bluetoothctl 2>/dev/null")
        
        # Get list of discovered devices
        logger.info("\n📋 DISCOVERED DEVICES:")
        out, _, _ = run_remote_command(client, "bluetoothctl devices")
        
        devices = []
        for line in out.split('\n'):
            if line.strip().startswith('Device'):
                parts = line.split()
                if len(parts) >= 3:
                    mac = parts[1]
                    name = ' '.join(parts[2:])
                    devices.append({'mac': mac, 'name': name})
                    logger.info(f"\n   {name}")
                    logger.info(f"   MAC: {mac}")
        
        if not devices:
            logger.warning("   No devices found")
            client.close()
            return None
        
        # Look for GL 91
        gl91 = None
        for dev in devices:
            if 'gl' in dev['name'].lower() and ('91' in dev['name'] or 'tws' in dev['name'].lower()):
                gl91 = dev
                break
        
        if gl91:
            logger.info(f"\n✅ FOUND: {gl91['name']} ({gl91['mac']})")
            logger.info("🔗 Pairing and connecting...")
            
            # Pair
            run_remote_command(client, f"bluetoothctl pair {gl91['mac']}")
            time.sleep(2)
            
            # Trust
            run_remote_command(client, f"bluetoothctl trust {gl91['mac']}")
            time.sleep(1)
            
            # Connect
            run_remote_command(client, f"bluetoothctl connect {gl91['mac']}")
            time.sleep(3)
            
            # Verify connection
            out, _, _ = run_remote_command(client, f"bluetoothctl info {gl91['mac']} | grep Connected")
            if "yes" in out.lower():
                logger.info(f"✅ Connected successfully!\n")
                client.close()
                return gl91['mac']
            else:
                logger.warning(f"⚠️  Connection may have failed")
        else:
            logger.warning("\n❌ GL 91 not found in scan results")
            logger.info("   Make sure GL 91 is powered on and in pairing mode")
        
        client.close()
        return None
        
    except Exception as e:
        logger.error(f"❌ Scan failed: {e}")
        import traceback
        traceback.print_exc()
        return None

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logger.error("Usage: python scan_bluetooth_devices.py <PI_IP>")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    device_mac = scan_bluetooth_devices(pi_ip)
    
    if device_mac:
        print(device_mac)
        sys.exit(0)
    else:
        sys.exit(1)
