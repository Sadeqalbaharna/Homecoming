#!/usr/bin/env python3
"""
Connect to GL-TWS91 Speaker
"""

import paramiko
import logging
import sys
from pathlib import Path
import time

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_USER = "pi"
GL91_MAC = "41:42:FF:3E:1F:25"
GL91_NAME = "GL-TWS91"

def run_remote_command(client, cmd):
    """Run command on remote Pi"""
    stdin, stdout, stderr = client.exec_command(cmd)
    out = stdout.read().decode('utf-8', errors='ignore').strip()
    err = stderr.read().decode('utf-8', errors='ignore').strip()
    return out, err, stdout.channel.recv_exit_status()

def connect_to_gl91(pi_ip):
    """Connect to GL-TWS91 speaker"""
    try:
        logger.info(f"\n🎵 CONNECTING TO GL-TWS91 on {pi_ip}\n")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        # Disconnect from old device
        logger.info("🔄 Disconnecting from old device...")
        run_remote_command(client, "bluetoothctl disconnect 39:3E:58:14:40:4A")
        time.sleep(2)
        
        # Connect to GL-TWS91
        logger.info(f"🔗 Connecting to {GL91_NAME}...")
        out, _, code = run_remote_command(client, f"bluetoothctl connect {GL91_MAC}")
        
        time.sleep(3)
        
        # Verify connection
        out, _, _ = run_remote_command(client, f"bluetoothctl info {GL91_MAC} | grep Connected")
        
        if "yes" in out.lower():
            logger.info(f"✅ Successfully connected to {GL91_NAME}!\n")
            
            # Test with bass tone
            logger.info("🔊 Testing with bass tone...")
            
            # Get Bluetooth sink for GL91
            out, _, _ = run_remote_command(
                client,
                "pactl list short sinks | grep bluez_output | awk '{print $2}' | head -1"
            )
            sink = out.strip()
            
            if sink:
                logger.info(f"   Sink: {sink}")
                logger.info("   Playing 80Hz bass tone...")
                
                cmd = f"""
sox -n -t raw -r 44100 -b 16 -c 1 - \\
    synth 5 sine 80 vol 0.5 \\
    | paplay -d {sink} --rate=44100 --channels=1 --format=s16le 2>&1
"""
                
                run_remote_command(client, cmd)
                logger.info("   ✅ Bass test sent")
                logger.info("   Did you hear the bass rumble?\n")
            
            client.close()
            return 0
        else:
            logger.error(f"❌ Could not connect to {GL91_NAME}")
            logger.info(out)
            client.close()
            return 1
        
    except Exception as e:
        logger.error(f"❌ Failed: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logger.error("Usage: python connect_gl91.py <PI_IP>")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    sys.exit(connect_to_gl91(pi_ip))
