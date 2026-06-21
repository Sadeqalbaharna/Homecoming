#!/usr/bin/env python3
"""
Play a single note on Bluetooth speaker
"""

import paramiko
import logging
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def play_note():
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        # Kill old processes
        client.exec_command("killall -9 mpv paplay 2>/dev/null; true")
        time.sleep(0.5)
        
        logger.info("Playing 3-second A note (440Hz) on Bluetooth speaker...\n")
        
        # Simple command to play a tone using sox (if available) or generate with python
        cmd = """python3 << 'EOF'
import wave
import struct
import math
import subprocess

sample_rate = 44100
duration = 3
frequency = 440  # A note
amplitude = 32767

with wave.open('/tmp/note.wav', 'wb') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sample_rate)
    for i in range(duration * sample_rate):
        value = int(amplitude * math.sin(2.0 * math.pi * frequency * i / sample_rate))
        f.writeframes(struct.pack('<h', value))

subprocess.run(['paplay', '--device=bluez_output.39_3E_58_14_40_4A.1', '/tmp/note.wav'])
EOF"""
        
        stdin, stdout, stderr = client.exec_command(cmd)
        time.sleep(4)
        
        error = stderr.read().decode()
        if error and "error" in error.lower():
            logger.error(f"Error: {error}")
        
        logger.info("\n✅ Note played")
        logger.info("If you heard a steady musical note → speaker is working!")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")

if __name__ == "__main__":
    play_note()
