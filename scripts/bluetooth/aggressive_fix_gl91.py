#!/usr/bin/env python3
"""
AGGRESSIVE fix for GL-TWS91 audio - force A2DP profile and resume sink.
"""

import sys
import time
import subprocess
from pathlib import Path

try:
    import paramiko
except ImportError:
    subprocess.run([sys.executable, "-m", "pip", "install", "paramiko", "-q"], check=True)
    import paramiko

if len(sys.argv) < 2:
    print("Usage: python aggressive_fix_gl91.py <pi_ip>")
    sys.exit(1)

PI_IP = sys.argv[1]
GL91_MAC = "41:42:FF:3E:1F:25"
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
print("⚡ AGGRESSIVE FIX for GL-TWS91 on " + PI_IP)
print("")

# Step 1: Kill any audio processes
print("1️⃣  Stopping any running audio...")
ssh_exec("pkill -f paplay; pkill -f sox; sleep 1", timeout=5)

# Step 2: Disconnect
print("2️⃣  Disconnecting GL-TWS91...")
ssh_exec(f"sudo bluetoothctl disconnect {GL91_MAC}")
time.sleep(1)

# Step 3: Remove and re-add device
print("3️⃣  Removing and re-adding device...")
ssh_exec(f"sudo bluetoothctl remove {GL91_MAC}")
time.sleep(1)

# Step 4: Reconnect with pairing
print("4️⃣  Re-pairing GL-TWS91...")
ssh_exec(f"sudo timeout 30 hcitool cc {GL91_MAC}")
time.sleep(2)
ssh_exec(f"sudo hcitool create {GL91_MAC}")
time.sleep(2)

# Step 5: Trust and connect via bluetoothctl
print("5️⃣  Trusting and connecting...")
ssh_exec(f"sudo bluetoothctl trust {GL91_MAC}")
ssh_exec(f"sudo timeout 30 bluetoothctl pair {GL91_MAC}")
time.sleep(2)
ssh_exec(f"sudo bluetoothctl connect {GL91_MAC}")
time.sleep(3)

# Step 6: Kill PipeWire/PulseAudio and restart
print("6️⃣  Restarting audio daemon...")
ssh_exec("systemctl --user stop pipewire pipewire-pulse", timeout=5)
time.sleep(1)
ssh_exec("systemctl --user start pipewire pipewire-pulse", timeout=5)
time.sleep(2)

# Step 7: Check sinks
print("7️⃣  Checking audio sinks...")
output, error = ssh_exec("pactl list short sinks")
print(output if output else "(checking...)")

# Step 8: Find and unsuspend the Bluetooth sink
print("8️⃣  Unsuspending audio sink...")
output, error = ssh_exec("pactl list short sinks | grep bluez")
if output.strip():
    sink_id = output.split()[0]
    print(f"   Sink ID: {sink_id}")
    ssh_exec(f"pactl suspend-sink {sink_id} false")
    print("   ✅ Sink resumed")
else:
    print("   ⚠️  No Bluetooth sink found yet, waiting...")
    time.sleep(2)
    output, error = ssh_exec("pactl list short sinks | grep bluez")
    if output.strip():
        sink_id = output.split()[0]
        ssh_exec(f"pactl suspend-sink {sink_id} false")
        print(f"   Found and resumed sink {sink_id}")

# Step 9: Set volume to 100%
print("9️⃣  Setting volume to 100%...")
output, error = ssh_exec("pactl list short sinks | grep bluez | awk '{print $1}'")
if output.strip():
    sink_id = output.strip()
    ssh_exec(f"pactl set-sink-volume {sink_id} 100%")
    print(f"   Volume set on sink {sink_id}")

# Step 10: Final check
print("🔟  Final status:")
output, error = ssh_exec("pactl list sinks | grep -A 15 bluez | head -20")
print(output)

print("")
print("✅ Aggressive fix complete!")
print("")
print("Testing audio now...")
time.sleep(1)

# Quick test
output, error = ssh_exec("pactl list short sinks | grep bluez | awk '{print $2}'")
sink_name = output.strip() if output.strip() else "bluez_output.41_42_FF_3E_1F_25.1"

cmd = f"sox -n -t raw -r 44100 -b 16 -c 1 - synth 3 sine 80 vol 0.7 | paplay -d {sink_name} --rate=44100 --channels=1 --format=s16le 2>&1"
print(f"Running: {cmd}")
output, error = ssh_exec(cmd, timeout=10)
if output:
    print(f"Output: {output}")
if error:
    print(f"Error: {error}")

print("")
print("🎵 If you hear the bass tone, success! Otherwise check speaker placement.")
