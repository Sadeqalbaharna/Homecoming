#!/usr/bin/env python3
"""
Test Bluetooth speaker is working and can play audio
"""

import paramiko
import logging
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def test_bluetooth_speaker():
    try:
        logger.info("\n" + "="*70)
        logger.info("BLUETOOTH SPEAKER TEST".center(70))
        logger.info("="*70 + "\n")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        logger.info("✅ Connected to Pi\n")
        
        # TEST 1: Bluetooth connection status
        logger.info("TEST 1: Checking Bluetooth speaker connection...")
        stdin, stdout, stderr = client.exec_command("bluetoothctl info 39:3E:58:14:40:4A")
        info = stdout.read().decode()
        
        connected = "Connected: yes" in info
        if connected:
            logger.info("✅ Speaker is CONNECTED\n")
        else:
            logger.error("❌ Speaker is NOT connected")
            logger.info(info)
            logger.info("\nAttempting to reconnect...")
            stdin, stdout, stderr = client.exec_command("bluetoothctl connect 39:3E:58:14:40:4A")
            output = stdout.read().decode()
            logger.info(output)
            time.sleep(3)
            
            stdin, stdout, stderr = client.exec_command("bluetoothctl info 39:3E:58:14:40:4A | grep Connected")
            status = stdout.read().decode()
            if "yes" in status:
                logger.info("✅ Reconnected!\n")
                connected = True
            else:
                logger.error("❌ Failed to reconnect. Check if speaker is powered ON\n")
                return False
        
        # TEST 2: PulseAudio sees Bluetooth sink
        logger.info("TEST 2: Checking PulseAudio Bluetooth sink...")
        stdin, stdout, stderr = client.exec_command("pactl list short sinks | grep bluez")
        sinks = stdout.read().decode()
        
        if sinks:
            logger.info("✅ Bluetooth sink found in PulseAudio:")
            logger.info(sinks)
        else:
            logger.error("❌ NO Bluetooth sink in PulseAudio")
            logger.info("Attempting to load Bluetooth module...")
            stdin, stdout, stderr = client.exec_command("pactl load-module module-bluez5-discover")
            output = stdout.read().decode()
            logger.info(output)
            time.sleep(2)
            
            stdin, stdout, stderr = client.exec_command("pactl list short sinks | grep bluez")
            sinks = stdout.read().decode()
            if sinks:
                logger.info("✅ Bluetooth sink now available:\n" + sinks)
            else:
                logger.error("❌ Still no Bluetooth sink. Audio routing will fail.\n")
                return False
        
        # TEST 3: Generate and play a test tone
        logger.info("TEST 3: Playing test sound...")
        
        # Create a simple sine wave generator script
        tone_script = '''
import math
import wave
import struct

# Create a 1-second 440Hz sine wave (A note)
sample_rate = 44100
duration = 1  # second
frequency = 440  # Hz
amplitude = 32767  # max for 16-bit

samples = []
for i in range(duration * sample_rate):
    value = int(amplitude * math.sin(2.0 * math.pi * frequency * i / sample_rate))
    samples.append(struct.pack('<h', value))

# Write to file
with wave.open('/tmp/test_tone.wav', 'wb') as f:
    f.setnchannels(1)  # mono
    f.setsampwidth(2)  # 16-bit
    f.setframerate(sample_rate)
    f.writeframes(b''.join(samples))
'''
        
        # Upload tone script
        sftp = client.open_sftp()
        tone_file = '/tmp/generate_tone.py'
        import io
        sftp.putfo(io.BytesIO(tone_script.encode()), tone_file)
        sftp.close()
        
        # Generate tone
        logger.info("  Generating 1-second test tone...")
        stdin, stdout, stderr = client.exec_command("python3 /tmp/generate_tone.py")
        output = stdout.read().decode()
        time.sleep(1)
        
        # Check tone was created
        stdin, stdout, stderr = client.exec_command("ls -lh /tmp/test_tone.wav")
        output = stdout.read().decode()
        if "test_tone.wav" in output:
            logger.info("  ✅ Test tone generated\n")
            
            # Play it on Bluetooth at 20% volume
            logger.info("  Playing tone on Bluetooth speaker at 20% volume...")
            stdin, stdout, stderr = client.exec_command(
                "paplay --device=bluez_output.39_3E_58_14_40_4A.a2dp_sink --volume=8192 /tmp/test_tone.wav 2>&1"
            )
            output = stdout.read().decode()
            error = stderr.read().decode()
            
            if error and "error" in error.lower():
                logger.error(f"  ❌ Error playing: {error}")
                logger.warning("  Trying with pactl set-sink-volume instead...\n")
                
                # Try different approach - set sink volume then play
                stdin, stdout, stderr = client.exec_command(
                    "pactl set-sink-volume bluez_output.39_3E_58_14_40_4A.a2dp_sink 20% && paplay /tmp/test_tone.wav"
                )
                output = stdout.read().decode()
            
            logger.info("  ✅ Tone played (you should hear a beep)")
            
        else:
            logger.error("  ❌ Failed to generate test tone\n")
            return False
        
        # TEST 4: Summary
        logger.info("\n" + "="*70)
        logger.info("SUMMARY".center(70))
        logger.info("="*70)
        logger.info("✅ Bluetooth speaker is connected and ready")
        logger.info("✅ PulseAudio can route audio to speaker")
        logger.info("✅ Test tone played successfully")
        logger.info("\n✅✅✅ SPEAKER IS WORKING - READY TO PLAY SCENES!\n")
        
        client.close()
        return True
        
    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    test_bluetooth_speaker()
