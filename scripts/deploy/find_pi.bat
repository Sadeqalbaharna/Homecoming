@echo off
echo 🔍 Finding your Raspberry Pi on the network...
echo.
echo Scanning common IP ranges for Raspberry Pi devices...
echo This may take a moment...
echo.

REM Scan local network for Pi devices
for /l %%i in (1,1,254) do (
    ping -n 1 -w 100 192.168.1.%%i >nul 2>&1
    if not errorlevel 1 (
        echo Found device at 192.168.1.%%i
        nslookup 192.168.1.%%i 2>nul | findstr /i "raspberrypi\|pi"
    )
)

echo.
echo Also try scanning 192.168.0.x range:
for /l %%i in (1,1,254) do (
    ping -n 1 -w 100 192.168.0.%%i >nul 2>&1  
    if not errorlevel 1 (
        echo Found device at 192.168.0.%%i
        nslookup 192.168.0.%%i 2>nul | findstr /i "raspberrypi\|pi"
    )
)

echo.
echo 💡 You can also check your router's admin panel to find "raspberrypi" or "pi" devices
echo 💡 Or run this command on your Pi directly: hostname -I
pause