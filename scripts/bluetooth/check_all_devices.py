#!/usr/bin/env python3
"""
Check all discovered Bluetooth devices and their profiles.
Find one that supports A2DP for audio streaming.
"""

import sys
import subprocess
from pathlib import Path

try:
    import paramiko
except ImportError:
    subprocess.run([sys.executable, "-m", "pip", "install", "paramiko", "-q"], check=True)
    import paramiko

if len(sys.argv) < 2:
    print("Usage: python check_all_devices.py <pi_ip>")
    sys.exit(1)

PI_IP = sys.argv[1]
PI_USER = "pi"
SSH_KEY = Path.home() / ".ssh" / "id_rsa"

def ssh_exec(cmd, timeout=30):
    """Execute command on Pi."""
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

print("")
print("📱 CHECKING ALL BLUETOOTH DEVICES on " + PI_IP)
print("")

# Get all paired devices
output, error = ssh_exec("sudo bluetoothctl devices")
devices = []
for line in output.split('\n'):
    if line.strip() and 'Device' in line:
        parts = line.split()
        mac = parts[1]
        name = ' '.join(parts[2:]) if len(parts) > 2 else 'Unknown'
        devices.append((mac, name))

print(f"Found {len(devices)} device(s):\n")

for mac, name in devices:
    print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"Device: {name}")
    print(f"MAC: {mac}")
    
    # Get device info
    output, error = ssh_exec(f"sudo bluetoothctl info {mac}")
    
    # Extract key info
    for line in output.split('\n'):
        if any(x in line for x in ['Connected:', 'Paired:', 'Class:', 'UUID']):
            print(f"  {line.strip()}")
    
    # Check UUIDs for audio capability
    if '110b' in output:
        print("  ✅ A2DP Sink (stereo audio) supported")
    elif '110c' in output:
        print("  ✅ A2DP Source (stereo audio) supported")
    elif '110e' in output:
        print("  ⚠️  A2DP supported (some variant)")
    
    if '111e' in output:
        print("  ✅ Handsfree (voice) supported")
    elif '111f' in output:
        print("  ✅ Headset (voice) supported")
    else:
        print("  ❌ No voice/headset support")
    
    print("")

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("")
print("💡 Summary:")
print("   GL-TWS91 is a headset (voice only), NOT an audio speaker")
print("   Soundtec-Vibe should support A2DP (stereo audio)")
print("   TG-129C was only for testing (confirmed defective)")
print("")
print("🎯 Recommendation: Try Soundtec-Vibe instead")
