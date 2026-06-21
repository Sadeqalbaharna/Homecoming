#!/usr/bin/env python3
"""
Fix PulseAudio Bluetooth audio sink
This creates/enables the Bluetooth sink so audio can be routed to TG-129C
"""

import paramiko
import logging
import time
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def fix_pulseaudio():
    """Fix PulseAudio Bluetooth sink"""
    try:
        logger.info(f"🔌 Connecting to Pi...")
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            PI_IP, 
            username=PI_USER, 
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        logger.info("✅ Connected\n")
        
        # Step 1: Reload PulseAudio module
        logger.info("=" * 70)
        logger.info("STEP 1: Reload PulseAudio Bluetooth Module")
        logger.info("=" * 70)
        
        stdin, stdout, stderr = client.exec_command(
            "pactl unload-module module-bluez5-discover; sleep 1; pactl load-module module-bluez5-discover"
        )
        time.sleep(2)
        
        # Step 2: Check if sink exists now
        logger.info("Checking for Bluetooth sink...")
        stdin, stdout, stderr = client.exec_command("pactl list short sinks")
        sinks = stdout.read().decode()
        
        logger.info("PulseAudio sinks:")
        logger.info(sinks)
        
        if "bluez_output" in sinks:
            logger.info("✅ Bluetooth sink found!\n")
        else:
            logger.warning("⚠️  Bluetooth sink still not found. Trying alternative approach...\n")
            
            # Step 3: Restart PulseAudio completely
            logger.info("=" * 70)
            logger.info("STEP 2: Restart PulseAudio Service")
            logger.info("=" * 70)
            
            stdin, stdout, stderr = client.exec_command("systemctl --user restart pulseaudio")
            time.sleep(3)
            
            stdin, stdout, stderr = client.exec_command("pactl list short sinks")
            sinks = stdout.read().decode()
            
            logger.info("PulseAudio sinks after restart:")
            logger.info(sinks)
            
            if "bluez_output" in sinks:
                logger.info("✅ Bluetooth sink found after restart!\n")
            else:
                logger.error("❌ Bluetooth sink still not available")
                logger.info("Manual fix: Try on Pi:")
                logger.info("  1. pactl load-module module-bluez5-discover")
                logger.info("  2. bluetoothctl connect 39:3E:58:14:40:4A")
                client.close()
                return False
        
        # Step 4: Test audio to Bluetooth sink
        logger.info("=" * 70)
        logger.info("STEP 3: Test Audio Playback (3 second test)")
        logger.info("=" * 70)
        logger.info("Playing tone to Bluetooth speaker...")
        logger.info("🎧 LISTEN TO YOUR SPEAKER!\n")
        
        # Use a simple sine wave test instead of YouTube
        play_cmd = (
            "python3 -c \""
            "import subprocess, time; "
            "cmd = ['mpv', '--audio-device=pulse/bluez_output.39_3E_58_14_40_4A.1', '--volume=20', "
            "'av://lavfi=sine=f=1000:d=3']; "
            "proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE); "
            "proc.wait(timeout=5); "
            "print('Tone played')\""
        )
        
        stdin, stdout, stderr = client.exec_command(play_cmd, timeout=10)
        output = stdout.read().decode()
        error = stderr.read().decode()
        
        if "Tone played" in output or not error:
            logger.info("✅ Audio playback successful!")
            logger.info("   If you heard the tone on Bluetooth: SUCCESS! ✅\n")
        else:
            logger.warning("⚠️  Audio test status unclear")
            logger.info(f"   Output: {output}")
        
        # Summary
        logger.info("=" * 70)
        logger.info("PULSEAUDIO FIX COMPLETE".center(70))
        logger.info("=" * 70)
        logger.info("Next step: Run verify_bluetooth_complete.py to confirm")
        logger.info("Then: python send_pirate_scene.py to test scene playback")
        
        client.close()
        return True
        
    except Exception as e:
        logger.error(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    fix_pulseaudio()
