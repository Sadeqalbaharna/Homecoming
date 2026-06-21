#!/usr/bin/env python3
"""Upload updated listener to Pi via SFTP"""
import os
import sys

try:
    import paramiko
except ImportError:
    print("Installing paramiko...")
    os.system("pip install paramiko")
    import paramiko

def upload_file_sftp(local_path, remote_path, hostname, username, port=22):
    """Upload file to Pi via SFTP"""
    try:
        # Create SSH client
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        
        # Connect
        print(f"Connecting to {username}@{hostname}...")
        ssh.connect(hostname, port=port, username=username)
        
        # Open SFTP session
        sftp = ssh.open_sftp()
        
        # Upload file
        print(f"Uploading {local_path} -> {remote_path}...")
        sftp.put(local_path, remote_path)
        
        # Close
        sftp.close()
        ssh.close()
        
        print(f"✅ Upload successful!")
        return True
        
    except Exception as e:
        print(f"❌ Upload failed: {e}")
        return False

if __name__ == "__main__":
    local_file = r"c:\code\homecoming_app\firebase_rest_listener_debug.py"
    remote_file = "/home/pi/firebase_rest_listener_debug.py"
    pi_ip = "192.168.2.5"
    pi_user = "pi"
    
    if os.path.exists(local_file):
        upload_file_sftp(local_file, remote_file, pi_ip, pi_user)
    else:
        print(f"❌ Local file not found: {local_file}")
