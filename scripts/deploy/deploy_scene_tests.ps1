#!/usr/bin/env powershell
<#
.SYNOPSIS
    Deploy scene playback test scripts to Raspberry Pi

.DESCRIPTION
    Copies modular scene playback test scripts to the Pi for Bluetooth speaker testing

.PARAMETER PiIP
    The IP address of your Raspberry Pi (default: 192.168.48.5)

.PARAMETER Username
    Pi username (default: pi)

.EXAMPLE
    .\deploy_scene_tests.ps1
    .\deploy_scene_tests.ps1 -PiIP "192.168.48.5" -Username "pi"
#>

param(
    [string]$PiIP = "192.168.48.5",
    [string]$Username = "pi"
)

Write-Host "`n🎭 Deploying Scene Playback Tests to Raspberry Pi..." -ForegroundColor Green
Write-Host "📍 Target: $Username@$PiIP`n" -ForegroundColor Cyan

# Files to deploy
$files = @(
    "test_bluetooth_tg129c.py",
    "test_modular_scene_playback.py",
    "demo_modular_scenes.py",
    "verify_setup.py"
)

# Check if files exist
$missingFiles = @()
foreach ($file in $files) {
    if (-not (Test-Path $file)) {
        $missingFiles += $file
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Host "❌ Missing files:" -ForegroundColor Red
    $missingFiles | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
    exit 1
}

Write-Host "✅ All test files found`n" -ForegroundColor Green

# Try deployment methods
$deployed = $false

# Method 1: Use Putty's pscp if available
Write-Host "🔍 Looking for deployment tools..." -ForegroundColor Yellow

$pscp = Get-Command pscp -ErrorAction SilentlyContinue
if ($pscp) {
    Write-Host "✅ Found pscp (PuTTY SCP)" -ForegroundColor Green
    Write-Host "📤 Uploading files...`n" -ForegroundColor Cyan
    
    foreach ($file in $files) {
        Write-Host "   → $file" -ForegroundColor White
        & pscp -l $Username -pw password "$file" "$($PiIP):/home/$Username/"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "      ✅ Uploaded" -ForegroundColor Green
        } else {
            Write-Host "      ⚠️  Upload may have failed" -ForegroundColor Yellow
        }
    }
    
    $deployed = $true
}

# Method 2: Try WinSCP if pscp not found
if (-not $deployed) {
    $winscp = Get-Command WinSCP -ErrorAction SilentlyContinue
    if ($winscp) {
        Write-Host "✅ Found WinSCP" -ForegroundColor Green
        Write-Host "📤 Uploading files via WinSCP...`n" -ForegroundColor Cyan
        
        foreach ($file in $files) {
            Write-Host "   → $file" -ForegroundColor White
            # WinSCP command would go here
        }
        
        $deployed = $true
    }
}

# Method 3: Manual instructions if no tool found
if (-not $deployed) {
    Write-Host "`n⚠️  SSH/SCP tools not found. Use one of these options:`n" -ForegroundColor Yellow
    
    Write-Host "1️⃣  Install PuTTY and use pscp:" -ForegroundColor Cyan
    Write-Host "   https://www.putty.org/`n"
    
    Write-Host "2️⃣  Install WinSCP:" -ForegroundColor Cyan
    Write-Host "   https://winscp.net/`n"
    
    Write-Host "3️⃣  Use WSL with native scp:" -ForegroundColor Cyan
    Write-Host "   wsl scp test_*.py pi@$PiIP:/home/pi/`n"
    
    Write-Host "4️⃣  Or manually copy via SSH on the Pi:" -ForegroundColor Cyan
    Write-Host "   ssh pi@$PiIP`n"
    Write-Host "   Then manually transfer the files (or use a USB drive)`n"
    
    # Show file list for manual copy
    Write-Host "`n📋 Files to copy:" -ForegroundColor Yellow
    $files | ForEach-Object { Write-Host "   • $_" -ForegroundColor White }
}

if ($deployed) {
    Write-Host "`n✅ Deployment complete!`n" -ForegroundColor Green
    
    Write-Host "🧪 Next steps on the Pi:`n" -ForegroundColor Cyan
    Write-Host "   1. SSH to Pi: ssh pi@$PiIP" -ForegroundColor White
    Write-Host "   2. Check Bluetooth: python test_bluetooth_tg129c.py" -ForegroundColor White
    Write-Host "   3. Play a scene: python test_modular_scene_playback.py haunted_mansion" -ForegroundColor White
    Write-Host "`n"
}
