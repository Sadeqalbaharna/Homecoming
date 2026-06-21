#!/usr/bin/env python3
"""
Bluetooth Speaker Wake & Force Audio - Aggressively wake speaker and force audio output
"""

import paramiko
import logging
import sys
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_USER = "pi"
SPEAKER_MAC = "39:3E:58:14:40:4A"

def run_remote_command(client, cmd):
    """Run command on remote Pi"""
    stdin, stdout, stderr = client.exec_command(cmd)
    out = stdout.read().decode('utf-8', errors='ignore').strip()
    err = stderr.read().decode('utf-8', errors='ignore').strip()
    return out, err, stdout.channel.recv_exit_status()

def force_speaker_wake(pi_ip):
    """Aggressively wake and activate speaker for audio"""
    try:
        logger.info(f"\n🔊 FORCING SPEAKER ACTIVATION on {pi_ip}...\n")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        # STEP 1: Hard disconnect and reconnect
        logger.info("STEP 1️⃣  Force Device Reconnect")
        logger.info("   🔄 Disconnecting speaker...")
        run_remote_command(client, f"bluetoothctl disconnect {SPEAKER_MAC}")
        time.sleep(2)
        
        logger.info("   🔄 Reconnecting speaker...")
        run_remote_command(client, f"bluetoothctl connect {SPEAKER_MAC}")
        time.sleep(5)
        
        logger.info("   ✅ Reconnection complete")
        
        # STEP 2: Get and set volume to MAX
        logger.info("\nSTEP 2️⃣  Set Volume to MAXIMUM")
        out, _, _ = run_remote_command(
            client,
            "pactl list short sinks | grep bluez_output | awk '{print $2}'"
        )
        sink = out.strip()
        
        if sink:
            logger.info(f"   Sink: {sink}")
            logger.info("   📢 Setting volume to 100%...")
            run_remote_command(client, f"pactl set-sink-volume {sink} 100%")
            
            out, _, _ = run_remote_command(client, f"pactl get-sink-volume {sink}")
            logger.info(f"   Volume: {out}")
        
        # STEP 3: Unmute if muted
        logger.info("\nSTEP 3️⃣  Unmute Speaker")
        out, _, _ = run_remote_command(client, f"pactl get-sink-mute {sink}")
        
        if "yes" in out.lower():
            logger.warning("   🔇 Sink is MUTED! Unmuting...")
            run_remote_command(client, f"pactl set-sink-mute {sink} 0")
            logger.info("   🔊 Unmuted")
        else:
            logger.info("   ✅ Already unmuted")
        
        # STEP 4: Send LOUD test tone
        logger.info("\nSTEP 4️⃣  Send LOUD Test Tone")
        logger.info("   🔊 Playing LOUD 1kHz tone for 5 seconds...")
        logger.info("   (You should DEFINITELY hear this)\n")
        
        # Generate and play loud tone
        cmd = f"""
cat > /tmp/loud_test.sh << 'EOF'
#!/bin/bash
# Generate 5 seconds of loud 1kHz sine wave and play it
sox -n -t raw -r 44100 -b 16 -c 1 - synth 5 sine 1000 vol 1.0 | paplay -d {sink} --rate=44100 --channels=1 --format=s16le
EOF
chmod +x /tmp/loud_test.sh
timeout 6 /tmp/loud_test.sh
"""
        
        out, err, code = run_remote_command(client, cmd)
        
        if "command not found" in err.lower() and "sox" in err.lower():
            logger.warning("   ⚠️  sox not found, trying alternate method...")
            # Use pure paplay with white noise
            cmd = f"""
dd if=/dev/urandom bs=4410 count=10 2>/dev/null | paplay -d {sink} --rate=44100 --channels=1 --format=u8 --volume=65536
"""
            out, err, code = run_remote_command(client, cmd)
            logger.info("   🎵 White noise sent to speaker")
        else:
            logger.info("   🎵 Loud tone sent to speaker")
        
        # STEP 5: Give user feedback
        logger.info("\n" + "="*70)
        logger.info("DID YOU HEAR THE LOUD TONE? (5 second blast)")
        logger.info("="*70)
        logger.info("\n✅ If YES: Speaker is working! Audio path is OK")
        logger.info("❌ If NO: Speaker may need:")
        logger.info("   - Manual power cycle (turn off/on)")
        logger.info("   - Check physical volume buttons on speaker")
        logger.info("   - Verify Bluetooth firmware is up to date")
        logger.info("   - Check if speaker is in pairing mode (usually needs reset)")
        
        client.close()
        return 0
        
    except Exception as e:
        logger.error(f"❌ Failed: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logger.error("Usage: python force_speaker_wake.py <PI_IP>")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    sys.exit(force_speaker_wake(pi_ip))
