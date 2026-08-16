$ErrorActionPreference = 'Stop'
$verifier = Join-Path $PSScriptRoot 'kai_reminder_runtime_acceptance.ps1'
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "kai-reminder-verifier-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temp | Out-Null

function Write-Json {
    param([string]$Path, [object]$Value)
    $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Hash-Text {
    param([string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Invoke-Case {
    param([string]$Name, [string[]]$Arguments, [int]$ExpectedExit, [string]$ExpectedText)
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifier @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne $ExpectedExit) {
        throw "$Name exit $LASTEXITCODE; expected $ExpectedExit. Output: $output"
    }
    if ($output -notmatch [regex]::Escape($ExpectedText)) {
        throw "$Name did not contain '$ExpectedText'. Output: $output"
    }
    Write-Host "[PASS] $Name" -ForegroundColor Green
    return $output
}

try {
    $health = Join-Path $temp 'health.json'
    $stale = Join-Path $temp 'stale.json'
    $created = Join-Path $temp 'created.json'
    $delivered = Join-Path $temp 'delivered.json'
    $due = Join-Path $temp 'due.json'
    $pending = Join-Path $temp 'pending.json'
    $journal = Join-Path $temp 'operations'
    New-Item -ItemType Directory -Path $journal | Out-Null

    Write-Json $health @{ ok = $true; startedAt = '2026-08-08T12:00:00Z'; capabilities = @('presence', 'scheduled_commitments') }
    Write-Json $stale @{ ok = $true; startedAt = '2026-08-07T12:00:00Z'; capabilities = @('presence') }

    $text = "  TEXTMARKER-UNIQUE`nexact $([char]0x2014) reminder  "
    $textHash = Hash-Text $text
    $record = [ordered]@{
        commitmentId = 'brief018-test'
        personaId = 'truekai'
        text = $text
        dueAt = '2026-08-08T13:00:00.000Z'
        dueWallClock = '2026-08-08 16:00'
        dueWallOffsetMinutes = 180
        audience = 'work'
        createdAt = '2026-08-08T12:00:00.000Z'
        status = 'scheduled'
        nextEvaluationAt = '2026-08-08T13:00:00.000Z'
        outboundId = $null
        targetBodyId = $null
        dispatchedAt = $null
        acknowledgedAt = $null
    }
    Write-Json $created @{ commitments = @($record) }
    Write-Json $due @{ commitments = @() }
    Write-Json $pending @{ outbound = @() }

    Invoke-Case 'rebuilt-preflight' @('-Mode','Preflight','-HealthPath',$health,'-CommitmentsPath',$created) 0 '[PASS]' | Out-Null
    Invoke-Case 'stale-runtime' @('-Mode','Preflight','-HealthPath',$stale,'-CommitmentsPath',$created) 2 'stale' | Out-Null

    $createdOutput = Invoke-Case 'created' @('-Mode','Created','-HealthPath',$health,'-CommitmentsPath',$created,'-CommitmentId','brief018-test','-ExpectedTextSha256',$textHash) 0 '[PASS]'
    $fingerprint = [regex]::Match($createdOutput, '"promiseFingerprint":\s*"([0-9a-f]+)"').Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($fingerprint)) { throw 'created did not return a promise fingerprint' }
    Invoke-Case 'survived' @('-Mode','Survived','-HealthPath',$health,'-CommitmentsPath',$created,'-CommitmentId','brief018-test','-ExpectedTextSha256',$textHash,'-ExpectedPromiseFingerprint',$fingerprint) 0 'survived' | Out-Null
    Invoke-Case 'fingerprint-drift' @('-Mode','Survived','-HealthPath',$health,'-CommitmentsPath',$created,'-CommitmentId','brief018-test','-ExpectedTextSha256',$textHash,'-ExpectedPromiseFingerprint',('0' * 64)) 1 'changed across the restart' | Out-Null
    Invoke-Case 'text-drift' @('-Mode','Created','-HealthPath',$health,'-CommitmentsPath',$created,'-CommitmentId','brief018-test','-ExpectedTextSha256',('0' * 64)) 1 'byte-for-byte hash' | Out-Null

    $acked = [ordered]@{}
    foreach ($key in $record.Keys) { $acked[$key] = $record[$key] }
    $acked.status = 'acknowledged'
    $acked.outboundId = 'brief018-test-outbound'
    $acked.targetBodyId = 'desktop-body-1'
    $acked.dispatchedAt = '2026-08-08T13:00:01.000Z'
    $acked.acknowledgedAt = '2026-08-08T13:00:02.000Z'
    Write-Json $delivered @{ commitments = @($acked) }

    $dispatch = @{ at = '2026-08-08T13:00:01.000Z'; event = 'due_commitment_dispatched'; component = 'due_commitments'; severity = 'info'; details = @{ commitmentId = 'brief018-test'; bodyId = 'desktop-body-1'; reasonCode = 'work_body' } }
    $dispatch | ConvertTo-Json -Compress -Depth 8 | Set-Content -LiteralPath (Join-Path $journal 'kai-operations.jsonl') -Encoding UTF8
    $deliveredArgs = @('-Mode','Delivered','-HealthPath',$health,'-CommitmentsPath',$delivered,'-DueCommitmentsPath',$due,'-PendingOutboundPath',$pending,'-OperationsDirectory',$journal,'-SinceUtc','2026-08-08T12:30:00Z','-CommitmentId','brief018-test','-ExpectedTextSha256',$textHash,'-ExpectedPromiseFingerprint',$fingerprint,'-Marker','TEXTMARKER-UNIQUE')
    Invoke-Case 'delivered' $deliveredArgs 0 'exactly-once' | Out-Null

    @($dispatch, $dispatch) | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 8 } | Set-Content -LiteralPath (Join-Path $journal 'kai-operations.jsonl') -Encoding UTF8
    Invoke-Case 'duplicate-dispatch' $deliveredArgs 1 'one clean correlated dispatch' | Out-Null

    $leak = @{ at = '2026-08-08T13:00:01.500Z'; event = 'due_commitment_note'; component = 'due_commitments'; severity = 'info'; details = @{ commitmentId = 'brief018-test'; note = 'TEXTMARKER-UNIQUE' } }
    @($dispatch, $leak) | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 8 } | Set-Content -LiteralPath (Join-Path $journal 'kai-operations.jsonl') -Encoding UTF8
    Invoke-Case 'journal-text-leak' $deliveredArgs 1 'marker leaked' | Out-Null
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
