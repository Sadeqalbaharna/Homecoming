#!/usr/bin/env python3
"""
Deep diagnostic of GL-TWS91 audio sink state.
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

print("\n🔍 DEEP DIAGNOSTIC: GL-TWS91 AUDIO SINK\n")

# 1. Connection status
print("1️⃣  Bluetooth Connection Status:")
output, _ = ssh_exec("sudo bluetoothctl info 41:42:FF:3E:1F:25")
for line in output.split('\n'):
    if any(x in line for x in ['Connected', 'ServicesResolved', 'State']):
        print(f"  {line.strip()}")

# 2. Check if sink is suspended
print("\n2️⃣  Sink Suspension Status:")
output, _ = ssh_exec("pactl list sinks | grep -A 20 bluez_output.41")
for line in output.split('\n'):
    if 'Suspended' in line or 'State' in line:
        print(f"  {line.strip()}")

# 3. Try direct PulseAudio test with verbose output
print("\n3️⃣  Testing PulseAudio audio output (verbose):")
cmd = "echo 'Testing' | paplay -d bluez_output.41_42_FF_3E_1F_25.1 --verbose --rate=16000 2>&1 | head -20"
output, error = ssh_exec(cmd, timeout=5)
if output or error:
    print(output if output else error)
else:
    print("  (no output)")

# 4. Check if device is actively using SCO (voice) transport
print("\n4️⃣  Checking Bluetooth transport mode:")
output, _ = ssh_exec("sudo hcitool con")
print(output if output else "  (no active connections)")

# 5. Try switching to test output
print("\n5️⃣  Trying to play to default ALSA device first:")
cmd = "sox -n -t raw -r 48000 -b 16 -c 2 - synth 2 sine 800 vol 0.5 | paplay -v --rate=48000 2>&1 | head -5"
output, error = ssh_exec(cmd, timeout=5)
print("ALSA test output:", output[:100] if output else error[:100])

# 6. Check for any errors in Bluetooth module
print("\n6️⃣  Checking for Bluetooth errors:")
output, _ = ssh_exec("journalctl -u pipewire --no-pager -n 20 | grep -i error")
if output.strip():
    print(output)
else:
    print("  (no recent errors)")

print("\n💡 ANALYSIS:")
print("  • If 'Connected: yes' - device is paired")
print("  • If 'Suspended: yes' - sink won't play audio (try: pactl suspend-sink X false)")
print("  • If 'Failed to open' - PipeWire/PulseAudio can't route to sink")
print("  • If ALSA test fails too - system-wide audio issue")
