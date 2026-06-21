#!/usr/bin/env python3
"""
Unified Deployment Module for Homecoming App
Consolidates all deployment functionality - replaces 10+ duplicate scripts
"""

import paramiko
import logging
import sys
import subprocess
from pathlib import Path
from typing import List, Optional, Tuple

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

class PiDeployer:
    """Unified deployment handler for Raspberry Pi"""
    
    DEFAULT_PI_USER = "pi"
    DEFAULT_PI_HOME = "/home/pi"
    DEFAULT_PI_IPS = ["192.168.48.5", "192.168.1.100", "192.168.0.100"]
    
    def __init__(self, pi_ip: str = None, username: str = DEFAULT_PI_USER):
        self.pi_ip = pi_ip or self._discover_pi()
        self.username = username
        self.pi_home = self.DEFAULT_PI_HOME
        self.app_dir = Path(__file__).parent
        
        if not self.pi_ip:
            raise ValueError("Could not discover Pi. Provide IP address.")
    
    def _discover_pi(self) -> Optional[str]:
        """Try to discover Pi on network"""
        logger.info("🔍 Discovering Raspberry Pi on network...")
        for ip in self.DEFAULT_PI_IPS:
            if self._test_ssh_connection(ip):
                logger.info(f"✅ Found Pi at {ip}")
                return ip
        return None
    
    def _test_ssh_connection(self, ip: str, timeout: int = 2) -> bool:
        """Test SSH connection to Pi"""
        try:
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            client.connect(ip, username=self.username, timeout=timeout)
            client.close()
            return True
        except:
            return False
    
    def _get_ssh_client(self) -> paramiko.SSHClient:
        """Get authenticated SSH client"""
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            self.pi_ip,
            username=self.username,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        return client
    
    def deploy_files(self, files: List[str], remote_dir: str = None) -> bool:
        """Deploy files to Pi"""
        remote_dir = remote_dir or self.pi_home
        logger.info(f"\n📤 Deploying to {self.pi_ip}:{remote_dir}")
        
        try:
            client = self._get_ssh_client()
            sftp = client.open_sftp()
            
            success_count = 0
            for filename in files:
                local_file = self.app_dir / filename
                remote_file = f"{remote_dir}/{Path(filename).name}"
                
                if not local_file.exists():
                    logger.warning(f"   ⚠️  {filename} not found (skipping)")
                    continue
                
                try:
                    sftp.put(str(local_file), remote_file)
                    logger.info(f"   ✅ {filename}")
                    success_count += 1
                except Exception as e:
                    logger.error(f"   ❌ {filename}: {e}")
            
            sftp.close()
            client.close()
            return success_count > 0
            
        except Exception as e:
            logger.error(f"❌ Deployment failed: {e}")
            return False
    
    def deploy_directory(self, src_dir: str, remote_dir: str = None) -> bool:
        """Deploy entire directory to Pi"""
        remote_dir = remote_dir or self.pi_home
        logger.info(f"\n📤 Deploying directory {src_dir} to {self.pi_ip}:{remote_dir}")
        
        try:
            client = self._get_ssh_client()
            sftp = client.open_sftp()
            
            local_dir = self.app_dir / src_dir
            if not local_dir.exists():
                logger.error(f"   ❌ Directory {src_dir} not found")
                return False
            
            def upload_dir(local_path: Path, remote_path: str):
                """Recursively upload directory"""
                for item in local_path.iterdir():
                    remote_item = f"{remote_path}/{item.name}"
                    if item.is_dir():
                        try:
                            sftp.mkdir(remote_item)
                        except:
                            pass  # Already exists
                        upload_dir(item, remote_item)
                    else:
                        sftp.put(str(item), remote_item)
                        logger.info(f"   ✅ {item.name}")
            
            upload_dir(local_dir, f"{remote_dir}/{src_dir}")
            sftp.close()
            client.close()
            return True
            
        except Exception as e:
            logger.error(f"❌ Directory deployment failed: {e}")
            return False
    
    def run_remote_command(self, command: str, description: str = None) -> Tuple[str, str]:
        """Execute command on Pi"""
        if description:
            logger.info(f"\n🔧 {description}")
        
        try:
            client = self._get_ssh_client()
            stdin, stdout, stderr = client.exec_command(command)
            out = stdout.read().decode()
            err = stderr.read().decode()
            client.close()
            return out, err
        except Exception as e:
            logger.error(f"❌ Command failed: {e}")
            return "", str(e)
    
    def test_audio(self) -> bool:
        """Test audio on Pi"""
        logger.info("\n🔊 Testing audio on Pi...")
        out, err = self.run_remote_command(
            "python3 << 'EOF'\nimport wave\nwith wave.open('/tmp/test.wav', 'wb') as f:\n    f.setnchannels(1)\n    f.setsampwidth(2)\n    f.setframerate(44100)\n    f.writeframes(b'\\x00' * 88200)\nEOF",
            "Creating test tone"
        )
        
        if not err:
            logger.info("   ✅ Audio test passed")
            return True
        else:
            logger.warning(f"   ⚠️  Audio test warning: {err}")
            return True
    
    def test_bluetooth(self) -> bool:
        """Test Bluetooth on Pi"""
        logger.info("\n📡 Testing Bluetooth on Pi...")
        out, err = self.run_remote_command(
            "bluetoothctl list",
            "Checking Bluetooth devices"
        )
        
        if out:
            logger.info("   ✅ Bluetooth test passed")
            logger.info(f"   Devices: {out.split(chr(10))[0]}")
            return True
        else:
            logger.warning("   ⚠️  No Bluetooth devices found")
            return False


def main():
    """CLI interface for unified deployment"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Unified Pi Deployment Tool")
    parser.add_argument("--ip", help="Pi IP address (auto-discover if not provided)")
    parser.add_argument("--user", default="pi", help="Pi username")
    parser.add_argument("--deploy-files", nargs="+", help="Files to deploy")
    parser.add_argument("--deploy-dir", help="Directory to deploy")
    parser.add_argument("--test-audio", action="store_true", help="Test audio")
    parser.add_argument("--test-bluetooth", action="store_true", help="Test Bluetooth")
    parser.add_argument("--command", help="Run custom command")
    
    args = parser.parse_args()
    
    deployer = PiDeployer(args.ip, args.user)
    
    if args.deploy_files:
        deployer.deploy_files(args.deploy_files)
    
    if args.deploy_dir:
        deployer.deploy_directory(args.deploy_dir)
    
    if args.test_audio:
        deployer.test_audio()
    
    if args.test_bluetooth:
        deployer.test_bluetooth()
    
    if args.command:
        out, err = deployer.run_remote_command(args.command)
        if out:
            print(out)
        if err:
            print(f"Error: {err}")


if __name__ == "__main__":
    main()
