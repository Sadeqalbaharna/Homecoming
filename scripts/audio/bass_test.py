#!/usr/bin/env python3
"""
Direct Bass Test - Play 80Hz bass tone on Bluetooth speaker
"""

import paramiko
import logging
import sys
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_USER = "pi"

def play_bass_test(pi_ip):
    """Play 80Hz bass tone for speaker test"""
    try:
        logger.info(f"\n🔊 BASS TEST TONE on {pi_ip}\n")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        # Get Bluetooth sink
        stdin, stdout, stderr = client.exec_command(
            "pactl list short sinks | grep bluez_output | awk '{print $2}' | head -1"
        )
        sink = stdout.read().decode('utf-8', errors='ignore').strip()
        
        if not sink:
            logger.error("❌ No Bluetooth sink found")
            client.close()
            return 1
        
        logger.info(f"📢 Sink: {sink}")
        logger.info("🎵 Playing 80Hz bass tone for 5 seconds...")
        logger.info("   (You should hear a low bass rumble)\n")
        
        # Play 80Hz bass tone for 5 seconds at 50% volume
        cmd = f"""
sox -n -t raw -r 44100 -b 16 -c 1 - \\
    synth 5 sine 80 vol 0.5 \\
    | paplay -d {sink} --rate=44100 --channels=1 --format=s16le 2>&1
"""
        
        stdin, stdout, stderr = client.exec_command(cmd)
        out = stdout.read().decode('utf-8', errors='ignore')
        err = stderr.read().decode('utf-8', errors='ignore')
        
        logger.info("✅ Tone sent to speaker")
        logger.info("\n❓ Did you hear the bass rumble?")
        
        if err:
            logger.warning(f"   (Note: {err[:100]})")
        
        client.close()
        return 0
        
    except Exception as e:
        logger.error(f"❌ Failed: {e}")
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logger.error("Usage: python bass_test.py <PI_IP>")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    sys.exit(play_bass_test(pi_ip))
