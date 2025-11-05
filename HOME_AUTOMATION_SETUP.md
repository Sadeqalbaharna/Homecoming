# 🏠 Kai Home Automation Integration Guide

## 🎯 Complete Setup Walkthrough

### Part 1: Raspberry Pi Setup (Hardware + Software)

#### Step 1: Flash SD Card

1. Download [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
2. Insert SD card (16GB+ recommended)
3. Open Imager → Choose OS → **Raspberry Pi OS Lite (64-bit)**
4. Click Settings ⚙️:
   - Hostname: `kai-home`
   - Enable SSH ✅
   - Username: `pi`, Password: (your choice)
   - WiFi SSID + Password
5. Write to SD card

#### Step 2: Boot & Connect

```powershell
# Find Pi on network (after ~2 minutes)
ping kai-home.local

# Connect via SSH
ssh pi@kai-home.local
# Enter password when prompted
```

#### Step 3: Update & Install Dependencies

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Python packages
sudo apt install python3-pip git -y

# Install Python libraries
pip3 install firebase-admin gpiozero python-dotenv
```

#### Step 4: Wire Up LEDs

**Materials Needed**:
- 3x LEDs (any color)
- 3x 220Ω resistors  
- Jumper wires
- Breadboard (optional)

**Wiring Diagram**:
```
GPIO 17 (Pin 11) → LED 1 (anode) → Resistor → GND
GPIO 27 (Pin 13) → LED 2 (anode) → Resistor → GND
GPIO 22 (Pin 15) → LED 3 (anode) → Resistor → GND
```

**Test LEDs**:
```bash
python3 << 'EOF'
from gpiozero import LED
from time import sleep

# Test each LED
for pin in [17, 27, 22]:
    print(f"Testing GPIO {pin}...")
    led = LED(pin)
    led.on()
    sleep(1)
    led.off()
    print(f"GPIO {pin} OK!")

print("All LEDs working!")
EOF
```

---

### Part 2: Firebase Configuration

#### Step 1: Get Service Account Key

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your Homecoming project
3. Click ⚙️ Settings → Project Settings
4. Go to **Service Accounts** tab
5. Click **Generate new private key**
6. Save the JSON file

#### Step 2: Copy Key to Raspberry Pi

**Option A: SCP (from Windows)**:
```powershell
# From your computer
scp C:\Downloads\your-project-firebase-adminsdk.json pi@kai-home.local:~/service-account.json
```

**Option B: Manual (SSH)**:
```bash
# On Raspberry Pi
nano ~/service-account.json
# Paste the entire JSON content
# Ctrl+X, Y, Enter to save
```

#### Step 3: Create .env File

```bash
# On Raspberry Pi
nano ~/.env
```

Paste this (replace with your values):
```env
FIREBASE_DATABASE_URL=https://YOUR-PROJECT-ID.firebaseio.com
FIREBASE_SERVICE_ACCOUNT=/home/pi/service-account.json
PERSONA_ID=truekai
DEVICE_ID=raspberry_pi_home
DEVICE_NAME=Home Pi
```

Save: Ctrl+X, Y, Enter

---

### Part 3: Install Kai Home Service

#### Step 1: Copy Service Files to Pi

**Option A: Git Clone** (if you push to GitHub):
```bash
cd ~
git clone https://github.com/YOUR_USERNAME/Homecoming.git
cp -r Homecoming/raspberry_pi ~/kai-home
cd ~/kai-home
```

**Option B: Manual Copy** (from Windows):
```powershell
# Copy Python service
scp C:\code\homecoming_app\raspberry_pi\*.py pi@kai-home.local:~/kai-home/

# Copy requirements
scp C:\code\homecoming_app\raspberry_pi\requirements.txt pi@kai-home.local:~/kai-home/
```

#### Step 2: Install Python Dependencies

```bash
cd ~/kai-home
pip3 install -r requirements.txt
```

#### Step 3: Test Service Manually

```bash
python3 kai_home_service.py
```

You should see:
```
============================================================
🏠 Kai Home Automation Service
============================================================

🏠 [Kai Home] Initializing...
✅ [Firebase] Connected successfully
✅ [GPIO] Initialized Living Room Light (GPIO 17)
✅ [GPIO] Initialized Bedroom Light (GPIO 27)
✅ [GPIO] Initialized Kitchen Light (GPIO 22)
✅ [Kai Home] Service started successfully!
📡 [Kai Home] Listening for commands at: home_automation/truekai/commands

💚 Service running! Press Ctrl+C to stop.
```

Press Ctrl+C to stop for now.

---

### Part 4: Auto-Start on Boot (Optional)

```bash
# Copy systemd service file
sudo cp ~/kai-home/kai-home.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable service (start on boot)
sudo systemctl enable kai-home

# Start service now
sudo systemctl start kai-home

# Check status
sudo systemctl status kai-home
```

**View logs**:
```bash
# Real-time logs
sudo journalctl -u kai-home -f

# Last 50 lines
sudo journalctl -u kai-home -n 50
```

---

### Part 5: Test From Firebase Console

#### Manual Test (Before Kai Integration)

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project → Realtime Database
3. Click **"+"** next to root
4. Create this structure:

```json
home_automation/
  truekai/
    commands/
      cmd_test/
        device: "raspberry_pi_home"
        target: "led_1"
        action: "turn_on"
        timestamp: 1730822400000
```

**Result**: LED 1 should turn ON, and you'll see logs on the Pi!

**Try other commands**:
- `"action": "turn_off"` - Turn off
- `"action": "toggle"` - Toggle state
- `"action": "blink", "duration": 5` - Blink for 5 seconds
- `"target": "led_2"` or `"led_3"` - Control other LEDs

---

### Part 6: Add to Homecoming App

#### Step 1: Update Version

Already done! Check `pubspec.yaml`:
```yaml
version: 0.7.5+107
```

#### Step 2: Test From Flutter

You can now use the `HomeAutomationService` in any Dart code:

```dart
import 'services/home_automation_service.dart';

// Turn on LED 1
await HomeAutomationService().turnOn(
  'truekai',
  'raspberry_pi_home',
  'led_1',
);

// Turn off LED 2
await HomeAutomationService().turnOff(
  'truekai',
  'raspberry_pi_home',
  'led_2',
);

// Toggle LED 3
await HomeAutomationService().toggle(
  'truekai',
  'raspberry_pi_home',
  'led_3',
);

// Blink LED 1 for 3 seconds
await HomeAutomationService().blink(
  'truekai',
  'raspberry_pi_home',
  'led_1',
  duration: 3,
);
```

---

### Part 7: Voice Commands (Coming Next)

We'll add these natural language commands to Kai:

- "Hey Kai, turn on the living room light"
- "Hey Kai, turn off all the lights"
- "Hey Kai, make the bedroom light blink"
- "Hey Kai, toggle the kitchen light"
- "Hey Kai, what lights are on?"

This requires adding intent recognition to the AI service - we'll do this next!

---

## 🎮 Quick Command Reference

### Raspberry Pi Commands

```bash
# Start service manually
python3 ~/kai-home/kai_home_service.py

# Start systemd service
sudo systemctl start kai-home

# Stop systemd service
sudo systemctl stop kai-home

# Restart service
sudo systemctl restart kai-home

# View logs
sudo journalctl -u kai-home -f

# Check status
sudo systemctl status kai-home
```

### Flutter Commands

```dart
// Turn device on/off
await HomeAutomationService().turnOn(personaId, deviceId, target);
await HomeAutomationService().turnOff(personaId, deviceId, target);

// Toggle device
await HomeAutomationService().toggle(personaId, deviceId, target);

// Blink device
await HomeAutomationService().blink(personaId, deviceId, target, duration: 5);

// Get device status
final status = await HomeAutomationService().getDeviceStatus(
  personaId: personaId,
  deviceId: deviceId,
);

// List all devices
final devices = await HomeAutomationService().listDevices(personaId);

// Watch device (real-time updates)
HomeAutomationService().watchDevice(
  personaId: personaId,
  deviceId: deviceId,
).listen((status) {
  print('Device updated: ${status.deviceName}');
});
```

---

## 🔧 Troubleshooting

### Pi won't boot
- Check SD card is fully inserted
- Try re-flashing with Raspberry Pi Imager
- Verify power supply is adequate (5V 2.5A minimum)

### Can't SSH to Pi
- Wait 2-3 minutes after boot
- Check WiFi credentials in imager
- Try `ping kai-home.local` or scan network with `arp -a`
- Try direct ethernet connection

### LEDs don't work
- Check wiring (LED polarity matters!)
- Verify resistor is included (prevents LED burnout)
- Test with manual Python script (see Part 1, Step 4)
- Check GPIO pin numbers (BCM numbering, not physical)

### Firebase connection fails
- Verify `FIREBASE_DATABASE_URL` in `.env`
- Check service account JSON path
- Ensure Firebase Realtime Database is enabled
- Check network connectivity: `ping google.com`

### Commands not received
- Check Firebase Realtime Database rules
- Verify service is running: `sudo systemctl status kai-home`
- Check logs: `sudo journalctl -u kai-home -n 50`
- Manually test in Firebase Console

---

## 🚀 What's Next?

### Immediate Next Steps (In Order):
1. ✅ Set up Raspberry Pi hardware
2. ✅ Install software dependencies  
3. ✅ Test LEDs manually
4. ✅ Configure Firebase & service
5. ✅ Test with Firebase Console
6. ⏳ **Add voice command parsing to Kai**
7. ⏳ **Test with "Hey Kai, turn on the light"**

### Future Enhancements:
- Add more device types (relays, sensors, servos)
- Temperature/humidity monitoring
- Motion detection triggers
- Scheduled automations
- Multiple Raspberry Pis
- Web dashboard for device control
- Alexa/Google Home integration
- Custom device names per user

---

## 📚 Resources

- [Raspberry Pi Documentation](https://www.raspberrypi.com/documentation/)
- [gpiozero Python Library](https://gpiozero.readthedocs.io/)
- [Firebase Admin SDK](https://firebase.google.com/docs/admin/setup)
- [GPIO Pin Reference](https://pinout.xyz/)

---

**Questions?** Start with Part 1 and let me know when you're ready for the next step!
