#!/usr/bin/env powershell
<#
.SYNOPSIS
    Deploy enhanced Firebase listener with intelligent ambiance lighting to Raspberry Pi

.DESCRIPTION
    This script copies the enhanced firebase_rest_listener_debug.py to the Pi
    and optionally restarts the service for immediate testing.

.PARAMETER PiIP
    The IP address of your Raspberry Pi (default: 192.168.1.100)

.PARAMETER Username
    Pi username (default: pi)

.EXAMPLE
    .\deploy_to_pi.ps1
    .\deploy_to_pi.ps1 -PiIP "192.168.1.150" -Username "admin"
#>

param(
    [string]$PiIP = "192.168.1.100",
    [string]$Username = "pi"
)

Write-Host "🚀 Deploying Enhanced Firebase Listener to Pi..." -ForegroundColor Green
Write-Host "📍 Target: $Username@$PiIP" -ForegroundColor Cyan

# Check if the enhanced listener file exists
$listenerFile = "firebase_rest_listener_debug.py"
if (-not (Test-Path $listenerFile)) {
    Write-Host "❌ Error: $listenerFile not found in current directory" -ForegroundColor Red
    Write-Host "📁 Current directory: $(Get-Location)" -ForegroundColor Yellow
    Write-Host "📋 Available files:" -ForegroundColor Yellow
    Get-ChildItem -Name "*.py" | ForEach-Object { Write-Host "   $_" -ForegroundColor White }
    exit 1
}

Write-Host "✅ Found enhanced listener: $listenerFile" -ForegroundColor Green

# Method 1: Try using built-in SSH (Windows 10/11)
Write-Host "🔧 Attempting deployment methods..." -ForegroundColor Yellow

try {
    Write-Host "📤 Method 1: Using PowerShell SSH/SCP..." -ForegroundColor Cyan
    
    # Check if ssh is available
    $sshPath = Get-Command ssh -ErrorAction SilentlyContinue
    if ($sshPath) {
        Write-Host "✅ SSH found at: $($sshPath.Source)" -ForegroundColor Green
        
        # Copy file using SSH
        Write-Host "📋 Copying file to Pi..." -ForegroundColor Yellow
        Get-Content $listenerFile | ssh $Username@$PiIP "cat > /home/$Username/firebase_rest_listener_debug.py"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ File copied successfully!" -ForegroundColor Green
            
            # Verify the file was copied
            Write-Host "🔍 Verifying deployment..." -ForegroundColor Yellow
            $verifyResult = ssh $Username@$PiIP "ls -la /home/$Username/firebase_rest_listener_debug.py"
            Write-Host $verifyResult -ForegroundColor White
            
            # Make executable
            Write-Host "🔧 Setting permissions..." -ForegroundColor Yellow
            ssh $Username@$PiIP "chmod +x /home/$Username/firebase_rest_listener_debug.py"
            
            Write-Host "🎉 Deployment completed successfully!" -ForegroundColor Green
            
            # Ask if user wants to restart the service
            $restart = Read-Host "Would you like to restart the Firebase listener service? (y/N)"
            if ($restart -eq 'y' -or $restart -eq 'Y') {
                Write-Host "🔄 Restarting Firebase listener..." -ForegroundColor Yellow
                ssh $Username@$PiIP "sudo pkill -f firebase_rest_listener_debug.py; nohup python3 /home/$Username/firebase_rest_listener_debug.py > /home/$Username/firebase_listener.log 2>&1 &"
                Write-Host "✅ Service restarted. Check logs with: ssh $Username@$PiIP 'tail -f /home/$Username/firebase_listener.log'" -ForegroundColor Green
            }
            
            Write-Host "🎯 Next steps:" -ForegroundColor Cyan
            Write-Host "   1. Test voice commands from your mobile app" -ForegroundColor White
            Write-Host "   2. Try: 'Kai, give me forest ambiance'" -ForegroundColor White
            Write-Host "   3. Try: 'Create ocean mood'" -ForegroundColor White
            Write-Host "   4. Monitor logs: ssh $Username@$PiIP 'tail -f /home/$Username/firebase_listener.log'" -ForegroundColor White
            
            exit 0
        }
    } else {
        throw "SSH not found in PATH"
    }
} catch {
    Write-Host "❌ Method 1 failed: $_" -ForegroundColor Red
}

# Method 2: Manual instructions
Write-Host "📋 Method 2: Manual deployment instructions" -ForegroundColor Cyan
Write-Host @"
Since automatic deployment failed, please follow these steps:

1. Connect to your Pi via your preferred method (SSH, direct access, etc.)

2. Navigate to your Pi's home directory:
   cd /home/$Username

3. Create/edit the Firebase listener file:
   nano firebase_rest_listener_debug.py

4. Copy the enhanced listener code from Windows to Pi
   - The file is located at: $(Resolve-Path $listenerFile)
   - You can use WinSCP, FileZilla, or copy-paste the content

5. Set permissions:
   chmod +x firebase_rest_listener_debug.py

6. Start the enhanced listener:
   python3 firebase_rest_listener_debug.py

7. Monitor the logs for ambiance system messages
"@ -ForegroundColor Yellow

Write-Host "The enhanced listener includes:" -ForegroundColor Green
Write-Host "   - Intelligent ambiance lighting control" -ForegroundColor White
Write-Host "   - Coordinated music and lighting commands" -ForegroundColor White
Write-Host "   - Voice analysis integration with Kai" -ForegroundColor White
Write-Host "   - 12 ambiance profiles (forest, ocean, romantic, etc.)" -ForegroundColor White
Write-Host "   - RGB color mapping and lighting effects" -ForegroundColor White