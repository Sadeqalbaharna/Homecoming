#!/usr/bin/env python3
"""
Force pair GL-TWS91 using paramiko SSH (Windows-compatible).
"""

import sys
import time
import logging
from pathlib import Path

try:
    import paramiko
except ImportError:
    print("Installing paramiko...")
    import subprocess
    subprocess.run([sys.executable, "-m", "pip", "install", "paramiko", "-q"], check=True)
    import paramiko

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
log = logging.getLogger(__name__)

if len(sys.argv) < 2:
    log.error("Usage: python force_pair_gl91_paramiko.py <pi_ip>")
    sys.exit(1)

PI_IP = sys.argv[1]
GL91_MAC = "41:42:FF:3E:1F:25"
PI_USER = "pi"
SSH_KEY = Path.home() / ".ssh" / "id_rsa"

if not SSH_KEY.exists():
    log.error(f"SSH key not found: {SSH_KEY}")
    sys.exit(1)

def ssh_exec(cmd):
    """Execute command on Pi via paramiko SSH."""
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(SSH_KEY), timeout=5)
        
        stdin, stdout, stderr = client.exec_command(cmd, timeout=30)
        output = stdout.read().decode('utf-8')
        error = stderr.read().decode('utf-8')
        
        client.close()
        return output, error
    except Exception as e:
        return "", str(e)

log.info("")
log.info("🔌 FORCE PAIR GL-TWS91 (paramiko) on " + PI_IP)
log.info("")

# Step 1: Check if already paired
log.info("1️⃣  Checking if GL-TWS91 already paired...")
output, error = ssh_exec(f"sudo bluetoothctl devices | grep -i {GL91_MAC}")
if output.strip():
    log.info(f"   ✅ Already in devices: {output.strip()}")
    # Try to connect
    log.info("2️⃣  Attempting to connect...")
    output, error = ssh_exec(f"sudo bluetoothctl connect {GL91_MAC}")
    time.sleep(2)
    
    output, error = ssh_exec(f"sudo bluetoothctl info {GL91_MAC} | grep Connected")
    if "yes" in output:
        log.info("   ✅ CONNECTED!")
        sys.exit(0)
    else:
        log.warning("   Not connected yet...")
else:
    log.warning("   Not in devices list - needs pairing")

# Step 2: Power on adapter
log.info("")
log.info("2️⃣  Powering on Bluetooth...")
ssh_exec("sudo bluetoothctl power on")
time.sleep(1)

# Step 3: Make discoverable
log.info("3️⃣  Making Pi discoverable...")
ssh_exec("sudo bluetoothctl discoverable on")
ssh_exec("sudo bluetoothctl pairable on")
time.sleep(0.5)

# Step 4: Scan aggressively
log.info("4️⃣  Scanning for GL-TWS91 (30 seconds)...")
log.info("    Keep speaker in pairing mode with blinking LED...")
output, error = ssh_exec("sudo timeout 30 hcitool scan")
log.info(output if output else "(scanning...)")

found = GL91_MAC in output
if found:
    log.info(f"   ✅ GL-TWS91 FOUND in scan!")
else:
    log.warning(f"   ❌ GL-TWS91 not in hcitool scan")
    
    # Try bluetoothctl scan too
    log.info("5️⃣  Trying bluetoothctl scan (20 seconds)...")
    output, error = ssh_exec("sudo timeout 20 bluetoothctl scan on")
    if GL91_MAC in output:
        found = True
        log.info(f"   ✅ GL-TWS91 FOUND!")

# Step 5: Pair
if found:
    log.info("")
    log.info("6️⃣  Pairing GL-TWS91...")
    output, error = ssh_exec(f"sudo timeout 30 bluetoothctl pair {GL91_MAC}")
    log.info(f"   {output.strip() if output else error.strip()}")
    time.sleep(1)
    
    # Trust
    log.info("7️⃣  Trusting device...")
    output, error = ssh_exec(f"sudo bluetoothctl trust {GL91_MAC}")
    time.sleep(0.5)
    
    # Connect
    log.info("8️⃣  Connecting...")
    output, error = ssh_exec(f"sudo bluetoothctl connect {GL91_MAC}")
    log.info(f"   {output.strip() if output else error.strip()}")
    time.sleep(3)
    
    # Verify
    log.info("9️⃣  Verifying...")
    output, error = ssh_exec(f"sudo bluetoothctl info {GL91_MAC}")
    if "Connected: yes" in output:
        log.info("   ✅ GL-TWS91 CONNECTED!")
        log.info("")
        log.info("🎉 SUCCESS!")
        sys.exit(0)
    else:
        log.warning(f"   Status: {[x for x in output.split(chr(10)) if 'Connected' in x]}")
else:
    log.error("")
    log.error("❌ GL-TWS91 not found in Bluetooth scan!")
    log.error("")
    log.error("⚠️  CHECK:")
    log.error("   1. Is GL-TWS91 LED blinking rapidly (blue/red)?")
    log.error("   2. Is it within 1 meter of the Pi?")
    log.error("   3. Is the speaker battery charged?")
    log.error("   4. Try pressing and holding power button again for full 10+ seconds")
    sys.exit(1)
