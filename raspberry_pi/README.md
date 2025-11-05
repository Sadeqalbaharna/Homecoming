# 🏠 Kai Home Automation - Raspberry Pi Setup

**Control physical devices with voice commands through Kai!**

---

## 🎯 Overview

This module enables Kai to control physical devices connected to a Raspberry Pi:
- Turn on/off LED lights
- Control relays (lamps, fans, etc.)
- Read sensors (temperature, motion, etc.)
- Trigger actions based on voice commands

**Communication**: Firebase Realtime Database (no direct network connection needed)

---

## 🛠️ Raspberry Pi Setup

### Requirements

**Hardware**:
- Raspberry Pi (any model with GPIO pins)
- LEDs + resistors (220Ω recommended)
- Jumper wires
- Breadboard (optional)
- Power supply for Pi

**Software**:
- Raspberry Pi OS (Lite or Desktop)
- Python 3.7+
- Internet connection

### Initial Setup

#### 1. Flash Raspberry Pi OS

**Download**: [Raspberry Pi Imager](https://www.raspberrypi.com/software/)

1. Insert SD card
2. Open Raspberry Pi Imager
3. Choose OS: Raspberry Pi OS (64-bit recommended)
4. Choose Storage: Your SD card
5. Click Settings (⚙️):
   - Set hostname: `kai-home`
   - Enable SSH (password authentication)
   - Set username/password
   - Configure WiFi (SSID + password)
6. Write to SD card

#### 2. Boot Raspberry Pi

1. Insert SD card into Pi
2. Connect power
3. Wait ~2 minutes for first boot
4. Find Pi on network:
   ```bash
   # Windows PowerShell
   ping kai-home.local
   
   # Or scan network
   arp -a | findstr "b8-27-eb"  # Common Pi MAC prefix
   ```

#### 3. Connect via SSH

```bash
# Windows PowerShell
ssh pi@kai-home.local

# Or use IP address
ssh pi@192.168.1.XXX
```

**Default credentials** (if you didn't set custom):
- Username: `pi`
- Password: `raspberry`

#### 4. Update System

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install python3-pip python3-gpiozero git -y
```

---

## 🔌 Hardware Connections

### LED Circuit

**Simple LED Setup**:

```
Raspberry Pi GPIO Pin
    ↓
    LED (long leg = anode)
    ↓
    220Ω Resistor
    ↓
Raspberry Pi Ground Pin
```

**Pin Layout** (GPIO numbering):

| Device | GPIO Pin | Physical Pin | Ground Pin |
|--------|----------|--------------|------------|
| LED 1  | GPIO 17  | Pin 11       | Pin 6, 9, 14, 20, 25, 30, 34, 39 (any) |
| LED 2  | GPIO 27  | Pin 13       | Same ground |
| LED 3  | GPIO 22  | Pin 15       | Same ground |

**Visual Guide**:
```
    3.3V  (1) (2)  5V
   GPIO2  (3) (4)  5V
   GPIO3  (5) (6)  GND      ← Ground for LEDs
   GPIO4  (7) (8)  GPIO14
     GND  (9) (10) GPIO15
  GPIO17 (11) (12) GPIO18   ← LED 1
  GPIO27 (13) (14) GND      ← LED 2
  GPIO22 (15) (16) GPIO23   ← LED 3
```

### Testing LEDs

```bash
# Test GPIO 17 (LED 1)
python3 << EOF
from gpiozero import LED
from time import sleep

led = LED(17)
print("Blinking LED on GPIO 17...")
for i in range(5):
    led.on()
    sleep(0.5)
    led.off()
    sleep(0.5)
print("Test complete!")
EOF
```

---

## 🔥 Firebase Setup

### 1. Get Firebase Credentials

**From your Homecoming project**:

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your Homecoming project
3. Go to Project Settings ⚙️
4. Scroll to "Your apps" section
5. Click "Add app" → Web app (or use existing)
6. Copy the config object

**You'll need**:
- `apiKey`
- `databaseURL`
- `projectId`

### 2. Generate Service Account Key

1. Firebase Console → Project Settings ⚙️
2. Service Accounts tab
3. Click "Generate new private key"
4. Save JSON file securely
5. Transfer to Raspberry Pi (use `scp` or paste content)

```bash
# On your computer (PowerShell)
scp path\to\service-account.json pi@kai-home.local:~/

# Or create file on Pi
ssh pi@kai-home.local
nano ~/service-account.json
# Paste content, Ctrl+X, Y, Enter
```

---

## 📦 Install Python Dependencies

```bash
# On Raspberry Pi
pip3 install firebase-admin gpiozero python-dotenv

# Verify installation
python3 -c "import firebase_admin; print('Firebase Admin OK')"
python3 -c "from gpiozero import LED; print('GPIO OK')"
```

---

## 🚀 Install Kai Home Service

### Download Service Files

```bash
# On Raspberry Pi
mkdir -p ~/kai-home
cd ~/kai-home

# Clone just the raspberry_pi folder (or copy files manually)
# We'll create the files next
```

### Configuration

Create `.env` file:

```bash
nano ~/.env
```

Add your Firebase credentials:

```env
FIREBASE_DATABASE_URL=https://your-project.firebaseio.com
FIREBASE_SERVICE_ACCOUNT=/home/pi/service-account.json
PERSONA_ID=truekai
DEVICE_ID=raspberry_pi_home
DEVICE_NAME=Home Pi
```

---

## 🎮 Service Files

I'll create these files next - they will:
1. Listen to Firebase for commands from Kai
2. Control GPIO pins based on commands
3. Report device status back to Kai
4. Auto-start on boot

---

## 🔐 Firebase Security Rules

Add to `database.rules.json`:

```json
{
  "rules": {
    "home_automation": {
      "$personaId": {
        "devices": {
          ".read": "auth != null",
          ".write": "auth != null"
        },
        "commands": {
          ".read": "auth != null",
          ".write": "auth != null"
        },
        "status": {
          ".read": "auth != null",
          ".write": "auth != null"
        }
      }
    }
  }
}
```

---

## 📱 Kai Integration

Kai will send commands like:

```json
{
  "home_automation/truekai/commands/cmd_123": {
    "device": "raspberry_pi_home",
    "action": "turn_on",
    "target": "led_1",
    "timestamp": 1730822400000
  }
}
```

Pi will respond with status:

```json
{
  "home_automation/truekai/status/raspberry_pi_home": {
    "led_1": "on",
    "led_2": "off",
    "led_3": "on",
    "last_updated": 1730822400000,
    "online": true
  }
}
```

---

## 🎯 Next Steps

1. ✅ Set up Raspberry Pi hardware
2. ✅ Install dependencies
3. ⏳ Create Python service files (next)
4. ⏳ Add Kai Flutter integration (after)
5. ⏳ Test with voice commands

---

**Ready to proceed?** Let me know when you've got the Pi set up and I'll create the Python service code!
