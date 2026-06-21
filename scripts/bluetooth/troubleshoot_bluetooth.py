#!/usr/bin/env python3
"""
Troubleshoot Bluetooth - Accepts Pi IP as command-line argument
Runs 5-stage Bluetooth diagnostics with automatic fixes
"""

import paramiko
import logging
import sys
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_USER = "pi"

# Speaker details
SPEAKER_MAC = "39:3E:58:14:40:4A"
SPEAKER_NAME = "TG-129C"

def run_remote_command(client, cmd):
    """Run command on remote Pi"""
    stdin, stdout, stderr = client.exec_command(cmd)
    out = stdout.read().decode('utf-8', errors='ignore').strip()
    err = stderr.read().decode('utf-8', errors='ignore').strip()
    return out, err

def troubleshoot(pi_ip):
    """Run Bluetooth troubleshooting on Pi"""
    try:
        logger.info(f"\n🔍 Connecting to Pi at {pi_ip}...")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        logger.info("✅ Connected\n")
        
        # STAGE 1: Bluetooth adapter
        logger.info("📊 STAGE 1: Bluetooth Adapter Check")
        out, _ = run_remote_command(client, "rfkill list all")
        if "blocked" in out.lower():
            logger.warning("   ⚠️  Bluetooth blocked by rfkill, unblocking...")
            run_remote_command(client, "sudo rfkill unblock bluetooth")
            time.sleep(1)
        
        out, _ = run_remote_command(client, "hciconfig")
        if "UP" in out:
            logger.info("   ✅ Adapter UP")
        else:
            logger.warning("   ⚠️  Adapter DOWN, bringing up...")
            run_remote_command(client, "sudo hciconfig hci0 up")
            time.sleep(2)
            logger.info("   ✅ Adapter UP")
        
        # STAGE 2: Speaker connection
        logger.info("\n📊 STAGE 2: Speaker Connection Check")
        out, _ = run_remote_command(client, "bluetoothctl devices Connected")
        if SPEAKER_MAC in out:
            logger.info(f"   ✅ {SPEAKER_NAME} connected")
        else:
            logger.warning(f"   ⚠️  {SPEAKER_NAME} not connected, reconnecting...")
            run_remote_command(client, f"bluetoothctl connect {SPEAKER_MAC}")
            time.sleep(3)
            out, _ = run_remote_command(client, "bluetoothctl devices Connected")
            if SPEAKER_MAC in out:
                logger.info(f"   ✅ {SPEAKER_NAME} connected")
            else:
                logger.error(f"   ❌ Failed to connect {SPEAKER_NAME}")
        
        # STAGE 3: PulseAudio sink
        logger.info("\n📊 STAGE 3: PulseAudio Sink Check")
        out, _ = run_remote_command(client, "pactl list short sinks | grep -i blue")
        if out:
            logger.info("   ✅ Bluetooth sink available")
            # Extract sink name
            sink_name = out.split()[1]
        else:
            logger.warning("   ⚠️  Bluetooth sink not available, loading module...")
            run_remote_command(client, "pactl load-module module-bluez5-device")
            time.sleep(1)
            out, _ = run_remote_command(client, "pactl list short sinks | grep -i blue")
            if out:
                logger.info("   ✅ Bluetooth sink available")
                sink_name = out.split()[1]
            else:
                logger.error("   ❌ Could not load Bluetooth sink")
                sink_name = None
        
        # STAGE 4: Volume settings
        logger.info("\n📊 STAGE 4: Volume Check")
        if sink_name:
            out, _ = run_remote_command(client, f"pactl get-sink-volume {sink_name}")
            if "0%" not in out:
                logger.info(f"   ✅ Volume: {out.strip()}")
            else:
                logger.warning("   ⚠️  Volume muted, setting to 20%...")
                run_remote_command(client, f"pactl set-sink-volume {sink_name} 20%")
                logger.info("   ✅ Volume: 20%")
        
        # STAGE 5: Test audio
        logger.info("\n📊 STAGE 5: Audio Test")
        logger.info("   🎵 Playing test tone...")
        if sink_name:
            cmd = f"speaker-test -D pulse -t sine -f 1000 -l 1 -s {sink_name.replace('bluez_output.', '')}"
            out, err = run_remote_command(client, cmd)
            logger.info("   ✅ Test tone sent")
        
        client.close()
        logger.info("\n✅ Troubleshooting complete!")
        return 0
        
    except Exception as e:
        logger.error(f"Troubleshooting failed: {e}")
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logger.error("Usage: python troubleshoot_bluetooth.py <PI_IP>")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    sys.exit(troubleshoot(pi_ip))
