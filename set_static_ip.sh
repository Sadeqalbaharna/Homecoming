#!/bin/bash
# Remove old static IP config
sudo cp /etc/dhcpcd.conf /etc/dhcpcd.conf.bak
sudo head -n -14 /etc/dhcpcd.conf.bak | sudo tee /etc/dhcpcd.conf > /dev/null

# Add correct static IP config
cat << 'EOF' | sudo tee -a /etc/dhcpcd.conf

# Static IP Configuration for Homecoming Pi
interface eth0
static ip_address=192.168.227.100/24
static routers=192.168.227.231
static domain_name_servers=8.8.8.8 8.8.4.4

interface wlan0
static ip_address=192.168.227.100/24
static routers=192.168.227.231
static domain_name_servers=8.8.8.8 8.8.4.4
EOF

echo "✅ Static IP configured to 192.168.227.100"
echo "Rebooting in 3 seconds..."
sleep 3
sudo reboot
