[CmdletBinding()]
param(
    [ValidateSet('Artifact', 'Preflight', 'Created', 'Survived', 'Delivered')]
    [string]$Mode = 'Preflight',
    [string]$CoreBaseUri = 'http://127.0.0.1:8790',
    [string]$CommitmentId,
    [string]$ExpectedTextSha256,
    [string]$ExpectedPromiseFingerprint,
    [string]$Marker,
    [string]$AcceptedArtifactPath,
    [string]$ExpectedBindingId,
    [string]$ExpectedRuntimeIdentityId,
    [string]$ExpectedPreviousRuntimeIdentityId,
    [string]$ExpectedJournalAnchorSha256,
    [long]$ExpectedJournalAnchorLength = 0,
    [datetime]$SinceUtc = [datetime]::MinValue,
    [string]$OperationsDirectory = $(Join-Path $env:LOCALAPPDATA 'Homecoming\KaiCore\operations'),
    [string]$EvidencePath,
    # Fixture seams. Live acceptance leaves all four empty.
    [string]$HealthPath,
    [string]$CommitmentsPath,
    [string]$DueCommitmentsPath,
    [string]$PendingOutboundPath,
    [string]$RuntimeIdentityPath
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

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-BytesSha256 {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-JournalAnchor {
    $current = Join-Path $OperationsDirectory 'kai-operations.jsonl'
    if (-not (Test-Path -LiteralPath $current -PathType Leaf)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($current)
    if ($bytes.Length -le 0) { return $null }
    return [ordered]@{ length = $bytes.Length; sha256 = Get-BytesSha256 $bytes }
}

function Test-JournalAnchorPreserved {
    param([System.IO.FileInfo[]]$Files)
    $script:journalAnchorCandidates = @()
    if ([string]::IsNullOrWhiteSpace($ExpectedJournalAnchorSha256) -or
        $ExpectedJournalAnchorSha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        $ExpectedJournalAnchorLength -le 0) { return $false }
    foreach ($file in $Files) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        if ($bytes.Length -lt $ExpectedJournalAnchorLength) { continue }
        $prefix = New-Object byte[] $ExpectedJournalAnchorLength
        [Array]::Copy($bytes, 0, $prefix, 0, $ExpectedJournalAnchorLength)
        $prefixHash = Get-BytesSha256 $prefix
        $script:journalAnchorCandidates += [ordered]@{ file = $file.Name; length = $bytes.Length; prefixSha256 = $prefixHash }
        if ($prefixHash -eq $ExpectedJournalAnchorSha256.ToLowerInvariant()) { return $true }
    }
    return $false
}

function Normalize-Path {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Read-AcceptedArtifact {
    if ([string]::IsNullOrWhiteSpace($AcceptedArtifactPath)) {
        Write-Result -Verdict FAIL -Reason 'AcceptedArtifactPath is required for every acceptance mode.' -Evidence @{} -ExitCode 1
    }
    if ([string]::IsNullOrWhiteSpace($ExpectedBindingId) -or $ExpectedBindingId -notmatch '^[0-9a-fA-F]{64}$') {
        Write-Result -Verdict FAIL -Reason 'ExpectedBindingId is required and must be an out-of-band SHA-256 pin.' -Evidence @{} -ExitCode 1
    }
    try { $manifest = Read-JsonFile -Path $AcceptedArtifactPath -Label 'accepted artifact' }
    catch { Write-Result -Verdict FAIL -Reason 'Accepted artifact manifest is unavailable or invalid.' -Evidence @{ error = $_.Exception.Message } -ExitCode 1 }
    if ([int]$manifest.schemaVersion -ne 1 -or
        [string]$manifest.bindingId -notmatch '^[0-9a-f]{64}$' -or
        [string]$manifest.sourceCommit -notmatch '^[0-9a-f]{40}$' -or
        [string]$manifest.sourceStatusSha256 -notmatch '^[0-9a-f]{64}$' -or
        [string]$manifest.buildCredentialProfile -ne 'empty-local-build-stub-v1' -or
        [string]$manifest.buildCredentialStubSha256 -notmatch '^[0-9a-f]{64}$' -or
        [string]$manifest.executableSha256 -notmatch '^[0-9a-f]{64}$' -or
        [string]$manifest.payloadSha256 -notmatch '^[0-9a-f]{64}$') {
        Write-Result -Verdict FAIL -Reason 'Accepted artifact manifest schema or hashes are invalid.' -Evidence @{} -ExitCode 1
    }
    $acceptedAt = [datetime]::MinValue
    $payloadAt = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$manifest.acceptedAtUtc, [ref]$acceptedAt) -or
        -not [datetime]::TryParse([string]$manifest.payloadLastWriteUtc, [ref]$payloadAt)) {
        Write-Result -Verdict FAIL -Reason 'Accepted artifact manifest timestamps are invalid.' -Evidence @{ bindingId = $manifest.bindingId } -ExitCode 1
    }
    $sourceAt = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$manifest.maxSourceLastWriteUtc, [ref]$sourceAt) -or
        $payloadAt.ToUniversalTime() -lt $sourceAt.ToUniversalTime()) {
        Write-Result -Verdict FAIL -Reason 'Accepted payload is older than a compiled source input.' -Evidence @{ bindingId = $manifest.bindingId } -ExitCode 1
    }
    $bindingKeys = @('schemaVersion','governedRoot','sourceCommit','sourceStatusSha256','maxSourceLastWriteUtc','buildCredentialProfile','buildCredentialStubSha256','executableRelativePath','executableSha256','executableLength','payloadRelativePath','payloadSha256','payloadLength','payloadLastWriteUtc','acceptedAtUtc')
    $canonical = @($bindingKeys | ForEach-Object { "$_=$($manifest.$_)" }) -join [char]31
    if ((Get-Sha256 -Value $canonical) -ne [string]$manifest.bindingId) {
        Write-Result -Verdict FAIL -Reason 'Accepted artifact manifest binding does not match its contents.' -Evidence @{} -ExitCode 1
    }
    if ([string]$manifest.bindingId -ne $ExpectedBindingId.ToLowerInvariant()) {
        Write-Result -Verdict FAIL -Reason 'Accepted artifact does not match the out-of-band binding ID.' -Evidence @{ actualBindingId = $manifest.bindingId } -ExitCode 1
    }
    return $manifest
}

