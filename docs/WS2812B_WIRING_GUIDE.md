# 🔌 WS2812B Multiple Strip Wiring Guide for Homecoming Pi

## Hardware Setup for 3 LED Strips

### Strip Configuration (From firebase_rest_listener_debug.py)
```
Main Strip:    150 LEDs → GPIO 18 (Pin 12)
Accent Strip:   60 LEDs → GPIO 13 (Pin 33)  
Ambient Strip:  30 LEDs → GPIO 12 (Pin 32)
```

### Complete Wiring Diagram
```
                    ┌─────────────────────────────────┐
                    │      Raspberry Pi 4 GPIO        │
                    │  ┌─────────────────────────────┐ │
                    │  │ 5V  5V GND    GPIO12 GPIO13│ │  
                    │  │ 2   4   6        32    33  │ │
                    │  │ •   •   •         •     •  │ │
                    │  └─────────────────────────────┘ │
                    │            │         │     │    │
                    │            │    GPIO18 (Pin 12) │
                    │            │         │     │    │
                    └────────────┼─────────┼─────┼────┘
                                 │         │     │
                    Power Bus ───┘         │     │
                    ┌───────────────────────┘     │
                    │                             │
                    │                             │
              ┌─────▼─────┐              ┌──────▼──────┐
              │Main Strip │              │Accent Strip │
              │150 LEDs   │              │60 LEDs      │
              │5V GND DIN │              │5V GND DIN   │
              └───────────┘              └─────────────┘
                                                │
                                      ┌─────────▼─────────┐
                                      │  Ambient Strip    │
                                      │  30 LEDs          │
                                      │  5V GND DIN       │
                                      └───────────────────┘
```

## Power Requirements & Safety

### Current Draw Calculations
```
Main Strip (150 LEDs):    150 × 60mA = 9.0A max
Accent Strip (60 LEDs):    60 × 60mA = 3.6A max  
Ambient Strip (30 LEDs):   30 × 60mA = 1.8A max
Total Maximum Draw:                   14.4A
```

⚠️ **CRITICAL:** Pi GPIO cannot supply this current!

### Recommended Power Setup
```
┌─────────────────┐    ┌─────────────────┐
│  5V 20A Power   │    │  Raspberry Pi   │
│  Supply         │    │  (Control Only) │
│                 │    │                 │
│ +5V ────────────┼────┤ GPIO Pins       │
│ GND ────────────┼────┤ GND Pins        │
│                 │    │                 │
│ LED Power Bus   │    │ Signal Only     │
│ (High Current)  │    │ (Low Current)   │
└─────────────────┘    └─────────────────┘
```

## Step-by-Step Connection Process

### Step 1: Power Distribution
1. Use thick wires (14-16 AWG) for 5V power bus
2. Connect external 5V supply to power bus
3. Connect Pi GND to power supply GND
4. **DO NOT** connect Pi 5V to high-current supply

### Step 2: Signal Connections  
```bash
# Use jumper wires or ribbon cable
Main Strip DIN    → Pi GPIO 18 (Pin 12)
Accent Strip DIN  → Pi GPIO 13 (Pin 33)  
Ambient Strip DIN → Pi GPIO 12 (Pin 32)
```

### Step 3: Ground Connections
```bash
# Critical: Common ground for all strips
All Strip GND → Power Supply GND → Pi GND
```

## Testing Your Setup

### 1. Install Required Libraries
```bash
sudo pip3 install rpi_ws281x adafruit-circuitpython-neopixel
```

### 2. Test Individual Strips
Your firebase_rest_listener_debug.py already includes test functions:
```python
# Test main strip
controller.set_strip_color("main", (255, 0, 0))  # Red

# Test accent strip  
controller.set_strip_color("accent", (0, 255, 0))  # Green

# Test ambient strip
controller.set_strip_color("ambient", (0, 0, 255))  # Blue
```

### 3. Voice Command Testing
Use Homecoming app voice commands:
- "Set main lights to red"
- "Make accent lights blue" 
- "Turn on ambient lighting"

## Troubleshooting

### Common Issues & Solutions

1. **LEDs don't light up**
   - Check power supply capacity (need 20A+ for full brightness)
   - Verify common ground connections
   - Test with lower LED count first

2. **Flickering or wrong colors**
   - Add 330Ω resistors between Pi GPIO and DIN pins
   - Add 1000µF capacitor across power supply
   - Reduce brightness in code

3. **Only first few LEDs work**
   - Insufficient power supply current
   - Bad data connection to subsequent LEDs
   - Wrong LED count in configuration

### Hardware Checklist
```
□ External 5V power supply (20A+ capacity)
□ Thick power wires (14-16 AWG)  
□ Common ground connections
□ Signal resistors (330Ω recommended)
□ Power supply capacitor (1000µF+)
□ Proper GPIO pin assignments
□ Secure connections (no loose wires)
```

## Your Current Code Features

Your firebase_rest_listener_debug.py supports:
- ✅ 3 independent strip control
- ✅ Different brightness levels per strip
- ✅ Synchronized effects across strips
- ✅ Voice command integration
- ✅ Scene-based lighting coordination
- ✅ Music-reactive lighting modes

The hardware setup will unlock the full potential of your Homecoming Kai consciousness system! 🏡✨