#!/usr/bin/env python3
"""
Force GL-TWS91 into A2DP mode by directly manipulating Bluetooth profiles.
"""

import sys
import subprocess
from pathlib import Path
import time

try:
    import paramiko
except ImportError:
    subprocess.run([sys.executable, "-m", "pip", "install", "paramiko", "-q"], check=True)
    import paramiko

PI_IP = "192.168.131.5"
GL91_MAC = "41:42:FF:3E:1F:25"
PI_USER = "pi"
SSH_KEY = Path.home() / ".ssh" / "id_rsa"

def ssh_exec(cmd, timeout=30):
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(SSH_KEY), timeout=5)
        
        stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout)
        output = stdout.read().decode('utf-8', errors='ignore')
        error = stderr.read().decode('utf-8', errors='ignore')
        
        client.close()
        return output, error
    except Exception as e:
        return "", str(e)

print("\n⚡ FORCE GL-TWS91 INTO A2DP MODE\n")

# Step 1: Disconnect
print("1️⃣  Disconnecting...")
ssh_exec(f"sudo bluetoothctl disconnect {GL91_MAC}")
time.sleep(1)

# Step 2: Remove device to reset profiles
print("2️⃣  Removing device to clear profile cache...")
ssh_exec(f"sudo bluetoothctl remove {GL91_MAC}")
time.sleep(1)

# Step 3: Scan for device again to see if it comes back with different profiles
print("3️⃣  Scanning for GL-TWS91...")
output, _ = ssh_exec("sudo timeout 10 hcitool scan")
if GL91_MAC in output:
    print(f"   ✅ Found: {output.strip()}")
else:
    print("   Make sure GL-TWS91 is in pairing mode (LED blinking)")

# Step 4: Pair with specific UUID hints for A2DP
print("4️⃣  Pairing with A2DP hint...")
ssh_exec(f"sudo hcitool cc {GL91_MAC}")
time.sleep(2)
ssh_exec(f"sudo hcitool create {GL91_MAC}")
time.sleep(2)

# Step 5: Try to select A2DP UUID (0x110b = A2DP Sink)
print("5️⃣  Selecting A2DP profile (UUID 110b)...")
# This might not work, but worth trying
output, err = ssh_exec(f"sudo bluetoothctl select-uuid {GL91_MAC} 0000110b-0000-1000-8000-00805f9b34fb")
print(f"   {output.strip() if output else err.strip()}")

# Step 6: Trust and pair
print("6️⃣  Trusting and pairing...")
ssh_exec(f"sudo bluetoothctl trust {GL91_MAC}")
ssh_exec(f"sudo timeout 30 bluetoothctl pair {GL91_MAC}")
time.sleep(2)

# Step 7: Connect
print("7️⃣  Connecting...")
ssh_exec(f"sudo bluetoothctl connect {GL91_MAC}")
time.sleep(3)

# Step 8: Check profiles again
print("8️⃣  Checking available profiles now...")
output, _ = ssh_exec(f"pactl list cards | grep -A 30 {GL91_MAC}")
print(output)

# Step 9: Try to use pw-cli to set profile
print("\n9️⃣  Attempting to set PipeWire profile to A2DP...")
# Get device number from pw-cli
output, _ = ssh_exec("pw-cli list-objects Node | grep -i GL-TWS91")
print(f"Devices: {output}")

print("\n🔟  Ready to test audio...")
print("   Try: python bass_test.py 192.168.131.5")
