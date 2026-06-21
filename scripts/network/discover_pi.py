#!/usr/bin/env python3
"""
Automatic Raspberry Pi Discovery
Scans network to find Pi's IP without manual entry
"""

import subprocess
import socket
import sys
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

COMMON_HOSTNAMES = [
    "raspberrypi",
    "raspberrypi.local",
    "homecoming",
    "homecoming.local",
    "kai",
    "kai.local",
]

FALLBACK_IPS = [
    "192.168.48.5",  # Known from previous use
    "192.168.1.100",
    "192.168.1.200",
    "192.168.0.100",
    "10.0.0.100",
]

def test_ssh_connection(ip, port=22, timeout=2):
    """Test if SSH is available"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((ip, port))
        sock.close()
        return result == 0
    except:
        return False

def discover_by_hostname():
    """Try resolving common Pi hostnames"""
    logger.info("[1/4] Trying common hostnames...")
    
    for hostname in COMMON_HOSTNAMES:
        try:
            ip = socket.gethostbyname(hostname)
            if test_ssh_connection(ip):
                logger.info(f"      ✅ Found: {hostname} → {ip}")
                return ip
        except:
            pass
    
    logger.info("      ❌ No hostnames resolved")
    return None

def discover_by_arp():
    """Use arp-scan if available"""
    logger.info("[2/4] Scanning with arp-scan...")
    
    try:
        result = subprocess.run(
            "arp-scan -l 2>/dev/null | grep -i 'broadcom\\|raspberry'",
            shell=True,
            capture_output=True,
            text=True,
            timeout=15
        )
        
        if result.stdout:
            for line in result.stdout.strip().split('\n'):
                parts = line.split()
                if parts and test_ssh_connection(parts[0]):
                    logger.info(f"      ✅ Found: {parts[0]}")
                    return parts[0]
    except:
        pass
    
    logger.info("      ❌ arp-scan not available or no Pi found")
    return None

def discover_by_nmap():
    """Use nmap to scan for SSH"""
    logger.info("[3/4] Scanning with nmap...")
    
    try:
        result = subprocess.run(
            "nmap -p 22 --open -oG - 2>/dev/null | grep 'Host:' | awk '{print $2}'",
            shell=True,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.stdout:
            for ip in result.stdout.strip().split('\n'):
                if ip and test_ssh_connection(ip):
                    logger.info(f"      ✅ Found: {ip}")
                    return ip
    except:
        pass
    
    logger.info("      ❌ nmap not available or no Pi found")
    return None

def discover_by_ping_sweep():
    """Ping common IPs in parallel"""
    logger.info("[4/4] Testing known IP addresses...")
    
    def test_ip(ip):
        if test_ssh_connection(ip):
            return ip
        return None
    
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = {executor.submit(test_ip, ip): ip for ip in FALLBACK_IPS}
        
        for future in as_completed(futures):
            result = future.result()
            if result:
                logger.info(f"      ✅ Found: {result}")
                return result
    
    logger.info("      ❌ No IP addresses responded")
    return None

def discover_pi():
    """Run full discovery sequence"""
    logger.info("\n" + "="*70)
    logger.info("AUTO-DISCOVERING RASPBERRY PI".center(70))
    logger.info("="*70)
    
    methods = [
        discover_by_hostname,
        discover_by_arp,
        discover_by_nmap,
        discover_by_ping_sweep,
    ]
    
    for method in methods:
        try:
            ip = method()
            if ip:
                logger.info("\n" + "="*70)
                logger.info(f"✅ FOUND: Pi at {ip}".center(70))
                logger.info("="*70 + "\n")
                return ip
        except Exception as e:
            logger.debug(f"Method failed: {e}")
    
    logger.error("\n" + "="*70)
    logger.error("❌ DISCOVERY FAILED".center(70))
    logger.error("="*70)
    logger.error("\nCould not find Raspberry Pi on network")
    logger.error("Options:")
    logger.error("  1. Ensure Pi is powered on and connected to WiFi")
    logger.error("  2. Check your network connection")
    logger.error("  3. Use 'ssh pi@<YOUR_PI_IP>' to find it manually")
    logger.error("  4. Update FALLBACK_IPS with your Pi's known IP\n")
    
    return None

if __name__ == "__main__":
    ip = discover_pi()
    if ip:
        print(ip)  # Print for scripting
        sys.exit(0)
    sys.exit(1)
