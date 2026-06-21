#!/usr/bin/env python3
"""
Direct Pirate Ship Scene Test
Skip Firebase, just send JSON to Pi and play audio
"""

import json
import paramiko
import logging
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"
PI_HOME = "/home/pi"

def test_pirate_scene():
    """Send scene JSON to Pi and play directly"""
    try:
        logger.info("=" * 70)
        logger.info("DIRECT PIRATE SHIP SCENE TEST".center(70))
        logger.info("=" * 70)
        logger.info("")
        
        # Load scene
        logger.info("Step 1: Loading pirate ship scene JSON...")
        with open("pirate_ship_scene.json", "r") as f:
            scene = json.load(f)
        logger.info(f"✅ Loaded: {scene['scene']['name']}\n")
        
        # Connect to Pi
        logger.info("Step 2: Connecting to Pi...")
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            PI_IP,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        logger.info("✅ Connected to Pi\n")
        
        # Prepare Bluetooth connection
        logger.info("Step 3: Ensuring Bluetooth speaker is connected...")
        stdin, stdout, stderr = client.exec_command("bluetoothctl connect 39:3E:58:14:40:4A")
        time.sleep(2)
        
        # Reload PulseAudio Bluetooth
        stdin, stdout, stderr = client.exec_command(
            "pactl unload-module module-bluez5-discover 2>/dev/null; "
            "sleep 1; "
            "pactl load-module module-bluez5-discover"
        )
        time.sleep(2)
        logger.info("✅ Bluetooth configured\n")
        
        # Create test script
        logger.info("Step 4: Creating audio test script...")
        
        script_content = f'''#!/usr/bin/env python3
import subprocess
import time
import json

print("")
print("=" * 70)
print("PIRATE SHIP SCENE - DIRECT AUDIO TEST".center(70))
print("=" * 70)
print("")

scene = {json.dumps(scene)}

# Audio config
query = scene["audio"]["query"]
volume = scene["audio"]["volume_percent"]
duration = scene["scene"]["duration_seconds"]

print(f"Scene: {{scene['scene']['name']}}")
print(f"Query: {{query}}")
print(f"Volume: {{volume}}%")
print(f"Duration: {{duration}} seconds")
print("")

# Try to get YouTube stream URL
print("Step 1: Getting YouTube stream URL...")
import subprocess

cmd = [
    "yt-dlp",
    "-f", "best[ext=m4a]/best",
    "-g",
    "--no-warnings",
    f"ytsearch1:{{query}}"
]

try:
    result = subprocess.run(cmd, timeout=30, capture_output=True, text=True)
    if result.returncode == 0:
        url = result.stdout.strip().split("\\n")[0]
        print(f"✅ Got stream URL")
    else:
        print(f"⚠️  YouTube search failed, using test video")
        url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
except subprocess.TimeoutExpired:
    print(f"⚠️  YouTube search timeout, using test video")
    url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

print("")
print("Step 2: Checking Bluetooth sink...")
result = subprocess.run(
    ["pactl", "get-sink-mute", "bluez_output.39_3E_58_14_40_4A.1"],
    timeout=5, capture_output=True, text=True
)

if result.returncode == 0:
    print(f"✅ Bluetooth sink available: {{result.stdout.strip()}}")
else:
    print(f"⚠️  Bluetooth sink check failed: {{result.stderr}}")

print("")
print("Step 3: Starting audio playback...")
print(f"🎧 LISTEN TO YOUR BLUETOOTH SPEAKER!")
print("")

# Play audio
cmd = [
    "mpv",
    "--audio-device=pulse/bluez_output.39_3E_58_14_40_4A.1",
    f"--volume={{volume}}",
    "--no-video",
    "--cache=auto",
    url
]

try:
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    time.sleep({{min(duration, 10)}})  # Play for up to 10 seconds for test
    proc.terminate()
    proc.wait(timeout=5)
    print("✅ Audio playback complete")
except Exception as e:
    print(f"❌ Playback error: {{e}}")

print("")
print("=" * 70)
print("SCENE TEST COMPLETE".center(70))
print("=" * 70)
'''
        
        # Upload and run script
        sftp = client.open_sftp()
        remote_script = f"{PI_HOME}/test_pirate_direct.py"
        
        # Write script locally first
        with open("test_pirate_direct.py", "w") as f:
            f.write(script_content)
        
        # Upload to Pi
        sftp.put("test_pirate_direct.py", remote_script)
        sftp.close()
        
        logger.info(f"✅ Script created\n")
        
        # Run script
        logger.info("Step 5: Running scene on Pi...")
        logger.info("=" * 70)
        logger.info("")
        
        stdin, stdout, stderr = client.exec_command(f"cd {PI_HOME} && python3 test_pirate_direct.py")
        
        # Stream output
        for line in stdout:
            print(line.rstrip())
        for line in stderr:
            if line.strip():
                print(f"STDERR: {line.rstrip()}")
        
        logger.info("")
        logger.info("=" * 70)
        logger.info("TEST COMPLETE - Did you hear audio on Bluetooth?".center(70))
        logger.info("=" * 70)
        
        client.close()
        
    except Exception as e:
        logger.error(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    test_pirate_scene()
