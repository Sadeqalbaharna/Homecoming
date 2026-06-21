#!/usr/bin/env python3
"""
Force Bluetooth sink to activate and test with high volume
"""

import paramiko
import logging
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def force_activate():
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        logger.info("\n" + "="*70)
        logger.info("FORCING BLUETOOTH SPEAKER ACTIVATION".center(70))
        logger.info("="*70 + "\n")
        
        # Verify speaker is connected
        logger.info("Checking speaker connection...")
        stdin, stdout, stderr = client.exec_command(
            "bluetoothctl info 39:3E:58:14:40:4A | grep -E 'Name|Connected'"
        )
        info = stdout.read().decode()
        logger.info(info)
        
        if "Connected: no" in info:
            logger.error("❌ Speaker not connected!")
            logger.info("Reconnecting...")
            stdin, stdout, stderr = client.exec_command("bluetoothctl connect 39:3E:58:14:40:4A")
            time.sleep(3)
        
        # Reload Bluetooth modules
        logger.info("\nReloading Bluetooth audio modules...")
        stdin, stdout, stderr = client.exec_command(
            "pactl load-module module-bluez5-discover && sleep 1"
        )
        
        # Check if sink is now active
        logger.info("Checking sink status...")
        stdin, stdout, stderr = client.exec_command(
            "pactl list sinks | grep -A 5 'bluez_output'"
        )
        output = stdout.read().decode()
        logger.info(output)
        
        # Play audio - this should activate the sink
        logger.info("\n🔊 PLAYING LOUD TEST SOUND (80Hz bass tone for 5 seconds)...\n")
        logger.info("(Check if TG-129C speaker is powered ON and has volume turned up)\n")
        
        cmd = """python3 << 'EOF'
import wave, struct, math, subprocess, time

# Create LOUD bass tone (80Hz)
with wave.open('/tmp/bass.wav', 'wb') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(44100)
    amplitude = 32767  # Maximum
    for i in range(44100*5):  # 5 seconds
        val = int(amplitude * math.sin(2*math.pi*80*i/44100))
        f.writeframes(struct.pack('<h', val))

# Play at maximum volume
subprocess.run([
    'paplay', 
    '--device=bluez_output.39_3E_58_14_40_4A.1',
    '--volume=65536',  # Max
    '/tmp/bass.wav'
], timeout=6)
EOF"""
        
        stdin, stdout, stderr = client.exec_command(cmd)
        time.sleep(6)
        
        err = stderr.read().decode()
        if err and "error" in err.lower():
            logger.error(f"Error: {err}")
        
        logger.info("\n" + "="*70)
        logger.info("TEST COMPLETE".center(70))
        logger.info("="*70 + "\n")
        logger.info("❓ Did you hear a low BASS rumble from the speaker?")
        logger.info("\n✅ YES  → Speaker is working, ready for scene playback")
        logger.info("❌ NO   → TG-129C may be OFF or volume at 0\n")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")

if __name__ == "__main__":
    force_activate()
