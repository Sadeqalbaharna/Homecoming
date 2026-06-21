#!/usr/bin/env python3
"""
Diagnose Bluetooth hardware issue on Pi
"""

import paramiko
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

PI_IP = "192.168.48.5"
PI_USER = "pi"

def diagnose():
    """Diagnose Bluetooth hardware"""
    try:
        logger.info("")
        logger.info("=" * 70)
        logger.info("BLUETOOTH HARDWARE DIAGNOSIS".center(70))
        logger.info("=" * 70)
        logger.info("")
        
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            PI_IP,
            username=PI_USER,
            key_filename=str(Path.home() / ".ssh" / "id_rsa"),
            timeout=10
        )
        
        # Check 1: HCI adapter status
        logger.info("CHECK 1: HCI Adapter Status")
        logger.info("-" * 70)
        stdin, stdout, stderr = client.exec_command("hciconfig")
        logger.info(stdout.read().decode())
        
        # Check 2: Bluetooth service status
        logger.info("\nCHECK 2: Bluetooth Service Status")
        logger.info("-" * 70)
        stdin, stdout, stderr = client.exec_command("sudo systemctl status bluetooth -q")
        status_out = stdout.read().decode()
        logger.info(status_out)
        
        # Check 3: Check if adapter is blocked
        logger.info("\nCHECK 3: Bluetooth Device Blocks")
        logger.info("-" * 70)
        stdin, stdout, stderr = client.exec_command("rfkill list")
        logger.info(stdout.read().decode())
        
        # Check 4: Check Bluetooth kernel driver
        logger.info("\nCHECK 4: Bluetooth Kernel Modules")
        logger.info("-" * 70)
        stdin, stdout, stderr = client.exec_command("lsmod | grep -i bluetooth")
        logger.info(stdout.read().decode())
        
        # Check 5: Check device tree
        logger.info("\nCHECK 5: Bluetooth Hardware Detection")
        logger.info("-" * 70)
        stdin, stdout, stderr = client.exec_command("cat /proc/device-tree/model 2>/dev/null")
        logger.info(stdout.read().decode())
        
        # Check 6: USB devices (if using USB Bluetooth)
        logger.info("\nCHECK 6: USB Bluetooth Adapters")
        logger.info("-" * 70)
        stdin, stdout, stderr = client.exec_command("lsusb | grep -i bluetooth")
        usb_out = stdout.read().decode()
        if usb_out.strip():
            logger.info(usb_out)
        else:
            logger.info("(No USB Bluetooth adapters found - using built-in adapter)")
        
        # Check 7: BlueZ version
        logger.info("\nCHECK 7: BlueZ Version")
        logger.info("-" * 70)
        stdin, stdout, stderr = client.exec_command("bluetoothd -v 2>/dev/null || echo 'Not available'")
        logger.info(stdout.read().decode())
        
        # Check 8: Last kernel messages
        logger.info("\nCHECK 8: Kernel Messages (last 10 Bluetooth-related)")
        logger.info("-" * 70)
        stdin, stdout, stderr = client.exec_command("dmesg | grep -i bluetooth | tail -10")
        kern_out = stdout.read().decode()
        if kern_out.strip():
            logger.info(kern_out)
        else:
            logger.info("(No Bluetooth messages in kernel log)")
        
        logger.info("")
        logger.info("=" * 70)
        logger.info("DIAGNOSIS COMPLETE".center(70))
        logger.info("=" * 70)
        logger.info("")
        logger.info("POSSIBLE SOLUTIONS:")
        logger.info("")
        logger.info("1. If adapter shows 'DOWN':")
        logger.info("   sudo hciconfig hci0 up")
        logger.info("")
        logger.info("2. If adapter is BLOCKED by rfkill:")
        logger.info("   sudo rfkill unblock bluetooth")
        logger.info("   sudo rfkill unblock all")
        logger.info("")
        logger.info("3. If modules not loaded:")
        logger.info("   sudo modprobe bluetooth")
        logger.info("   sudo modprobe btusb")
        logger.info("")
        logger.info("4. If it's a power issue:")
        logger.info("   sudo rpi-eeprom-update  # Check Pi firmware")
        logger.info("")
        logger.info("After fixing, test:")
        logger.info("   bluetoothctl scan on")
        logger.info("   bluetoothctl connect 39:3E:58:14:40:4A")
        logger.info("")
        
        client.close()
        
    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    diagnose()
