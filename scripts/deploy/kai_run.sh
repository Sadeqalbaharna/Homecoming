#!/bin/bash
# Kill any process using GPIO
sudo pkill -f "python.*led"
sudo pkill -f "python.*gpio"
sleep 1

# Run the main script with proper GPIO access
sudo python3 /home/pi/kai_reliable_wake.py
