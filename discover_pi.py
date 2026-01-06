#!/usr/bin/env python3
"""
Network Discovery Tool - Find Raspberry Pi
Scans the network to discover the Pi's current IP address
"""

import subprocess
import socket
import sys
from ipaddress import ip_network

def discover_pi():
    """Scan network for Raspberry Pi"""
    print("=" * 80)
    print("RASPBERRY PI NETWORK DISCOVERY")
    print("=" * 80)
    
    # Get local network info
    print("\n1. Getting local network info...")
    try:
        # Get hostname and IP
        hostname = socket.gethostname()
        local_ip = socket.gethostbyname(hostname)
        print(f"   Local hostname: {hostname}")
        print(f"   Local IP: {local_ip}")
        
        # Get network range (assume /24 subnet)
        network_prefix = '.'.join(local_ip.split('.')[:3])
        print(f"   Scanning network: {network_prefix}.0/24")
    except Exception as e:
        print(f"   ❌ Error getting local info: {e}")
        return
    
    # Try common Pi hostnames
    print("\n2. Trying common hostnames...")
    hostnames = [
        'raspberrypi',
        'raspberrypi.local',
        'pi',
        'pi.local',
        'raspberry',
    ]
    
    for hostname in hostnames:
        try:
            ip = socket.gethostbyname(hostname)
            print(f"   ✅ {hostname} → {ip}")
            return ip
        except:
            pass
    
    # Scan network range
    print("\n3. Scanning network for Pi (this may take a minute)...")
    print(f"   Testing {network_prefix}.1-254...")
    
    found_ips = []
    
    # Fast scan using ping
    for i in range(1, 255):
        ip = f"{network_prefix}.{i}"
        try:
            # Use ping with timeout
            result = subprocess.run(
                ['ping', '-n', '1', '-w', '100', ip],
                capture_output=True,
                timeout=2
            )
            if result.returncode == 0:
                found_ips.append(ip)
                print(f"   ✅ {ip} is online")
        except:
            pass
    
    if found_ips:
        print(f"\n4. Found {len(found_ips)} online device(s):")
        for ip in found_ips:
            print(f"   - {ip}")
            
            # Try to identify which is Pi
            try:
                hostname = socket.gethostbyaddr(ip)[0]
                print(f"     Hostname: {hostname}")
                if 'rasp' in hostname.lower() or 'pi' in hostname.lower():
                    print(f"     🎯 This looks like the Raspberry Pi!")
            except:
                pass
    else:
        print("\n   ⚠️  No online devices found in range")
    
    return found_ips

if __name__ == "__main__":
    print("Starting Pi discovery...\n")
    ips = discover_pi()
    
    if ips:
        print("\n" + "=" * 80)
        print("✅ DISCOVERY COMPLETE")
        print("=" * 80)
        print(f"\nFound {len(ips)} device(s). Try connecting with:")
        for ip in ips:
            print(f"  ssh pi@{ip}")
    else:
        print("\n" + "=" * 80)
        print("❌ NO DEVICES FOUND")
        print("=" * 80)
        print("\nTroubleshooting:")
        print("1. Check that Pi is powered on")
        print("2. Check that Pi is connected to the network")
        print("3. Check your network connectivity")
        print("4. Try the IP addresses shown in your router's device list")
