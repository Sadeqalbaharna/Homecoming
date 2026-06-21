#!/usr/bin/env python3
"""
Deploy scene test files to Pi via SSH using paramiko
"""

import sys
import paramiko
from pathlib import Path

PI_IP = "192.168.48.5"
PI_USER = "pi"
PI_PASS = "raspberry"

FILES_TO_DEPLOY = [
    "test_bluetooth_tg129c.py",
    "test_modular_scene_playback.py",
    "demo_modular_scenes.py",
    "verify_setup.py",
]

# Also need to deploy the fixtures_v2 modular system
DIRS_TO_DEPLOY = [
    "fixtures_v2",
]

def deploy_files(pi_ip=PI_IP, username=PI_USER):
    """Deploy test files to Pi via SSH/SFTP"""
    
    print("\n" + "="*70)
    print("📤 DEPLOYING SCENE TEST FILES TO PI")
    print("="*70 + "\n")
    
    # Check files exist
    missing = [f for f in FILES_TO_DEPLOY if not Path(f).exists()]
    if missing:
        print(f"❌ Missing files: {missing}")
        return False
    
    print("✅ All files found locally\n")
    
    try:
        # Create SSH/SFTP connection
        print(f"🔌 Connecting to {username}@{pi_ip}...")
        transport = paramiko.Transport((pi_ip, 22))
        
        # Try key-based auth first (SSH noticed "publickey" was used)
        try:
            key_path = Path.home() / ".ssh" / "id_rsa"
            if key_path.exists():
                key = paramiko.RSAKey.from_private_key_file(str(key_path))
                transport.connect(username=username, pkey=key)
                auth_method = "SSH key"
            else:
                # Fallback to password
                transport.connect(username=username, password=PI_PASS)
                auth_method = "password"
        except paramiko.ssh_exception.AuthenticationException:
            # Try empty password as last resort
            transport.connect(username=username, password="")
            auth_method = "empty password"
        
        sftp = paramiko.SFTPClient.from_transport(transport)
        
        print(f"✅ Connected via SFTP ({auth_method})\n")
        
        # Upload files
        print("📤 Uploading files...\n")
        for filename in FILES_TO_DEPLOY:
            local_path = Path(filename)
            remote_path = f"/home/{username}/{filename}"
            
            print(f"   → {filename}", end=" ")
            sftp.put(str(local_path), remote_path)
            print("✅")
        
        # Upload directories
        if DIRS_TO_DEPLOY:
            print("\n📂 Uploading directories...\n")
            
            def upload_dir(sftp, local_dir, remote_dir):
                """Recursively upload directory"""
                for item in Path(local_dir).rglob('*'):
                    # Skip __pycache__ and other non-essential dirs
                    if '__pycache__' in str(item) or item.name.startswith('.'):
                        continue
                    
                    if item.is_file():
                        rel_path = item.relative_to(local_dir)
                        remote_file = f"{remote_dir}/{rel_path}".replace("\\", "/")
                        remote_parent = remote_file.rsplit('/', 1)[0]
                        
                        # Create remote directory if needed
                        try:
                            sftp.stat(remote_parent)
                        except:
                            sftp.mkdir(remote_parent)
                        
                        sftp.put(str(item), remote_file)
                        print(f"   → {rel_path}")
            
            for dir_name in DIRS_TO_DEPLOY:
                print(f"   Uploading {dir_name}/...")
                upload_dir(sftp, dir_name, f"/home/{username}/{dir_name}")
        
        print("\n" + "="*70)
        print("✅ DEPLOYMENT COMPLETE!")
        print("="*70 + "\n")
        
        print("🧪 Next: Run a scene test")
        print("   python ssh_scene_activator.py haunted_mansion\n")
        
        sftp.close()
        transport.close()
        return True
        
    except paramiko.ssh_exception.AuthenticationException:
        print(f"❌ Authentication failed")
        return False
    except Exception as e:
        print(f"❌ Error: {e}")
        return False

if __name__ == "__main__":
    success = deploy_files()
    sys.exit(0 if success else 1)