function Assert-AcceptedArtifactFiles {
    param([object]$Manifest)
    $root = Normalize-Path ([string]$Manifest.governedRoot)
    $expectedExe = Normalize-Path (Join-Path $root ([string]$Manifest.executableRelativePath))
    $expectedPayload = Normalize-Path (Join-Path $root ([string]$Manifest.payloadRelativePath))
    $rootPrefix = "$root\"
    if (-not $expectedExe.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not $expectedPayload.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Result -Verdict FAIL -Reason 'Accepted artifact paths escape the governed root.' -Evidence @{ governedRoot = $root } -ExitCode 1
    }
    if (-not (Test-Path -LiteralPath $expectedExe -PathType Leaf) -or
        -not (Test-Path -LiteralPath $expectedPayload -PathType Leaf)) {
        Write-Result -Verdict FAIL -Reason 'Accepted artifact files are unavailable at the governed root.' -Evidence @{ governedRoot = $root } -ExitCode 1
    }
    $exe = Get-Item -LiteralPath $expectedExe
    $payload = Get-Item -LiteralPath $expectedPayload
    if ((Get-FileSha256 $expectedExe) -ne [string]$Manifest.executableSha256 -or
        (Get-FileSha256 $expectedPayload) -ne [string]$Manifest.payloadSha256 -or
        $exe.Length -ne [long]$Manifest.executableLength -or
        $payload.Length -ne [long]$Manifest.payloadLength) {
        Write-Result -Verdict FAIL -Reason 'Accepted artifact files no longer match the bound hashes or lengths.' -Evidence @{ bindingId = $Manifest.bindingId } -ExitCode 1
    }
    $accepted = [datetime]::Parse([string]$Manifest.acceptedAtUtc).ToUniversalTime()
    $payloadWrite = $payload.LastWriteTimeUtc.ToUniversalTime()
    if ($accepted -lt $payloadWrite) {
        Write-Result -Verdict FAIL -Reason 'Artifact binding predates the payload currently on disk.' -Evidence @{ acceptedAtUtc = $accepted.ToString('o'); payloadLastWriteUtc = $payloadWrite.ToString('o') } -ExitCode 1
    }
    return [ordered]@{
        bindingId = [string]$Manifest.bindingId
        governedRoot = $root
        sourceCommit = [string]$Manifest.sourceCommit
        executablePath = $expectedExe
        executableSha256 = [string]$Manifest.executableSha256
        payloadPath = $expectedPayload
        payloadSha256 = [string]$Manifest.payloadSha256
        payloadLastWriteUtc = $payloadWrite.ToString('o')
        acceptedAtUtc = $accepted.ToString('o')
    }
}

