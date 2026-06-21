#!/usr/bin/env python3
"""
Create and play ambiance directly on Pi without YouTube dependency
"""

import paramiko
import logging
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"
PI_HOME = "/home/pi"

def play_local_ambiance():
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        logger.info("\n" + "="*70)
        logger.info("PIRATE SHIP AMBIANCE - LOCAL PLAYBACK".center(70))
        logger.info("="*70 + "\n")
        
        # Kill any old processes
        client.exec_command("killall -9 mpv yt-dlp paplay 2>/dev/null; true")
        time.sleep(0.5)
        
        # Create ambiance on Pi - sea sounds + music
        logger.info("🎵 Creating pirate ship ambiance...")
        
        ambiance_script = '''
import wave
import struct
import math
import subprocess

# Create 60-second ambiance with:
# - Ocean waves sound (low frequency base)
# - Creaking ship sounds (random variation)
# - Sea shanty melody

sample_rate = 44100
duration = 60  # seconds
amplitude = 32767 * 0.4  # 40% volume for layering

with wave.open('/tmp/ambiance.wav', 'wb') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sample_rate)
    
    for i in range(duration * sample_rate):
        t = i / sample_rate
        
        # Ocean waves: deep bass (40Hz) + movement (1-2Hz modulation)
        wave_sound = math.sin(2*math.pi*40*t) * (0.5 + 0.3*math.sin(2*math.pi*1.2*t))
        
        # Creaking (random impulses every 2-3 seconds)
        creak = 0
        if int(t * 2) % 3 == 0 and (int(t*sample_rate)) % 44100 < 4410:  # 100ms bursts
            creak = math.sin(2*math.pi*120*t) * 0.3
        
        # Sea shanty melody (simple pattern)
        melody_freq = [220, 247, 277, 330, 220, 247, 277, 330][int(t*2) % 8]
        melody = math.sin(2*math.pi*melody_freq*t) * 0.2 * math.sin(2*math.pi*0.5*t)
        
        # Combine all sounds
        sample = wave_sound + creak + melody
        sample = int(amplitude * sample)
        sample = max(-32768, min(32767, sample))  # Clamp
        
        f.writeframes(struct.pack('<h', sample))

# Play it
print("Playing ambiance...")
result = subprocess.run([
    'paplay',
    '--device=bluez_output.39_3E_58_14_40_4A.1',
    '--volume=13107',  # 20% of 65536
    '/tmp/ambiance.wav'
], timeout=65)

print("Ambiance playback complete")
'''
        
        stdin, stdout, stderr = client.exec_command(f"python3 << 'EOF'\n{ambiance_script}\nEOF")
        
        logger.info("Playing 60-second ambiance sample...\n")
        logger.info("🎭 PIRATE SHIP ADVENTURE")
        logger.info("🌊 Ocean waves crashing")
        logger.info("⛵ Ship creaking")
        logger.info("🎵 Sea shanty playing\n")
        
        # Wait for playback
        time.sleep(65)
        
        # Get output
        output = stdout.read().decode()
        if output:
            logger.info(output)
        
        logger.info("\n" + "="*70)
        logger.info("Did you hear ocean waves, ship creaking, and sea shanty?".center(70))
        logger.info("="*70 + "\n")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    play_local_ambiance()
