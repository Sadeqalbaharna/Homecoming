[CmdletBinding()]
param(
    [string]$LogPath = $(Join-Path $env:LOCALAPPDATA 'Homecoming\KaiCore\operations\kai-operations.jsonl'),
    [string]$RequestId,
    [ValidateSet('deliverNow', 'deferUntil', 'storeForLater')]
    [string]$ExpectedOutcome = 'deliverNow',
    [datetime]$SinceUtc = [datetime]::MinValue,
    [int]$WaitSeconds = 0,
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'

function Write-Result {
    param(
        [ValidateSet('PASS', 'FAIL', 'UNVERIFIED')]
        [string]$Verdict,
        [string]$Reason,
        [object]$Evidence,
        [int]$ExitCode
    )
    $result = [ordered]@{
        verdict = $Verdict
        reason = $Reason
        checkedAt = (Get-Date).ToUniversalTime().ToString('o')
        logPath = $LogPath
        expectedOutcome = $ExpectedOutcome
        evidence = $Evidence
    }
    $json = $result | ConvertTo-Json -Depth 8
    if ($EvidencePath) {
        $parent = Split-Path -Parent $EvidencePath
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Set-Content -LiteralPath $EvidencePath -Value $json -Encoding UTF8
    }
    $color = if ($Verdict -eq 'PASS') { 'Green' } elseif ($Verdict -eq 'FAIL') { 'Red' } else { 'Yellow' }
    Write-Host "[$Verdict] $Reason" -ForegroundColor $color
    Write-Output $json
    exit $ExitCode
}

function Read-JournalWindow {
    if (-not (Test-Path -LiteralPath $LogPath)) { return @() }
    $records = @()
    foreach ($line in Get-Content -LiteralPath $LogPath -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $record = $line | ConvertFrom-Json
            $at = [datetime]::Parse([string]$record.at).ToUniversalTime()
            if ($at -lt $SinceUtc.ToUniversalTime()) { continue }
            $records += [pscustomobject]@{
                parsed = $record
                raw = $line
                at = $at
            }
        }
        catch {
            # A malformed journal line is evidence failure, not a reason to print
            # the line (which may itself contain a credential).
            $records += [pscustomobject]@{
                parsed = $null
                raw = ''
                at = [datetime]::MinValue
            }
        }
    }
    return @($records)
}

function Has-SensitiveMaterial {
    param([string[]]$Lines)
    $patterns = @(
        '(?i)(?:[?&;,\s])(?:auth|authorization|token|access_token|refresh_token|id_token|api_key|apikey|key|signature|sig)=((?!\[REDACTED\])[^&#;,\s]+)',
        '(?i)Bearer\s+(?!\[REDACTED\])[A-Za-z0-9._~+\-/=]+',
        'AIza[0-9A-Za-z_-]{20,}',
        '(?:sk-ant-|sk-)[0-9A-Za-z_-]{16,}',
        'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'
    )
    foreach ($line in $Lines) {
        foreach ($pattern in $patterns) {
            if ($line -match $pattern) { return $true }
        }
    }
    return $false
}

$deadline = (Get-Date).AddSeconds([Math]::Max(0, $WaitSeconds))
do {
    $window = @(Read-JournalWindow)
    $valid = @($window | Where-Object { $null -ne $_.parsed })
    $received = @($valid | Where-Object { $_.parsed.event -eq 'attention_event_received' })
    if ($RequestId) {
        $received = @($received | Where-Object { $_.parsed.requestId -eq $RequestId })
    }
    if ($received.Count -gt 0) { break }
    if ((Get-Date) -ge $deadline) { break }
    Start-Sleep -Milliseconds 500
} while ($true)

if ($window.Count -eq 0) {
    Write-Result -Verdict UNVERIFIED -Reason 'No operations journal records exist in the requested window.' -Evidence @{} -ExitCode 2
}
if (@($window | Where-Object { $null -eq $_.parsed }).Count -gt 0) {
    Write-Result -Verdict FAIL -Reason 'The operations journal contains malformed JSON in the requested window.' -Evidence @{} -ExitCode 1
}
if ($received.Count -eq 0) {
    Write-Result -Verdict UNVERIFIED -Reason 'No Central Attention receipt was observed. Restart the rebuilt coordinator and trigger one proactive nudge.' -Evidence @{} -ExitCode 2
}

