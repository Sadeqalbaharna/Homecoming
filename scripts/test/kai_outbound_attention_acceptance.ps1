[CmdletBinding()]
param(
    [ValidateSet("vr", "ar")]
    [string]$Surface = "vr",
    [string]$CoreBaseUri = "http://127.0.0.1:8790",
    [string]$Text = "Central Kai found the way back to this body.",
    [int]$WaitSeconds = 20
)

$ErrorActionPreference = "Stop"
$base = $CoreBaseUri.TrimEnd('/')

try {
    $health = Invoke-RestMethod -Uri "$base/health" -Method Get
    if ($health.ok -ne $true -or @($health.capabilities) -notcontains "outbound_inbox") {
        throw "Kai Core is reachable but does not advertise outbound_inbox."
    }

    $presence = Invoke-RestMethod -Uri "$base/v1/presence" -Method Get
    $body = @($presence.devices) |
        Where-Object { $_.surface -eq $Surface -and $_.online -eq $true } |
        Sort-Object lastHeartbeatAt -Descending |
        Select-Object -First 1
    if ($null -eq $body) {
        throw "No live $Surface body is registered. Enter Play Mode and wait for its heartbeat."
    }

    $safeDeviceId = ([string]$body.deviceId) -replace '[^a-zA-Z0-9_-]', '-'
    $bodyId = "core-$Surface-$safeDeviceId"
    $outboundId = "acceptance-$Surface-$([Guid]::NewGuid().ToString('N'))"
    $expiresAt = (Get-Date).ToUniversalTime().AddMinutes(5).ToString('o')
    $payload = [ordered]@{
        outboundId = $outboundId
        kind = "direct_reply"
        fromSurface = "central"
        toSurface = $Surface
        targetBodyId = $bodyId
        conversationId = $(if ($Surface -eq "vr") { "vr_shack" } else { "ar" })
        correlationId = $outboundId
        text = $Text
        gesture = "wave"
        expiresAt = $expiresAt
    }

    Invoke-RestMethod -Uri "$base/v1/outbound" -Method Post `
        -ContentType "application/json" -Body ($payload | ConvertTo-Json -Depth 5) | Out-Null
    Write-Host "[QUEUED] $outboundId -> $bodyId" -ForegroundColor Cyan

    $deadline = (Get-Date).AddSeconds([Math]::Max(1, $WaitSeconds))
    do {
        Start-Sleep -Milliseconds 500
        $pending = Invoke-RestMethod -Uri "$base/v1/outbound?toSurface=$Surface&bodyId=$bodyId" -Method Get
        if (@($pending.outbound).Count -eq 0) {
            Write-Host "[PASS] $Surface accepted the outbound moment." -ForegroundColor Green
            exit 0
        }
    } while ((Get-Date) -lt $deadline)

    throw "The envelope is still pending after $WaitSeconds seconds. Check the Unity Console and KaiBridgeController."
}
catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
