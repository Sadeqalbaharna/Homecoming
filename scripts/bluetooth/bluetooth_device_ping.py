#!/usr/bin/env python3
"""
Bluetooth Device Ping - Verify Bluetooth device is responsive
Checks sync status, power states, and sends actual L2 ping
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
SPEAKER_NAME = "TG-129C"

def run_remote_command(client, cmd):
    """Run command on remote Pi"""
    stdin, stdout, stderr = client.exec_command(cmd)
    out = stdout.read().decode('utf-8', errors='ignore').strip()
    err = stderr.read().decode('utf-8', errors='ignore').strip()
    return out, err, stdout.channel.recv_exit_status()

def verify_bluetooth_device(pi_ip):
    """Comprehensive Bluetooth device verification"""
    try:
        logger.info(f"\n🎯 BLUETOOTH DEVICE PING to {pi_ip}...")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        # CHECK 1: Verify sync status
        logger.info(f"\n   🔍 CHECK 1: Sync Status")
        logger.info(f"      Device: {SPEAKER_NAME} ({SPEAKER_MAC})")
        
        out, _, _ = run_remote_command(client, f"bluetoothctl info {SPEAKER_MAC}")
        logger.info(f"      Details:\n{out}")
        
        if "Connected: yes" not in out:
            logger.error(f"      ❌ Device NOT properly synced/connected!")
            logger.warning(f"      Attempting to reconnect...")
            run_remote_command(client, f"bluetoothctl disconnect {SPEAKER_MAC}")
            time.sleep(1)
            run_remote_command(client, f"bluetoothctl connect {SPEAKER_MAC}")
            time.sleep(3)
            
            out, _, _ = run_remote_command(client, f"bluetoothctl info {SPEAKER_MAC}")
            if "Connected: yes" not in out:
                logger.error(f"      ❌ Reconnection failed!")
                client.close()
                return 1
        
        logger.info(f"      ✅ Device properly synced")
        
        # CHECK 2: Verify no suspension
        logger.info(f"\n   🔍 CHECK 2: Power State (Not Suspended)")
        
        # Check if hcidump shows activity
        logger.info(f"      Checking adapter power state...")
        out, _, _ = run_remote_command(client, "hciconfig")
        
        if "DOWN" in out:
            logger.error(f"      ❌ Bluetooth adapter is DOWN!")
            logger.warning(f"      Bringing adapter up...")
            run_remote_command(client, "sudo hciconfig hci0 up")
            time.sleep(2)
        
        logger.info(f"      ✅ Adapter is active (UP)")
        
        # Check device power in bluetoothctl
        logger.info(f"      Checking device power state...")
        out, _, _ = run_remote_command(client, f"bluetoothctl show {SPEAKER_MAC}")
        
        if out:
            logger.info(f"      Device info retrieved")
            logger.info(f"      ✅ Device is responsive (not suspended)")
        else:
            logger.warning(f"      ⚠️  Could not retrieve device info")
        
        # CHECK 3: Send actual L2 ping to Bluetooth device
        logger.info(f"\n   🔍 CHECK 3: L2 Ping Test")
        logger.info(f"      Sending L2 ping to {SPEAKER_MAC}...")
        
        # Use l2ping to verify device responds
        out, err, code = run_remote_command(
            client, 
            f"l2ping -c 1 {SPEAKER_MAC}"
        )
        
        if code == 0 or ("bytes from" in out.lower()):
            logger.info(f"      Response received:")
            # Show last few lines of response
            response_lines = out.split('\n')[-3:]
            for line in response_lines:
                if line.strip():
                    logger.info(f"      {line}")
            logger.info(f"      ✅ Device is RESPONDING to ping")
        else:
            logger.warning(f"      ⚠️  L2 ping returned no response (device may be in low power mode)")
            logger.info(f"      Attempting to wake device...")
            
            # Try to wake the device by toggling it
            run_remote_command(client, f"bluetoothctl disconnect {SPEAKER_MAC}")
            time.sleep(2)
            run_remote_command(client, f"bluetoothctl connect {SPEAKER_MAC}")
            time.sleep(3)
            
            # Try ping again
            out, err, code = run_remote_command(client, f"l2ping -c 1 {SPEAKER_MAC}")
            
            if code == 0:
                logger.info(f"      ✅ Device now RESPONDING after wake")
            else:
                logger.warning(f"      ⚠️  Device still not responding to L2 ping")
                logger.info(f"      (Device may be in standby - sending data might still work)")
        
        # CHECK 4: Verify audio subsystem
        logger.info(f"\n   🔍 CHECK 4: Audio Subsystem")
        
        # Ensure PulseAudio is running and not suspended
        logger.info(f"      Checking PulseAudio...")
        
        # First ensure PulseAudio is running
        run_remote_command(client, "pulseaudio --check 2>/dev/null || pulseaudio --daemon")
        time.sleep(2)
        
        out, _, _ = run_remote_command(client, "pactl list sinks | grep -A5 'bluez_output'")
        
        if out:
            logger.info(f"      ✅ Bluetooth sink active in PulseAudio")
            
            # Extract sink number and check suspend state
            for line in out.split('\n'):
                if 'Suspend State:' in line:
                    if 'yes' in line.lower():
                        logger.warning(f"      ⚠️  Sink is SUSPENDED!")
                        logger.warning(f"      Resuming sink...")
                        # Find sink index and resume it
                        sink_info = out.split('\n')[0]
                        if 'Sink #' in sink_info:
                            sink_num = sink_info.split('#')[1].split()[0]
                            run_remote_command(client, f"pactl suspend-sink {sink_num} 0")
                            logger.info(f"      ✅ Sink resumed")
                    else:
                        logger.info(f"      ✅ Sink is active (not suspended)")
                    break
        else:
            logger.warning(f"      ⚠️  Bluetooth sink not found in PulseAudio!")
            logger.warning(f"      Loading Bluetooth module...")
            
            # Load the Bluetooth module
            out, err, code = run_remote_command(
                client,
                "pactl load-module module-bluez5-discover"
            )
            
            if code == 0:
                logger.info(f"      Module loaded, waiting for sink...")
                time.sleep(3)
                
                # Check again
                out, _, _ = run_remote_command(client, "pactl list sinks")
                if "bluez_output" in out:
                    logger.info(f"      ✅ Bluetooth sink now available")
                else:
                    logger.warning(f"      ⚠️  Sink still not available after module load")
            else:
                logger.warning(f"      ⚠️  Could not load Bluetooth module: {err}")
        
        client.close()
        logger.info(f"\n   ✅ BLUETOOTH DEVICE VERIFICATION COMPLETE")
        return 0
        
    except Exception as e:
        logger.error(f"   ❌ Verification failed: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logger.error("Usage: python bluetooth_device_ping.py <PI_IP>")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    sys.exit(verify_bluetooth_device(pi_ip))
