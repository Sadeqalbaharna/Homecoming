#!/usr/bin/env powershell
<#
.SYNOPSIS
    Simple deployment guide for the intelligent ambiance system

.DESCRIPTION  
    This guide helps you deploy the enhanced Firebase listener to your Raspberry Pi
    using whatever method works best for your setup.
#>

Write-Host "🎯 INTELLIGENT AMBIANCE SYSTEM - DEPLOYMENT GUIDE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

Write-Host "📁 Files you need to copy to your Pi:" -ForegroundColor Cyan
Write-Host "   Source: firebase_rest_listener_debug.py (in this folder)" -ForegroundColor White
Write-Host "   Target: /home/pi/firebase_rest_listener_debug.py (on your Pi)" -ForegroundColor White
Write-Host ""

Write-Host "🔧 METHOD 1: Direct Copy (Recommended)" -ForegroundColor Yellow
Write-Host "--------------------------------------"
Write-Host "1. Connect to your Pi (keyboard/mouse or VNC)" -ForegroundColor White
Write-Host "2. Open terminal on Pi" -ForegroundColor White
Write-Host "3. Run: nano /home/pi/firebase_rest_listener_debug.py" -ForegroundColor White
Write-Host "4. Copy ALL content from Windows file and paste into nano" -ForegroundColor White
Write-Host "5. Press Ctrl+X, then Y, then Enter to save" -ForegroundColor White
Write-Host "6. Run: chmod +x /home/pi/firebase_rest_listener_debug.py" -ForegroundColor White
Write-Host ""

Write-Host "🌐 METHOD 2: Network Copy (if you know Pi's IP)" -ForegroundColor Yellow
Write-Host "-----------------------------------------------"
$piIP = Read-Host "Enter your Pi's IP address (or press Enter to skip)"
if ($piIP) {
    Write-Host "Trying to copy to $piIP..." -ForegroundColor Green
    try {
        $sshPath = "C:\Windows\System32\OpenSSH\ssh.exe"
        if (Test-Path $sshPath) {
            Write-Host "Testing connection..." -ForegroundColor Yellow
            & $sshPath pi@$piIP "echo 'Connection successful!'"
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Connection works! Copying file..." -ForegroundColor Green
                Get-Content "firebase_rest_listener_debug.py" | & $sshPath pi@$piIP "cat > /home/pi/firebase_rest_listener_debug.py"
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ File copied successfully!" -ForegroundColor Green
                    & $sshPath pi@$piIP "chmod +x /home/pi/firebase_rest_listener_debug.py"
                    Write-Host "✅ Permissions set!" -ForegroundColor Green
                } else {
                    Write-Host "❌ Copy failed. Use Method 1 instead." -ForegroundColor Red
                }
            } else {
                Write-Host "❌ Cannot connect to Pi. Use Method 1 instead." -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "❌ Network copy failed: $_" -ForegroundColor Red
        Write-Host "💡 Use Method 1 (Direct Copy) instead" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "🚀 STEP 3: Start the Enhanced Listener" -ForegroundColor Yellow
Write-Host "--------------------------------------"
Write-Host "On your Pi, run:" -ForegroundColor White
Write-Host "   cd /home/pi" -ForegroundColor Gray
Write-Host "   python3 firebase_rest_listener_debug.py" -ForegroundColor Gray
Write-Host ""

Write-Host "📊 STEP 4: Test the System" -ForegroundColor Yellow
Write-Host "--------------------------"
Write-Host "From your mobile app, try saying:" -ForegroundColor White
Write-Host "   'Kai, give me forest ambiance'" -ForegroundColor Gray
Write-Host "   'Create ocean mood'" -ForegroundColor Gray
Write-Host "   'Set romantic atmosphere'" -ForegroundColor Gray
Write-Host ""

Write-Host "🎯 You should see in Pi logs:" -ForegroundColor Green
Write-Host "   🎭 Ambiance profile: Forest (85% confidence)" -ForegroundColor Gray
Write-Host "   💡 Setting ambiance lighting: light_green at 70%" -ForegroundColor Gray
Write-Host "   🎵 Playing track 7 (forest mood) via Bluetooth" -ForegroundColor Gray
Write-Host ""

Write-Host "🔍 TROUBLESHOOTING:" -ForegroundColor Red
Write-Host "------------------"
Write-Host "If nothing happens:" -ForegroundColor White
Write-Host "   1. Check Pi is connected to internet" -ForegroundColor Gray
Write-Host "   2. Verify Firebase listener is running" -ForegroundColor Gray
Write-Host "   3. Test with: python test_ambiance_system.py" -ForegroundColor Gray
Write-Host "   4. Check mobile app permissions for Firebase" -ForegroundColor Gray
Write-Host ""

Write-Host "🎉 WHAT THE SYSTEM DOES:" -ForegroundColor Green
Write-Host "------------------------"
Write-Host "✅ Analyzes your voice commands intelligently" -ForegroundColor White
Write-Host "✅ Coordinates music AND lighting together" -ForegroundColor White  
Write-Host "✅ 12 ambiance profiles (forest, ocean, party, etc.)" -ForegroundColor White
Write-Host "✅ Natural responses from Kai" -ForegroundColor White
Write-Host "✅ Works with your existing music tracks" -ForegroundColor White
Write-Host ""

$continue = Read-Host "Press Enter to continue, or type 'test' to run the test system now"
if ($continue -eq 'test') {
    Write-Host "🧪 Running ambiance system test..." -ForegroundColor Green
    python test_ambiance_system.py
}