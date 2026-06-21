#!/usr/bin/env python3
"""
Reboot Pi and wait for recovery
"""

import paramiko
import logging
import time
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def reboot_pi():
    try:
        logger.info("Connecting to Pi for reboot...")
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            PI_IP,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        logger.info("Sending reboot command...")
        client.exec_command("sudo reboot")
        client.close()
        
        logger.info("✅ Reboot initiated")
        logger.info("\nWaiting 45 seconds for Pi to come back up...")
        time.sleep(45)
        
        logger.info("Attempting to reconnect...")
        for attempt in range(10):
            try:
                client = paramiko.SSHClient()
                client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                client.connect(
                    PI_IP,
                    username=PI_USER,
                    key_filename=str(Path.home() / ".ssh" / "id_rsa"),
                    timeout=5
                )
                logger.info("✅ Pi is back online!")
                
                # Check Bluetooth
                logger.info("\nChecking Bluetooth adapter status...")
                stdin, stdout, stderr = client.exec_command("hciconfig hci0")
                status = stdout.read().decode()
                logger.info(status)
                
                if "UP" in status:
                    logger.info("✅✅ BLUETOOTH ADAPTER IS UP!")
                    logger.info("\nNow testing connection to TG-129C...")
                    stdin, stdout, stderr = client.exec_command("bluetoothctl connect 39:3E:58:14:40:4A")
                    output = stdout.read().decode()
                    logger.info(output)
                    time.sleep(3)
                    
                    stdin, stdout, stderr = client.exec_command("bluetoothctl info 39:3E:58:14:40:4A")
                    info = stdout.read().decode()
                    if "Connected: yes" in info:
                        logger.info("✅✅✅ SPEAKER CONNECTED!")
                        logger.info("\nReady to play scene: python deploy_and_play_pirate_scene.py")
                    else:
                        logger.info("Speaker not connected yet. Info:")
                        logger.info(info)
                else:
                    logger.warning("Adapter still DOWN after reboot")
                    logger.info(status)
                
                client.close()
                return
                
            except Exception as e:
                logger.warning(f"Attempt {attempt+1}/10: Still booting... ({e})")
                time.sleep(5)
        
        logger.error("❌ Pi did not come back online")
        
    except Exception as e:
        logger.error(f"Error: {e}")

if __name__ == "__main__":
    reboot_pi()
