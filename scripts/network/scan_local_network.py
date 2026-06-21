#!/usr/bin/env python3
"""
Local Network Scanner - Finds Raspberry Pi on shared network
Scans all devices on your local network and identifies which is the Pi
"""

import subprocess
import socket
import ipaddress
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def get_local_network():
    """Get local network range from your machine"""
    try:
        # Get hostname and local IP
        hostname = socket.gethostname()
        local_ip = socket.gethostbyname(hostname)
        
        logger.info(f"Your IP: {local_ip}")
        
        # Extract network (assume /24 subnet)
        parts = local_ip.split('.')
        network = f"{parts[0]}.{parts[1]}.{parts[2]}.0/24"
        
        logger.info(f"Scanning network: {network}\n")
        return network
    except Exception as e:
        logger.error(f"Error getting network info: {e}")
        return None

def ping_host(ip):
    """Ping a single host"""
    try:
        result = subprocess.run(
            f"ping -n 1 -w 500 {ip}",
            shell=True,
            capture_output=True,
            timeout=2
        )
        if result.returncode == 0:
            return ip
    except:
        pass
    return None

def check_ssh(ip):
    """Check if SSH is available on host"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)
        result = sock.connect_ex((ip, 22))
        sock.close()
        return result == 0
    except:
        return False

def identify_pi(ip):
    """Try to identify if this is a Raspberry Pi"""
    try:
        # Try reverse DNS lookup
        try:
            hostname = socket.gethostbyaddr(ip)[0]
            if 'rasp' in hostname.lower() or 'pi' in hostname.lower() or 'homecoming' in hostname.lower():
                return hostname
        except:
            pass
        
        # Check if SSH is open (Pi usually has SSH)
        if check_ssh(ip):
            return "SSH_AVAILABLE"
    except:
        pass
    
    return None

def scan_network():
    """Scan entire local network"""
    logger.info("="*70)
    logger.info("LOCAL NETWORK SCANNER - FINDING RASPBERRY PI".center(70))
    logger.info("="*70 + "\n")
    
    network_range = get_local_network()
    if not network_range:
        return None
    
    # Generate all IPs in range
    try:
        network = ipaddress.ip_network(network_range, strict=False)
        ips = [str(ip) for ip in network.hosts()]
    except Exception as e:
        logger.error(f"Error parsing network: {e}")
        return None
    
    logger.info(f"Pinging {len(ips)} devices... (this takes ~30 seconds)\n")
    
    responsive_ips = []
    
    # Ping all IPs in parallel
    with ThreadPoolExecutor(max_workers=20) as executor:
        futures = {executor.submit(ping_host, ip): ip for ip in ips}
        
        completed = 0
        for future in as_completed(futures):
            completed += 1
            ip = future.result()
            if ip:
                responsive_ips.append(ip)
                logger.info(f"[{completed}/{len(ips)}] ✅ {ip} is online")
            else:
                if completed % 10 == 0:
                    logger.info(f"[{completed}/{len(ips)}] Scanning...")
    
    if not responsive_ips:
        logger.error("\n❌ No devices found on network")
        return None
    
    logger.info(f"\n" + "="*70)
    logger.info(f"Found {len(responsive_ips)} device(s)".center(70))
    logger.info("="*70 + "\n")
    
    # Check each responsive IP for SSH
    logger.info("Identifying devices...\n")
    
    pi_candidates = []
    for ip in responsive_ips:
        identification = identify_pi(ip)
        
        if identification:
            logger.info(f"🎯 {ip} - {identification}")
            pi_candidates.append((ip, identification))
        else:
            logger.info(f"   {ip} - Unknown device")
    
    if pi_candidates:
        logger.info("\n" + "="*70)
        logger.info("LIKELY RASPBERRY PI CANDIDATES:".center(70))
        logger.info("="*70 + "\n")
        
        for ip, info in pi_candidates:
            logger.info(f"  {ip}  ({info})")
        
        # Return first Pi candidate
        return pi_candidates[0][0]
    
    logger.info("\n" + "="*70)
    logger.info("ALTERNATIVE: Use SSH manually".center(70))
    logger.info("="*70 + "\n")
    
    logger.info("Try SSHing to any of these IPs:\n")
    for ip in responsive_ips:
        logger.info(f"  ssh pi@{ip}")
    
    return None

def main():
    pi_ip = scan_network()
    
    if pi_ip:
        logger.info(f"\n✅ Pi found at: {pi_ip}\n")
        return pi_ip
    else:
        logger.info("\n❌ Could not identify Pi")
        logger.info("Try connecting manually: ssh pi@<IP_ADDRESS>\n")
        return None

if __name__ == "__main__":
    pi_ip = main()
    if pi_ip:
        print(pi_ip)
