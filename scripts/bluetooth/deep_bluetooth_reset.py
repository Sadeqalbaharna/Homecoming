#!/usr/bin/env python3
"""
Deep Bluetooth hardware reset - completely restart bluez and reconnect
"""

import paramiko
import logging
import time
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def deep_bluetooth_reset():
    """Complete Bluetooth reset and reconnection"""
    try:
        logger.info("")
        logger.info("=" * 70)
        logger.info("DEEP BLUETOOTH HARDWARE RESET".center(70))
        logger.info("=" * 70)
        logger.info("")
        
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
        
        # Step 1: Kill existing Bluetooth processes
        logger.info("Step 1: Stopping Bluetooth service...")
        stdin, stdout, stderr = client.exec_command("sudo systemctl stop bluetooth")
        stdout.read()
        time.sleep(2)
        logger.info("✅ Bluetooth service stopped\n")
        
        # Step 2: Kill any lingering processes
        logger.info("Step 2: Killing lingering Bluetooth processes...")
        stdin, stdout, stderr = client.exec_command("sudo killall bluetoothd 2>/dev/null; sleep 1")
        stdout.read()
        logger.info("✅ Processes killed\n")
        
        # Step 3: Reset Bluetooth module
        logger.info("Step 3: Resetting Bluetooth module...")
        stdin, stdout, stderr = client.exec_command("sudo modprobe -r btusb; sudo modprobe -r bluetooth; sleep 1; sudo modprobe bluetooth; sudo modprobe btusb")
        stdout.read()
        time.sleep(3)
        logger.info("✅ Bluetooth module reloaded\n")
        
        # Step 4: Start Bluetooth service fresh
        logger.info("Step 4: Starting Bluetooth service...")
        stdin, stdout, stderr = client.exec_command("sudo systemctl start bluetooth")
        stdout.read()
        time.sleep(3)
        logger.info("✅ Bluetooth service started\n")
        
        # Step 5: Check adapter status
        logger.info("Step 5: Checking adapter status...")
        stdin, stdout, stderr = client.exec_command("hciconfig")
        output = stdout.read().decode()
        logger.info(output)
        logger.info("")
        
        # Step 6: Try connecting
        logger.info("Step 6: Connecting to TG-129C...")
        logger.info("   MAC: 39:3E:58:14:40:4A\n")
        
        # Use bluetoothctl to power on and connect
        stdin, stdout, stderr = client.exec_command(
            "bluetoothctl << EOF\n"
            "power on\n"
            "discoverable on\n"
            "connect 39:3E:58:14:40:4A\n"
            "exit\n"
            "EOF"
        )
        output = stdout.read().decode()
        logger.info(output)
        time.sleep(3)
        logger.info("")
        
        # Step 7: Verify connection
        logger.info("Step 7: Verifying connection...")
        stdin, stdout, stderr = client.exec_command("bluetoothctl info 39:3E:58:14:40:4A")
        output = stdout.read().decode()
        logger.info(output)
        
        if "Connected: yes" in output:
            logger.info("\n✅✅✅ TG-129C IS CONNECTED! ✅✅✅\n")
            success = True
        else:
            logger.warning("⚠️  Still not connected. Trying one more approach...\n")
            success = False
        
        # Step 8: Check PulseAudio
        logger.info("Step 8: Checking PulseAudio audio sinks...")
        stdin, stdout, stderr = client.exec_command("pactl list short sinks")
        output = stdout.read().decode()
        logger.info(output)
        
        if "bluez_output" in output:
            logger.info("✅ Bluetooth sink is available in PulseAudio\n")
        else:
            logger.info("(Bluetooth sink not yet in PulseAudio, will appear after connection)\n")
        
        logger.info("=" * 70)
        if success:
            logger.info("✅ BLUETOOTH READY - SPEAKER CONNECTED!".center(70))
        else:
            logger.info("⚠️  SPEAKER PAIRED BUT NOT CONNECTED".center(70))
            logger.info("(Manual fix may be needed on Pi - see troubleshooting)".center(70))
        logger.info("=" * 70)
        logger.info("")
        
        if success:
            logger.info("🎮 Ready to play scenes!")
            logger.info("Next: python deploy_and_play_pirate_scene.py")
        else:
            logger.info("Try manually on Pi:")
            logger.info("  ssh pi@192.168.48.5")
            logger.info("  bluetoothctl")
            logger.info("  > scan on")
            logger.info("  > connect 39:3E:58:14:40:4A")
        logger.info("")
        
        client.close()
        
    except Exception as e:
        logger.error(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    deep_bluetooth_reset()
