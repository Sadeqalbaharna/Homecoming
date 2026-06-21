#!/usr/bin/env python3
"""
Deploy minimal test to Pi and run with full debugging output
"""

import paramiko
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"
PI_HOME = "/home/pi"

def run_minimal_test():
    """Run minimal audio test on Pi"""
    try:
        logger.info(f"🔌 Connecting to Pi: {PI_USER}@{PI_IP}")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        logger.info("✅ Connected to Pi")
        
        # Upload test file
        sftp = client.open_sftp()
        
        local_test = Path(__file__).parent / "test_audio_minimal.py"
        remote_test = f"{PI_HOME}/test_audio_minimal.py"
        logger.info(f"📤 Uploading test_audio_minimal.py...")
        sftp.put(str(local_test), remote_test)
        logger.info(f"✅ Uploaded")
        
        sftp.close()
        
        # Run test with full output
        logger.info("")
        logger.info("🚀 Running minimal audio test on Pi...")
        logger.info("=" * 70)
        
        stdin, stdout, stderr = client.exec_command(f"cd {PI_HOME} && python3 test_audio_minimal.py")
        
        # Stream output line by line
        for line in stdout:
            print(line.rstrip())
        
        client.close()
        
    except Exception as e:
        logger.error(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    run_minimal_test()
