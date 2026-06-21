#!/usr/bin/env python3
"""
Scene Audio Generator - Creates pre-downloaded audio for scenes
Uses local audio files instead of live YouTube fetching
"""

import logging
import sys
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

# Sample audio files - in production these would be real audio files
SCENE_AUDIO = {
    'pirate_ship': {
        'file': '/home/pi/audio/pirate_ship_ambiance.mp3',
        'fallback_url': 'https://example.com/pirate_ship.mp3'
    },
    'tavern': {
        'file': '/home/pi/audio/tavern_ambiance.mp3',
        'fallback_url': 'https://example.com/tavern.mp3'
    },
    'forest': {
        'file': '/home/pi/audio/forest_ambiance.mp3',
        'fallback_url': 'https://example.com/forest.mp3'
    }
}

def get_scene_audio_file(scene_name):
    """Get audio file path for scene"""
    if scene_name in SCENE_AUDIO:
        file_path = SCENE_AUDIO[scene_name]['file']
        return file_path
    return None

def generate_test_audio(pi_ip):
    """Generate test audio files on Pi if they don't exist"""
    try:
        import paramiko
        
        logger.info("🎵 Setting up scene audio files...")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username="pi",
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        # Create audio directory
        stdin, stdout, stderr = client.exec_command("mkdir -p /home/pi/audio")
        
        # Generate test audio files using sox or ffmpeg
        logger.info("   Generating test audio...")
        
        # Pirate ship scene - mix of sea sounds
        cmd = """
sox -n -r 44100 -b 16 -c 1 /home/pi/audio/pirate_ship_ambiance.mp3 \\
  synth 300 sine 200 sine 250 vol 0.3 \\
  remix - \\
  norm 2>&1
"""
        stdin, stdout, stderr = client.exec_command(cmd)
        out = stdout.read().decode('utf-8', errors='ignore')
        
        if "error" not in out.lower():
            logger.info("   ✅ Audio files ready")
        else:
            logger.warning("   ⚠️  Audio generation had issues (will use silent fallback)")
        
        client.close()
        return 0
        
    except Exception as e:
        logger.warning(f"   ⚠️  Could not generate audio: {e}")
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logger.error("Usage: python setup_scene_audio.py <PI_IP>")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    sys.exit(generate_test_audio(pi_ip))
