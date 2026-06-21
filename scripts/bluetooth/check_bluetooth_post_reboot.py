#!/usr/bin/env python3
"""
Check Bluetooth after reboot
"""

import paramiko
import logging
import time
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def check_bluetooth():
    try:
        logger.info("Connecting to Pi...")
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            PI_IP,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        logger.info("✅ Connected\n")
        
        # Check Bluetooth
        logger.info("Checking Bluetooth adapter status...")
        stdin, stdout, stderr = client.exec_command("hciconfig hci0")
        status = stdout.read().decode()
        logger.info(status)
        
        if "UP" in status:
            logger.info("✅ BLUETOOTH ADAPTER IS UP AFTER REBOOT!\n")
            
            # Try connecting
            logger.info("Attempting to connect to TG-129C (39:3E:58:14:40:4A)...")
            stdin, stdout, stderr = client.exec_command("bluetoothctl connect 39:3E:58:14:40:4A")
            output = stdout.read().decode()
            logger.info(output)
            time.sleep(3)
            
            # Check status
            stdin, stdout, stderr = client.exec_command("bluetoothctl info 39:3E:58:14:40:4A")
            info = stdout.read().decode()
            
            if "Connected: yes" in info:
                logger.info("✅✅✅ SPEAKER CONNECTED!")
                logger.info("\n" + "="*70)
                logger.info("READY TO PLAY SCENE!".center(70))
                logger.info("="*70)
                logger.info("\nRun: python deploy_and_play_pirate_scene.py")
            else:
                logger.warning("⚠️  Not connected yet. Details:")
                logger.info(info)
                logger.warning("\nChecking PulseAudio...")
                stdin, stdout, stderr = client.exec_command("pactl list short sinks")
                sinks = stdout.read().decode()
                logger.info(sinks)
        else:
            logger.error("❌ Bluetooth still DOWN after reboot - HARDWARE ISSUE")
            logger.info(status)
            logger.error("\nPossible causes:")
            logger.error("1. Bluetooth module disabled in Pi firmware")
            logger.error("2. Physical Bluetooth chip failure")
            logger.error("3. Power delivery issue to Bluetooth module")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")

if __name__ == "__main__":
    check_bluetooth()
