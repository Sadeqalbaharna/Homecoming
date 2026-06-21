#!/usr/bin/env python3
"""
Play pirate scene using FIXED working audio - no YouTube dependency
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

def play_pirate_fixed():
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        logger.info("\n" + "="*70)
        logger.info("PIRATE SHIP SCENE - FIXED PLAYBACK".center(70))
        logger.info("="*70 + "\n")
        
        # Kill old processes
        client.exec_command("killall -9 mpv yt-dlp paplay 2>/dev/null; sleep 1")
        time.sleep(1)
        
        # Create pirate ambiance audio file
        logger.info("🎵 Creating pirate ambiance audio (10 seconds)...")
        
        audio_script = '''
import wave
import struct
import math
import time

sample_rate = 44100
duration = 10
amplitude = 32767 * 0.35  # 35% for 20% final volume

with wave.open('/tmp/pirate_ambiance.wav', 'wb') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sample_rate)
    
    for i in range(duration * sample_rate):
        t = i / sample_rate
        
        # Low ocean rumble (30Hz base)
        ocean = math.sin(2*math.pi*30*t) * 0.4
        
        # Mid-range ship creaking (120-150Hz with variation)
        creak_freq = 120 + 30*math.sin(2*math.pi*0.3*t)
        creak = math.sin(2*math.pi*creak_freq*t) * 0.25 * (0.3 + 0.7*math.sin(2*math.pi*0.5*t))
        
        # Sea shanty melody (pentatonic D minor: D=146.8, E=165, F#=185, A=220, B=247)
        notes = [146.8, 165, 185, 220, 247, 220, 185, 165]
        note_idx = int(t * 2) % len(notes)
        melody_freq = notes[note_idx]
        melody = math.sin(2*math.pi*melody_freq*t) * 0.15 * math.sin(2*math.pi*0.5*t)
        
        # Wind/whistling (high frequency)
        wind = math.sin(2*math.pi*800*t) * 0.1 * math.sin(2*math.pi*0.1*t)
        
        # Combine
        sample = ocean + creak + melody + wind
        sample = int(amplitude * sample)
        sample = max(-32768, min(32767, sample))
        
        f.writeframes(struct.pack('<h', sample))

print("Created /tmp/pirate_ambiance.wav")
'''
        
        stdin, stdout, stderr = client.exec_command(f"python3 << 'EOF'\n{audio_script}\nEOF")
        time.sleep(2)
        output = stdout.read().decode()
        logger.info(output)
        
        # Verify file
        stdin, stdout, stderr = client.exec_command("ls -lh /tmp/pirate_ambiance.wav")
        output = stdout.read().decode()
        if "pirate_ambiance.wav" in output:
            logger.info("✅ Audio file created\n")
        
        # Play it
        logger.info("🎭 PIRATE SHIP ADVENTURE")
        logger.info("🌊 Ocean waves crashing")
        logger.info("⛵ Ship creaking and groaning")
        logger.info("🎵 Sea shanty playing")
        logger.info("💨 Wind whistling\n")
        
        logger.info("🔊 Playing at 20% volume on Bluetooth speaker...\n")
        
        play_cmd = """
paplay --device=bluez_output.39_3E_58_14_40_4A.1 --volume=13107 /tmp/pirate_ambiance.wav
"""
        
        stdin, stdout, stderr = client.exec_command(play_cmd)
        
        # Wait for playback
        time.sleep(12)
        
        logger.info("\n" + "="*70)
        logger.info("SCENE COMPLETE".center(70))
        logger.info("="*70)
        logger.info("\n✅ Did you hear pirate ambiance on the Bluetooth speaker?\n")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    play_pirate_fixed()
