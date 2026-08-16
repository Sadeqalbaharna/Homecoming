[CmdletBinding()]
param(
    [ValidateSet('Preflight', 'Created', 'Survived', 'Delivered')]
    [string]$Mode = 'Preflight',
    [string]$CoreBaseUri = 'http://127.0.0.1:8790',
    [string]$CommitmentId,
    [string]$ExpectedTextSha256,
    [string]$ExpectedPromiseFingerprint,
    [string]$Marker,
    [datetime]$SinceUtc = [datetime]::MinValue,
    [string]$OperationsDirectory = $(Join-Path $env:LOCALAPPDATA 'Homecoming\KaiCore\operations'),
    [string]$EvidencePath,
    # Fixture seams. Live acceptance leaves all four empty.
    [string]$HealthPath,
    [string]$CommitmentsPath,
    [string]$DueCommitmentsPath,
    [string]$PendingOutboundPath
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
        mode = $Mode
        reason = $Reason
        checkedAt = (Get-Date).ToUniversalTime().ToString('o')
        coreBaseUri = $CoreBaseUri
        evidence = $Evidence
    }
    $json = $result | ConvertTo-Json -Depth 10
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

function Read-JsonFile {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label fixture does not exist: $Path"
    }
    return Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json
}

function Read-Core {
    param([string]$RelativePath, [string]$FixturePath, [string]$Label)
    if ($FixturePath) { return Read-JsonFile -Path $FixturePath -Label $Label }
    $uri = "$($CoreBaseUri.TrimEnd('/'))$RelativePath"
    return Invoke-RestMethod -Method Get -Uri $uri -TimeoutSec 3
}

