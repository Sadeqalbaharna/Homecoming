#!/bin/bash

# Bluetooth Audio Setup for Raspberry Pi
# This script sets up Bluetooth audio output for the Homecoming Pi

echo "🔵 Setting up Bluetooth Audio for Homecoming Pi..."

# Update system packages
echo "📦 Updating system packages..."
sudo apt update
sudo apt upgrade -y

# Install Bluetooth and audio packages
echo "🎵 Installing Bluetooth and audio packages..."
sudo apt install -y \
    bluetooth \
    bluez \
    bluez-tools \
    pulseaudio \
    pulseaudio-module-bluetooth \
    pavucontrol \
    alsa-utils \
    sox \
    mpg123 \
    espeak-ng \
    festival \
    flac

# Enable Bluetooth service
echo "🔧 Enabling Bluetooth service..."
sudo systemctl enable bluetooth
sudo systemctl start bluetooth

# Add pi user to bluetooth group
echo "👤 Adding user to bluetooth group..."
sudo usermod -a -G bluetooth pi

# Configure PulseAudio for Bluetooth
echo "🔊 Configuring PulseAudio..."
cat > ~/.config/pulse/default.pa << 'EOF'
#!/usr/bin/pulseaudio -nF

# Load Bluetooth modules
load-module module-bluetooth-policy
load-module module-bluetooth-discover

# Load other essential modules
load-module module-native-protocol-unix auth-anonymous=1 socket=/tmp/pulse-socket
load-module module-alsa-sink
load-module module-alsa-source device=hw:1,0
load-module module-null-sink sink_name=rtp
EOF

# Configure Bluetooth for A2DP
echo "📡 Configuring Bluetooth A2DP..."
sudo bash -c 'cat > /etc/bluetooth/main.conf << EOF
[General]
Class = 0x41C
DiscoverableTimeout = 0
Discoverable = yes
PairableTimeout = 0
Pairable = yes
AutoConnectTimeout = 60
Name = Homecoming-Pi
DeviceID = bluetooth:1234:1234:abcd

[Policy]
AutoConnect = true
ReconnectAttempts = 7
ReconnectIntervals = 1,2,4,8,16,32,64
EOF'

# Create Bluetooth audio service
echo "🤖 Creating Bluetooth audio service..."
sudo bash -c 'cat > /etc/systemd/system/bluetooth-audio.service << EOF
[Unit]
Description=Homecoming Bluetooth Audio Service
After=bluetooth.service pulseaudio.service
Requires=bluetooth.service

[Service]
Type=simple
User=pi
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/python3 /home/pi/homecoming_pi/bluetooth_audio_manager.py
Restart=always
RestartSec=10
Environment=DISPLAY=:0

[Install]
WantedBy=multi-user.target
EOF'

# Make Bluetooth discoverable on boot
echo "🔍 Setting up auto-discoverable..."
sudo bash -c 'cat > /etc/systemd/system/bluetooth-discoverable.service << EOF
[Unit]
Description=Make Bluetooth Discoverable
After=bluetooth.service
Requires=bluetooth.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 10
ExecStart=/bin/bash -c "bluetoothctl discoverable on && bluetoothctl pairable on"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF'

# Enable services
sudo systemctl enable bluetooth-audio.service
sudo systemctl enable bluetooth-discoverable.service

echo "✅ Bluetooth Audio setup complete!"
echo ""
echo "📱 Next steps:"
echo "1. Run: sudo reboot"
echo "2. Pair your phone/device to 'Homecoming-Pi'"
echo "3. Test audio with: python3 test_bluetooth_audio.py"
echo ""
echo "🎵 Your Pi can now output audio via Bluetooth!"