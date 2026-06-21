#!/usr/bin/env python3
"""
Deploy scene executor to Pi and start listener
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

def deploy_and_run():
    """Deploy scene executor to Pi and start it"""
    try:
        # Connect to Pi
        logger.info(f"🔌 Connecting to Pi: {PI_USER}@{PI_IP}")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        logger.info("✅ Connected to Pi")
        
        # Upload firebase_scene_executor.py
        sftp = client.open_sftp()
        
        local_file = Path(__file__).parent / "firebase_scene_executor.py"
        remote_file = f"{PI_HOME}/firebase_scene_executor.py"
        
        logger.info(f"📤 Uploading firebase_scene_executor.py...")
        sftp.put(str(local_file), remote_file)
        logger.info(f"✅ Uploaded to {remote_file}")
        
        sftp.close()
        
        # Start the listener
        logger.info(f"\n🚀 Starting scene executor on Pi...")
        logger.info("=" * 70)
        
        stdin, stdout, stderr = client.exec_command(
            f"cd {PI_HOME} && python3 firebase_scene_executor.py"
        )
        
        # Stream output from Pi
        for line in stdout:
            print(line.rstrip())
        
        for line in stderr:
            print(f"ERROR: {line.rstrip()}")
        
    except Exception as e:
        logger.error(f"❌ Deployment failed: {e}")
    finally:
        client.close()

if __name__ == "__main__":
    deploy_and_run()
