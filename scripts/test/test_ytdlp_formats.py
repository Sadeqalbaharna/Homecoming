#!/usr/bin/env python3
"""
Test yt-dlp directly to see what formats work
"""

import paramiko
import logging
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def test_ytdlp():
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        logger.info("Testing yt-dlp formats...\n")
        
        url = "https://www.youtube.com/watch?v=aweJ7DzlEIo"
        
        # Get available formats
        logger.info("1. Checking available formats...")
        stdin, stdout, stderr = client.exec_command(f"yt-dlp -F '{url}' 2>&1 | head -30")
        output = stdout.read().decode()
        logger.info(output)
        
        # Try different extraction methods
        logger.info("\n2. Testing direct audio extraction...")
        stdin, stdout, stderr = client.exec_command(
            f"timeout 30 yt-dlp -f 'ba' -o - '{url}' 2>&1 | file - & sleep 2 && ps aux | grep yt-dlp | grep -v grep"
        )
        time.sleep(3)
        output = stdout.read().decode()
        logger.info(output)
        
        # Kill it
        client.exec_command("killall -9 yt-dlp 2>/dev/null")
        
        logger.info("\n3. Testing with wget/curl fallback...")
        stdin, stdout, stderr = client.exec_command("which wget && which curl")
        output = stdout.read().decode()
        logger.info(output if output else "Neither wget nor curl found")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")

if __name__ == "__main__":
    test_ytdlp()
