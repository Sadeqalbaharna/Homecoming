#!/usr/bin/env python3
"""
Check if Bluetooth speaker is actually connected and accessible on Pi
"""

import paramiko
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def check_bluetooth():
    """SSH to Pi and check Bluetooth connection"""
    try:
        logger.info(f"🔌 Connecting to Pi: {PI_USER}@{PI_IP}")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        logger.info("✅ Connected to Pi\n")
        
        # Check 1: List Bluetooth devices
        logger.info("=" * 70)
        logger.info("CHECK 1: Bluetooth Devices")
        logger.info("=" * 70)
        stdin, stdout, stderr = client.exec_command("bluetoothctl list")
        for line in stdout:
            print(line.rstrip())
        
        # Check 2: Show TG-129C info
        logger.info("\n" + "=" * 70)
        logger.info("CHECK 2: TG-129C Device Info")
        logger.info("=" * 70)
        stdin, stdout, stderr = client.exec_command("bluetoothctl info 39:3E:58:14:40:4A")
        for line in stdout:
            print(line.rstrip())
        
        # Check 3: PulseAudio sinks
        logger.info("\n" + "=" * 70)
        logger.info("CHECK 3: PulseAudio Sinks")
        logger.info("=" * 70)
        stdin, stdout, stderr = client.exec_command("pactl list short sinks")
        for line in stdout:
            print(line.rstrip())
        
        # Check 4: Check if specific Bluetooth sink exists
        logger.info("\n" + "=" * 70)
        logger.info("CHECK 4: Verify Bluetooth Sink Exists")
        logger.info("=" * 70)
        stdin, stdout, stderr = client.exec_command("pactl get-sink-mute bluez_output.39_3E_58_14_40_4A.1")
        output = stdout.read().decode().strip()
        error = stderr.read().decode().strip()
        
        if "Mute" in output:
            logger.info(f"✅ Sink exists: {output}")
        else:
            logger.info(f"⚠️  Sink query result: {output}")
            if error:
                logger.error(f"Error: {error}")
        
        # Check 5: Test simple audio playback (1 second tone)
        logger.info("\n" + "=" * 70)
        logger.info("CHECK 5: Test Audio Playback (1 second tone)")
        logger.info("=" * 70)
        logger.info("Generating and playing 1-second test tone...")
        
        cmd = (
            "python3 -c \""
            "import subprocess; "
            "import time; "
            "cmd = ['mpv', '--audio-device=pulse/bluez_output.39_3E_58_14_40_4A.1', '--volume=20', 'https://www.youtube.com/watch?v=LXb3EKWsInQ']; "
            "proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE); "
            "time.sleep(2); "
            "proc.terminate(); "
            "print('Test tone played for 2 seconds')\""
        )
        
        stdin, stdout, stderr = client.exec_command(cmd, timeout=10)
        for line in stdout:
            print(line.rstrip())
        for line in stderr:
            print(f"STDERR: {line.rstrip()}")
        
        logger.info("\n✅ Bluetooth checks complete")
        client.close()
        
    except Exception as e:
        logger.error(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    check_bluetooth()
