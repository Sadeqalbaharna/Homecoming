#!/usr/bin/env python3
"""
Check if scene is currently playing
"""

import paramiko
from pathlib import Path

PI_IP = "192.168.48.5"
PI_USER = "pi"

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))

print("\nChecking if audio is playing...\n")

# Check for mpv or yt-dlp processes
stdin, stdout, stderr = client.exec_command("ps aux | grep -E 'mpv|yt-dlp|paplay' | grep -v grep")
output = stdout.read().decode()

if output:
    print("✅ Audio processes running:")
    print(output)
else:
    print("❌ No audio processes found")

# Check Bluetooth sink status
print("\nBluetooth sink status:")
stdin, stdout, stderr = client.exec_command(
    "pactl list sinks | grep -A 3 'bluez_output' | grep -E 'State|Running'"
)
output = stdout.read().decode()
print(output)

client.close()
