#!/usr/bin/env python3
"""
Play pirate scene at 50% volume
"""

import paramiko
import logging
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def play_50_percent():
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        logger.info("\n" + "="*70)
        logger.info("PIRATE SCENE - 50% VOLUME".center(70))
        logger.info("="*70 + "\n")
        
        # Kill old processes
        client.exec_command("killall -9 mpv yt-dlp paplay 2>/dev/null; sleep 1")
        time.sleep(1)
        
        # Create audio with LOUDER amplitude
        logger.info("🎵 Creating pirate ambiance (50% volume)...")
        
        audio_script = '''
import wave
import struct
import math

sample_rate = 44100
duration = 10
amplitude = 32767 * 0.7  # 70% for 50% final volume

with wave.open('/tmp/pirate_50.wav', 'wb') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sample_rate)
    
    for i in range(duration * sample_rate):
        t = i / sample_rate
        
        # Ocean rumble (30Hz)
        ocean = math.sin(2*math.pi*30*t) * 0.5
        
        # Ship creaking (120-150Hz)
        creak_freq = 120 + 30*math.sin(2*math.pi*0.3*t)
        creak = math.sin(2*math.pi*creak_freq*t) * 0.4 * (0.3 + 0.7*math.sin(2*math.pi*0.5*t))
        
        # Sea shanty (D minor pentatonic)
        notes = [146.8, 165, 185, 220, 247, 220, 185, 165]
        note_idx = int(t * 2) % len(notes)
        melody = math.sin(2*math.pi*notes[note_idx]*t) * 0.3 * math.sin(2*math.pi*0.5*t)
        
        # Wind
        wind = math.sin(2*math.pi*800*t) * 0.2 * math.sin(2*math.pi*0.1*t)
        
        # Combine
        sample = ocean + creak + melody + wind
        sample = int(amplitude * sample)
        sample = max(-32768, min(32767, sample))
        
        f.writeframes(struct.pack('<h', sample))

print("Created")
'''
        
        stdin, stdout, stderr = client.exec_command(f"python3 << 'EOF'\n{audio_script}\nEOF")
        time.sleep(2)
        
        logger.info("✅ Audio ready\n")
        
        logger.info("🎭 PIRATE SHIP ADVENTURE")
        logger.info("🌊 Ocean waves, ship creaking, sea shanty")
        logger.info("🔊 Volume: 50% (LOUD)\n")
        
        # 50% volume = 32768
        play_cmd = "paplay --device=bluez_output.39_3E_58_14_40_4A.1 --volume=32768 /tmp/pirate_50.wav"
        
        stdin, stdout, stderr = client.exec_command(play_cmd)
        
        # Wait for playback
        time.sleep(12)
        
        logger.info("\n" + "="*70)
        logger.info("SCENE COMPLETE - 50% VOLUME".center(70))
        logger.info("="*70)
        logger.info("\n❓ Hearing anything now at 50% volume?\n")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")

if __name__ == "__main__":
    play_50_percent()
