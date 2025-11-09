#!/usr/bin/env pwsh
# Raspberry Pi Firebase Listener Deployment Script
# Deploys the enhanced WS2812B LED system to Pi

param(
    [string]$PiHost = "192.168.29.5",  # Your Pi's IP address
    [string]$PiUser = "pi",
    [switch]$InstallDependencies,
    [switch]$TestOnly
)

Write-Host "🚀 Deploying Firebase Listener with WS2812B Support to Raspberry Pi" -ForegroundColor Green
Write-Host "Target: $PiUser@$PiHost" -ForegroundColor Cyan

# Files to deploy
$FilesToDeploy = @(
    "firebase_rest_listener_debug.py"
)

# Check if files exist locally
foreach ($file in $FilesToDeploy) {
    if (!(Test-Path $file)) {
        Write-Error "❌ File not found: $file"
        exit 1
    }
    Write-Host "✅ Found: $file" -ForegroundColor Green
}

# Function to execute SSH commands
function Invoke-PiCommand {
    param([string]$Command)
    Write-Host "🔧 Executing: $Command" -ForegroundColor Yellow
    ssh "${PiUser}@${PiHost}" $Command
}

# Function to copy files to Pi
function Copy-ToPi {
    param([string]$LocalFile, [string]$RemotePath = "/home/pi/")
    Write-Host "📁 Copying $LocalFile to ${PiUser}@${PiHost}:${RemotePath}" -ForegroundColor Cyan
    scp $LocalFile "${PiUser}@${PiHost}:${RemotePath}"
}

try {
    # Test connection
    Write-Host "`n🔍 Testing SSH connection..." -ForegroundColor Yellow
    $testResult = ssh -o ConnectTimeout=5 "${PiUser}@${PiHost}" "echo 'Connection successful'"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Cannot connect to Pi. Check IP address and SSH access."
        Write-Host "💡 Make sure SSH is enabled on your Pi: sudo systemctl enable ssh" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "✅ SSH connection successful" -ForegroundColor Green

    if ($TestOnly) {
        Write-Host "✅ Test complete - connection working" -ForegroundColor Green
        exit 0
    }

    # Create backup of existing listener
    Write-Host "`n💾 Creating backup of existing files..." -ForegroundColor Yellow
    Invoke-PiCommand "if [ -f firebase_rest_listener_debug.py ]; then cp firebase_rest_listener_debug.py firebase_rest_listener_debug.py.backup.$(date +%Y%m%d_%H%M%S); fi"

    # Deploy files
    Write-Host "`n📦 Deploying files..." -ForegroundColor Yellow
    foreach ($file in $FilesToDeploy) {
        Copy-ToPi $file
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Deployed: $file" -ForegroundColor Green
        } else {
            Write-Error "❌ Failed to deploy: $file"
            exit 1
        }
    }

    # Set executable permissions
    Write-Host "`n🔐 Setting permissions..." -ForegroundColor Yellow
    Invoke-PiCommand "chmod +x firebase_rest_listener_debug.py"

    # Install dependencies if requested
    if ($InstallDependencies) {
        Write-Host "`n📚 Installing Python dependencies..." -ForegroundColor Yellow
        
        # Update package lists
        Invoke-PiCommand "sudo apt update"
        
        # Install system dependencies
        Write-Host "🔧 Installing system packages..." -ForegroundColor Cyan
        Invoke-PiCommand "sudo apt install -y python3-pip python3-dev build-essential scons swig"
        
        # Install Python packages
        Write-Host "🐍 Installing Python packages..." -ForegroundColor Cyan
        Invoke-PiCommand "pip3 install requests"
        
        # Install WS2812B library (requires sudo)
        Write-Host "🌈 Installing WS2812B library..." -ForegroundColor Cyan
        Invoke-PiCommand "sudo pip3 install rpi_ws281x"
        
        Write-Host "✅ Dependencies installed" -ForegroundColor Green
    }

    # Create music directory if it doesn't exist
    Write-Host "`n🎵 Setting up music directory..." -ForegroundColor Yellow
    Invoke-PiCommand "mkdir -p /home/pi/music_tracks"
    Invoke-PiCommand "ls -la /home/pi/music_tracks/"

    # Check system requirements
    Write-Host "`n🔍 System check..." -ForegroundColor Yellow
    
    # Check Python version
    Invoke-PiCommand "python3 --version"
    
    # Check if mpv is installed
    $mpvCheck = Invoke-PiCommand "which mpv"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠️ mpv not found - installing..." -ForegroundColor Yellow
        Invoke-PiCommand "sudo apt install -y mpv"
    } else {
        Write-Host "✅ mpv is available" -ForegroundColor Green
    }
    
    # Check audio devices
    Write-Host "🔊 Available audio devices:" -ForegroundColor Cyan
    Invoke-PiCommand "pactl list short sinks"

    # Test script syntax
    Write-Host "`n✅ Testing script syntax..." -ForegroundColor Yellow
    Invoke-PiCommand "python3 -m py_compile firebase_rest_listener_debug.py"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Python syntax check passed" -ForegroundColor Green
    } else {
        Write-Error "❌ Python syntax errors detected"
        exit 1
    }

    # Show deployment summary
    Write-Host "`n🎉 DEPLOYMENT COMPLETE!" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
    Write-Host "📍 Deployed to: ${PiUser}@${PiHost}:/home/pi/" -ForegroundColor Cyan
    Write-Host "🎯 Features included:" -ForegroundColor Cyan
    Write-Host "   ✅ WS2812B RGB LED control with 3 strips" -ForegroundColor White
    Write-Host "   ✅ GM Kai direct control system" -ForegroundColor White
    Write-Host "   ✅ Intelligent profile matching" -ForegroundColor White
    Write-Host "   ✅ Scene lighting support" -ForegroundColor White
    Write-Host "   ✅ Dynamic effects including pulse wave rainbow flicker" -ForegroundColor White
    Write-Host "`n🚀 To start the listener:" -ForegroundColor Yellow
    Write-Host "   ssh ${PiUser}@${PiHost}" -ForegroundColor Gray
    Write-Host "   python3 firebase_rest_listener_debug.py" -ForegroundColor Gray
    Write-Host "`n🔧 To run as service:" -ForegroundColor Yellow
    Write-Host "   sudo nano /etc/systemd/system/firebase-listener.service" -ForegroundColor Gray
    Write-Host "`n📋 Hardware setup needed:" -ForegroundColor Yellow
    Write-Host "   🔌 Main strip: 150 LEDs on GPIO 18" -ForegroundColor White
    Write-Host "   🔌 Accent strip: 60 LEDs on GPIO 13" -ForegroundColor White
    Write-Host "   🔌 Ambient strip: 30 LEDs on GPIO 12" -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

} catch {
    Write-Error "❌ Deployment failed: $_"
    exit 1
}