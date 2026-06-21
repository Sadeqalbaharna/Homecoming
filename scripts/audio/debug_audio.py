#!/usr/bin/env python3
"""
Debug 3.5mm jack audio output.
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

log.info("\n🔧 DEBUGGING 3.5MM JACK AUDIO\n")

# Step 1: Check aplay can output
log.info("1️⃣  Testing aplay directly...")
output, error = ssh_exec("aplay --list-devices")
log.info(output if output else "(checking...)")

# Step 2: Check ffmpeg
log.info("2️⃣  Checking ffmpeg...")
output, error = ssh_exec("which ffmpeg")
if output.strip():
    log.info(f"   ✅ ffmpeg: {output.strip()}")
else:
    log.warning("   ❌ ffmpeg not found - YouTube streaming won't work")

# Step 3: Check yt-dlp
log.info("3️⃣  Checking yt-dlp...")
output, error = ssh_exec("yt-dlp --version")
if output.strip():
    log.info(f"   ✅ yt-dlp: {output.strip()}")
else:
    log.warning("   ❌ yt-dlp not found")

# Step 4: Simple test tone
log.info("4️⃣  Sending test tone to hw:0,0...")
test_cmd = "dd if=/dev/zero bs=1024 count=100 2>/dev/null | aplay -D hw:0,0 --rate=48000 --channels=2 --format=S16_LE 2>&1 &"
ssh_exec(test_cmd)
time.sleep(2)
log.info("   ✅ White noise sent (2 seconds)")

# Step 5: ALSA card info
log.info("\n5️⃣  Audio device info...")
output, error = ssh_exec("cat /proc/asound/cards")
log.info(output)

log.info("\n💡 TROUBLESHOOTING:")
log.info("   • Physically check: Are headphones plugged into 3.5mm jack?")
log.info("   • Check volume: Is the Pi volume set high enough?")
log.info("   • Check headphones: Try a different audio source (phone, computer)")
log.info("   • Check jack: Look for dirt/debris in the jack")
log.info("")
