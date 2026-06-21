#!/usr/bin/env python3
"""
Deep debug of audio pipeline on Pi - check PulseAudio status, sinks, and audio routing.
"""

import sys
import subprocess
from pathlib import Path

try:
    import paramiko
except ImportError:
    print("Installing paramiko...")
    subprocess.run([sys.executable, "-m", "pip", "install", "paramiko", "-q"], check=True)
    import paramiko

if len(sys.argv) < 2:
    print("Usage: python debug_audio_pipeline.py <pi_ip>")
    sys.exit(1)

PI_IP = sys.argv[1]
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
print("🔍 AUDIO PIPELINE DEBUG on " + PI_IP)
print("")

# Check if PulseAudio is running
print("1️⃣  PulseAudio Status:")
output, error = ssh_exec("ps aux | grep pulseaudio | grep -v grep")
if output.strip():
    print("   ✅ PulseAudio is running")
else:
    print("   ❌ PulseAudio NOT RUNNING - this is the problem!")
    print("   Attempting to start PulseAudio...")
    ssh_exec("pulseaudio --start")

# List all sinks
print("")
print("2️⃣  Available Audio Sinks:")
output, error = ssh_exec("pactl list short sinks")
print(output if output else "   (no sinks)")
for line in output.split('\n'):
    if line.strip():
        print(f"   {line}")

# Check default sink
print("")
print("3️⃣  Default Sink:")
output, error = ssh_exec("pactl get-default-sink")
print(f"   {output.strip() if output else '(none set)'}")

# Check Bluetooth sink specifically
print("")
print("4️⃣  Bluetooth Audio Sinks:")
output, error = ssh_exec("pactl list short sinks | grep bluez")
if output.strip():
    for line in output.split('\n'):
        if line.strip():
            print(f"   {line}")
else:
    print("   ❌ NO Bluetooth sinks found!")
    print("   This means PulseAudio Bluetooth module isn't loaded")

# Check PulseAudio modules
print("")
print("5️⃣  Loaded PulseAudio Modules:")
output, error = ssh_exec("pactl list short modules | grep -i bluez")
if output.strip():
    for line in output.split('\n'):
        if line.strip():
            print(f"   {line}")
else:
    print("   ❌ Bluetooth module not loaded!")
    print("   Need to load: module-bluez5-discover")

# Try to load the module
print("")
print("6️⃣  Attempting to load Bluetooth module...")
output, error = ssh_exec("pactl load-module module-bluez5-discover")
print(f"   {output.strip() if output else error.strip()}")

# Wait and check again
print("")
print("7️⃣  Waiting 2 seconds and checking sinks again...")
import time
time.sleep(2)

output, error = ssh_exec("pactl list short sinks | grep bluez")
if output.strip():
    print("   ✅ Bluetooth sinks now available:")
    for line in output.split('\n'):
        if line.strip():
            print(f"      {line}")
else:
    print("   ❌ Still no Bluetooth sinks")

# Check suspend state
print("")
print("8️⃣  Checking if sinks are suspended:")
output, error = ssh_exec("pactl list sinks | grep -A 5 bluez")
for line in output.split('\n'):
    if any(x in line for x in ['Suspended', 'State', 'bluez']):
        print(f"   {line.strip()}")

# Try to unsuspend
print("")
print("9️⃣  Attempting to resume all sinks...")
output, error = ssh_exec("pactl list short sinks | awk '{print $1}' | xargs -I {} pactl suspend-sink {} false")
print("   (resumed)")

# Final check - try test-alsa-output
print("")
print("🔟 Testing ALSA audio output directly...")
output, error = ssh_exec("speaker-test -t wav -c 2 -l 1 -s 1", timeout=10)
if "Front Left" in output or "test completed" in output.lower():
    print("   ✅ ALSA working")
else:
    print("   ⚠️  ALSA test output: " + (output[:100] if output else error[:100]))

print("")
print("💡 SUMMARY:")
print("   If no Bluetooth sinks found, audio won't reach the speakers")
print("   If sinks are suspended, audio won't play")
print("   Check that module-bluez5-discover is loaded")
