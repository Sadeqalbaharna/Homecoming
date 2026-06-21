#!/usr/bin/env python3
"""
Deploy to Pi - Accepts Pi IP as command-line argument
"""

import paramiko
import logging
import sys
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_USER = "pi"
PI_HOME = "/home/pi"

def deploy(pi_ip):
    """Deploy to specified Pi IP"""
    try:
        logger.info(f"\n📤 Uploading to {pi_ip}...")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            pi_ip,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        sftp = client.open_sftp()
        app_dir = Path(__file__).parent
        
        # Upload scripts
        files = [
            "bluetooth_startup_check.py",
            "troubleshoot_bluetooth.py",
        ]
        
        for filename in files:
            local_file = app_dir / filename
            remote_file = f"{PI_HOME}/{filename}"
            
            if local_file.exists():
                sftp.put(str(local_file), remote_file)
                logger.info(f"   ✅ {filename}")
            else:
                logger.warning(f"   ⚠️  {filename} not found")
        
        sftp.close()
        
        # Make executable
        logger.info("\n🔧 Setting permissions...")
        for filename in files:
            client.exec_command(f"chmod +x {PI_HOME}/{filename}")
        
        logger.info("   ✅ Executable permissions set")
        
        # Install systemd service
        logger.info("\n📋 Installing systemd service...")
        service_content = '''[Unit]
Description=Homecoming Bluetooth Check
After=bluetooth.service
Wants=bluetooth.service

[Service]
Type=oneshot
User=pi
ExecStart=/usr/bin/python3 /home/pi/bluetooth_startup_check.py
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
'''
        
        stdin, stdout, stderr = client.exec_command(
            f"cat > /tmp/homecoming-check.service << 'EOF'\n{service_content}\nEOF"
        )
        
        client.exec_command("sudo mv /tmp/homecoming-check.service /etc/systemd/system/")
        client.exec_command("sudo systemctl daemon-reload")
        client.exec_command("sudo systemctl enable homecoming-check.service")
        
        logger.info("   ✅ Systemd service installed")
        
        client.close()
        
        logger.info("\n✅ Deployment complete!")
        return 0
        
    except Exception as e:
        logger.error(f"Deployment failed: {e}")
        return 1

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logger.error("Usage: python deploy_to_pi.py <PI_IP>")
        sys.exit(1)
    
    pi_ip = sys.argv[1]
    sys.exit(deploy(pi_ip))
