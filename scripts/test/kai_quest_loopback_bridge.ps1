[CmdletBinding()]
param(
    [string]$Serial = "",
    [switch]$IncludeAr,
    [switch]$Remove
)

$ErrorActionPreference = "Stop"

function Resolve-Adb {
    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"),
        "C:\Program Files\Unity\Hub\Editor\6000.5.6f1\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\platform-tools\adb.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw "adb.exe was not found. Install Android platform-tools or Unity Android Build Support."
}

function Invoke-Adb {
    param(
        [Parameter(Mandatory = $true)][string]$Adb,
        [Parameter(Mandatory = $true)][string]$Device,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $output = & $Adb -s $Device @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed: $($output -join ' ')"
    }
    return $output
}

$adb = Resolve-Adb
$deviceRows = & $adb devices
if ($LASTEXITCODE -ne 0) { throw "adb devices failed." }
$devices = @($deviceRows | Select-Object -Skip 1 | ForEach-Object {
    if ($_ -match '^([^\s]+)\s+device$') { $matches[1] }
})

if ([string]::IsNullOrWhiteSpace($Serial)) {
    $questDevices = @()
    foreach ($device in $devices) {
        $manufacturer = (Invoke-Adb -Adb $adb -Device $device -Arguments @("shell", "getprop", "ro.product.manufacturer")) -join ""
        $model = (Invoke-Adb -Adb $adb -Device $device -Arguments @("shell", "getprop", "ro.product.model")) -join ""
        if ("$manufacturer $model" -match '(?i)meta|oculus|quest') {
            $questDevices += [pscustomobject]@{
                Serial = $device
                Manufacturer = $manufacturer.Trim()
                Model = $model.Trim()
            }
        }
    }
    if ($questDevices.Count -eq 0) {
        throw "No authorized Meta Quest was found. Connect it, enable USB debugging, and accept the headset prompt."
    }
    if ($questDevices.Count -gt 1) {
        $choices = ($questDevices | ForEach-Object { "$($_.Serial) ($($_.Model))" }) -join ', '
        throw "Multiple Quest devices are connected: $choices. Rerun with -Serial."
    }
    $selected = $questDevices[0]
    $Serial = $selected.Serial
    Write-Host "Quest: $($selected.Model) [$Serial]" -ForegroundColor Cyan
} elseif ($devices -notcontains $Serial) {
    throw "Device '$Serial' is not connected and authorized."
}

$ports = @(8787, 8790)
if ($IncludeAr) { $ports += 8788 }

if ($Remove) {
    foreach ($port in $ports) {
        Invoke-Adb -Adb $adb -Device $Serial -Arguments @("reverse", "--remove", "tcp:$port") | Out-Null
        Write-Host "[REMOVED] Quest tcp:$port reversal" -ForegroundColor Yellow
    }
    exit 0
}

$requiredHealth = @(
    [pscustomobject]@{ Port = 8787; Name = "VR embodiment gateway" },
    [pscustomobject]@{ Port = 8790; Name = "Kai Core" }
)
if ($IncludeAr) {
    $requiredHealth += [pscustomobject]@{ Port = 8788; Name = "AR embodiment gateway" }
}

foreach ($service in $requiredHealth) {
    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:$($service.Port)/health" -TimeoutSec 3
        if ($health.ok -ne $true) { throw "health returned ok=$($health.ok)" }
    } catch {
        throw "$($service.Name) is not healthy on host port $($service.Port): $($_.Exception.Message)"
    }
}

foreach ($port in $ports) {
    Invoke-Adb -Adb $adb -Device $Serial -Arguments @("reverse", "tcp:$port", "tcp:$port") | Out-Null
}

$reversals = @(Invoke-Adb -Adb $adb -Device $Serial -Arguments @("reverse", "--list"))
foreach ($port in $ports) {
    if (-not ($reversals -match "tcp:$port\s+tcp:$port")) {
        throw "Port reversal for tcp:$port was not listed after setup."
    }
    Write-Host "[PASS] Quest 127.0.0.1:$port -> laptop 127.0.0.1:$port" -ForegroundColor Green
}

Write-Host "Loopback bridge ready for this USB debugging session." -ForegroundColor Cyan
Write-Host "This proves tethered device transport only; it does not prove untethered or always-on transport." -ForegroundColor Yellow

