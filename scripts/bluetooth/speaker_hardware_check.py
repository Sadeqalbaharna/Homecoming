#!/usr/bin/env python3
"""
Speaker Hardware Diagnostics - Check if speaker is alive and responsive
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

def check_speaker_hardware(pi_ip):
    """Check if speaker hardware is responding"""
    try:
        logger.info(f"\n🔍 SPEAKER HARDWARE DIAGNOSTICS on {pi_ip}...\n")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        # CHECK 1: Device discovered
        logger.info("CHECK 1️⃣  Is speaker DISCOVERED?")
        out, _, _ = run_remote_command(client, f"bluetoothctl devices | grep {SPEAKER_MAC}")
        if SPEAKER_MAC in out:
            logger.info("   ✅ Speaker discovered by Bluetooth")
        else:
            logger.error("   ❌ Speaker NOT discovered - need to scan/pair first")
            client.close()
            return 1
        
        # CHECK 2: Device paired
        logger.info("\nCHECK 2️⃣  Is speaker PAIRED?")
        out, _, _ = run_remote_command(client, f"bluetoothctl info {SPEAKER_MAC} | grep Paired")
        if "yes" in out.lower():
            logger.info("   ✅ Speaker paired")
        else:
            logger.error("   ❌ Speaker NOT paired")
            client.close()
            return 1
        
        # CHECK 3: Device connected
        logger.info("\nCHECK 3️⃣  Is speaker CONNECTED?")
        out, _, _ = run_remote_command(client, f"bluetoothctl info {SPEAKER_MAC} | grep Connected")
        if "yes" in out.lower():
            logger.info("   ✅ Speaker connected")
        else:
            logger.warning("   ⚠️  Speaker DISCONNECTED - attempting reconnect...")
            run_remote_command(client, f"bluetoothctl connect {SPEAKER_MAC}")
            time.sleep(5)
            out, _, _ = run_remote_command(client, f"bluetoothctl info {SPEAKER_MAC} | grep Connected")
            if "yes" in out.lower():
                logger.info("   ✅ Speaker now connected")
            else:
                logger.error("   ❌ Reconnect failed - speaker may be OFF or in wrong mode")
                client.close()
                return 1
        
        # CHECK 4: Get complete device info
        logger.info("\nCHECK 4️⃣  Speaker Information")
        out, _, _ = run_remote_command(client, f"bluetoothctl info {SPEAKER_MAC}")
        logger.info(f"   {out}")
        
        # CHECK 5: Check Bluetooth signal strength
        logger.info("\nCHECK 5️⃣  Bluetooth Signal Strength")
        out, _, _ = run_remote_command(client, f"bluetoothctl info {SPEAKER_MAC} | grep RSSI")
        if out:
            logger.info(f"   {out}")
        else:
            logger.info("   (Signal strength not available)")
        
        # CHECK 6: Try to trigger speaker action
        logger.info("\nCHECK 6️⃣  Can we interact with speaker?")
        logger.info("   Attempting to query audio profiles...")
        out, _, _ = run_remote_command(client, f"bluetoothctl info {SPEAKER_MAC} | grep UUID")
        
        if "Audio Sink" in out:
            logger.info("   ✅ Speaker has Audio Sink capability")
        else:
            logger.warning("   ⚠️  No Audio Sink found in UUIDs")
            logger.warning(f"   Available: {out}")
        
        # CHECK 7: Direct L2 ping (hardware response)
        logger.info("\nCHECK 7️⃣  L2 PING (Does speaker respond at all?)")
        out, err, code = run_remote_command(client, f"l2ping -c 3 {SPEAKER_MAC} 2>&1")
        
        if code == 0 or ("3 sent" in out):
            logger.info("   ✅ Speaker RESPONDING to L2 ping")
            logger.info(f"   Response:\n{out[:300]}")
        else:
            logger.error("   ❌ Speaker NOT responding to L2 ping")
            logger.error("   This means the speaker is:")
            logger.error("      - Powered OFF")
            logger.error("      - In deep sleep (power button may help)")
            logger.error("      - Out of range")
            logger.error("      - Has hardware issue")
        
        logger.info("\n" + "="*70)
        logger.info("DIAGNOSIS:")
        logger.info("="*70)
        logger.info("\nIf speaker is NOT responding to L2 ping, it's a HARDWARE issue:")
        logger.info("  1. Try turning speaker OFF completely")
        logger.info("  2. Wait 30 seconds")
        logger.info("  3. Turn it back ON")
        logger.info("  4. Wait 10 seconds for boot")
        logger.info("  5. Run this test again")
        logger.info("\nIf still not responding, speaker may be:")
        logger.info("  - Defective")
        logger.info("  - In pairing mode (need to exit first)")
        logger.info("  - Need firmware update")
        
        client.close()
        return 0
        
    except Exception as e:
        logger.error(f"❌ Diagnostics failed: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logger.error("Usage: python speaker_hardware_check.py <PI_IP>")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    sys.exit(check_speaker_hardware(pi_ip))
