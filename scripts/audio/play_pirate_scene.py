#!/usr/bin/env python3
"""
Play pirate ship scene on Bluetooth speaker
"""

import paramiko
import logging
import json
from pathlib import Path
import time
import sys

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

# Get Pi IP from command line or use discovered IP from environment
PI_IP = sys.argv[1] if len(sys.argv) > 1 else "192.168.131.5"
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
        
        # Create scene player script on Pi
        logger.info("🎬 Setting up scene player...")
        
        player_script = '''#!/usr/bin/env python3
import json
import subprocess
import time
import sys

# Load scene
with open('/home/pi/pirate_ship_scene.json') as f:
    scene = json.load(f)

query = scene['audio']['query']
volume = scene['audio']['volume_percent']
duration = scene['scene']['duration_seconds']

print(f"\\n🎭 SCENE: {scene['scene']['name']}")
print(f"📝 {scene['scene']['description']}")
print(f"🎵 Query: {query}")
print(f"🔊 Volume: {volume}%")
print(f"⏱️  Duration: {duration}s\\n")

# Get YouTube URL
print("Getting audio stream...")
cmd = f"yt-dlp -f bestaudio -o - '{query}' 2>/dev/null"
try:
    # Get first result from YouTube search
    search_url = f"ytsearch:{query}"
    
    # Retry logic for yt-dlp
    url = None
    for attempt in range(3):
        try:
            result = subprocess.run(
                f"yt-dlp -f bestaudio -g '{search_url}' 2>/dev/null | head -1",
                shell=True, capture_output=True, text=True, timeout=30
            )
            url = result.stdout.strip()
            
            if url.startswith('http'):
                break
            elif attempt < 2:
                print(f"  Retry {attempt + 1}/3...")
                time.sleep(2)
        except subprocess.TimeoutExpired:
            if attempt < 2:
                print(f"  Timeout, retrying {attempt + 1}/3...")
                time.sleep(2)
            continue
    
    if not url or not url.startswith('http'):
        print("ERROR: Could not get stream URL after retries")
        sys.exit(1)
    
    print(f"✅ Got stream\\n")
    
    # Convert 20% to PulseAudio volume (0-65536)
    pa_volume = int(65536 * volume / 100)
    
    print(f"🎵 Playing for {duration} seconds at {volume}% volume...\\n")
    
    # Play audio
    cmd = f"yt-dlp -f bestaudio -o - '{search_url}' 2>/dev/null | mpv --no-video --audio-device=pulse/bluez_output.39_3E_58_14_40_4A.1 --volume={volume} - 2>&1"
    
    proc = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    
    # Let it play for duration or until it finishes
    for i in range(duration):
        time.sleep(1)
        if proc.poll() is not None:
            # Process finished early
            break
        if i % 30 == 0 and i > 0:
            print(f"  Playing... ({i}/{duration}s)")
    
    # Stop if still running
    if proc.poll() is None:
        proc.terminate()
        time.sleep(1)
        if proc.poll() is None:
            proc.kill()
    
    print(f"\\n✅ Scene complete!")
    
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
'''
        
        sftp = client.open_sftp()
        import io
        sftp.putfo(io.BytesIO(player_script.encode()), f"{PI_HOME}/play_scene.py")
        sftp.close()
        
        logger.info("✅ Scene player ready\n")
        
        # Run the scene
        logger.info("🚀 Starting scene playback...\n")
        
        stdin, stdout, stderr = client.exec_command(f"cd {PI_HOME} && python3 play_scene.py")
        
        # Stream output
        for line in stdout:
            print(line.rstrip())
        
        time.sleep(5)  # Wait for startup
        
        logger.info("\n" + "="*70)
        logger.info("SCENE PLAYING ON BLUETOOTH SPEAKER".center(70))
        logger.info("="*70 + "\n")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    play_scene()
