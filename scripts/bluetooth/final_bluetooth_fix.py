#!/usr/bin/env python3
"""
Final Bluetooth fix - force adapter up and try connection
"""

import paramiko
import logging
import time
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def final_fix():
    """Final attempt to bring Bluetooth adapter up"""
    try:
        logger.info("")
        logger.info("=" * 70)
        logger.info("FINAL BLUETOOTH ADAPTER FIX".center(70))
        logger.info("=" * 70)
        logger.info("")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            PI_IP,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        logger.info("✅ Connected\n")
        
        # Try bringing adapter UP
        logger.info("Attempting: sudo hciconfig hci0 up")
        stdin, stdout, stderr = client.exec_command("sudo hciconfig hci0 up")
        output = stdout.read().decode()
        logger.info(output)
        time.sleep(2)
        
        # Check status
        logger.info("Checking adapter status...")
        stdin, stdout, stderr = client.exec_command("hciconfig hci0")
        status = stdout.read().decode()
        logger.info(status)
        
        if "DOWN" in status:
            logger.error("\n❌ Adapter still DOWN")
            logger.error("   This indicates a HARDWARE ISSUE with the Bluetooth adapter on the Pi")
            logger.error("   Options:")
            logger.error("   1. Try rebooting the Pi: sudo reboot")
            logger.error("   2. Check if Bluetooth is enabled in Pi firmware: sudo raspi-config")
            logger.error("   3. The Bluetooth module may be faulty and need replacement")
        elif "UP" in status:
            logger.info("✅ Adapter is UP!")
            
            # Try scanning for devices
            logger.info("\nScanning for Bluetooth devices...")
            stdin, stdout, stderr = client.exec_command("timeout 10 bluetoothctl scan on &")
            time.sleep(3)
            
            # Try connecting
            logger.info("Attempting connection to TG-129C...")
            stdin, stdout, stderr = client.exec_command("bluetoothctl connect 39:3E:58:14:40:4A")
            output = stdout.read().decode()
            logger.info(output)
            time.sleep(3)
            
            # Verify
            stdin, stdout, stderr = client.exec_command("bluetoothctl info 39:3E:58:14:40:4A")
            info = stdout.read().decode()
            
            if "Connected: yes" in info:
                logger.info("✅✅✅ SUCCESS! Speaker is connected!")
                logger.info("\nNext: python deploy_and_play_pirate_scene.py")
            else:
                logger.warning("⚠️  Still not connected. Check:")
                logger.warning("  1. Is TG-129C powered ON?")
                logger.warning("  2. Is speaker in Bluetooth pairing mode?")
                logger.warning("  3. Try pairing manually: bluetoothctl pair 39:3E:58:14:40:4A")
        else:
            logger.warning("⚠️  Unknown adapter status")
            logger.info(status)
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")

if __name__ == "__main__":
    final_fix()
