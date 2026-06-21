#!/usr/bin/env python3
"""
Verify Bluetooth speaker is actually receiving audio
"""

import paramiko
import logging
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def verify_speaker():
    try:
        logger.info("\n" + "="*70)
        logger.info("BLUETOOTH SPEAKER AUDIO VERIFICATION".center(70))
        logger.info("="*70 + "\n")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        # Step 1: Is speaker connected?
        logger.info("STEP 1: Checking speaker connection...")
        stdin, stdout, stderr = client.exec_command("bluetoothctl info 39:3E:58:14:40:4A | grep -E 'Connected|Name'")
        info = stdout.read().decode()
        logger.info(info)
        
        if "yes" not in info:
            logger.error("❌ Speaker not connected! Reconnecting...")
            stdin, stdout, stderr = client.exec_command("bluetoothctl connect 39:3E:58:14:40:4A")
            time.sleep(3)
        
        # Step 2: Check if speaker is ON (test by setting volume)
        logger.info("STEP 2: Checking if speaker responds to commands...")
        stdin, stdout, stderr = client.exec_command(
            "pactl set-sink-volume bluez_output.39_3E_58_14_40_4A.1 50%"
        )
        error = stderr.read().decode()
        if error:
            logger.error(f"❌ Speaker not responding: {error}")
            logger.error("Speaker may be OFF or disconnected")
            return
        logger.info("✅ Speaker responds to volume commands")
        
        # Step 3: List actual sinks to verify Bluetooth
        logger.info("\nSTEP 3: Checking available audio sinks...")
        stdin, stdout, stderr = client.exec_command("pactl list short sinks")
        sinks = stdout.read().decode()
        logger.info(sinks)
        
        bluez_sink = None
        for line in sinks.split('\n'):
            if 'bluez_output' in line:
                bluez_sink = line.split()[0]  # Get sink index
                logger.info(f"✅ Found Bluetooth sink: {bluez_sink}")
        
        if not bluez_sink:
            logger.error("❌ No Bluetooth sink found!")
            return
        
        # Step 4: Set sink to max volume for test
        logger.info(f"\nSTEP 4: Setting speaker to 100% volume...")
        stdin, stdout, stderr = client.exec_command(f"pactl set-sink-volume {bluez_sink} 100%")
        time.sleep(1)
        
        # Step 5: Play actual audio file with mpv to test
        logger.info("\nSTEP 5: Playing test audio (checking for errors)...")
        logger.info("Playing YouTube stream for 5 seconds...\n")
        
        # Use a known good video URL
        stdin, stdout, stderr = client.exec_command(
            "timeout 5 yt-dlp -f bestaudio -o - 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' 2>/dev/null | "
            "mpv --no-video --audio-device=pulse/bluez_output.39_3E_58_14_40_4A.1 - 2>&1 | tail -20"
        )
        
        time.sleep(7)
        
        output = stdout.read().decode()
        error = stderr.read().decode()
        
        if output:
            logger.info("Audio output:")
            logger.info(output)
        
        if error and "error" in error.lower():
            logger.error("Errors detected:")
            logger.error(error)
        
        # Step 6: Check if audio is actually playing
        logger.info("\nSTEP 6: Checking for active audio processes...")
        stdin, stdout, stderr = client.exec_command("ps aux | grep -E 'mpv|paplay|pulseaudio'")
        processes = stdout.read().decode()
        logger.info(processes)
        
        # Step 7: Direct audio test - use speaker's actual sink name
        logger.info("\nSTEP 7: Direct audio routing test...")
        logger.info("Generating tone and piping directly to speaker...")
        
        stdin, stdout, stderr = client.exec_command(
            "python3 -c \"import math, sys; "
            "[sys.stdout.buffer.write(int(32767*math.sin(2*math.pi*440*i/44100)).to_bytes(2,'little')) "
            "for i in range(44100*2)]\""
            " | paplay --device=bluez_output.39_3E_58_14_40_4A.1 2>&1"
        )
        
        time.sleep(3)
        output = stdout.read().decode()
        error = stderr.read().decode()
        
        if error:
            logger.warning(f"Playback warning: {error}")
        else:
            logger.info("✅ Audio sent to speaker successfully")
        
        logger.info("\n" + "="*70)
        logger.info("DIAGNOSTICS COMPLETE".center(70))
        logger.info("="*70)
        logger.info("\nIF YOU HEARD AUDIO:")
        logger.info("  ✅ Speaker is working - ready for scene playback")
        logger.info("\nIF YOU HEARD NOTHING:")
        logger.info("  ❌ Check:")
        logger.info("     1. Is TG-129C speaker POWERED ON?")
        logger.info("     2. Is Bluetooth pairing still active? (check LED)")
        logger.info("     3. Try unmuting speaker manually")
        logger.info("     4. Try power cycling speaker")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    verify_speaker()
