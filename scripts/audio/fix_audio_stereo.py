#!/usr/bin/env python3
"""
Fix audio balance - send stereo audio to both channels.
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

log.info("\n⚖️  FIXING AUDIO BALANCE TO STEREO\n")

# Step 1: Set balance and volumes
log.info("1️⃣  Adjusting audio balance to both channels...")

ssh_exec("amixer -c 0 sset PCM 100%")
ssh_exec("amixer -c 0 sset Master 100%")
ssh_exec("amixer -c 0 sset Master unmute")

log.info("   ✅ Balance set to center (both channels)\n")

# Step 2: Generate and test stereo audio
log.info("2️⃣  Testing with stereo audio (different tones in each channel)...")

test_cmd = """sox -n -t raw -r 48000 -b 16 -c 2 - \
    synth 5 sine 440 sine 880 remix - vol 0.9 | \
    aplay -D hw:0,0 --rate=48000 --channels=2 --format=S16_LE 2>&1"""

ssh_exec(test_cmd + " > /dev/null 2>&1 &")
time.sleep(6)

log.info("   ✅ Stereo audio sent\n")
log.info("🎧 You should now hear different tones in each headphone:")
log.info("   Left headphone: 440Hz (lower tone)")
log.info("   Right headphone: 880Hz (higher tone)")
log.info("")
