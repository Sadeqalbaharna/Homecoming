#!/usr/bin/env python3
"""
Debug the actual device routing
"""

import paramiko
from pathlib import Path
import time

PI_IP = "192.168.48.5"
PI_USER = "pi"

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))

print("\n" + "="*70)
print("AUDIO DEVICE DEBUG")
print("="*70 + "\n")

# List all sinks with full details
print("1. ALL AUDIO SINKS:")
stdin, stdout, stderr = client.exec_command("pactl list sinks")
output = stdout.read().decode()
print(output)

print("\n2. DEFAULT SINK:")
stdin, stdout, stderr = client.exec_command("pactl get-default-sink")
output = stdout.read().decode()
print(f"Default: {output}")

print("3. BLUETOOTH CONNECTION STATUS:")
stdin, stdout, stderr = client.exec_command("bluetoothctl info 39:3E:58:14:40:4A")
output = stdout.read().decode()
print(output)

print("4. TRYING DIRECT PAPLAY TO ALSA (FALLBACK):")
# Try playing to ALSA directly instead
stdin, stdout, stderr = client.exec_command(
    "python3 -c \"import wave, struct, math; "
    "f = wave.open('/tmp/test.wav', 'wb'); "
    "f.setnchannels(1); f.setsampwidth(2); f.setframerate(44100); "
    "[f.writeframes(struct.pack('<h', int(32767*math.sin(2*math.pi*440*i/44100)))) for i in range(44100*2)]; "
    "f.close(); "
    "print('File created')\" && "
    "paplay /tmp/test.wav 2>&1 &"
)
time.sleep(3)
output = stdout.read().decode()
print(output)
time.sleep(3)

client.exec_command("killall paplay 2>/dev/null")

print("\n5. Did you hear a tone just now?")
print("   YES → Audio can route to ALSA, not to Bluetooth")
print("   NO  → Check if speakers are powered on\n")

client.close()
