#!/usr/bin/env python3
"""
Debug: Check which sink is receiving audio
"""

import paramiko
import logging
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def debug_audio_routing():
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        logger.info("\n" + "="*70)
        logger.info("AUDIO ROUTING DEBUG".center(70))
        logger.info("="*70 + "\n")
        
        # Check current default sink
        logger.info("1. Checking default sink...")
        stdin, stdout, stderr = client.exec_command("pactl get-default-sink")
        default = stdout.read().decode().strip()
        logger.info(f"Default sink: {default}\n")
        
        if "alsa" in default:
            logger.error("❌ Audio is going to ALSA (speaker), not Bluetooth!")
            logger.info("Setting default to Bluetooth sink...")
            stdin, stdout, stderr = client.exec_command(
                "pactl set-default-sink bluez_output.39_3E_58_14_40_4A.1"
            )
            time.sleep(1)
        
        # Check all sinks
        logger.info("2. All available sinks:")
        stdin, stdout, stderr = client.exec_command("pactl list short sinks")
        sinks = stdout.read().decode()
        logger.info(sinks)
        
        # Check if Bluetooth sink exists
        if "bluez_output" not in sinks:
            logger.error("❌ Bluetooth sink NOT available!")
            logger.info("\nAttempting to load Bluetooth module...")
            stdin, stdout, stderr = client.exec_command(
                "pactl load-module module-bluez5-discover"
            )
            time.sleep(2)
            
            stdin, stdout, stderr = client.exec_command("pactl list short sinks | grep bluez")
            sinks = stdout.read().decode()
            if sinks:
                logger.info("✅ Bluetooth sink loaded:\n" + sinks)
            else:
                logger.error("❌ Failed to load Bluetooth sink")
                logger.error("\nThis is a critical issue. Checking speaker connection...")
                
                stdin, stdout, stderr = client.exec_command("bluetoothctl info 39:3E:58:14:40:4A")
                info = stdout.read().decode()
                logger.info(info)
                return
        
        # Set Bluetooth as default
        logger.info("\n3. Setting Bluetooth as default sink...")
        stdin, stdout, stderr = client.exec_command(
            "pactl set-default-sink bluez_output.39_3E_58_14_40_4A.1"
        )
        time.sleep(1)
        
        stdin, stdout, stderr = client.exec_command("pactl get-default-sink")
        default = stdout.read().decode().strip()
        logger.info(f"New default: {default}\n")
        
        # Unmute and set volume
        logger.info("4. Unmuting and setting volume to 100%...")
        stdin, stdout, stderr = client.exec_command(
            "pactl set-sink-mute bluez_output.39_3E_58_14_40_4A.1 0 && "
            "pactl set-sink-volume bluez_output.39_3E_58_14_40_4A.1 100%"
        )
        time.sleep(1)
        
        stdin, stdout, stderr = client.exec_command(
            "pactl get-sink-mute bluez_output.39_3E_58_14_40_4A.1 && "
            "pactl get-sink-volume bluez_output.39_3E_58_14_40_4A.1"
        )
        output = stdout.read().decode()
        logger.info(output)
        
        # Now play test sound to Bluetooth specifically
        logger.info("\n5. Playing test tone to Bluetooth sink...\n")
        
        cmd = """python3 << 'EOF'
import wave, struct, math, subprocess

# Create test tone
with wave.open('/tmp/test.wav', 'wb') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(44100)
    for i in range(44100*2):  # 2 seconds
        val = int(32767 * math.sin(2*math.pi*880*i/44100))
        f.writeframes(struct.pack('<h', val))

# Play to Bluetooth sink
subprocess.run(['paplay', '--device=bluez_output.39_3E_58_14_40_4A.1', '/tmp/test.wav'], 
               timeout=3)
EOF"""
        
        stdin, stdout, stderr = client.exec_command(cmd)
        time.sleep(3)
        
        err = stderr.read().decode()
        if err:
            logger.warning(f"Messages: {err}")
        
        logger.info("\n" + "="*70)
        logger.info("AUDIO SETUP COMPLETE".center(70))
        logger.info("="*70)
        logger.info("\nIf you hear a tone: ✅ Audio is working")
        logger.info("If silent: ❌ Check if TG-129C speaker is powered ON\n")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    debug_audio_routing()
