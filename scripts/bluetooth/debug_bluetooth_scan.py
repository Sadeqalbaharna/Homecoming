#!/usr/bin/env python3
"""
Deep Bluetooth scan debug - shows all scanning output and states.
"""

import sys
import subprocess
import time
import logging

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
log = logging.getLogger(__name__)

if len(sys.argv) < 2:
    log.error("Usage: python debug_bluetooth_scan.py <pi_ip>")
    sys.exit(1)

PI_IP = sys.argv[1]
GL91_MAC = "41:42:FF:3E:1F:25"

def ssh_cmd(cmd):
    return f"ssh -i ~/.ssh/id_rsa pi@{PI_IP} '{cmd}'"

log.info("")
log.info("🔍 DEEP BLUETOOTH SCAN DEBUG on " + PI_IP)
log.info("")

# Step 1: Check adapter
log.info("1️⃣  Bluetooth Adapter Status:")
result = subprocess.run(
    ssh_cmd("sudo hciconfig"),
    shell=True,
    capture_output=True,
    text=True
)
log.info(result.stdout if result.stdout else result.stderr)

# Step 2: Reset adapter
log.info("")
log.info("2️⃣  Resetting Bluetooth adapter...")
result = subprocess.run(
    ssh_cmd("sudo hciconfig hci0 down && sleep 1 && sudo hciconfig hci0 up"),
    shell=True,
    capture_output=True,
    text=True
)
time.sleep(2)

# Step 3: Check bluetoothctl power
log.info("")
log.info("3️⃣  bluetoothctl adapter state:")
result = subprocess.run(
    ssh_cmd("sudo bluetoothctl show"),
    shell=True,
    capture_output=True,
    text=True
)
log.info(result.stdout if result.stdout else "(no output)")

# Step 4: Scan with verbose output
log.info("")
log.info("4️⃣  Scanning for 15 seconds (VERBOSE)...")
log.info("    (GL-TWS91 should appear if in pairing mode)")
log.info("")
result = subprocess.run(
    ssh_cmd("sudo timeout 15 hcitool scan"),
    shell=True,
    capture_output=True,
    text=True
)
for line in result.stdout.split('\n'):
    if line.strip():
        log.info(f"    {line}")
        if GL91_MAC in line:
            log.info("    ✅✅✅ GL-TWS91 FOUND! ✅✅✅")

# Step 5: Also try bluetoothctl scan
log.info("")
log.info("5️⃣  bluetoothctl scan (5 seconds)...")
result = subprocess.run(
    ssh_cmd("sudo timeout 5 bluetoothctl scan on"),
    shell=True,
    capture_output=True,
    text=True
)
if result.stdout:
    for line in result.stdout.split('\n')[:20]:  # First 20 lines
        if line.strip():
            log.info(f"    {line}")

# Step 6: List discovered devices
log.info("")
log.info("6️⃣  Currently discovered devices:")
result = subprocess.run(
    ssh_cmd("sudo bluetoothctl devices"),
    shell=True,
    capture_output=True,
    text=True
)
if result.stdout.strip():
    for line in result.stdout.split('\n'):
        if line.strip():
            log.info(f"    {line}")
            if GL91_MAC in line:
                log.info("    ✅ GL-TWS91 in list!")
else:
    log.warning("    (no devices)")

# Step 7: Check signal strength of GL-TWS91 if found
log.info("")
log.info("7️⃣  Checking signal from all nearby devices:")
result = subprocess.run(
    ssh_cmd("sudo hcitool rssi --help 2>/dev/null || echo 'rssi not available'"),
    shell=True,
    capture_output=True,
    text=True
)

log.info("")
log.info("💡 TROUBLESHOOTING:")
log.info("   • If GL-TWS91 not in scan: Speaker might be off or too far away")
log.info("   • Check LED blinking pattern (should be rapid blue/red alternating)")
log.info("   • Try moving speaker closer to Pi (within 1 meter)")
log.info("   • Try restarting the speaker completely")
log.info("")
