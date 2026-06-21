#!/usr/bin/env python3
"""
Comprehensive Bluetooth Audio Test - Debug why audio isn't reaching speaker
Tests every step of the audio pipeline
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

def run_remote_command(client, cmd, show_output=True):
    """Run command on remote Pi and return output"""
    stdin, stdout, stderr = client.exec_command(cmd)
    out = stdout.read().decode('utf-8', errors='ignore').strip()
    err = stderr.read().decode('utf-8', errors='ignore').strip()
    code = stdout.channel.recv_exit_status()
    
    if show_output and out:
        logger.info(f"      Output: {out[:200]}")
    if err and show_output:
        logger.warning(f"      Error: {err[:200]}")
    
    return out, err, code

def test_audio_pipeline(pi_ip):
    """Test complete audio pipeline"""
    try:
        logger.info(f"\n🔊 BLUETOOTH AUDIO PIPELINE TEST on {pi_ip}...\n")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        # TEST 1: Check PulseAudio is running
        logger.info("TEST 1️⃣  PulseAudio Daemon")
        out, _, code = run_remote_command(client, "pulseaudio --check 2>&1")
        
        if code != 0:
            logger.warning("   ⚠️  PulseAudio not running, starting...")
            run_remote_command(client, "pulseaudio --daemon", show_output=False)
            time.sleep(2)
        else:
            logger.info("   ✅ PulseAudio running")
        
        # TEST 2: List all sinks
        logger.info("\nTEST 2️⃣  Available Audio Sinks")
        out, _, _ = run_remote_command(client, "pactl list short sinks")
        logger.info(f"   Sinks:\n{out}")
        
        # TEST 3: Check for Bluetooth sink specifically
        logger.info("\nTEST 3️⃣  Bluetooth Sink Status")
        out, _, _ = run_remote_command(client, "pactl list sinks | grep -A10 'bluez_output'")
        
        if out:
            logger.info("   ✅ Bluetooth sink found")
            logger.info(f"   Details:\n{out[:500]}")
        else:
            logger.warning("   ❌ Bluetooth sink NOT FOUND")
            logger.warning("   Attempting to load Bluetooth module...")
            
            out, err, code = run_remote_command(
                client,
                "pactl load-module module-bluez5-discover",
                show_output=True
            )
            
            if code == 0:
                logger.info("   Module load returned success")
                time.sleep(3)
                
                # Check again
                out, _, _ = run_remote_command(client, "pactl list sinks | grep -c bluez_output", show_output=False)
                if out.strip() != '0':
                    logger.info("   ✅ Bluetooth sink now available")
                else:
                    logger.warning("   ⚠️  Still no Bluetooth sink after module load")
            else:
                logger.error(f"   ❌ Module load failed: {err}")
        
        # TEST 4: Get Bluetooth sink name
        logger.info("\nTEST 4️⃣  Get Bluetooth Sink Name")
        out, _, _ = run_remote_command(
            client,
            "pactl list short sinks | grep bluez_output | awk '{print $2}'",
            show_output=False
        )
        
        sink_name = out.strip() if out else None
        
        if sink_name:
            logger.info(f"   ✅ Sink name: {sink_name}")
        else:
            logger.error("   ❌ Could not determine sink name")
            logger.info("   Trying alternate method...")
            out, _, _ = run_remote_command(
                client,
                "pactl list sinks | grep Name:",
                show_output=True
            )
            return 1
        
        # TEST 5: Set default sink
        logger.info("\nTEST 5️⃣  Set Default Sink")
        out, err, code = run_remote_command(
            client,
            f"pactl set-default-sink {sink_name}",
            show_output=False
        )
        
        if code == 0:
            logger.info(f"   ✅ Set default to {sink_name}")
        else:
            logger.warning(f"   ⚠️  Failed to set default: {err}")
        
        # TEST 6: Check suspend state
        logger.info("\nTEST 6️⃣  Check Suspend State")
        out, _, _ = run_remote_command(
            client,
            f"pactl list sinks | grep -A5 '{sink_name}' | grep 'Suspend State'",
            show_output=True
        )
        
        if "yes" in out.lower():
            logger.warning("   ⚠️  Sink is SUSPENDED! Resuming...")
            # Get sink number
            sink_num = sink_name.split('.')[-1] if '.' in sink_name else '0'
            run_remote_command(client, f"pactl suspend-sink {sink_num} 0", show_output=False)
            logger.info("   ✅ Sink resumed")
        
        # TEST 7: Check volume
        logger.info("\nTEST 7️⃣  Check Volume")
        out, _, _ = run_remote_command(
            client,
            f"pactl get-sink-volume {sink_name}",
            show_output=True
        )
        
        if "0%" in out or out == "":
            logger.warning("   ⚠️  Volume is 0%, setting to 30%...")
            run_remote_command(client, f"pactl set-sink-volume {sink_name} 30%", show_output=False)
            logger.info("   ✅ Volume set to 30%")
        
        # TEST 8: Test audio with speaker-test
        logger.info("\nTEST 8️⃣  Speaker Test Tone (should hear brief noise)")
        logger.info("   🔊 Playing test tone for 3 seconds...")
        
        out, err, code = run_remote_command(
            client,
            f"timeout 3 speaker-test -D {sink_name} -t sine -f 1000 -l 1 2>&1",
            show_output=True
        )
        
        logger.info("   ⏱️  Test tone sent. Did you hear anything?")
        
        # TEST 9: Direct paplay test
        logger.info("\nTEST 9️⃣  Direct Audio Stream Test")
        logger.info("   🎵 Playing white noise for 2 seconds...")
        
        out, err, code = run_remote_command(
            client,
            f"dd if=/dev/urandom bs=1024 count=50 2>/dev/null | paplay -d {sink_name} --rate=44100 --channels=1 --format=u8 2>&1",
            show_output=False
        )
        
        logger.info("   ⏱️  Audio stream sent. Did you hear static/noise?")
        
        # TEST 10: Check if Bluetooth device is actually connected
        logger.info("\nTEST 🔟  Bluetooth Device Connection")
        out, _, _ = run_remote_command(
            client,
            f"bluetoothctl devices Connected | grep {SPEAKER_MAC}",
            show_output=True
        )
        
        if SPEAKER_MAC in out:
            logger.info(f"   ✅ Device connected")
        else:
            logger.error(f"   ❌ Device NOT connected!")
            logger.warning("   Reconnecting...")
            run_remote_command(client, f"bluetoothctl disconnect {SPEAKER_MAC}", show_output=False)
            time.sleep(2)
            run_remote_command(client, f"bluetoothctl connect {SPEAKER_MAC}", show_output=False)
            time.sleep(3)
        
        logger.info("\n" + "="*70)
        logger.info("SUMMARY:")
        logger.info("="*70)
        logger.info("✅ Audio pipeline diagnostic complete")
        logger.info("❓ Did you hear any sounds from the speaker during tests 8 or 9?")
        logger.info("   - If YES: Audio is reaching the speaker!")
        logger.info("   - If NO: Check speaker power, restart Bluetooth, or try manual reconnect")
        
        client.close()
        return 0
        
    except Exception as e:
        logger.error(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logger.error("Usage: python test_bluetooth_audio.py <PI_IP>")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    sys.exit(test_audio_pipeline(pi_ip))
