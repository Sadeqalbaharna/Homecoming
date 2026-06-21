#!/usr/bin/env python3
"""
Test exact bass command and capture full output/errors from Pi.
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
    print("Usage: python test_bass_verbose.py <pi_ip>")
    sys.exit(1)

PI_IP = sys.argv[1]
PI_USER = "pi"
SSH_KEY = Path.home() / ".ssh" / "id_rsa"

def ssh_exec_verbose(cmd, timeout=30):
    """Execute command and return full output."""
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
print("🔍 VERBOSE BASS TEST on " + PI_IP)
print("")

# Step 1: List sinks
print("1️⃣  Finding Bluetooth sink...")
output, error = ssh_exec_verbose("pactl list short sinks")
print("All sinks:")
print(output)
print("")

# Find the bluez sink
bluez_sinks = [line for line in output.split('\n') if 'bluez' in line]
if bluez_sinks:
    print("Bluetooth sinks found:")
    for sink in bluez_sinks:
        print(f"   {sink}")
    sink_name = bluez_sinks[0].split()[1]
    print(f"Using sink: {sink_name}")
else:
    print("❌ NO Bluetooth sink found!")
    sys.exit(1)

print("")

# Step 2: Check sox is available
print("2️⃣  Checking if sox is installed...")
output, error = ssh_exec_verbose("which sox")
if output.strip():
    print(f"   ✅ sox found: {output.strip()}")
else:
    print("   ❌ sox NOT INSTALLED")
    print("   Installing sox...")
    ssh_exec_verbose("sudo apt-get update && sudo apt-get install -y sox libsox-fmt-all")

print("")

# Step 3: Check paplay is available
print("3️⃣  Checking if paplay is installed...")
output, error = ssh_exec_verbose("which paplay")
if output.strip():
    print(f"   ✅ paplay found: {output.strip()}")
else:
    print("   ❌ paplay NOT INSTALLED")

print("")

# Step 4: Check if we can list the specific sink
print("4️⃣  Checking sink details...")
output, error = ssh_exec_verbose(f"pactl list sinks | grep -A 20 'Name: {sink_name}'")
print(output if output else "(no details)")

print("")

# Step 5: Test simple tone command
print("5️⃣  Testing simple sox command (no piping)...")
output, error = ssh_exec_verbose("sox -n -t raw -r 44100 -b 16 -c 1 /tmp/test_tone.raw synth 2 sine 80 vol 0.5")
if not error or "error" not in error.lower():
    print("   ✅ sox command succeeded")
    # Check if file was created
    output, error = ssh_exec_verbose("ls -lh /tmp/test_tone.raw")
    print(f"   File: {output.strip()}")
else:
    print(f"   ❌ sox error: {error}")

print("")

# Step 6: Try to play it with paplay
print("6️⃣  Trying to play the file with paplay...")
output, error = ssh_exec_verbose(f"paplay -d {sink_name} --rate=44100 --channels=1 --format=s16le /tmp/test_tone.raw")
if output:
    print(f"   Output: {output}")
if error:
    print(f"   Error: {error}")
else:
    print("   ✅ Command sent (may be playing)")

print("")

# Step 7: Try the piped version
print("7️⃣  Testing piped sox→paplay command...")
cmd = f"sox -n -t raw -r 44100 -b 16 -c 1 - synth 3 sine 80 vol 0.5 | paplay -d {sink_name} --rate=44100 --channels=1 --format=s16le 2>&1"
print(f"Command: {cmd}")
print("")
output, error = ssh_exec_verbose(cmd, timeout=10)
if output:
    print(f"Output:\n{output}")
if error:
    print(f"Error:\n{error}")

print("")
print("💡 Check:")
print("   • Is sink suspended? (should see 'Suspended: no')")
print("   • Is volume > 0?")
print("   • Are you near the speaker?")
