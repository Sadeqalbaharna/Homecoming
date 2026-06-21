#!/usr/bin/env python3
"""
Generate realistic D&D ambient audio scenes through 3.5mm jack.
Creates layered ambient sounds instead of simple sine waves.
"""

import paramiko
import logging
import sys
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_USER = "pi"
AUDIO_DEVICE = "hw:0,0"  # 3.5mm jack

SCENES = {
    "pirate": {
        "name": "Pirate Ship",
        "description": "Creaky ship, waves, seagulls, wind",
        "sox_cmd": """
sox -n -t raw -r 48000 -b 16 -c 2 - \\
    synth {duration} brownnoise vol 0.1 : \\
    synth {duration} sine 40 vol 0.15 : \\
    synth {duration} sine 80:60 vol 0.08 tremolo 0.5 2 : \\
    remix - \\
    vol {volume}
"""
    },
    "tavern": {
        "name": "Tavern",
        "description": "Crowd ambiance, clinking glasses, laughter",
        "sox_cmd": """
sox -n -t raw -r 48000 -b 16 -c 2 - \\
    synth {duration} brownnoise vol 0.12 : \\
    synth {duration} sine 200:250 vol 0.05 tremolo 3 15 : \\
    synth {duration} sine 300 vol 0.04 tremolo 0.3 20 : \\
    remix - \\
    vol {volume}
"""
    },
    "forest": {
        "name": "Forest",
        "description": "Wind, rustling leaves, distant animals",
        "sox_cmd": """
sox -n -t raw -r 48000 -b 16 -c 2 - \\
    synth {duration} brownnoise vol 0.08 : \\
    synth {duration} sine 30:50 vol 0.1 tremolo 0.3 5 : \\
    synth {duration} sine 200 vol 0.03 tremolo 2 10 : \\
    remix - \\
    vol {volume}
"""
    },
    "dungeon": {
        "name": "Dungeon",
        "description": "Dripping water, echoes, stone atmosphere",
        "sox_cmd": """
sox -n -t raw -r 48000 -b 16 -c 2 - \\
    synth {duration} brownnoise vol 0.05 : \\
    synth {duration} sine 60 vol 0.12 tremolo 1 20 : \\
    synth {duration} sine 100 vol 0.06 tremolo 0.2 30 : \\
    remix - \\
    vol {volume}
"""
    },
    "battle": {
        "name": "Battle",
        "description": "Tense atmosphere, drums, clashing",
        "sox_cmd": """
sox -n -t raw -r 48000 -b 16 -c 2 - \\
    synth {duration} brownnoise vol 0.15 : \\
    synth {duration} sine 50 vol 0.2 tremolo 4 8 : \\
    synth {duration} sine 150:200 vol 0.1 tremolo 2 15 : \\
    remix - \\
    vol {volume}
"""
    }
}

def play_scene_jack(pi_ip, scene_name, duration=30, volume=0.2):
    """Play scene audio through 3.5mm jack"""
    try:
        if scene_name not in SCENES:
            logger.error(f"Unknown scene: {scene_name}")
            logger.error(f"Available scenes: {', '.join(SCENES.keys())}")
            return 1
        
        scene = SCENES[scene_name]
        
        logger.info(f"\n🎵 PLAYING: {scene['name']}")
        logger.info(f"   {scene['description']}")
        logger.info(f"   Duration: {duration}s at {int(volume*100)}% volume")
        logger.info("")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        # Build sox command with scene-specific parameters
        sox_cmd = scene['sox_cmd'].format(duration=duration, volume=volume)
        
        # Complete command with audio output
        full_cmd = f"{sox_cmd} | aplay -D {AUDIO_DEVICE} --rate=48000 --channels=2 --format=S16_LE 2>&1"
        
        logger.info(f"🎧 Streaming audio to 3.5mm jack...")
        
        stdin, stdout, stderr = client.exec_command(full_cmd, timeout=duration+10)
        
        # Wait for playback
        time.sleep(duration + 1)
        
        out = stdout.read().decode('utf-8', errors='ignore')
        err = stderr.read().decode('utf-8', errors='ignore')
        
        if err and "underrun" not in err.lower():
            logger.warning(f"Note: {err[:100]}")
        
        logger.info(f"✅ Scene complete!\n")
        
        client.close()
        return 0
        
    except Exception as e:
        logger.error(f"❌ Failed: {e}")
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logger.error("Usage: python play_ambient_scene.py <PI_IP> [SCENE] [DURATION] [VOLUME]")
        logger.error("")
        logger.error("Available scenes:")
        for name, scene in SCENES.items():
            logger.error(f"  {name:10} - {scene['description']}")
        logger.error("")
        logger.error("Examples:")
        logger.error("  python play_ambient_scene.py 192.168.131.5 pirate")
        logger.error("  python play_ambient_scene.py 192.168.131.5 tavern 60 0.3")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    scene = sys.argv[2] if len(sys.argv) > 2 else "pirate"
    duration = int(sys.argv[3]) if len(sys.argv) > 3 else 30
    volume = float(sys.argv[4]) if len(sys.argv) > 4 else 0.2
    
    sys.exit(play_scene_jack(pi_ip, scene, duration, volume))
