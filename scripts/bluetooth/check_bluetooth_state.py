#!/usr/bin/env python3
"""
Check Bluetooth adapter and device state on Pi.
Shows: Adapter power, Discoverable, Pairable, Devices list, Device info
"""

import sys
import subprocess
import logging

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
log = logging.getLogger(__name__)

if len(sys.argv) < 2:
    log.error("Usage: python check_bluetooth_state.py <pi_ip>")
    sys.exit(1)

PI_IP = sys.argv[1]
GL91_MAC = "41:42:FF:3E:1F:25"

def ssh_cmd(cmd):
    return f"ssh -i ~/.ssh/id_rsa pi@{PI_IP} '{cmd}'"

log.info("")
log.info("📡 BLUETOOTH STATE CHECK on " + PI_IP)
log.info("")

# Check adapter power
log.info("🔌 Adapter State:")
result = subprocess.run(
    ssh_cmd("sudo bluetoothctl show"),
    shell=True,
    capture_output=True,
    text=True
)
for line in result.stdout.split('\n'):
    if 'Powered' in line or 'Discoverable' in line or 'Pairable' in line:
        log.info(f"   {line.strip()}")

# List all devices
log.info("")
log.info("📱 All Devices:")
result = subprocess.run(
    ssh_cmd("sudo bluetoothctl devices"),
    shell=True,
    capture_output=True,
    text=True
)
if result.stdout.strip():
    for line in result.stdout.split('\n'):
        if line.strip():
            log.info(f"   {line.strip()}")
else:
    log.warning("   No devices found")

# Check if GL-TWS91 is in paired list
log.info("")
log.info("🔍 Looking for GL-TWS91...")
result = subprocess.run(
    ssh_cmd(f"sudo bluetoothctl devices | grep -i {GL91_MAC}"),
    shell=True,
    capture_output=True,
    text=True
)
if result.stdout.strip():
    log.info(f"   ✅ Found: {result.stdout.strip()}")
    
    # Get full info
    log.info(f"   Details:")
    result = subprocess.run(
        ssh_cmd(f"sudo bluetoothctl info {GL91_MAC}"),
        shell=True,
        capture_output=True,
        text=True
    )
    for line in result.stdout.split('\n'):
        if line.strip() and any(x in line for x in ['Device', 'Name', 'Alias', 'Connected', 'Paired', 'Trusted']):
            log.info(f"      {line.strip()}")
else:
    log.warning(f"   ❌ GL-TWS91 ({GL91_MAC}) not in paired devices")
    
# Check adapter discoverable/pairable
log.info("")
log.info("🔧 Making Pi discoverable for GL-TWS91...")
subprocess.run(ssh_cmd("sudo bluetoothctl discoverable on"), shell=True, capture_output=True)
subprocess.run(ssh_cmd("sudo bluetoothctl pairable on"), shell=True, capture_output=True)

log.info("")
log.info("💡 To pair GL-TWS91:")
log.info("   1. Power OFF the speaker completely")
log.info("   2. Power it ON again")
log.info("   3. Immediately hold button for 10+ seconds (LED should blink rapidly)")
log.info("   4. Keep it in pairing mode and run: python wake_and_pair_gl91.py 192.168.131.5")
log.info("")
