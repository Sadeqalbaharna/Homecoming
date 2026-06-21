#!/usr/bin/env python3
"""
Fix Bluetooth hardware on Pi and connect speaker
"""

import paramiko
import logging
import time
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def fix_bluetooth():
    """SSH to Pi and fix Bluetooth hardware"""
    try:
        logger.info("")
        logger.info("=" * 70)
        logger.info("BLUETOOTH HARDWARE RESET & CONNECTION".center(70))
        logger.info("=" * 70)
        logger.info("")
        
        logger.info(f"🔌 Connecting to Pi: {PI_USER}@{PI_IP}")
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            PI_IP,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        logger.info("✅ Connected\n")
        
        # Step 1: Restart Bluetooth service
        logger.info("Step 1: Restarting Bluetooth service...")
        stdin, stdout, stderr = client.exec_command("sudo systemctl restart bluetooth")
        stdout.read()
        time.sleep(2)
        logger.info("✅ Bluetooth service restarted\n")
        
        # Step 2: Bring up Bluetooth adapter
        logger.info("Step 2: Bringing up Bluetooth adapter...")
        stdin, stdout, stderr = client.exec_command("sudo hciconfig hci0 up")
        output = stdout.read().decode()
        logger.info(output)
        time.sleep(2)
        logger.info("✅ Bluetooth adapter up\n")
        
        # Step 3: Enable Bluetooth power
        logger.info("Step 3: Enabling Bluetooth power...")
        stdin, stdout, stderr = client.exec_command("bluetoothctl power on")
        output = stdout.read().decode()
        logger.info(output)
        time.sleep(1)
        logger.info("")
        
        # Step 4: Connect to TG-129C
        logger.info("Step 4: Connecting to TG-129C speaker...")
        logger.info("   MAC: 39:3E:58:14:40:4A")
        stdin, stdout, stderr = client.exec_command("bluetoothctl connect 39:3E:58:14:40:4A")
        output = stdout.read().decode()
        logger.info(output)
        time.sleep(3)
        logger.info("")
        
        # Step 5: Verify connection
        logger.info("Step 5: Verifying connection...")
        stdin, stdout, stderr = client.exec_command("bluetoothctl info 39:3E:58:14:40:4A")
        output = stdout.read().decode()
        logger.info(output)
        
        if "Connected: yes" in output:
            logger.info("✅ TG-129C IS CONNECTED!\n")
        else:
            logger.warning("⚠️  Connection status unclear. Check above.\n")
        
        # Step 6: List Bluetooth devices
        logger.info("Step 6: Checking PulseAudio sinks...")
        stdin, stdout, stderr = client.exec_command("pactl list short sinks")
        output = stdout.read().decode()
        logger.info(output)
        
        logger.info("")
        logger.info("=" * 70)
        logger.info("✅ BLUETOOTH READY!".center(70))
        logger.info("=" * 70)
        logger.info("")
        logger.info("Next: python deploy_and_play_pirate_scene.py")
        logger.info("")
        
        client.close()
        
    except Exception as e:
        logger.error(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    fix_bluetooth()