function Read-RuntimeIdentity {
    param([object]$Manifest)
    if ($RuntimeIdentityPath) { return Read-JsonFile -Path $RuntimeIdentityPath -Label 'runtime identity' }

    $uri = [uri]$CoreBaseUri
    if ($uri.Host -notin @('127.0.0.1', 'localhost', '::1')) {
        Write-Result -Verdict FAIL -Reason 'Runtime identity inspection is restricted to loopback Core.' -Evidence @{ coreBaseUri = $CoreBaseUri } -ExitCode 1
    }
    $port = if ($uri.Port -gt 0) { $uri.Port } else { 8790 }
    $firstOwners = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop | Select-Object -ExpandProperty OwningProcess -Unique)
    if ($firstOwners.Count -ne 1) {
        Write-Result -Verdict FAIL -Reason 'Expected exactly one Core port owner.' -Evidence @{ port = $port; ownerCount = $firstOwners.Count } -ExitCode 1
    }
    $core = Get-CimInstance Win32_Process -Filter "ProcessId=$($firstOwners[0])"
    if ($null -eq $core) {
        Write-Result -Verdict FAIL -Reason 'The Core port owner disappeared before identity inspection.' -Evidence @{ portOwnerPid = $firstOwners[0] } -ExitCode 1
    }
    $allKai = @(Get-CimInstance Win32_Process -Filter "Name='Kai.exe'")
    $watchdogs = @($allKai | Where-Object {
        [string]$_.CommandLine -match "--watchdog\s+--watch-pid=$($core.ProcessId)(?:\s|$)"
    })
    $exePath = Normalize-Path ([string]$core.ExecutablePath)
    $payloadPath = Join-Path (Split-Path -Parent $exePath) 'data\app.so'
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf) -or -not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
        Write-Result -Verdict FAIL -Reason 'The Core executable or Dart payload is unavailable.' -Evidence @{ corePid = $core.ProcessId; executablePath = $exePath } -ExitCode 1
    }
    $exeHash = Get-FileSha256 $exePath
    $payloadHash = Get-FileSha256 $payloadPath
    $secondOwners = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop | Select-Object -ExpandProperty OwningProcess -Unique)
    $governedRoot = Normalize-Path ([string]$Manifest.governedRoot)
    $governedPrefix = "$governedRoot\"
    $governedKai = @($allKai | Where-Object {
        (Normalize-Path ([string]$_.ExecutablePath)).StartsWith($governedPrefix, [StringComparison]::OrdinalIgnoreCase)
    })
    return [pscustomobject]@{
        observedPortOwnerPid = [int]$firstOwners[0]
        confirmedPortOwnerPid = if ($secondOwners.Count -eq 1) { [int]$secondOwners[0] } else { 0 }
        corePid = [int]$core.ProcessId
        coreParentPid = [int]$core.ParentProcessId
        coreCommandLine = [string]$core.CommandLine
        executablePath = $exePath
        executableSha256 = $exeHash
        payloadPath = Normalize-Path $payloadPath
        payloadSha256 = $payloadHash
        processCreationUtc = ([datetime]$core.CreationDate).ToUniversalTime().ToString('o')
        watchdogCount = $watchdogs.Count
        watchdogPid = if ($watchdogs.Count -eq 1) { [int]$watchdogs[0].ProcessId } else { 0 }
        watchdogParentPid = if ($watchdogs.Count -eq 1) { [int]$watchdogs[0].ParentProcessId } else { 0 }
        watchdogExecutablePath = if ($watchdogs.Count -eq 1) { Normalize-Path ([string]$watchdogs[0].ExecutablePath) } else { '' }
        kaiProcessCount = $allKai.Count
        governedKaiProcessCount = $governedKai.Count
        ungovernedKaiProcessCount = $allKai.Count - $governedKai.Count
    }
}

