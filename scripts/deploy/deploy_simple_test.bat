@echo off
echo 🚀 Deploying Simple LED Test to Pi
echo =====================================
echo Target: 192.168.213.5
echo.

echo 📁 Uploading test file...
scp test_simple.py pi@192.168.213.5:/home/pi/

echo 📦 Installing dependencies...
ssh pi@192.168.213.5 "sudo pip3 install rpi_ws281x"

echo 🔐 Setting permissions...
ssh pi@192.168.213.5 "chmod +x /home/pi/test_simple.py"

echo.
echo ✅ Deployment complete!
echo.
echo 🧪 To run the test, SSH to your Pi and run:
echo    ssh pi@192.168.213.5
echo    sudo python3 test_simple.py
echo.
echo 💡 If GPIO 18 doesn't work, edit test_simple.py and try:
echo    LED_PIN = 12  or  LED_PIN = 13
echo.
pause