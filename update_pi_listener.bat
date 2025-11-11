@echo off
echo Updating Pi listener with sudo LED support...

REM Use PuTTY's pscp if available
where pscp >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo Using pscp to copy file...
    pscp firebase_rest_listener_debug.py pi@192.168.26.5:/home/pi/
    goto :end
)

REM Use WSL scp if available
where wsl >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo Using WSL scp to copy file...
    wsl scp firebase_rest_listener_debug.py pi@192.168.26.5:/home/pi/
    goto :end
)

echo Please manually copy firebase_rest_listener_debug.py to your Pi
echo You can use WinSCP, FileZilla, or copy the file via shared folder
echo Target location: /home/pi/firebase_rest_listener_debug.py

:end
pause