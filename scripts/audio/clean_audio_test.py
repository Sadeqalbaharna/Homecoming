#!/usr/bin/env python3
"""
Clean test - kill old processes and play simple audio
"""

import paramiko
import logging
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def clean_test():
    try:
        logger.info("\n" + "="*70)
        logger.info("CLEAN AUDIO TEST".center(70))
        logger.info("="*70 + "\n")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        # Kill any running audio processes
        logger.info("Cleaning up old audio processes...")
        stdin, stdout, stderr = client.exec_command("killall -9 mpv 2>/dev/null; killall -9 paplay 2>/dev/null; true")
        time.sleep(1)
        logger.info("✅ Cleaned\n")
        
        # Check speaker is connected
        logger.info("Verifying speaker connection...")
        stdin, stdout, stderr = client.exec_command("bluetoothctl info 39:3E_58:14:40:4A | grep Connected")
        result = stdout.read().decode()
        if "yes" not in result:
            logger.error("Speaker not connected!")
            return
        logger.info("✅ Connected\n")
        
        # Create simple test WAV file directly
        logger.info("Creating 2-second test tone (1000Hz beep)...")
        
        wav_creation = '''import wave
import struct
import math

# Generate 2 seconds of 1000Hz sine wave at full volume
sample_rate = 44100
duration = 2
frequency = 1000
amplitude = 32767

with wave.open('/tmp/beep.wav', 'wb') as f:
    f.setnchannels(1)  # mono
    f.setsampwidth(2)  # 16-bit
    f.setframerate(sample_rate)
    
    for i in range(duration * sample_rate):
        value = int(amplitude * math.sin(2.0 * math.pi * frequency * i / sample_rate))
        f.writeframes(struct.pack('<h', value))
        
print("Created /tmp/beep.wav")
'''
        
        stdin, stdout, stderr = client.exec_command(f"python3 -c '{wav_creation}'")
        output = stdout.read().decode()
        logger.info(output)
        time.sleep(1)
        
        # Verify file exists
        stdin, stdout, stderr = client.exec_command("ls -lh /tmp/beep.wav")
        output = stdout.read().decode()
        if "beep.wav" in output:
            logger.info("✅ Test tone created\n")
        
        # Set volume to 100% and mute if needed
        logger.info("Setting speaker volume to 100%...")
        stdin, stdout, stderr = client.exec_command(
            "pactl set-sink-volume bluez_output.39_3E_58_14_40_4A.1 100% && "
            "pactl set-sink-mute bluez_output.39_3E_58_14_40_4A.1 0"
        )
        time.sleep(1)
        
        # Play the test tone using paplay
        logger.info("Playing 2-second beep on Bluetooth speaker...")
        logger.info("(You should hear a clear beeping sound now)\n")
        
        stdin, stdout, stderr = client.exec_command(
            "paplay --device=bluez_output.39_3E_58_14_40_4A.1 /tmp/beep.wav"
        )
        
        # Wait for playback to complete
        time.sleep(3)
        
        error = stderr.read().decode()
        if error:
            logger.warning(f"Playback messages: {error}")
        
        logger.info("\n" + "="*70)
        logger.info("DID YOU HEAR A BEEP?".center(70))
        logger.info("="*70)
        logger.info("\n✅ YES → Speaker is working")
        logger.info("❌ NO  → Speaker may be off or disconnected\n")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    clean_test()
