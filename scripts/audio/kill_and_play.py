#!/usr/bin/env python3
"""
Kill hanging processes and play with direct URL
"""

import paramiko
import logging
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def kill_and_play():
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        logger.info("Killing hanging processes...")
        client.exec_command("killall -9 yt-dlp mpv paplay python3 2>/dev/null; sleep 1")
        time.sleep(2)
        logger.info("✅ Cleaned\n")
        
        # Direct pirate music URL
        pirate_url = "https://www.youtube.com/watch?v=aweJ7DzlEIo"  # Sea Shanty
        
        logger.info(f"Playing pirate music: {pirate_url}\n")
        
        # Simpler command: just get stream and play
        cmd = f"""
yt-dlp -f bestaudio -o - '{pirate_url}' 2>/dev/null | \
mpv --no-video \
    --audio-device=pulse/bluez_output.39_3E_58_14_40_4A.1 \
    --volume=20 \
    --cache=no \
    - &
sleep 3
ps aux | grep mpv | grep -v grep
"""
        
        stdin, stdout, stderr = client.exec_command(cmd)
        output = stdout.read().decode()
        
        if output:
            logger.info("Process started:")
            logger.info(output)
        
        logger.info("\n🎵 Playing pirate scene on Bluetooth speaker...")
        logger.info("🔊 Volume: 20%\n")
        
        # Wait and listen
        for i in range(20):
            time.sleep(1)
            if i % 5 == 0:
                logger.info(f"   ⏱️  {i}s...")
        
        logger.info("\n✅ Should be hearing pirate music now!")
        logger.info("   (If not, speaker may be off or volume at 0)\n")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")

if __name__ == "__main__":
    kill_and_play()
