#!/usr/bin/env python3
"""
SSH to Pi, upload scene files, and run direct playback test
"""

import paramiko
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"
PI_HOME = "/home/pi"

def run_direct_test():
    """Upload files and run direct test on Pi"""
    try:
        logger.info(f"🔌 Connecting to Pi: {PI_USER}@{PI_IP}")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        logger.info("✅ Connected to Pi")
        
        # Upload files
        sftp = client.open_sftp()
        
        # Upload scene JSON
        local_scene = Path(__file__).parent / "pirate_ship_scene.json"
        remote_scene = f"{PI_HOME}/pirate_ship_scene.json"
        logger.info(f"📤 Uploading pirate_ship_scene.json...")
        sftp.put(str(local_scene), remote_scene)
        logger.info(f"✅ Uploaded")
        
        # Upload direct player
        local_player = Path(__file__).parent / "play_scene_direct.py"
        remote_player = f"{PI_HOME}/play_scene_direct.py"
        logger.info(f"📤 Uploading play_scene_direct.py...")
        sftp.put(str(local_player), remote_player)
        logger.info(f"✅ Uploaded")
        
        sftp.close()
        
        # Run the test
        logger.info("")
        logger.info("🚀 Running direct playback test on Pi...")
        logger.info("=" * 70)
        
        stdin, stdout, stderr = client.exec_command(f"cd {PI_HOME} && python3 play_scene_direct.py")
        
        # Stream output
        for line in stdout:
            print(line.rstrip())
        
        for line in stderr:
            print(f"STDERR: {line.rstrip()}")
        
        client.close()
        
    except Exception as e:
        logger.error(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    run_direct_test()
