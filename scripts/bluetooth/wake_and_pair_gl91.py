#!/usr/bin/env python3
"""
Wake up GL-TWS91 and pair it to Bluetooth.
This script aggressively wakes the speaker and puts it in pairing mode.
"""

import sys
import subprocess
import time
import logging

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
log = logging.getLogger(__name__)

if len(sys.argv) < 2:
    log.error("Usage: python wake_and_pair_gl91.py <pi_ip>")
    sys.exit(1)

PI_IP = sys.argv[1]
GL91_MAC = "41:42:FF:3E:1F:25"

# SSH command prefix
def ssh_cmd(cmd):
    return f"ssh -i ~/.ssh/id_rsa pi@{PI_IP} '{cmd}'"

log.info("")
log.info("🔌 WAKE & PAIR GL-TWS91 on " + PI_IP)
log.info("")

# Step 1: Turn on Bluetooth
log.info("1️⃣  Powering on Bluetooth adapter...")
result = subprocess.run(ssh_cmd("sudo bluetoothctl power on"), shell=True, capture_output=True, text=True)
time.sleep(0.5)

# Step 2: Scan for devices (this also puts Pi in discovery mode for GL-TWS91)
log.info("2️⃣  Starting Bluetooth scan for 8 seconds...")
result = subprocess.run(
    ssh_cmd("sudo timeout 8 bluetoothctl scan on"),
    shell=True,
    capture_output=True,
    text=True
)
time.sleep(1)

# Step 3: Check if GL-TWS91 was discovered
log.info("3️⃣  Checking for GL-TWS91...")
result = subprocess.run(
    ssh_cmd(f"sudo bluetoothctl devices | grep -i '{GL91_MAC}'"),
    shell=True,
    capture_output=True,
    text=True
)
if result.returncode == 0:
    log.info(f"   ✅ Found: {result.stdout.strip()}")
else:
    log.warning(f"   ❌ GL-TWS91 not found in devices list")
    log.warning("   Try:")
    log.warning("   1. Hold the power button on GL-TWS91 for 10 seconds")
    log.warning("   2. Look for blinking LED lights (pairing mode)")
    log.warning("   3. Make sure it's within 2 meters of the Pi")
    log.warning("")
    sys.exit(1)

# Step 4: Remove old pairing
log.info("4️⃣  Removing any old pairing...")
result = subprocess.run(ssh_cmd(f"sudo bluetoothctl remove {GL91_MAC}"), shell=True, capture_output=True, text=True)
time.sleep(0.5)

# Step 5: Pair
log.info(f"5️⃣  Pairing GL-TWS91 ({GL91_MAC})...")
result = subprocess.run(
    ssh_cmd(f"sudo timeout 30 bluetoothctl pair {GL91_MAC}"),
    shell=True,
    capture_output=True,
    text=True
)
log.info(f"   Output: {result.stdout.strip() if result.stdout else result.stderr.strip()}")

# Step 6: Trust
log.info("6️⃣  Trusting device...")
result = subprocess.run(ssh_cmd(f"sudo bluetoothctl trust {GL91_MAC}"), shell=True, capture_output=True, text=True)
time.sleep(0.5)

# Step 7: Connect
log.info("7️⃣  Connecting...")
result = subprocess.run(
    ssh_cmd(f"sudo bluetoothctl connect {GL91_MAC}"),
    shell=True,
    capture_output=True,
    text=True
)
log.info(f"   Output: {result.stdout.strip() if result.stdout else result.stderr.strip()}")
time.sleep(2)

# Step 8: Verify
log.info("8️⃣  Verifying connection...")
result = subprocess.run(
    ssh_cmd(f"sudo bluetoothctl info {GL91_MAC}"),
    shell=True,
    capture_output=True,
    text=True
)
if "Connected: yes" in result.stdout:
    log.info("   ✅ GL-TWS91 CONNECTED!")
    log.info("")
    log.info("🎉 SUCCESS - GL-TWS91 is ready to use!")
    sys.exit(0)
else:
    log.warning("   ⚠️  Connection status unclear, trying next step...")
    log.info(f"   Raw output:\n{result.stdout}")

# Step 9: Wait a bit and retest
log.info("9️⃣  Waiting 3 seconds for stable connection...")
time.sleep(3)

result = subprocess.run(
    ssh_cmd(f"sudo bluetoothctl info {GL91_MAC} | grep Connected"),
    shell=True,
    capture_output=True,
    text=True
)
if "yes" in result.stdout:
    log.info("   ✅ GL-TWS91 CONNECTED!")
    log.info("")
    log.info("🎉 SUCCESS - GL-TWS91 is ready to use!")
    sys.exit(0)
else:
    log.error("   ❌ Still not connected")
    log.error("")
    log.error("⚠️  MANUAL STEPS:")
    log.error("   1. Power off GL-TWS91 (hold button 5+ seconds)")
    log.error("   2. Power on GL-TWS91 (short button press)")
    log.error("   3. Hold button again for 10 seconds to enter pairing mode (LED should blink rapidly)")
    log.error("   4. Run this script again")
    sys.exit(1)
