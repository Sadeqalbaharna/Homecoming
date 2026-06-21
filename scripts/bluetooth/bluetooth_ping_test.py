#!/usr/bin/env python3
"""
Bluetooth Ping Test - Quick connectivity check on startup
Verifies Bluetooth adapter and speaker are reachable
"""

import paramiko
import logging
import sys
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_USER = "pi"
SPEAKER_MAC = "39:3E:58:14:40:4A"
SPEAKER_NAME = "TG-129C"

def run_remote_command(client, cmd):
    """Run command on remote Pi"""
    stdin, stdout, stderr = client.exec_command(cmd)
    out = stdout.read().decode('utf-8', errors='ignore').strip()
    err = stderr.read().decode('utf-8', errors='ignore').strip()
    return out, err

def bluetooth_ping(pi_ip):
    """Quick Bluetooth connectivity ping"""
    try:
        logger.info(f"\n📡 Bluetooth Ping to {pi_ip}...")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        # Check adapter status
        logger.info("   🔍 Checking Bluetooth adapter...")
        out, _ = run_remote_command(client, "hciconfig")
        
        if "UP" not in out:
            logger.warning("   ⚠️  Adapter DOWN, bringing up...")
            run_remote_command(client, "sudo hciconfig hci0 up")
            time.sleep(2)
        
        # Check speaker connection
        logger.info("   🔍 Checking speaker connection...")
        out, _ = run_remote_command(client, "bluetoothctl devices Connected")
        
        if SPEAKER_MAC in out:
            logger.info(f"   ✅ {SPEAKER_NAME} CONNECTED & READY")
            client.close()
            return 0
        else:
            logger.warning(f"   ⚠️  {SPEAKER_NAME} not connected")
            logger.info(f"   🔄 Reconnecting to {SPEAKER_NAME}...")
            run_remote_command(client, f"bluetoothctl connect {SPEAKER_MAC}")
            time.sleep(3)
            
            # Verify connection
            out, _ = run_remote_command(client, "bluetoothctl devices Connected")
            if SPEAKER_MAC in out:
                logger.info(f"   ✅ {SPEAKER_NAME} CONNECTED & READY")
                client.close()
                return 0
            else:
                logger.error(f"   ❌ {SPEAKER_NAME} connection failed")
                client.close()
                return 1
        
    except Exception as e:
        logger.error(f"   ❌ Bluetooth ping failed: {e}")
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logger.error("Usage: python bluetooth_ping_test.py <PI_IP>")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    sys.exit(bluetooth_ping(pi_ip))