$receipt = $received | Sort-Object at -Descending | Select-Object -First 1
$id = [string]$receipt.parsed.requestId
$correlated = @($valid | Where-Object {
    $_.parsed.requestId -eq $id -or $_.parsed.details.eventId -eq $id
})

if (Has-SensitiveMaterial -Lines @($correlated.raw)) {
    Write-Result -Verdict FAIL -Reason 'Credential-like material appears in correlated operational evidence.' -Evidence @{ requestId = $id } -ExitCode 1
}

$decisions = @($correlated | Where-Object { $_.parsed.event -eq 'attention_decision' })
if ($decisions.Count -eq 0) {
    Write-Result -Verdict FAIL -Reason 'The received attention event has no correlated decision.' -Evidence @{ requestId = $id } -ExitCode 1
}

$matching = @($decisions | Where-Object { $_.parsed.details.outcome -eq $ExpectedOutcome })
if ($matching.Count -eq 0) {
    $seen = @($decisions | ForEach-Object { [string]$_.parsed.details.outcome } | Select-Object -Unique)
    Write-Result -Verdict FAIL -Reason 'The attention event never produced the expected outcome.' -Evidence @{ requestId = $id; outcomesSeen = $seen } -ExitCode 1
}

$decision = $matching | Sort-Object at -Descending | Select-Object -First 1
$bodyIds = @($decisions |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.parsed.details.bodyId) } |
    ForEach-Object { [string]$_.parsed.details.bodyId } |
    Select-Object -Unique)
if ($bodyIds.Count -gt 1) {
    Write-Result -Verdict FAIL -Reason 'One attention event selected more than one body.' -Evidence @{ requestId = $id; bodyIds = $bodyIds } -ExitCode 1
}

$evidence = [ordered]@{
    requestId = $id
    receivedAt = $receipt.at.ToString('o')
    decisionAt = $decision.at.ToString('o')
    outcome = [string]$decision.parsed.details.outcome
    reasonCode = [string]$decision.parsed.details.reasonCode
    bodyId = [string]$decision.parsed.details.bodyId
    notBefore = [string]$decision.parsed.details.notBefore
}

if ($ExpectedOutcome -eq 'deliverNow') {
    if ([string]::IsNullOrWhiteSpace($evidence.bodyId)) {
        Write-Result -Verdict FAIL -Reason 'deliverNow selected no exact body.' -Evidence $evidence -ExitCode 1
    }
    $delivered = @($correlated | Where-Object { $_.parsed.event -eq 'proactive_delivered' })
    if ($delivered.Count -ne 1) {
        Write-Result -Verdict FAIL -Reason "Expected exactly one proactive_delivered record; observed $($delivered.Count)." -Evidence $evidence -ExitCode 1
    }
    $terminalBody = [string]$delivered[0].parsed.details.bodyId
    if ($terminalBody -ne $evidence.bodyId) {
        Write-Result -Verdict FAIL -Reason 'Decision body and delivered body do not match.' -Evidence $evidence -ExitCode 1
    }
    $evidence.deliveredAt = $delivered[0].at.ToString('o')
}
elseif ($ExpectedOutcome -eq 'deferUntil') {
    if ([string]::IsNullOrWhiteSpace($evidence.notBefore)) {
        Write-Result -Verdict FAIL -Reason 'deferUntil has no retry instant.' -Evidence $evidence -ExitCode 1
    }
}
elseif (-not [string]::IsNullOrWhiteSpace($evidence.bodyId)) {
    Write-Result -Verdict FAIL -Reason 'storeForLater unexpectedly selected a body.' -Evidence $evidence -ExitCode 1
}

Write-Result -Verdict PASS -Reason 'Central Attention receipt, decision, one-body routing, and terminal evidence are coherent.' -Evidence $evidence -ExitCode 0
