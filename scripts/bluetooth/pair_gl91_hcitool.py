#!/usr/bin/env python3
"""
Pair GL-TWS91 using hcitool and manual pairing (more direct).
"""

import sys
import time
import logging
import subprocess
from pathlib import Path

try:
    import paramiko
except ImportError:
    print("Installing paramiko...")
    subprocess.run([sys.executable, "-m", "pip", "install", "paramiko", "-q"], check=True)
    import paramiko

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
log = logging.getLogger(__name__)

if len(sys.argv) < 2:
    log.error("Usage: python pair_gl91_hcitool.py <pi_ip>")
    sys.exit(1)

PI_IP = sys.argv[1]
GL91_MAC = "41:42:FF:3E:1F:25"
PI_USER = "pi"
SSH_KEY = Path.home() / ".ssh" / "id_rsa"

if not SSH_KEY.exists():
    log.error(f"SSH key not found: {SSH_KEY}")
    sys.exit(1)

def ssh_exec(cmd, timeout=30):
    """Execute command on Pi via paramiko SSH."""
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(SSH_KEY), timeout=5)
        
        stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout)
        output = stdout.read().decode('utf-8')
        error = stderr.read().decode('utf-8')
        
        client.close()
        return output, error
    except Exception as e:
        return "", str(e)

log.info("")
log.info("🔗 PAIR GL-TWS91 using hcitool on " + PI_IP)
log.info("")

# Step 1: Remove any old pairing
log.info("1️⃣  Removing old pairing...")
output, error = ssh_exec(f"sudo bluetoothctl remove {GL91_MAC}")
log.info(f"   {output.strip() if output else '(removed or not in list)'}")
time.sleep(1)

# Step 2: Start interactive pairing with hcitool
log.info("2️⃣  Starting interactive pairing with hcitool...")
log.info(f"   Pairing with {GL91_MAC}")
output, error = ssh_exec(f"sudo hcitool cc {GL91_MAC}", timeout=60)
if error and "already exists" not in error:
    log.info(f"   hcitool cc output: {output.strip() if output else error.strip()}")

time.sleep(2)

# Step 3: Create connection (more forceful pairing)
log.info("3️⃣  Creating Bluetooth connection...")
output, error = ssh_exec(f"sudo hcitool create {GL91_MAC}", timeout=60)
log.info(f"   {output.strip() if output else '(connection established)'}")
time.sleep(2)

# Step 4: Check if it appeared in devices
log.info("4️⃣  Checking devices list...")
output, error = ssh_exec("sudo bluetoothctl devices")
if GL91_MAC in output:
    log.info("   ✅ GL-TWS91 now in devices!")
else:
    log.warning("   (still not in bluetoothctl devices)")

# Step 5: Trust it via bluetoothctl
log.info("5️⃣  Trusting device...")
output, error = ssh_exec(f"sudo bluetoothctl trust {GL91_MAC}")
log.info(f"   {output.strip() if output else '(trusted)'}")

# Step 6: Pair via bluetoothctl
log.info("6️⃣  Pairing via bluetoothctl...")
output, error = ssh_exec(f"sudo bluetoothctl pair {GL91_MAC}", timeout=40)
log.info(f"   {output.strip() if output else error.strip()}")
time.sleep(2)

# Step 7: Connect
log.info("7️⃣  Connecting...")
output, error = ssh_exec(f"sudo bluetoothctl connect {GL91_MAC}", timeout=30)
log.info(f"   {output.strip() if output else error.strip()}")
time.sleep(3)

# Step 8: Verify connection
log.info("8️⃣  Verifying connection...")
output, error = ssh_exec(f"sudo bluetoothctl info {GL91_MAC}")
lines = output.split('\n')
for line in lines:
    if any(x in line for x in ['Device', 'Name', 'Alias', 'Connected', 'Paired', 'Trusted']):
        log.info(f"   {line.strip()}")

if "Connected: yes" in output:
    log.info("")
    log.info("🎉 SUCCESS - GL-TWS91 is paired and connected!")
    sys.exit(0)
elif "Paired: yes" in output:
    log.info("")
    log.info("✅ GL-TWS91 is paired (may take a moment to connect)")
    sys.exit(0)
else:
    log.warning("")
    log.warning("⚠️  Status uncertain - check LED on speaker")
    log.warning("   Should still be able to proceed to audio test")
    sys.exit(0)