function Assert-RuntimeIdentity {
    param([object]$Manifest, [object]$Identity)
    $root = Normalize-Path ([string]$Manifest.governedRoot)
    $expectedExe = Normalize-Path (Join-Path $root ([string]$Manifest.executableRelativePath))
    $expectedPayload = Normalize-Path (Join-Path $root ([string]$Manifest.payloadRelativePath))
    $rootPrefix = "$root\"
    if (-not $expectedExe.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not $expectedPayload.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Result -Verdict FAIL -Reason 'Accepted artifact paths escape the governed root.' -Evidence @{ governedRoot = $root } -ExitCode 1
    }
    $creation = [datetime]::MinValue
    $accepted = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$Identity.processCreationUtc, [ref]$creation) -or
        -not [datetime]::TryParse([string]$Manifest.acceptedAtUtc, [ref]$accepted)) {
        Write-Result -Verdict FAIL -Reason 'Runtime identity contains an invalid process or binding timestamp.' -Evidence @{ bindingId = $Manifest.bindingId } -ExitCode 1
    }
    if ([int]$Identity.observedPortOwnerPid -le 0 -or
        [int]$Identity.observedPortOwnerPid -ne [int]$Identity.confirmedPortOwnerPid -or
        [int]$Identity.corePid -ne [int]$Identity.observedPortOwnerPid) {
        Write-Result -Verdict FAIL -Reason 'Core port ownership changed or does not match the inspected process.' -Evidence @{ observed = $Identity.observedPortOwnerPid; confirmed = $Identity.confirmedPortOwnerPid; corePid = $Identity.corePid } -ExitCode 1
    }
    if ([int]$Identity.kaiProcessCount -lt 2 -or
        [int]$Identity.governedKaiProcessCount -ne [int]$Identity.kaiProcessCount -or
        [int]$Identity.ungovernedKaiProcessCount -ne 0) {
        Write-Result -Verdict FAIL -Reason 'An ungoverned or incomplete Kai process set is present.' -Evidence @{ total = $Identity.kaiProcessCount; governed = $Identity.governedKaiProcessCount; ungoverned = $Identity.ungovernedKaiProcessCount } -ExitCode 1
    }
    if (-not ([string]$Identity.coreCommandLine).Contains('--coordinator-worker')) {
        Write-Result -Verdict FAIL -Reason 'The Core port owner is not the coordinator worker.' -Evidence @{ corePid = $Identity.corePid } -ExitCode 1
    }
    if ([int]$Identity.watchdogCount -ne 1 -or [int]$Identity.watchdogPid -le 0 -or
        [int]$Identity.watchdogParentPid -ne [int]$Identity.corePid -or
        -not (Normalize-Path ([string]$Identity.watchdogExecutablePath)).Equals($expectedExe, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Result -Verdict FAIL -Reason 'The coordinator does not have one matching watchdog.' -Evidence @{ corePid = $Identity.corePid; watchdogCount = $Identity.watchdogCount } -ExitCode 1
    }
    if (-not (Normalize-Path ([string]$Identity.executablePath)).Equals($expectedExe, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Normalize-Path ([string]$Identity.payloadPath)).Equals($expectedPayload, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Result -Verdict FAIL -Reason 'The running Core root does not match the accepted governed artifact.' -Evidence @{ expectedExecutable = $expectedExe; actualExecutable = $Identity.executablePath } -ExitCode 1
    }
    if ([string]$Identity.executableSha256 -ne [string]$Manifest.executableSha256 -or
        [string]$Identity.payloadSha256 -ne [string]$Manifest.payloadSha256) {
        Write-Result -Verdict FAIL -Reason 'The running executable or payload hash does not match the accepted artifact.' -Evidence @{ bindingId = $Manifest.bindingId } -ExitCode 1
    }
    if ($creation.ToUniversalTime() -le $accepted.ToUniversalTime()) {
        Write-Result -Verdict FAIL -Reason 'The Core process is not newer than the accepted artifact binding.' -Evidence @{ processCreationUtc = $Identity.processCreationUtc; acceptedAtUtc = $Manifest.acceptedAtUtc } -ExitCode 1
    }
    $runtimeId = Get-Sha256 -Value (@($Manifest.bindingId, $Identity.corePid, $creation.ToUniversalTime().ToString('o'), $Identity.watchdogPid) -join [char]31)
    if ($ExpectedRuntimeIdentityId -and $runtimeId -ne $ExpectedRuntimeIdentityId.ToLowerInvariant()) {
        Write-Result -Verdict FAIL -Reason 'Acceptance evidence belongs to a different runtime identity.' -Evidence @{ actualRuntimeIdentityId = $runtimeId } -ExitCode 1
    }
    if ($ExpectedPreviousRuntimeIdentityId -and $runtimeId -eq $ExpectedPreviousRuntimeIdentityId.ToLowerInvariant()) {
        Write-Result -Verdict FAIL -Reason 'The required restart did not produce a new runtime identity.' -Evidence @{ runtimeIdentityId = $runtimeId } -ExitCode 1
    }
    return [ordered]@{
        bindingId = [string]$Manifest.bindingId
        governedRoot = $root
        sourceCommit = [string]$Manifest.sourceCommit
        corePid = [int]$Identity.corePid
        watchdogPid = [int]$Identity.watchdogPid
        kaiProcessCount = [int]$Identity.kaiProcessCount
        executablePath = $expectedExe
        executableSha256 = [string]$Identity.executableSha256
        payloadSha256 = [string]$Identity.payloadSha256
        processCreationUtc = $creation.ToUniversalTime().ToString('o')
        acceptedAtUtc = $accepted.ToUniversalTime().ToString('o')
        runtimeIdentityId = $runtimeId
    }
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

if ($Mode -notin @('Artifact','Preflight') -and [string]::IsNullOrWhiteSpace($ExpectedRuntimeIdentityId)) {
    Write-Result -Verdict FAIL -Reason 'ExpectedRuntimeIdentityId is required after preflight.' -Evidence @{} -ExitCode 1
}
if ($Mode -eq 'Survived' -and [string]::IsNullOrWhiteSpace($ExpectedPreviousRuntimeIdentityId)) {
    Write-Result -Verdict FAIL -Reason 'ExpectedPreviousRuntimeIdentityId is required to prove restart.' -Evidence @{} -ExitCode 1
}

$acceptedArtifact = Read-AcceptedArtifact
if ($Mode -eq 'Artifact') {
    $artifactEvidence = Assert-AcceptedArtifactFiles -Manifest $acceptedArtifact
    Write-Result -Verdict PASS -Reason 'The governed acceptance artifact still matches its immutable binding.' -Evidence $artifactEvidence -ExitCode 0
}
try { $observedRuntime = Read-RuntimeIdentity -Manifest $acceptedArtifact }
catch {
    Write-Result -Verdict FAIL -Reason 'Runtime identity could not be collected.' -Evidence @{ error = $_.Exception.Message } -ExitCode 1
}
$runtimeEvidence = Assert-RuntimeIdentity -Manifest $acceptedArtifact -Identity $observedRuntime

try {
    $health = Read-Core -RelativePath '/health' -FixturePath $HealthPath -Label 'health'
} catch {
    Write-Result -Verdict UNVERIFIED -Reason 'Central Core health is unavailable.' -Evidence @{ error = $_.Exception.Message } -ExitCode 2
}

$capabilities = @($health.capabilities | ForEach-Object { [string]$_ })
if (-not $health.ok) {
    Write-Result -Verdict FAIL -Reason 'Core answered but did not report ok=true.' -Evidence @{ persistedStateStartedAt = $health.startedAt; capabilities = $capabilities; runtime = $runtimeEvidence } -ExitCode 1
}
if ($capabilities -notcontains 'scheduled_commitments') {
    Write-Result -Verdict UNVERIFIED -Reason 'The bound runtime does not advertise scheduled commitments.' -Evidence @{ persistedStateStartedAt = $health.startedAt; capabilities = $capabilities; runtime = $runtimeEvidence } -ExitCode 2
}

try {
    $ledger = Read-Core -RelativePath '/v1/commitments' -FixturePath $CommitmentsPath -Label 'commitments'
} catch {
    Write-Result -Verdict UNVERIFIED -Reason 'The running Core does not expose the commitment ledger.' -Evidence @{ persistedStateStartedAt = $health.startedAt; runtime = $runtimeEvidence; error = $_.Exception.Message } -ExitCode 2
}
$records = @($ledger.commitments)

if ($Mode -eq 'Preflight') {
    $journalAnchor = Get-JournalAnchor
    if ($null -eq $journalAnchor) {
        Write-Result -Verdict UNVERIFIED -Reason 'No non-empty operations journal anchor exists for the acceptance window.' -Evidence @{ runtime = $runtimeEvidence } -ExitCode 2
    }
    $statusCounts = [ordered]@{}
    foreach ($record in $records) {
        $status = [string]$record.status
        if (-not $statusCounts.Contains($status)) { $statusCounts[$status] = 0 }
        $statusCounts[$status]++
    }
    Write-Result -Verdict PASS -Reason 'Rebuilt Core supports scheduled commitments.' -Evidence @{
        persistedStateStartedAt = [string]$health.startedAt
        capabilities = $capabilities
        commitmentCount = $records.Count
        statusCounts = $statusCounts
        runtime = $runtimeEvidence
        journalAnchor = $journalAnchor
    } -ExitCode 0
}

if ([string]::IsNullOrWhiteSpace($CommitmentId) -or
    [string]::IsNullOrWhiteSpace($ExpectedTextSha256) -or
    [string]::IsNullOrWhiteSpace($Marker)) {
    Write-Result -Verdict FAIL -Reason 'CommitmentId, ExpectedTextSha256, and Marker are required for this mode.' -Evidence @{} -ExitCode 1
}

$idMatches = @($records | Where-Object { [string]$_.commitmentId -eq $CommitmentId })
if ($idMatches.Count -ne 1) {
    Write-Result -Verdict FAIL -Reason "Expected exactly one commitment with the requested ID; observed $($idMatches.Count)." -Evidence @{ commitmentId = $CommitmentId; matchCount = $idMatches.Count } -ExitCode 1
}
$record = $idMatches[0]
$markerMatches = @($records | Where-Object { ([string]$_.text).Contains($Marker) })
if ($markerMatches.Count -ne 1 -or [string]$markerMatches[0].commitmentId -ne $CommitmentId) {
    Write-Result -Verdict FAIL -Reason 'The acceptance run does not map to exactly one commitment.' -Evidence @{ commitmentId = $CommitmentId; runCommitmentCount = $markerMatches.Count } -ExitCode 1
}
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
if (($Mode -eq 'Survived' -or $Mode -eq 'Delivered') -and
    [string]::IsNullOrWhiteSpace($ExpectedPromiseFingerprint)) {
    Write-Result -Verdict FAIL -Reason 'ExpectedPromiseFingerprint is required after the restart.' -Evidence @{ commitmentId = $CommitmentId } -ExitCode 1
}
if ($ExpectedPromiseFingerprint -and
    $fingerprint -ne $ExpectedPromiseFingerprint.ToLowerInvariant()) {
    Write-Result -Verdict FAIL -Reason 'The promise fields changed across the restart.' -Evidence @{ commitmentId = $CommitmentId; actualPromiseFingerprint = $fingerprint } -ExitCode 1
}

$baseEvidence = [ordered]@{
    persistedStateStartedAt = [string]$health.startedAt
    runtime = $runtimeEvidence
    commitmentId = $CommitmentId
    runCommitmentCount = $markerMatches.Count
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
    $dueInstant = [datetime]::Parse([string]$record.dueAt).ToUniversalTime()
    $evaluationInstant = [datetime]::Parse([string]$record.nextEvaluationAt).ToUniversalTime()
    $dispatchInstant = [datetime]::Parse([string]$record.dispatchedAt).ToUniversalTime()
    $acknowledgedInstant = [datetime]::Parse([string]$record.acknowledgedAt).ToUniversalTime()
} catch {
    Write-Result -Verdict FAIL -Reason 'The delivered commitment contains an invalid lifecycle instant.' -Evidence $baseEvidence -ExitCode 1
}
if ($dispatchInstant -lt $dueInstant -or $dispatchInstant -lt $evaluationInstant) {
    Write-Result -Verdict FAIL -Reason 'The commitment dispatched before its authoritative due/evaluation instant.' -Evidence $baseEvidence -ExitCode 1
}
if ($acknowledgedInstant -lt $dispatchInstant) {
    Write-Result -Verdict FAIL -Reason 'The commitment acknowledgement predates dispatch.' -Evidence $baseEvidence -ExitCode 1
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
if (-not (Test-JournalAnchorPreserved -Files $journalFiles)) {
    Write-Result -Verdict FAIL -Reason 'The preflight journal anchor was lost before delivery; retention may have discarded acceptance evidence.' -Evidence @{ commitmentId = $CommitmentId; journalFileCount = $journalFiles.Count; expectedAnchorSha256 = $ExpectedJournalAnchorSha256; expectedAnchorLength = $ExpectedJournalAnchorLength; candidates = $script:journalAnchorCandidates } -ExitCode 1
}
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
if (Has-SensitiveMaterial -Lines @($window.raw)) {
    Write-Result -Verdict FAIL -Reason 'Credential-like material appears in the acceptance-window journal.' -Evidence @{ commitmentId = $CommitmentId } -ExitCode 1
}
if (@($window | Where-Object { $_.raw.Contains($Marker) }).Count -gt 0) {
    Write-Result -Verdict FAIL -Reason 'Reminder text marker leaked into the content-free operations journal.' -Evidence @{ commitmentId = $CommitmentId } -ExitCode 1
}
$dispatches = @($correlated | Where-Object { [string]$_.parsed.event -eq 'due_commitment_dispatched' })
$failures = @($correlated | Where-Object {
    [string]$_.parsed.event -match '^due_commitment_.*(?:failed|refused|malformed|unreadable|route_without_body|undeliverable)'
})
if ($dispatches.Count -ne 1 -or $failures.Count -ne 0) {
    Write-Result -Verdict FAIL -Reason 'Expected one clean correlated dispatch transition.' -Evidence @{ commitmentId = $CommitmentId; dispatchCount = $dispatches.Count; failureCount = $failures.Count } -ExitCode 1
}

$baseEvidence.dispatchCount = $dispatches.Count
$baseEvidence.failureCount = $failures.Count
$baseEvidence.dueCount = $dueMatches.Count
$baseEvidence.pendingCount = $pendingMatches.Count
Write-Result -Verdict PASS -Reason 'One reminder completed the durable exactly-once Core lifecycle.' -Evidence $baseEvidence -ExitCode 0
