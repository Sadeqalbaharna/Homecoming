# Pi Network Scanner Script
# Scans for Raspberry Pi devices on your network

Write-Host "🔍 Scanning for Raspberry Pi on network 192.168.254.x..." -ForegroundColor Green
Write-Host "Your computer IP: 192.168.254.20" -ForegroundColor Yellow
Write-Host ""

$found_devices = @()

# Common Pi IP ranges to check
$ips_to_check = @(
    "192.168.254.10", "192.168.254.11", "192.168.254.12", 
    "192.168.254.100", "192.168.254.101", "192.168.254.102",
    "192.168.254.150", "192.168.254.151", "192.168.254.152",
    "192.168.254.25", "192.168.254.50", "192.168.254.75",
    "192.168.254.200", "192.168.254.201", "192.168.254.202"
)

Write-Host "Testing common Pi IP addresses..." -ForegroundColor Cyan

foreach ($ip in $ips_to_check) {
    Write-Host "Testing $ip..." -NoNewline
    
    $ping_result = Test-Connection -ComputerName $ip -Count 1 -Quiet
    
    if ($ping_result) {
        Write-Host " ✅ RESPONDING!" -ForegroundColor Green
        $found_devices += $ip
        
        # Try SSH connection test
        Write-Host "  → Testing SSH connection..." -NoNewline
        try {
            $ssh_test = & "C:\Windows\System32\OpenSSH\ssh.exe" -o ConnectTimeout=3 -o BatchMode=yes pi@$ip "echo 'Pi Found'" 2>$null
            if ($ssh_test -like "*Pi Found*") {
                Write-Host " 🎯 SSH WORKS! This is likely your Pi!" -ForegroundColor Yellow
            } else {
                Write-Host " SSH connection available but no Pi response" -ForegroundColor Gray
            }
        } catch {
            Write-Host " No SSH or connection refused" -ForegroundColor Gray
        }
    } else {
        Write-Host " ❌ No response" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "📊 Results Summary:" -ForegroundColor Green
Write-Host "Devices responding to ping: $($found_devices.Count)" -ForegroundColor Yellow

if ($found_devices.Count -eq 0) {
    Write-Host ""
    Write-Host "🤔 No Pi devices found. Possible reasons:" -ForegroundColor Yellow
    Write-Host "  • Pi still booting up"
    Write-Host "  • Pi on different network segment"  
    Write-Host "  • Pi has different IP range"
    Write-Host "  • SSH not enabled on Pi"
    Write-Host ""
    Write-Host "💡 Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Check router admin panel at: http://192.168.254.162"
    Write-Host "  2. Look for 'Connected Devices' or 'DHCP Clients'"
    Write-Host "  3. Find device named 'raspberrypi' or similar"
    Write-Host "  4. Try connecting with Pi actual IP address"
} else {
    Write-Host ""
    Write-Host "🎯 Try connecting to these devices:" -ForegroundColor Cyan
    foreach ($device in $found_devices) {
        Write-Host "  ssh pi@$device" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "🚀 Once connected, run the music system deployment:" -ForegroundColor Green  
Write-Host "  1. Upload music system files to Pi"
Write-Host "  2. Run: ./bluetooth_audio_setup.sh"
Write-Host "  3. Generate music: python3 music_player_service.py"
Write-Host "  4. Test with mobile app music system!"