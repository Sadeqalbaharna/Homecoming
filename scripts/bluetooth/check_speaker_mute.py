#!/usr/bin/env python3
"""
Check if speaker is muted
"""

import paramiko
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def check_mute():
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        logger.info("Checking speaker mute status...\n")
        
        # Get mute status
        stdin, stdout, stderr = client.exec_command(
            "pactl get-sink-mute bluez_output.39_3E_58_14_40_4A.1"
        )
        mute_status = stdout.read().decode().strip()
        logger.info(f"Mute status: {mute_status}")
        
        if "yes" in mute_status:
            logger.warning("⚠️  Speaker is MUTED - unmuting...")
            stdin, stdout, stderr = client.exec_command(
                "pactl set-sink-mute bluez_output.39_3E_58_14_40_4A.1 0"
            )
            logger.info("✅ Speaker unmuted")
        else:
            logger.info("✅ Speaker is NOT muted")
        
        # Check volume
        stdin, stdout, stderr = client.exec_command(
            "pactl get-sink-volume bluez_output.39_3E_58_14_40_4A.1"
        )
        volume = stdout.read().decode().strip()
        logger.info(f"Volume: {volume}")
        
        # Set to 100%
        logger.info("\nSetting volume to 100%...")
        stdin, stdout, stderr = client.exec_command(
            "pactl set-sink-volume bluez_output.39_3E_58_14_40_4A.1 100%"
        )
        
        stdin, stdout, stderr = client.exec_command(
            "pactl get-sink-volume bluez_output.39_3E_58_14_40_4A.1"
        )
        volume = stdout.read().decode().strip()
        logger.info(f"New volume: {volume}")
        
        logger.info("\n✅ Speaker should now be loud and ready for audio")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")

if __name__ == "__main__":
    check_mute()
