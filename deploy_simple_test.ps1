# PowerShell script to deploy simple LED test
Write-Host "🚀 Deploying Simple LED Test to Pi" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Yellow
Write-Host "Target: 192.168.29.5" -ForegroundColor Cyan
Write-Host ""

# Check if we're in WSL or need to use alternative method
Write-Host "📁 Copying test file to Pi..." -ForegroundColor Yellow

# Method 1: Try WSL scp
try {
    wsl scp test_simple.py pi@192.168.29.5:/home/pi/
    Write-Host "✅ File uploaded via WSL" -ForegroundColor Green
} catch {
    Write-Host "⚠️  WSL not available. Manual steps required:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "MANUAL DEPLOYMENT:" -ForegroundColor Red
    Write-Host "1. Copy the content of test_simple.py"
    Write-Host "2. SSH to Pi: ssh pi@192.168.29.5"
    Write-Host "3. Create file: nano test_simple.py"
    Write-Host "4. Paste the content and save (Ctrl+X, Y, Enter)"
    Write-Host ""
}

Write-Host "📦 Installing dependencies on Pi..." -ForegroundColor Yellow
try {
    ssh pi@192.168.29.5 "sudo pip3 install rpi_ws281x"
    Write-Host "✅ Dependencies installed" -ForegroundColor Green
} catch {
    Write-Host "⚠️  Manual dependency install needed:" -ForegroundColor Yellow
    Write-Host "   SSH to Pi and run: sudo pip3 install rpi_ws281x"
}

Write-Host ""
Write-Host "🧪 TO RUN THE TEST:" -ForegroundColor Green
Write-Host "1. SSH to Pi: ssh pi@192.168.29.5" -ForegroundColor Cyan
Write-Host "2. Run test: sudo python3 test_simple.py" -ForegroundColor Cyan
Write-Host ""
Write-Host "💡 If GPIO 18 doesn't work, try GPIO 12 or 13" -ForegroundColor Yellow