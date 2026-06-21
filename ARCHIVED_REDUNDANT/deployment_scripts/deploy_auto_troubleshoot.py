#!/usr/bin/env python3
"""
Deploy auto-troubleshoot system to Pi
"""

import paramiko
import logging
import subprocess
import sys
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_USER = "pi"
PI_HOME = "/home/pi"
PI_IP = None  # Will be auto-discovered

def deploy():
    global PI_IP
    
    try:
        # Auto-discover Pi if not set
        if not PI_IP:
            logger.info("🔍 Auto-discovering Pi...")
            result = subprocess.run(
                [sys.executable, str(Path(__file__).parent / "scan_local_network.py")],
                capture_output=True,
                text=True,
                timeout=120
            )
            
            if result.returncode == 0:
                PI_IP = result.stdout.strip().split('\n')[-1]
                logger.info(f"✅ Found Pi at: {PI_IP}\n")
            else:
                logger.error("Could not discover Pi")
                return 1
        
        logger.info("\n" + "="*70)
        logger.info("DEPLOYING AUTO-TROUBLESHOOT SYSTEM TO PI".center(70))
        logger.info("="*70 + "\n")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(PI_IP, username=PI_USER, key_filename=str(Path.home() / ".ssh" / "id_rsa"))
        
        sftp = client.open_sftp()
        app_dir = Path(__file__).parent
        
        # Upload scripts
        files_to_upload = [
            "bluetooth_startup_check.py",
            "auto_troubleshoot_bluetooth.py",
            "play_pirate_fixed.py",
        ]
        
        logger.info("📤 Uploading scripts to Pi...")
        for filename in files_to_upload:
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
        for filename in files_to_upload:
            client.exec_command(f"chmod +x {PI_HOME}/{filename}")
        logger.info("   ✅ Executable permissions set")
        
        # Option 1: Install as systemd service
        logger.info("\n📋 Installing systemd service...")
        service_content = '''[Unit]
Description=Homecoming Bluetooth Troubleshoot
After=bluetooth.service

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
        
        # Test it
        logger.info("\n🧪 Testing troubleshoot script...")
        stdin, stdout, stderr = client.exec_command(f"cd {PI_HOME} && python3 bluetooth_startup_check.py")
        
        output = stdout.read().decode()
        if "SPEAKER READY" in output:
            logger.info("   ✅ Test successful!")
        
        for line in output.split('\n')[-10:]:
            if line.strip():
                logger.info(f"   {line}")
        
        client.close()
        
        logger.info("\n" + "="*70)
        logger.info("DEPLOYMENT COMPLETE".center(70))
        logger.info("="*70)
        logger.info("\n✅ Auto-troubleshoot system deployed!")
        logger.info("\nNow when Pi boots, it will:")
        logger.info("  1. Auto-check Bluetooth adapter")
        logger.info("  2. Auto-reconnect speaker if needed")
        logger.info("  3. Auto-fix PulseAudio issues")
        logger.info("  4. Confirm speaker is ready\n")
        
        return 0
        
    except Exception as e:
        logger.error(f"Deployment failed: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(deploy())
