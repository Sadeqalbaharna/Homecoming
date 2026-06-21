#!/usr/bin/env python3
"""
Fix headphone audio output on Raspberry Pi.
Unmute and maximize all audio controls.
"""

import paramiko
from pathlib import Path
import time
import logging

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
log = logging.getLogger(__name__)

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

log.info("\n🔧 FIXING HEADPHONE AUDIO OUTPUT\n")

# Step 1: Unmute and maximize all audio controls
log.info("1️⃣  Unmuting and maximizing audio controls...")

controls = [
    ("Master", True),
    ("Headphone", True),
    ("Headphone Jack", True),
    ("PCM", True),
    ("Speaker", False),  # Disable speakers
]

for control, unmute in controls:
    # Try to unmute
    if unmute:
        ssh_exec(f"amixer -c 0 sset '{control}' unmute 2>/dev/null")
        ssh_exec(f"amixer -c 0 sset '{control}' 100% 2>/dev/null")
        log.info(f"   ✅ Unmuted {control} to 100%")
    else:
        ssh_exec(f"amixer -c 0 sset '{control}' 0 2>/dev/null")
        log.info(f"   ✅ Disabled {control}")

# Step 2: Check current settings
log.info("\n2️⃣  Current mixer settings:")
output, _ = ssh_exec("amixer -c 0")
# Show just the relevant lines
for line in output.split('\n'):
    if any(x in line.lower() for x in ['simple', 'pcm', 'headphone', 'master', 'limits', 'playback', '[on]', '[off]']):
        if line.strip():
            log.info(f"   {line.strip()[:80]}")

# Step 3: Test with loud brown noise
log.info("\n3️⃣  Testing with loud brown noise...")
test_cmd = "sox -n -t raw -r 48000 -b 16 -c 2 - synth 5 brownnoise vol 1.0 | aplay -D hw:0,0 --rate=48000 --channels=2 --format=S16_LE 2>&1 > /dev/null &"
ssh_exec(test_cmd)

time.sleep(6)

log.info("   ✅ Audio sent (5 second brown noise at max volume)\n")

log.info("🎧 You should hear loud brown noise from the headphones")
log.info("   If you hear it: Audio is working!")
log.info("   If not: Check if headphones are plugged in firmly")
log.info("")
