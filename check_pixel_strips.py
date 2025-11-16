#!/usr/bin/env python3
"""Check what pixel_strips contains on the Pi"""

# Simulate the WS281X controller initialization
try:
    from rpi_ws281x import PixelStrip
    WS281X_AVAILABLE = True
    print("✅ rpi_ws281x library available")
except ImportError:
    WS281X_AVAILABLE = False
    print("⚠️ rpi_ws281x library NOT available")

# This mimics what WS281XController does
pixel_strips = {}
strip_configs = {
    'main': {'pin': 18, 'count': 60},
    'ambient': {'pin': 13, 'count': 60},
    'accent': {'pin': 19, 'count': 30},
    'zone1': {'pin': 21, 'count': 40},
    'zone2': {'pin': 12, 'count': 40},
    'zone3': {'pin': 16, 'count': 40}
}

for name, config in strip_configs.items():
    if WS281X_AVAILABLE:
        try:
            strip = PixelStrip(config['count'], config['pin'])
            pixel_strips[name] = strip
            print(f"💡 Created PixelStrip for {name}")
        except Exception as e:
            print(f"⚠️ Failed to create PixelStrip for {name}, using sudo mode: {e}")
            pixel_strips[name] = "sudo_mode"
    else:
        pixel_strips[name] = "sudo_mode"
        print(f"💡 Enabling sudo LED control for {name}")

print("\n📊 pixel_strips summary:")
print(f"  Type: {type(pixel_strips)}")
print(f"  Length: {len(pixel_strips)}")

for name, val in pixel_strips.items():
    print(f"  {name}: {type(val).__name__} = {val if isinstance(val, str) else 'PixelStrip object'}")

# Check all_sudo logic
all_sudo = all(strip == "sudo_mode" for strip in pixel_strips.values())
print(f"\n🔍 all_sudo check result: {all_sudo}")
