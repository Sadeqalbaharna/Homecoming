#!/usr/bin/env python3
"""
Deploy and run pirate ship scene with automatic Bluetooth wake-up
"""

import paramiko
import logging
import time
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"
PI_HOME = "/home/pi"

def deploy_and_play():
    """Deploy scene files to Pi and play scene"""
    try:
        logger.info("")
        logger.info("=" * 70)
        logger.info("PIRATE SHIP SCENE - WITH BLUETOOTH AUTO-WAKE".center(70))
        logger.info("=" * 70)
        logger.info("")
        
        # Connect to Pi
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
        
        # Upload files via SFTP
        logger.info("📤 Uploading files to Pi...")
        sftp = client.open_sftp()
        
        files_to_upload = [
            ("pirate_ship_scene.json", "pirate_ship_scene.json"),
            ("bluetooth_auto_wake.py", "bluetooth_auto_wake.py"),
            ("play_scene_with_bluetooth.py", "play_scene_with_bluetooth.py"),
        ]
        
        for local_file, remote_file in files_to_upload:
            local_path = Path(__file__).parent / local_file
            remote_path = f"{PI_HOME}/{remote_file}"
            
            if local_path.exists():
                sftp.put(str(local_path), remote_path)
                logger.info(f"   ✅ {remote_file}")
            else:
                logger.warning(f"   ⚠️  {local_file} not found locally")
        
        sftp.close()
        logger.info("")
        
        # Run the scene player
        logger.info("🚀 Running pirate ship scene on Pi...")
        logger.info("=" * 70)
        logger.info("")
        
        stdin, stdout, stderr = client.exec_command(
            f"cd {PI_HOME} && python3 play_scene_with_bluetooth.py pirate_ship_scene.json"
        )
        
        # Stream output
        for line in stdout:
            print(line.rstrip())
        
        # Check for errors
        error_lines = []
        for line in stderr:
            error_lines.append(line.rstrip())
        
        if error_lines and any("error" in line.lower() for line in error_lines):
            for line in error_lines:
                print(f"ERROR: {line}")
        
        logger.info("")
        logger.info("=" * 70)
        logger.info("SCENE EXECUTION COMPLETE".center(70))
        logger.info("Did you hear the pirate ship ambiance on your Bluetooth speaker?".center(70))
        logger.info("=" * 70)
        
        client.close()
        
    except Exception as e:
        logger.error(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    deploy_and_play()
