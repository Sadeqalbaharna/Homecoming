#!/usr/bin/env python3
"""
Play D&D scenes through 3.5mm headphone jack on Raspberry Pi.
Uses ALSA directly instead of Bluetooth.
"""

import paramiko
import logging
import sys
import json
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_USER = "pi"
AUDIO_DEVICE = "hw:0,0"  # 3.5mm jack on Raspberry Pi

def play_scene_jack(pi_ip, scene_file):
    """Play scene audio through 3.5mm jack"""
    try:
        logger.info(f"\n🎵 PLAYING SCENE through 3.5mm jack on {pi_ip}\n")
        
        # Load scene
        with open(scene_file, 'r') as f:
            scene = json.load(f)
        
        scene_name = scene.get('name', 'Unknown')
        duration = scene.get('duration', 30)
        volume = scene.get('volume', 0.2)
        
        logger.info(f"Scene: {scene_name}")
        logger.info(f"Duration: {duration}s")
        logger.info(f"Volume: {int(volume*100)}%")
        logger.info("")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        # Create audio using sox and play through 3.5mm jack
        # Using frequency sweep for ambient sound
        cmd = f"""
sox -n -t raw -r 48000 -b 16 -c 2 - \\
    synth {duration} sine 440:880 vol {volume} tremolo 2 20 \\
    | aplay -D {AUDIO_DEVICE} --rate=48000 --channels=2 --format=S16_LE 2>&1
"""
        
        logger.info("🎧 Streaming audio to 3.5mm jack...")
        
        stdin, stdout, stderr = client.exec_command(cmd, timeout=duration+10)
        
        # Wait for playback
        time.sleep(duration + 1)
        
        out = stdout.read().decode('utf-8', errors='ignore')
        err = stderr.read().decode('utf-8', errors='ignore')
        
        if err and "underrun" not in err.lower():
            logger.warning(f"Note: {err[:100]}")
        
        logger.info(f"✅ Scene complete!")
        logger.info(f"\n📍 Playing: {scene_name}")
        logger.info(f"   Frequency sweep: 440Hz → 880Hz")
        logger.info(f"   With tremolo effect (wavy sound)")
        
        client.close()
        return 0
        
    except Exception as e:
        logger.error(f"❌ Failed: {e}")
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 3:
        logger.error("Usage: python play_scene_jack.py <PI_IP> <SCENE_FILE>")
        logger.error("Example: python play_scene_jack.py 192.168.131.5 pirate_ship_scene.json")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    scene_file = sys.argv[2]
    
    if not Path(scene_file).exists():
        logger.error(f"Scene file not found: {scene_file}")
        sys.exit(1)
    
    sys.exit(play_scene_jack(pi_ip, scene_file))
