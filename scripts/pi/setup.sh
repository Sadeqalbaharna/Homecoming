#!/usr/bin/env bash
# setup.sh — deploys the Kai NFC station onto a fresh Raspberry Pi.
#
# Run this FROM the extracted bundle directory (the one containing
# nfc_listener.py, kai_screen.py, kai_station.py, requirements.txt, frames/,
# and the three *.service files) — e.g.:
#
#   scp -r kai_station_bundle/ kai@<pi-ip>:~/
#   ssh kai@<pi-ip>
#   cd ~/kai_station_bundle && chmod +x setup.sh && ./setup.sh
#
# What it does: lays out /home/kai/tavern_station, installs system + pip
# deps, installs and enables the three systemd services. It does NOT start
# them for you at the end — see the printed next steps.

set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATION_DIR="/home/kai/tavern_station"

echo "==> Laying out $STATION_DIR"
mkdir -p "$STATION_DIR"
cp "$BUNDLE_DIR"/nfc_listener.py "$STATION_DIR"/
cp "$BUNDLE_DIR"/kai_screen.py   "$STATION_DIR"/
cp "$BUNDLE_DIR"/kai_station.py  "$STATION_DIR"/
cp -r "$BUNDLE_DIR"/frames       "$STATION_DIR"/media/frames 2>/dev/null || {
  mkdir -p "$STATION_DIR/media"
  cp -r "$BUNDLE_DIR"/frames "$STATION_DIR"/media/frames
}

if [ ! -f "$STATION_DIR/serviceAccountKey.json" ]; then
  echo "⚠️  $STATION_DIR/serviceAccountKey.json not found."
  echo "    Copy your Firebase service account key there before starting the"
  echo "    services — nfc_listener.py and kai_station.py both need it."
fi

echo "==> Installing system packages (apt)"
sudo apt-get update -qq
sudo apt-get install -y python3-pip portaudio19-dev mpg123 espeak pcscd libpcsclite-dev

echo "==> Installing Python packages (pip)"
python3 -m pip install --break-system-packages -r "$BUNDLE_DIR"/requirements.txt

echo "==> Installing systemd services"
sudo cp "$BUNDLE_DIR"/tavern.service      /etc/systemd/system/
sudo cp "$BUNDLE_DIR"/kai-screen.service  /etc/systemd/system/
sudo cp "$BUNDLE_DIR"/kai-station.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable tavern.service kai-screen.service kai-station.service

echo ""
echo "✅ Station laid out at $STATION_DIR, services enabled (not started)."
echo ""
echo "Before starting, edit these on the Pi:"
echo "  1. $STATION_DIR/serviceAccountKey.json      — Firebase admin key (place it, don't create it here)"
echo "  2. /etc/systemd/system/tavern.service        — set TABLE_ID / TABLE_NAME / ELEVENLABS_KEY / KAI_VOICE_ID / OPENAI_KEY"
echo "  3. /etc/systemd/system/kai-screen.service     — uncomment KAI_FB_DEVICE / KAI_FB_PIXFMT once the DSI screen is confirmed working"
echo ""
echo "Then: sudo systemctl daemon-reload && sudo systemctl start tavern kai-screen kai-station"
echo "Logs: journalctl -u tavern -f   (or kai-screen / kai-station, or tail the *.log files in $STATION_DIR)"
