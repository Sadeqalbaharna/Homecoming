#!/usr/bin/env python3
"""
kai_station.py — Homecoming Station daemon
Watches Firebase RTDB for device commands and controls GPIO.

Setup:
  pip install firebase-admin RPi.GPIO
  Place serviceAccountKey.json in the same directory.

Run:
  python3 kai_station.py

Auto-start on boot: handled by kai-station.service (see scripts/pi/kai-station.service),
not rc.local — that unit runs this from /home/kai/tavern_station.

Firebase DB structure:
  /devices/
    led/
      state:        "on" | "off"      ← Kai writes here
      status:       "on" | "off"      ← Pi confirms here
      last_command: ISO timestamp
"""

import firebase_admin
from firebase_admin import credentials, db
import time
import sys
import signal

# ── Config ───────────────────────────────────────────────────────────────────

FIREBASE_URL   = 'https://kingdom-ac44f-default-rtdb.europe-west1.firebasedatabase.app'
SERVICE_ACCOUNT = 'serviceAccountKey.json'

# GPIO pin assignments (BCM numbering)
DEVICES = {
    'led':    17,   # GPIO 17 — change to match your wiring
    # 'fan':  27,   # add more devices here
    # 'relay1': 22,
}

# ── GPIO setup ───────────────────────────────────────────────────────────────

try:
    import RPi.GPIO as GPIO
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    for pin in DEVICES.values():
        GPIO.setup(pin, GPIO.OUT, initial=GPIO.LOW)
    print(f'✅ GPIO ready — devices: {list(DEVICES.keys())}')
except ImportError:
    # Running on a non-Pi machine for testing
    print('⚠️  RPi.GPIO not available — running in simulation mode')
    class GPIO:
        BCM = HIGH = 1
        LOW = 0
        @staticmethod
        def setmode(_): pass
        @staticmethod
        def setwarnings(_): pass
        @staticmethod
        def setup(pin, *a, **kw): pass
        @staticmethod
        def output(pin, state):
            print(f'  [SIM] GPIO {pin} → {"HIGH" if state else "LOW"}')
        @staticmethod
        def cleanup(): pass

# ── Firebase ─────────────────────────────────────────────────────────────────

cred = credentials.Certificate(SERVICE_ACCOUNT)
firebase_admin.initialize_app(cred, {'databaseURL': FIREBASE_URL})
print(f'✅ Firebase connected: {FIREBASE_URL}')

# ── Device control ────────────────────────────────────────────────────────────

def set_device(device: str, state: str):
    """Apply state to GPIO and report status back to Firebase."""
    pin = DEVICES.get(device)
    if pin is None:
        print(f'❓ Unknown device: {device}')
        return

    gpio_state = GPIO.HIGH if state == 'on' else GPIO.LOW
    GPIO.output(pin, gpio_state)
    print(f'💡 [{device.upper()}] → {state.upper()}')

    # Report confirmed status back so Kai can read it
    db.reference(f'devices/{device}/status').set(state)


def make_listener(device: str):
    """Return a Firebase listener callback for a specific device."""
    def on_change(event):
        # event.data is None on initial connect or delete; skip
        if not isinstance(event.data, str):
            return
        state = event.data.strip().lower()
        if state not in ('on', 'off'):
            print(f'⚠️  [{device}] Unexpected state value: {repr(state)}')
            return
        set_device(device, state)
    return on_change


# ── Start listeners ───────────────────────────────────────────────────────────

listeners = []
for device in DEVICES:
    ref = db.reference(f'devices/{device}/state')
    listener = ref.listen(make_listener(device))
    listeners.append(listener)
    print(f'👂 Listening: devices/{device}/state')

print('\n🏠 Kai Station running. Press Ctrl+C to stop.\n')

# ── Graceful shutdown ─────────────────────────────────────────────────────────

def shutdown(sig, frame):
    print('\n🛑 Shutting down...')
    for l in listeners:
        l.close()
    GPIO.cleanup()
    sys.exit(0)

signal.signal(signal.SIGINT,  shutdown)
signal.signal(signal.SIGTERM, shutdown)

# Keep the main thread alive
while True:
    time.sleep(60)
