# Simple Pi Scanner
Write-Host "Scanning for Raspberry Pi on network 192.168.254.x..."
Write-Host "Your computer IP: 192.168.254.20"
Write-Host ""

$found_devices = @()
$ips_to_check = @(
    "192.168.254.10", "192.168.254.25", "192.168.254.50", 
    "192.168.254.100", "192.168.254.101", "192.168.254.102",
    "192.168.254.150", "192.168.254.200"
)

foreach ($ip in $ips_to_check) {
    Write-Host "Testing $ip..." -NoNewline
    
    $ping_result = Test-Connection -ComputerName $ip -Count 1 -Quiet
    
    if ($ping_result) {
        Write-Host " RESPONDING!"
        $found_devices += $ip
    } else {
        Write-Host " No response"
    }
}

Write-Host ""
Write-Host "Found responding devices: $($found_devices.Count)"

if ($found_devices.Count -gt 0) {
    Write-Host "Try SSH to these IPs:"
    foreach ($device in $found_devices) {
        Write-Host "  ssh pi@$device"
    }
} else {
    Write-Host "No Pi devices found."
    Write-Host "Check router admin at: http://192.168.254.162"
}

Write-Host ""
Write-Host "Ready to deploy music system once Pi is found!"