function Get-Sha256 {
    param([string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
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

function Promise-Fingerprint {
    param([object]$Record, [string]$TextHash)
    $parts = @(
        [string]$Record.commitmentId,
        [string]$Record.personaId,
        $TextHash,
        [string]$Record.dueAt,
        [string]$Record.dueWallClock,
        [string]$Record.dueWallOffsetMinutes,
        [string]$Record.audience,
        [string]$Record.createdAt,
        [string]$Record.nextEvaluationAt
    )
    return Get-Sha256 -Value ($parts -join [char]31)
}

try {
    $health = Read-Core -RelativePath '/health' -FixturePath $HealthPath -Label 'health'
} catch {
    Write-Result -Verdict UNVERIFIED -Reason 'Central Core health is unavailable.' -Evidence @{ error = $_.Exception.Message } -ExitCode 2
}

$capabilities = @($health.capabilities | ForEach-Object { [string]$_ })
if (-not $health.ok) {
    Write-Result -Verdict FAIL -Reason 'Core answered but did not report ok=true.' -Evidence @{ startedAt = $health.startedAt; capabilities = $capabilities } -ExitCode 1
}
if ($capabilities -notcontains 'scheduled_commitments') {
    Write-Result -Verdict UNVERIFIED -Reason 'The running Core is stale: scheduled_commitments is not advertised.' -Evidence @{ startedAt = $health.startedAt; capabilities = $capabilities } -ExitCode 2
}

try {
    $ledger = Read-Core -RelativePath '/v1/commitments' -FixturePath $CommitmentsPath -Label 'commitments'
} catch {
    Write-Result -Verdict UNVERIFIED -Reason 'The running Core does not expose the commitment ledger.' -Evidence @{ startedAt = $health.startedAt; error = $_.Exception.Message } -ExitCode 2
}
$records = @($ledger.commitments)

if ($Mode -eq 'Preflight') {
    $statusCounts = [ordered]@{}
    foreach ($record in $records) {
        $status = [string]$record.status
        if (-not $statusCounts.Contains($status)) { $statusCounts[$status] = 0 }
        $statusCounts[$status]++
    }
    Write-Result -Verdict PASS -Reason 'Rebuilt Core supports scheduled commitments.' -Evidence @{
        startedAt = [string]$health.startedAt
        capabilities = $capabilities
        commitmentCount = $records.Count
        statusCounts = $statusCounts
    } -ExitCode 0
}

if ([string]::IsNullOrWhiteSpace($CommitmentId) -or
    [string]::IsNullOrWhiteSpace($ExpectedTextSha256)) {
    Write-Result -Verdict FAIL -Reason 'CommitmentId and ExpectedTextSha256 are required for this mode.' -Evidence @{} -ExitCode 1
}

$matches = @($records | Where-Object { [string]$_.commitmentId -eq $CommitmentId })
if ($matches.Count -ne 1) {
    Write-Result -Verdict FAIL -Reason "Expected exactly one commitment with the requested ID; observed $($matches.Count)." -Evidence @{ commitmentId = $CommitmentId; matchCount = $matches.Count } -ExitCode 1
}
$record = $matches[0]
$textHash = Get-Sha256 -Value ([string]$record.text)
if ($textHash -ne $ExpectedTextSha256.ToLowerInvariant()) {
    Write-Result -Verdict FAIL -Reason 'Stored reminder text does not match the expected byte-for-byte hash.' -Evidence @{ commitmentId = $CommitmentId; actualTextSha256 = $textHash } -ExitCode 1
}
if ([string]$record.personaId -ne 'truekai' -or
    [string]$record.audience -ne 'work' -or
    [int]$record.dueWallOffsetMinutes -ne 180 -or
    [string]::IsNullOrWhiteSpace([string]$record.dueAt) -or
    [string]::IsNullOrWhiteSpace([string]$record.dueWallClock)) {
    Write-Result -Verdict FAIL -Reason 'Commitment identity, audience, or Bahrain provenance is invalid.' -Evidence @{ commitmentId = $CommitmentId } -ExitCode 1
}

$fingerprint = Promise-Fingerprint -Record $record -TextHash $textHash
if ($ExpectedPromiseFingerprint -and
    $fingerprint -ne $ExpectedPromiseFingerprint.ToLowerInvariant()) {
    Write-Result -Verdict FAIL -Reason 'The promise fields changed across the restart.' -Evidence @{ commitmentId = $CommitmentId; actualPromiseFingerprint = $fingerprint } -ExitCode 1
}

$baseEvidence = [ordered]@{
    coreStartedAt = [string]$health.startedAt
    commitmentId = $CommitmentId
    textSha256 = $textHash
    promiseFingerprint = $fingerprint
    status = [string]$record.status
    dueAt = [string]$record.dueAt
    dueWallClock = [string]$record.dueWallClock
    nextEvaluationAt = [string]$record.nextEvaluationAt
    outboundId = [string]$record.outboundId
    targetBodyId = [string]$record.targetBodyId
    dispatchedAt = [string]$record.dispatchedAt
    acknowledgedAt = [string]$record.acknowledgedAt
}

if ($Mode -eq 'Created' -or $Mode -eq 'Survived') {
    if ([string]$record.status -ne 'scheduled' -or
        -not [string]::IsNullOrWhiteSpace([string]$record.outboundId) -or
        [string]$record.nextEvaluationAt -ne [string]$record.dueAt) {
        Write-Result -Verdict FAIL -Reason 'The newly created/restarted promise is not one untouched scheduled commitment.' -Evidence $baseEvidence -ExitCode 1
    }
    $reason = if ($Mode -eq 'Created') { 'One exact durable commitment exists before restart.' } else { 'The exact promise survived restart unchanged.' }
    Write-Result -Verdict PASS -Reason $reason -Evidence $baseEvidence -ExitCode 0
}

$expectedOutbound = "$CommitmentId-outbound"
if ([string]$record.status -ne 'acknowledged' -or
    [string]$record.outboundId -ne $expectedOutbound -or
    [string]::IsNullOrWhiteSpace([string]$record.targetBodyId) -or
    [string]::IsNullOrWhiteSpace([string]$record.dispatchedAt) -or
    [string]::IsNullOrWhiteSpace([string]$record.acknowledgedAt)) {
    Write-Result -Verdict FAIL -Reason 'The commitment has not completed the dispatch-to-acknowledgement lifecycle.' -Evidence $baseEvidence -ExitCode 1
}

try {
    $due = Read-Core -RelativePath '/v1/commitments?due=true' -FixturePath $DueCommitmentsPath -Label 'due commitments'
    $dueMatches = @($due.commitments | Where-Object { [string]$_.commitmentId -eq $CommitmentId })
    $body = [uri]::EscapeDataString([string]$record.targetBodyId)
    $pending = Read-Core -RelativePath "/v1/outbound?toSurface=desktop&bodyId=$body" -FixturePath $PendingOutboundPath -Label 'pending outbound'
    $pendingMatches = @($pending.outbound | Where-Object { [string]$_.outboundId -eq $expectedOutbound })
} catch {
    Write-Result -Verdict UNVERIFIED -Reason 'Could not verify due and pending queues after acknowledgement.' -Evidence @{ commitmentId = $CommitmentId; error = $_.Exception.Message } -ExitCode 2
}
if ($dueMatches.Count -ne 0 -or $pendingMatches.Count -ne 0) {
    Write-Result -Verdict FAIL -Reason 'Acknowledged work remains visible in a due or pending queue.' -Evidence @{ commitmentId = $CommitmentId; dueCount = $dueMatches.Count; pendingCount = $pendingMatches.Count } -ExitCode 1
}

if (-not (Test-Path -LiteralPath $OperationsDirectory -PathType Container)) {
    Write-Result -Verdict UNVERIFIED -Reason 'Operations journal directory is unavailable.' -Evidence @{ commitmentId = $CommitmentId } -ExitCode 2
}
$journalFiles = @(Get-ChildItem -LiteralPath $OperationsDirectory -File |
    Where-Object { $_.Name -match '^kai-operations(?:\.\d+)?\.jsonl$' })
$window = @()
foreach ($file in $journalFiles) {
    foreach ($line in Get-Content -LiteralPath $file.FullName -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $parsed = $line | ConvertFrom-Json
            $at = [datetime]::Parse([string]$parsed.at).ToUniversalTime()
            if ($at -lt $SinceUtc.ToUniversalTime()) { continue }
            $window += [pscustomobject]@{ parsed = $parsed; raw = $line; at = $at }
        } catch {
            Write-Result -Verdict FAIL -Reason 'The operations journal contains malformed JSON in the acceptance window.' -Evidence @{ commitmentId = $CommitmentId; file = $file.Name } -ExitCode 1
        }
    }
}
$correlated = @($window | Where-Object { [string]$_.parsed.details.commitmentId -eq $CommitmentId })
if (Has-SensitiveMaterial -Lines @($correlated.raw)) {
    Write-Result -Verdict FAIL -Reason 'Credential-like material appears in correlated reminder evidence.' -Evidence @{ commitmentId = $CommitmentId } -ExitCode 1
}
if ($Marker -and @($correlated | Where-Object { $_.raw -like "*$Marker*" }).Count -gt 0) {
    Write-Result -Verdict FAIL -Reason 'Reminder text marker leaked into the content-free operations journal.' -Evidence @{ commitmentId = $CommitmentId } -ExitCode 1
}
$dispatches = @($correlated | Where-Object { [string]$_.parsed.event -eq 'due_commitment_dispatched' })
$failures = @($correlated | Where-Object {
    [string]$_.parsed.event -match '^due_commitment_.*(?:failed|refused|malformed|unreadable|route_without_body|undeliverable)'
})
if ($dispatches.Count -ne 1 -or $failures.Count -ne 0) {
    Write-Result -Verdict FAIL -Reason 'Expected one clean correlated dispatch transition.' -Evidence @{ commitmentId = $CommitmentId; dispatchCount = $dispatches.Count; failureCount = $failures.Count } -ExitCode 1
}

$baseEvidence.dispatchCount = 1
$baseEvidence.failureCount = 0
$baseEvidence.dueCount = 0
$baseEvidence.pendingCount = 0
Write-Result -Verdict PASS -Reason 'One reminder completed the durable exactly-once Core lifecycle.' -Evidence $baseEvidence -ExitCode 0
