#!/usr/bin/env python3
"""
Pair and Connect to GL-TWS91
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

def pair_and_connect_gl91(pi_ip):
    """Pair and connect to GL-TWS91 speaker"""
    try:
        logger.info(f"\n🎵 PAIRING GL-TWS91 on {pi_ip}\n")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        # Make sure Bluetooth is on
        logger.info("🔋 Ensuring Bluetooth adapter is on...")
        run_remote_command(client, "sudo hciconfig hci0 up")
        time.sleep(1)
        
        # Remove any old pairing
        logger.info("🔄 Removing any old pairing...")
        run_remote_command(client, f"bluetoothctl remove {GL91_MAC}")
        time.sleep(1)
        
        # Pair
        logger.info(f"🔗 Pairing {GL91_NAME}...")
        logger.info("   (Make sure GL-TWS91 is in pairing mode)")
        
        out, err, code = run_remote_command(client, f"bluetoothctl pair {GL91_MAC}")
        logger.info(f"   Pairing result: {out[:100]}")
        time.sleep(2)
        
        # Trust
        logger.info("✅ Trusting device...")
        run_remote_command(client, f"bluetoothctl trust {GL91_MAC}")
        time.sleep(1)
        
        # Connect
        logger.info("🔗 Connecting...")
        out, err, code = run_remote_command(client, f"bluetoothctl connect {GL91_MAC}")
        time.sleep(3)
        
        # Verify connection
        out, _, _ = run_remote_command(client, f"bluetoothctl info {GL91_MAC} | grep Connected")
        
        if "yes" in out.lower():
            logger.info(f"✅ Successfully connected to {GL91_NAME}!\n")
            client.close()
            return 0
        else:
            logger.warning(f"⚠️  Status: {out}")
            logger.info("   Device may need to be in pairing mode")
            client.close()
            return 1
        
    except Exception as e:
        logger.error(f"❌ Failed: {e}")
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logger.error("Usage: python pair_gl91.py <PI_IP>")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    sys.exit(pair_and_connect_gl91(pi_ip))
