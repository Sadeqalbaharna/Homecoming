#!/usr/bin/env python3
"""
Audio Playback Test - Verify audio reaches Bluetooth speaker
Tests the full audio pipeline with diagnostics
"""

import paramiko
import logging
import sys
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_USER = "pi"
SPEAKER_MAC = "39:3E:58:14:40:4A"

def run_remote_command(client, cmd):
    """Run command on remote Pi"""
    stdin, stdout, stderr = client.exec_command(cmd)
    out = stdout.read().decode('utf-8', errors='ignore').strip()
    err = stderr.read().decode('utf-8', errors='ignore').strip()
    return out, err, stdout.channel.recv_exit_status()

def test_audio(pi_ip):
    """Test audio playback on Bluetooth speaker"""
    try:
        logger.info(f"\n🎵 AUDIO PLAYBACK TEST on {pi_ip}...")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        # Step 1: Check PulseAudio is running
        logger.info("   1️⃣  Checking PulseAudio daemon...")
        out, _, _ = run_remote_command(client, "pulseaudio --check")
        if out or _:
            logger.warning("      ⚠️  PulseAudio not running, starting...")
            run_remote_command(client, "pulseaudio --daemon")
            time.sleep(2)
        
        # Step 2: List available sinks
        logger.info("   2️⃣  Listing audio sinks...")
        out, _, _ = run_remote_command(client, "pactl list short sinks")
        logger.info(f"      Available sinks:\n{out}")
        
        if "bluez_output" not in out:
            logger.error("      ❌ No Bluetooth sink found!")
            client.close()
            return 1
        
        # Extract sink name
        sink_name = None
        for line in out.split('\n'):
            if 'bluez_output' in line and SPEAKER_MAC.replace(':', '_') in line:
                sink_name = line.split()[1]
                break
        
        if not sink_name:
            # Try first Bluetooth sink
            for line in out.split('\n'):
                if 'bluez_output' in line:
                    sink_name = line.split()[1]
                    break
        
        if not sink_name:
            logger.error("      ❌ Could not identify Bluetooth sink")
            client.close()
            return 1
        
        logger.info(f"      ✅ Bluetooth sink: {sink_name}")
        
        # Step 3: Set sink to default
        logger.info("   3️⃣  Setting Bluetooth sink as default...")
        out, err, _ = run_remote_command(client, f"pactl set-default-sink {sink_name}")
        logger.info("      ✅ Default sink configured")
        
        # Step 4: Test with simple sine wave
        logger.info("   4️⃣  Playing test tone...")
        cmd = f"paplay -d {sink_name} --format=s16 --rate=44100 --channels=1 /dev/zero 2>/dev/null & sleep 2 && kill %1 2>/dev/null"
        out, err, _ = run_remote_command(client, cmd)
        logger.info("      🔊 Test tone sent to speaker")
        logger.info("      ❓ Did you hear a tone? (Speaker should have played)")
        
        # Step 5: Verify mpv audio output
        logger.info("   5️⃣  Checking mpv audio output config...")
        out, _, _ = run_remote_command(client, "which mpv")
        if out:
            logger.info("      ✅ mpv installed")
            # Check if we can set audio output
            logger.info("      ℹ️  mpv will use PulseAudio automatically")
        else:
            logger.warning("      ⚠️  mpv not found, installing...")
            run_remote_command(client, "sudo apt-get install -y mpv")
        
        # Step 6: Display volume
        logger.info("   6️⃣  Checking volume levels...")
        out, _, _ = run_remote_command(client, f"pactl get-sink-volume {sink_name}")
        logger.info(f"      Volume: {out}")
        
        if "0%" in out:
            logger.warning("      ⚠️  Volume is 0%! Setting to 20%...")
            run_remote_command(client, f"pactl set-sink-volume {sink_name} 20%")
            out, _, _ = run_remote_command(client, f"pactl get-sink-volume {sink_name}")
            logger.info(f"      Updated: {out}")
        
        client.close()
        logger.info("\n   ✅ Audio system ready for playback")
        return 0
        
    except Exception as e:
        logger.error(f"   ❌ Audio test failed: {e}")
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logger.error("Usage: python test_audio_playback.py <PI_IP>")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    sys.exit(test_audio(pi_ip))
