#!/usr/bin/env pwsh
# Load GitHub secrets for V1 testing

Write-Host "Load GitHub Secrets for V1 Testing" -ForegroundColor Cyan
Write-Host "==================================`n" -ForegroundColor Cyan

$openChoice = Read-Host "Open GitHub secrets page? (y/n)"
if ($openChoice -eq 'y') {
    Start-Process "https://github.com/YOUR_REPO/settings/secrets/actions"
    Write-Host "`nOpened in browser..." -ForegroundColor Green
    Start-Sleep -Seconds 2
}

Write-Host "`nPaste your secrets below (from https://github.com/YOUR_REPO/settings/secrets/actions):`n" -ForegroundColor Yellow

# Get OPENAI_API_KEY
$apiKey = Read-Host "OPEN_API_KEY (paste or leave blank)"
if ($apiKey) {
    [Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $apiKey, "Process")
    Write-Host "✓ OPENAI_API_KEY set" -ForegroundColor Green
}

# Get ELEVENLABS_API_KEY  
$elevenKey = Read-Host "ELEVENLABS_API_KEY (paste or leave blank)"
if ($elevenKey) {
    [Environment]::SetEnvironmentVariable("ELEVENLABS_API_KEY", $elevenKey, "Process")
    Write-Host "✓ ELEVENLABS_API_KEY set" -ForegroundColor Green
}

# Get GOOGLE_API_KEY
$googleKey = Read-Host "GOOGLE_API_KEY (paste or leave blank)"
if ($googleKey) {
    [Environment]::SetEnvironmentVariable("GOOGLE_API_KEY", $googleKey, "Process")
    Write-Host "✓ GOOGLE_API_KEY set" -ForegroundColor Green
}

Write-Host "`nRunning kai_table_v1_core.py...`n" -ForegroundColor Green
cd C:\code\homecoming_app
python kai_table_v1_core.py
