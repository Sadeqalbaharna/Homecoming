#!/usr/bin/env python3
"""
Find PipeWire profiles for GL-TWS91 and try to switch to A2DP.
"""

import sys
import subprocess
from pathlib import Path

try:
    import paramiko
except ImportError:
    subprocess.run([sys.executable, "-m", "pip", "install", "paramiko", "-q"], check=True)
    import paramiko

PI_IP = "192.168.131.5"
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

print("\n🔧 CHECKING PIPEWIRE PROFILES FOR GL-TWS91\n")

# Get PipeWire device info
output, _ = ssh_exec("pw-dump | grep -B5 -A20 '41:42:FF:3E:1F:25' | head -50")
print("PipeWire Device Info:")
print(output if output else "(no info)")

# Get PulseAudio card
output, _ = ssh_exec("pactl list cards")
print("\nPulseAudio Cards:")
in_gl91 = False
for line in output.split('\n'):
    if 'GL-TWS91' in line or '41:42:FF:3E:1F:25' in line:
        in_gl91 = True
    if in_gl91:
        print(line)
        if 'Profiles:' in line:
            # Print next 10 lines for profiles
            idx = output.split('\n').index(line)
            for i in range(idx, min(idx+15, len(output.split('\n')))):
                print(output.split('\n')[i])
            break

# Try to list and switch profiles
print("\nTrying to switch to A2DP profile...")
output, err = ssh_exec("pactl list cards | grep -A 100 'GL-TWS91' | grep -A 20 'Profiles:'")
print(output if output else "(checking...)")

# Try setting A2DP
print("\nAttempting to switch to a2dp_sink profile...")
output, err = ssh_exec("pactl set-card-profile bluez_card.41_42_FF_3E_1F_25 a2dp_sink")
print(f"Result: {output if output else err}")

import time
time.sleep(2)

# Check if it changed
print("\nChecking current profile after switch...")
output, _ = ssh_exec("pactl list short cards | grep 41_42_FF")
print(output if output else "(checking...)")

output, _ = ssh_exec("pactl list sinks | grep -A 10 'bluez_output.41'")
print("\nCurrent sink details:")
for line in output.split('\n'):
    if any(x in line for x in ['Name:', 'Profile', 'Sample', 'Volume', 'Mute']):
        print(line)
