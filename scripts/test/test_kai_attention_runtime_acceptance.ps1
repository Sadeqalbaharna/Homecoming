$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'kai_attention_runtime_acceptance.ps1'
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "kai-attention-verifier-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temp | Out-Null

function Write-Fixture {
    param([string]$Path, [object[]]$Records)
    $Records | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 8 } |
        Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-Case {
    param(
        [string]$Name,
        [object[]]$Records,
        [int]$ExpectedExit,
        [string]$ExpectedText
    )
    $path = Join-Path $temp "$Name.jsonl"
    Write-Fixture -Path $path -Records $Records
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script `
        -LogPath $path -SinceUtc '2026-08-08T09:00:00Z' 2>&1 | Out-String
    if ($LASTEXITCODE -ne $ExpectedExit) {
        throw "$Name exit $LASTEXITCODE; expected $ExpectedExit. Output: $output"
    }
    if ($output -notmatch [regex]::Escape($ExpectedText)) {
        throw "$Name did not contain '$ExpectedText'. Output: $output"
    }
    Write-Host "[PASS] $Name" -ForegroundColor Green
}

try {
    $at = '2026-08-08T09:30:00.000Z'
    $receipt = @{ at = $at; event = 'attention_event_received'; component = 'coordinator'; severity = 'info'; requestId = 'event-1'; details = @{ kind = 'proactiveNudge' } }
    $decision = @{ at = '2026-08-08T09:30:01.000Z'; event = 'attention_decision'; component = 'coordinator'; severity = 'info'; requestId = 'event-1'; details = @{ outcome = 'deliverNow'; reasonCode = 'foreground_friend_body'; eventId = 'event-1'; correlationId = 'event-1'; bodyId = 'messenger-phone'; remainsDurable = $false } }
    $delivered = @{ at = '2026-08-08T09:30:02.000Z'; event = 'proactive_delivered'; component = 'coordinator'; severity = 'info'; surface = 'messenger'; details = @{ eventId = 'event-1'; bodyId = 'messenger-phone'; route = 'foreground_friend_body' } }

    Invoke-Case -Name 'coherent-delivery' -Records @($receipt, $decision, $delivered) -ExpectedExit 0 -ExpectedText '[PASS]'
    Invoke-Case -Name 'missing-terminal' -Records @($receipt, $decision) -ExpectedExit 1 -ExpectedText 'exactly one proactive_delivered'

    $secondBody = @{ at = '2026-08-08T09:30:01.500Z'; event = 'attention_decision'; component = 'coordinator'; severity = 'info'; requestId = 'event-1'; details = @{ outcome = 'deliverNow'; reasonCode = 'foreground_friend_body'; eventId = 'event-1'; correlationId = 'event-1'; bodyId = 'desktop-main' } }
    Invoke-Case -Name 'fanout' -Records @($receipt, $decision, $secondBody, $delivered) -ExpectedExit 1 -ExpectedText 'more than one body'

    $secretDecision = @{ at = '2026-08-08T09:30:01.000Z'; event = 'attention_decision'; component = 'coordinator'; severity = 'info'; requestId = 'event-1'; details = @{ outcome = 'deliverNow'; reasonCode = 'foreground_friend_body'; eventId = 'event-1'; correlationId = 'event-1'; bodyId = 'messenger-phone'; error = 'https://example.test/x?auth=eyJhbGciOiJub25lIn0.eyJzdWIiOiJrYWkifQ.signature' } }
    Invoke-Case -Name 'credential-leak' -Records @($receipt, $secretDecision, $delivered) -ExpectedExit 1 -ExpectedText 'Credential-like material'

    Invoke-Case -Name 'no-receipt' -Records @(@{ at = $at; event = 'coordinator_ready'; component = 'coordinator'; severity = 'info' }) -ExpectedExit 2 -ExpectedText '[UNVERIFIED]'
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
