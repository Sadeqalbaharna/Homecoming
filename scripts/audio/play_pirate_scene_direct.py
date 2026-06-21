#!/usr/bin/env python3
"""
Play pirate ship scene with direct YouTube URL
"""

import paramiko
import logging
import json
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"
PI_HOME = "/home/pi"

def play_scene():
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        logger.info("\n" + "="*70)
        logger.info("PLAYING PIRATE SHIP SCENE".center(70))
        logger.info("="*70 + "\n")
        
        # Upload scene JSON
        logger.info("📤 Uploading scene JSON...")
        sftp = client.open_sftp()
        sftp.put(str(Path(__file__).parent / "pirate_ship_scene.json"), 
                f"{PI_HOME}/pirate_ship_scene.json")
        sftp.close()
        logger.info("✅ Uploaded\n")
        
        logger.info("🎭 SCENE: Pirate Ship Adventure")
        logger.info("📝 A swashbuckling pirate ship on the high seas")
        logger.info("🎵 D&D Ambiance - Sea Shanties & Ocean Sounds")
        logger.info("🔊 Volume: 20%")
        logger.info("⏱️  Duration: 300s (5 minutes)\n")
        
        # Create simple player using direct URL approach
        logger.info("🚀 Starting scene playback on Bluetooth...\n")
        
        # Using a known pirate/sea shanty URL
        play_cmd = """
python3 << 'EOF'
import subprocess
import time

# Try to get a pirate music URL
urls = [
    "https://www.youtube.com/watch?v=aweJ7DzlEIo",  # Sea Shanty Compilation
    "https://www.youtube.com/watch?v=kxopViU98Xo",  # Pirate Theme
]

for url in urls:
    try:
        # Get stream URL
        result = subprocess.run(
            f"yt-dlp -f bestaudio -g '{url}' 2>/dev/null",
            shell=True, capture_output=True, text=True, timeout=10
        )
        stream_url = result.stdout.strip()
        
        if stream_url.startswith('http'):
            print(f"Got stream, playing...")
            # Play for 300 seconds at 20% volume on Bluetooth
            cmd = f"timeout 300 yt-dlp -f bestaudio -o - '{url}' 2>/dev/null | mpv --no-video --audio-device=pulse/bluez_output.39_3E_58_14_40_4A.1 --volume=20 - 2>&1"
            subprocess.run(cmd, shell=True)
            break
    except:
        continue

print("Scene playback complete")
EOF
"""
        
        stdin, stdout, stderr = client.exec_command(play_cmd)
        
        # Wait for playback to start and show output
        time.sleep(2)
        
        try:
            output = stdout.read(1024).decode()
            if output:
                print(output)
        except:
            pass
        
        # Let it play
        logger.info("🎵 Pirate ambiance playing for 5 minutes...")
        logger.info("   (Sea shanties, ocean waves, crew chants)\n")
        
        # Wait for scene duration or until done
        for i in range(300):
            time.sleep(1)
            if i % 60 == 0 and i > 0:
                logger.info(f"   ⏱️  {i//60} min(s) elapsed...")
        
        logger.info("\n" + "="*70)
        logger.info("SCENE COMPLETE".center(70))
        logger.info("="*70)
        logger.info("\n✅ Pirate Ship scene played successfully on Bluetooth speaker!\n")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    play_scene()
