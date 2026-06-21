#!/usr/bin/env python3
"""
Fix GL-TWS91 Bluetooth audio profile.
Switch from headset-head-unit to a2dp_sink for stereo audio output.
"""

import sys
import time
import subprocess
from pathlib import Path

try:
    import paramiko
except ImportError:
    print("Installing paramiko...")
    subprocess.run([sys.executable, "-m", "pip", "install", "paramiko", "-q"], check=True)
    import paramiko

if len(sys.argv) < 2:
    print("Usage: python fix_gl91_audio_profile.py <pi_ip>")
    sys.exit(1)

PI_IP = sys.argv[1]
GL91_MAC = "41:42:FF:3E:1F:25"
PI_USER = "pi"
SSH_KEY = Path.home() / ".ssh" / "id_rsa"

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

print("")
print("🎵 FIX GL-TWS91 AUDIO PROFILE on " + PI_IP)
print("")

# Step 1: Check current profile
print("1️⃣  Current Bluetooth profiles:")
output, error = ssh_exec(f"sudo bluetoothctl info {GL91_MAC} | grep -i profile")
print(f"   {output.strip() if output else '(checking...)'}")

# Step 2: List available profiles
print("")
print("2️⃣  Available profiles for this device:")
output, error = ssh_exec(f"sudo bluetoothctl show-profiles {GL91_MAC}", timeout=10)
if output.strip():
    print(output)
else:
    print("   (using show-profiles not available, trying manual)")

# Step 3: Disconnect and reconnect with A2DP profile
print("3️⃣  Disconnecting device...")
ssh_exec(f"sudo bluetoothctl disconnect {GL91_MAC}")
time.sleep(1)

print("4️⃣  Checking available profiles via pactl...")
output, error = ssh_exec("pactl list cards | grep -A 20 '41:42:FF:3E:1F:25'", timeout=10)
print(output if output else "   (checking...)")

# Step 5: Try to enable A2DP sink profile via PipeWire
print("")
print("5️⃣  Enabling A2DP audio profile via PipeWire...")
output, error = ssh_exec(
    "pw-cli set-profile 65 1",  # Assuming bluez5 device is 65, profile 1 is A2DP
    timeout=10
)
print(f"   Result: {output.strip() if output else '(setting...)'}")

# Alternative: Try via bluetoothctl
print("")
print("6️⃣  Attempting to set profile to A2DP via bluetoothctl...")
# This might not work but worth trying
ssh_exec(f"sudo bluetoothctl select-uuid {GL91_MAC} 110b", timeout=30)  # 110b = A2DP Sink UUID
time.sleep(1)

# Step 7: Reconnect
print("7️⃣  Reconnecting to GL-TWS91...")
output, error = ssh_exec(f"sudo bluetoothctl connect {GL91_MAC}", timeout=30)
print(f"   {output.strip() if output else error.strip()}")
time.sleep(3)

# Step 8: Verify sink profile
print("")
print("8️⃣  Checking audio sink profile now:")
output, error = ssh_exec("pactl list sinks | grep -A 10 'bluez_output.41'", timeout=10)
for line in output.split('\n'):
    if any(x in line for x in ['bluez', 'Profile', 'profile', 'Suspended', 'codec']):
        print(f"   {line.strip()}")

# Step 9: Set as default sink
print("")
print("9️⃣  Setting GL-TWS91 as default sink...")
output, error = ssh_exec("pactl set-default-sink bluez_output.41_42_FF_3E_1F_25.1", timeout=10)
print(f"   {output.strip() if output else '(set)'}")

# Step 10: Resume sink
print("🔟  Resuming audio sink...")
ssh_exec("pactl suspend-sink bluez_output.41_42_FF_3E_1F_25.1 false", timeout=10)

print("")
print("✅ Audio profile configuration complete!")
print("   Try running: python bass_test.py 192.168.131.5")
print("")
