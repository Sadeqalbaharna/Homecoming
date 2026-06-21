#!/usr/bin/env powershell

Write-Host "INTELLIGENT AMBIANCE SYSTEM - DEPLOYMENT GUIDE" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""

Write-Host "FILES TO DEPLOY:" -ForegroundColor Cyan
Write-Host "   Source: firebase_rest_listener_debug.py (in this folder)" -ForegroundColor White
Write-Host "   Target: /home/pi/firebase_rest_listener_debug.py (on your Pi)" -ForegroundColor White
Write-Host ""

Write-Host "METHOD 1: Direct Copy (Easiest)" -ForegroundColor Yellow
Write-Host "-------------------------------"
Write-Host "1. Connect to your Pi directly" -ForegroundColor White
Write-Host "2. Open terminal on Pi" -ForegroundColor White
Write-Host "3. Run: nano /home/pi/firebase_rest_listener_debug.py" -ForegroundColor White
Write-Host "4. Copy content from Windows file and paste into nano" -ForegroundColor White
Write-Host "5. Press Ctrl+X, then Y, then Enter to save" -ForegroundColor White
Write-Host "6. Run: chmod +x firebase_rest_listener_debug.py" -ForegroundColor White
Write-Host ""

Write-Host "METHOD 2: Try Network Copy" -ForegroundColor Yellow
Write-Host "-------------------------"
$piIP = Read-Host "Enter your Pi's IP address (or press Enter to skip)"

if ($piIP) {
    Write-Host "Testing connection to $piIP..." -ForegroundColor Yellow
    try {
        $sshPath = "C:\Windows\System32\OpenSSH\ssh.exe"
        if (Test-Path $sshPath) {
            & $sshPath pi@$piIP "echo 'Connected successfully'"
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Connection successful! Copying file..." -ForegroundColor Green
                Get-Content "firebase_rest_listener_debug.py" | & $sshPath pi@$piIP "cat > /home/pi/firebase_rest_listener_debug.py"
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "File copied successfully!" -ForegroundColor Green
                    & $sshPath pi@$piIP "chmod +x /home/pi/firebase_rest_listener_debug.py"
                    Write-Host "Permissions set! Ready to start." -ForegroundColor Green
                    
                    $startNow = Read-Host "Start the listener now? (y/n)"
                    if ($startNow -eq 'y') {
                        Write-Host "Starting Firebase listener..." -ForegroundColor Green
                        & $sshPath pi@$piIP "cd /home/pi && nohup python3 firebase_rest_listener_debug.py > firebase_listener.log 2>&1 &"
                        Write-Host "Listener started! Monitor with: ssh pi@$piIP 'tail -f /home/pi/firebase_listener.log'" -ForegroundColor Green
                    }
                } else {
                    Write-Host "Copy failed. Use Method 1 instead." -ForegroundColor Red
                }
            } else {
                Write-Host "Cannot connect. Use Method 1 instead." -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "Network copy failed. Use Method 1 instead." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "-----------"
Write-Host "1. Start the listener on Pi: python3 firebase_rest_listener_debug.py" -ForegroundColor White
Write-Host "2. Test from mobile app: 'Kai, give me forest ambiance'" -ForegroundColor White
Write-Host "3. Or run test script: python test_ambiance_system.py" -ForegroundColor White
Write-Host ""

Write-Host "WHAT SHOULD HAPPEN:" -ForegroundColor Green
Write-Host "- Voice command analyzed intelligently" -ForegroundColor White
Write-Host "- Music and lighting coordinated together" -ForegroundColor White
Write-Host "- Kai responds naturally about the ambiance" -ForegroundColor White
Write-Host ""

$runTest = Read-Host "Run test now to verify system works? (y/n)"
if ($runTest -eq 'y') {
    Write-Host "Running ambiance system test..." -ForegroundColor Green
    python test_ambiance_system.py
}