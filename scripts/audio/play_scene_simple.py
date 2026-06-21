#!/usr/bin/env python3
"""
Simple Scene Player - Works without YouTube
Generates audio locally and plays it on Bluetooth speaker
"""

import paramiko
import logging
import json
from pathlib import Path
import time
import sys

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_USER = "pi"

def play_scene_simple(pi_ip, scene_json_path):
    """Play scene with generated audio (no YouTube dependency)"""
    try:
        # Read scene JSON
        with open(scene_json_path) as f:
            scene = json.load(f)
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        logger.info("\n" + "="*70)
        logger.info("PLAYING SCENE (LOCAL AUDIO)".center(70))
        logger.info("="*70 + "\n")
        
        scene_name = scene['scene']['name']
        duration = scene['scene']['duration_seconds']
        volume = scene['audio']['volume_percent']
        
        logger.info(f"🎭 Scene: {scene_name}")
        logger.info(f"⏱️  Duration: {duration}s")
        logger.info(f"🔊 Volume: {volume}%\n")
        
        # Create a simple player script that generates audio locally
        player_script = f'''#!/bin/bash
# Get Bluetooth sink
SINK=$(pactl list short sinks | grep bluez_output | awk '{{print $2}}' | head -1)

if [ -z "$SINK" ]; then
    echo "ERROR: No Bluetooth sink found"
    exit 1
fi

echo "Playing on: $SINK"

# Generate simple audio: chirp that sweeps from 440Hz to 880Hz
# This works without any internet or external files
sox -n -t raw -r 44100 -b 16 -c 1 - \\
    synth {duration} sine 440:880 vol {volume/100.0} tremolo 2 20 \\
    | paplay -d "$SINK" --rate=44100 --channels=1 --format=s16le

echo "Done"
'''
        
        # Upload and run
        logger.info("🚀 Starting playback...")
        
        sftp = client.open_sftp()
        sftp.putfo(__import__('io').StringIO(player_script), '/tmp/play_scene.sh')
        sftp.close()
        
        # Run it
        stdin, stdout, stderr = client.exec_command("chmod +x /tmp/play_scene.sh && /tmp/play_scene.sh")
        
        # Wait for output
        for line in stdout:
            logger.info(f"   {line.strip()}")
        
        # Check for errors
        err_output = stderr.read().decode('utf-8', errors='ignore')
        if err_output:
            logger.warning(f"   {err_output}")
        
        logger.info("\n" + "="*70)
        logger.info("✅ SCENE COMPLETE".center(70))
        logger.info("="*70 + "\n")
        
        client.close()
        return 0
        
    except Exception as e:
        logger.error(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 3:
        logger.error("Usage: python play_scene_simple.py <PI_IP> <SCENE_JSON>")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    scene_json = sys.argv[2]
    sys.exit(play_scene_simple(pi_ip, scene_json))
