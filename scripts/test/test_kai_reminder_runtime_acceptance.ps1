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

function Set-ManifestBinding {
    param([object]$Value)
    $keys = @('schemaVersion','governedRoot','sourceCommit','sourceStatusSha256','maxSourceLastWriteUtc')
    if ([int]$Value.schemaVersion -eq 2) { $keys += @('maxDartSourceLastWriteUtc','maxNativeSourceLastWriteUtc') }
    $keys += @('buildCredentialProfile','buildCredentialStubSha256','executableRelativePath','executableSha256','executableLength','payloadRelativePath','payloadSha256','payloadLength','payloadLastWriteUtc','acceptedAtUtc')
    $canonical = @($keys | ForEach-Object { "$_=$($Value.$_)" }) -join [char]31
    $binding = Hash-Text $canonical
    if ($Value -is [System.Collections.IDictionary]) { $null = ($Value.bindingId = $binding) }
    else { $null = ($Value.bindingId = $binding) }
    return ,$Value
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
    $capableButOld = Join-Path $temp 'capable-but-old.json'
    $created = Join-Path $temp 'created.json'
    $delivered = Join-Path $temp 'delivered.json'
    $due = Join-Path $temp 'due.json'
    $pending = Join-Path $temp 'pending.json'
    $manifest = Join-Path $temp 'accepted-artifact.json'
    $identity = Join-Path $temp 'runtime-identity.json'
    $journal = Join-Path $temp 'operations'
    New-Item -ItemType Directory -Path $journal | Out-Null
    $anchor = @{ at = '2026-08-08T12:00:00.000Z'; event = 'acceptance_anchor'; component = 'coordinator'; severity = 'info' }
    $anchorLine = $anchor | ConvertTo-Json -Compress -Depth 8
    $anchorLine | Set-Content -LiteralPath (Join-Path $journal 'kai-operations.jsonl') -Encoding UTF8

    # Deliberately ancient persisted state time: a valid runtime identity must
    # pass independently of /health.startedAt.
    Write-Json $health @{ ok = $true; startedAt = '2026-08-01T12:00:00Z'; capabilities = @('presence', 'scheduled_commitments') }
    Write-Json $stale @{ ok = $true; startedAt = '2026-08-07T12:00:00Z'; capabilities = @('presence') }
    $acceptedRoot = 'C:\accepted\homecoming_app'
    $exeHash = '1' * 64
    $payloadHash = '2' * 64
    $manifestValue = [ordered]@{
        schemaVersion = 2
        governedRoot = $acceptedRoot
        sourceCommit = 'b' * 40
        sourceStatusSha256 = 'c' * 64
        maxSourceLastWriteUtc = '2026-08-08T09:00:00Z'
        maxDartSourceLastWriteUtc = '2026-08-08T09:00:00Z'
        maxNativeSourceLastWriteUtc = '2026-08-08T09:00:00Z'
        buildCredentialProfile = 'empty-local-build-stub-v1'
        buildCredentialStubSha256 = 'd' * 64
        executableRelativePath = 'build\windows\x64\runner\Release\Kai.exe'
        executableSha256 = $exeHash
        executableLength = 100
        payloadRelativePath = 'build\windows\x64\runner\Release\data\app.so'
        payloadSha256 = $payloadHash
        payloadLength = 200
        payloadLastWriteUtc = '2026-08-08T10:00:00Z'
        acceptedAtUtc = '2026-08-08T11:00:00Z'
    }
    $manifestValue = Set-ManifestBinding $manifestValue
    Write-Json $manifest $manifestValue
    $runtime = [ordered]@{
        observedPortOwnerPid = 4100
        confirmedPortOwnerPid = 4100
        corePid = 4100
        coreParentPid = 4000
        coreCommandLine = '"C:\accepted\homecoming_app\build\windows\x64\runner\Release\Kai.exe" --coordinator-worker --background'
        executablePath = 'C:\accepted\homecoming_app\build\windows\x64\runner\Release\Kai.exe'
        executableSha256 = $exeHash
        payloadPath = 'C:\accepted\homecoming_app\build\windows\x64\runner\Release\data\app.so'
        payloadSha256 = $payloadHash
        processCreationUtc = '2026-08-08T12:00:00Z'
        watchdogCount = 1
        watchdogPid = 4200
        watchdogParentPid = 4100
        watchdogExecutablePath = 'C:\accepted\homecoming_app\build\windows\x64\runner\Release\Kai.exe'
        kaiProcessCount = 2
        governedKaiProcessCount = 2
        ungovernedKaiProcessCount = 0
    }
    Write-Json $identity $runtime

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

    $boundary = @('-AcceptedArtifactPath',$manifest,'-ExpectedBindingId',$manifestValue.bindingId,'-RuntimeIdentityPath',$identity)
    $preflightOutput = Invoke-Case 'persistent-startedAt-ignored' (@('-Mode','Preflight','-HealthPath',$health,'-CommitmentsPath',$created,'-OperationsDirectory',$journal) + $boundary) 0 '[PASS]'
    $preflightJson = $preflightOutput.Substring($preflightOutput.IndexOf('{')) | ConvertFrom-Json
    $runtimeId = [string]$preflightJson.evidence.runtime.runtimeIdentityId
    if ([string]::IsNullOrWhiteSpace($runtimeId)) { throw 'preflight did not return a runtime identity id' }
    $journalAnchorHash = [string]$preflightJson.evidence.journalAnchor.sha256
    $journalAnchorLength = [string]$preflightJson.evidence.journalAnchor.length
    if ([string]::IsNullOrWhiteSpace($journalAnchorHash) -or [string]::IsNullOrWhiteSpace($journalAnchorLength)) { throw 'preflight did not return a journal anchor' }
    Invoke-Case 'missing-artifact-binding' @('-Mode','Preflight','-HealthPath',$health,'-CommitmentsPath',$created,'-RuntimeIdentityPath',$identity) 1 'AcceptedArtifactPath is required' | Out-Null
    Invoke-Case 'missing-out-of-band-binding' @('-Mode','Preflight','-HealthPath',$health,'-CommitmentsPath',$created,'-AcceptedArtifactPath',$manifest,'-RuntimeIdentityPath',$identity) 1 'ExpectedBindingId is required' | Out-Null
    Invoke-Case 'missing-capability' (@('-Mode','Preflight','-HealthPath',$stale,'-CommitmentsPath',$created) + $boundary) 2 'does not advertise' | Out-Null

    $wrongRoot = Join-Path $temp 'wrong-root.json'
    $variant = $runtime | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $variant.executablePath = 'C:\other\Kai.exe'
    Write-Json $wrongRoot $variant
    Invoke-Case 'wrong-root' (@('-Mode','Preflight','-HealthPath',$health,'-CommitmentsPath',$created,'-AcceptedArtifactPath',$manifest,'-ExpectedBindingId',$manifestValue.bindingId,'-RuntimeIdentityPath',$wrongRoot)) 1 'root does not match' | Out-Null

    $wrongPayload = Join-Path $temp 'wrong-payload.json'
    $variant = $runtime | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $variant.payloadSha256 = '9' * 64
    Write-Json $wrongPayload $variant
    Invoke-Case 'wrong-payload' (@('-Mode','Preflight','-HealthPath',$health,'-CommitmentsPath',$created,'-AcceptedArtifactPath',$manifest,'-ExpectedBindingId',$manifestValue.bindingId,'-RuntimeIdentityPath',$wrongPayload)) 1 'hash does not match' | Out-Null

    $changedOwner = Join-Path $temp 'changed-owner.json'
    $variant = $runtime | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $variant.confirmedPortOwnerPid = 4101
    Write-Json $changedOwner $variant
    Invoke-Case 'pid-reuse-port-owner-change' (@('-Mode','Preflight','-HealthPath',$health,'-CommitmentsPath',$created,'-AcceptedArtifactPath',$manifest,'-ExpectedBindingId',$manifestValue.bindingId,'-RuntimeIdentityPath',$changedOwner)) 1 'port ownership changed' | Out-Null

    $staleArtifact = Join-Path $temp 'stale-artifact.json'
    $variant = $runtime | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $variant.processCreationUtc = '2026-08-08T10:59:59Z'
    Write-Json $staleArtifact $variant
    Invoke-Case 'stale-artifact-process' (@('-Mode','Preflight','-HealthPath',$health,'-CommitmentsPath',$created,'-AcceptedArtifactPath',$manifest,'-ExpectedBindingId',$manifestValue.bindingId,'-RuntimeIdentityPath',$staleArtifact)) 1 'not newer than' | Out-Null

    $wrongWatchdog = Join-Path $temp 'wrong-watchdog.json'
    $variant = $runtime | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $variant.watchdogCount = 0
    $variant.watchdogPid = 0
    Write-Json $wrongWatchdog $variant
    Invoke-Case 'missing-watchdog-relationship' (@('-Mode','Preflight','-HealthPath',$health,'-CommitmentsPath',$created,'-AcceptedArtifactPath',$manifest,'-ExpectedBindingId',$manifestValue.bindingId,'-RuntimeIdentityPath',$wrongWatchdog)) 1 'one matching watchdog' | Out-Null

    Invoke-Case 'cross-run-evidence' (@('-Mode','Preflight','-HealthPath',$health,'-CommitmentsPath',$created,'-ExpectedRuntimeIdentityId',('0' * 64)) + $boundary) 1 'different runtime identity' | Out-Null

    $ungoverned = Join-Path $temp 'ungoverned-kai.json'
    $variant = $runtime | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $variant.kaiProcessCount = 3
    $variant.governedKaiProcessCount = 2
    $variant.ungovernedKaiProcessCount = 1
    Write-Json $ungoverned $variant
    Invoke-Case 'ungoverned-second-kai' (@('-Mode','Preflight','-HealthPath',$health,'-CommitmentsPath',$created,'-AcceptedArtifactPath',$manifest,'-ExpectedBindingId',$manifestValue.bindingId,'-RuntimeIdentityPath',$ungoverned)) 1 'ungoverned or incomplete' | Out-Null

    $tamperedManifest = Join-Path $temp 'tampered-manifest.json'
    $manifestVariant = $manifestValue | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $manifestVariant.governedRoot = 'C:\other\homecoming_app'
    $manifestVariant = Set-ManifestBinding $manifestVariant
    Write-Json $tamperedManifest $manifestVariant
    Invoke-Case 'self-consistent-manifest-tamper' @('-Mode','Preflight','-HealthPath',$health,'-CommitmentsPath',$created,'-AcceptedArtifactPath',$tamperedManifest,'-ExpectedBindingId',$manifestValue.bindingId,'-RuntimeIdentityPath',$identity) 1 'out-of-band binding ID' | Out-Null

    $staleSourceManifest = Join-Path $temp 'stale-source-manifest.json'
    $manifestVariant = $manifestValue | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $manifestVariant.maxDartSourceLastWriteUtc = '2026-08-08T10:00:01Z'
    $manifestVariant = Set-ManifestBinding $manifestVariant
    Write-Json $staleSourceManifest $manifestVariant
    Invoke-Case 'payload-older-than-source' @('-Mode','Preflight','-HealthPath',$health,'-CommitmentsPath',$created,'-AcceptedArtifactPath',$staleSourceManifest,'-ExpectedBindingId',$manifestVariant.bindingId,'-RuntimeIdentityPath',$identity) 1 'older than a Dart build input' | Out-Null

    $createdArgs = @('-Mode','Created','-HealthPath',$health,'-CommitmentsPath',$created,'-CommitmentId','brief018-test','-ExpectedTextSha256',$textHash,'-Marker','TEXTMARKER-UNIQUE','-ExpectedRuntimeIdentityId',$runtimeId) + $boundary
    $createdOutput = Invoke-Case 'created' $createdArgs 0 '[PASS]'
    $fingerprint = [regex]::Match($createdOutput, '"promiseFingerprint":\s*"([0-9a-f]+)"').Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($fingerprint)) { throw 'created did not return a promise fingerprint' }
    $survivedArgs = @('-Mode','Survived','-HealthPath',$health,'-CommitmentsPath',$created,'-CommitmentId','brief018-test','-ExpectedTextSha256',$textHash,'-ExpectedPromiseFingerprint',$fingerprint,'-Marker','TEXTMARKER-UNIQUE','-ExpectedRuntimeIdentityId',$runtimeId,'-ExpectedPreviousRuntimeIdentityId',('f' * 64)) + $boundary
    Invoke-Case 'survived' $survivedArgs 0 'survived' | Out-Null
    Invoke-Case 'restart-identity-unchanged' (@('-Mode','Survived','-HealthPath',$health,'-CommitmentsPath',$created,'-CommitmentId','brief018-test','-ExpectedTextSha256',$textHash,'-ExpectedPromiseFingerprint',$fingerprint,'-Marker','TEXTMARKER-UNIQUE','-ExpectedRuntimeIdentityId',$runtimeId,'-ExpectedPreviousRuntimeIdentityId',$runtimeId) + $boundary) 1 'did not produce a new runtime identity' | Out-Null
    Invoke-Case 'missing-survival-fingerprint' (@('-Mode','Survived','-HealthPath',$health,'-CommitmentsPath',$created,'-CommitmentId','brief018-test','-ExpectedTextSha256',$textHash,'-Marker','TEXTMARKER-UNIQUE','-ExpectedRuntimeIdentityId',$runtimeId,'-ExpectedPreviousRuntimeIdentityId',('f' * 64)) + $boundary) 1 'required after the restart' | Out-Null
    Invoke-Case 'fingerprint-drift' (@('-Mode','Survived','-HealthPath',$health,'-CommitmentsPath',$created,'-CommitmentId','brief018-test','-ExpectedTextSha256',$textHash,'-ExpectedPromiseFingerprint',('0' * 64),'-Marker','TEXTMARKER-UNIQUE','-ExpectedRuntimeIdentityId',$runtimeId,'-ExpectedPreviousRuntimeIdentityId',('f' * 64)) + $boundary) 1 'changed across the restart' | Out-Null
    Invoke-Case 'text-drift' (@('-Mode','Created','-HealthPath',$health,'-CommitmentsPath',$created,'-CommitmentId','brief018-test','-ExpectedTextSha256',('0' * 64),'-Marker','TEXTMARKER-UNIQUE','-ExpectedRuntimeIdentityId',$runtimeId) + $boundary) 1 'byte-for-byte hash' | Out-Null

    $duplicateRecord = [ordered]@{}
    foreach ($key in $record.Keys) { $duplicateRecord[$key] = $record[$key] }
    $duplicateRecord.commitmentId = 'brief018-duplicate'
    $duplicates = Join-Path $temp 'duplicates.json'
    Write-Json $duplicates @{ commitments = @($record, $duplicateRecord) }
    Invoke-Case 'duplicate-run-commitment' (@('-Mode','Created','-HealthPath',$health,'-CommitmentsPath',$duplicates,'-CommitmentId','brief018-test','-ExpectedTextSha256',$textHash,'-Marker','TEXTMARKER-UNIQUE','-ExpectedRuntimeIdentityId',$runtimeId) + $boundary) 1 'does not map to exactly one' | Out-Null

    $acked = [ordered]@{}
    foreach ($key in $record.Keys) { $acked[$key] = $record[$key] }
    $acked.status = 'acknowledged'
    $acked.outboundId = 'brief018-test-outbound'
    $acked.targetBodyId = 'desktop-body-1'
    $acked.dispatchedAt = '2026-08-08T13:00:01.000Z'
    $acked.acknowledgedAt = '2026-08-08T13:00:02.000Z'
    Write-Json $delivered @{ commitments = @($acked) }

    $dispatch = @{ at = '2026-08-08T13:00:01.000Z'; event = 'due_commitment_dispatched'; component = 'due_commitments'; severity = 'info'; details = @{ commitmentId = 'brief018-test'; bodyId = 'desktop-body-1'; reasonCode = 'work_body' } }
    @($anchorLine, ($dispatch | ConvertTo-Json -Compress -Depth 8)) | Set-Content -LiteralPath (Join-Path $journal 'kai-operations.jsonl') -Encoding UTF8
    $deliveredArgs = @('-Mode','Delivered','-HealthPath',$health,'-CommitmentsPath',$delivered,'-DueCommitmentsPath',$due,'-PendingOutboundPath',$pending,'-OperationsDirectory',$journal,'-SinceUtc','2026-08-08T12:30:00Z','-CommitmentId','brief018-test','-ExpectedTextSha256',$textHash,'-ExpectedPromiseFingerprint',$fingerprint,'-Marker','TEXTMARKER-UNIQUE','-ExpectedRuntimeIdentityId',$runtimeId,'-ExpectedJournalAnchorSha256',$journalAnchorHash,'-ExpectedJournalAnchorLength',$journalAnchorLength) + $boundary
    Invoke-Case 'delivered' $deliveredArgs 0 'exactly-once' | Out-Null

    $lostJournal = Join-Path $temp 'lost-anchor-operations'
    New-Item -ItemType Directory -Path $lostJournal | Out-Null
    $dispatch | ConvertTo-Json -Compress -Depth 8 | Set-Content -LiteralPath (Join-Path $lostJournal 'kai-operations.jsonl') -Encoding UTF8
    $lostAnchorArgs = @($deliveredArgs)
    $lostAnchorArgs[[array]::IndexOf($lostAnchorArgs, $journal)] = $lostJournal
    Invoke-Case 'journal-anchor-lost' $lostAnchorArgs 1 'journal anchor was lost' | Out-Null

    $early = [ordered]@{}
    foreach ($key in $acked.Keys) { $early[$key] = $acked[$key] }
    $early.dispatchedAt = '2026-08-08T12:59:59.000Z'
    $earlyPath = Join-Path $temp 'early.json'
    Write-Json $earlyPath @{ commitments = @($early) }
    $earlyArgs = @($deliveredArgs)
    $earlyArgs[[array]::IndexOf($earlyArgs, $delivered)] = $earlyPath
    Invoke-Case 'early-dispatch' $earlyArgs 1 'before its authoritative' | Out-Null

    $reversed = [ordered]@{}
    foreach ($key in $acked.Keys) { $reversed[$key] = $acked[$key] }
    $reversed.acknowledgedAt = '2026-08-08T13:00:00.500Z'
    $reversedPath = Join-Path $temp 'reversed.json'
    Write-Json $reversedPath @{ commitments = @($reversed) }
    $reversedArgs = @($deliveredArgs)
    $reversedArgs[[array]::IndexOf($reversedArgs, $delivered)] = $reversedPath
    Invoke-Case 'ack-before-dispatch' $reversedArgs 1 'predates dispatch' | Out-Null

    $malformed = [ordered]@{}
    foreach ($key in $acked.Keys) { $malformed[$key] = $acked[$key] }
    $malformed.acknowledgedAt = 'not-an-instant'
    $malformedPath = Join-Path $temp 'malformed.json'
    Write-Json $malformedPath @{ commitments = @($malformed) }
    $malformedArgs = @($deliveredArgs)
    $malformedArgs[[array]::IndexOf($malformedArgs, $delivered)] = $malformedPath
    Invoke-Case 'malformed-lifecycle-instant' $malformedArgs 1 'invalid lifecycle instant' | Out-Null

    @($anchorLine, ($dispatch | ConvertTo-Json -Compress -Depth 8), ($dispatch | ConvertTo-Json -Compress -Depth 8)) | Set-Content -LiteralPath (Join-Path $journal 'kai-operations.jsonl') -Encoding UTF8
    Invoke-Case 'duplicate-dispatch' $deliveredArgs 1 'one clean correlated dispatch' | Out-Null

    $leak = @{ at = '2026-08-08T13:00:01.500Z'; event = 'due_commitment_note'; component = 'due_commitments'; severity = 'info'; details = @{ commitmentId = 'brief018-test'; note = 'TEXTMARKER-UNIQUE' } }
    @($anchorLine, ($dispatch | ConvertTo-Json -Compress -Depth 8), ($leak | ConvertTo-Json -Compress -Depth 8)) | Set-Content -LiteralPath (Join-Path $journal 'kai-operations.jsonl') -Encoding UTF8
    Invoke-Case 'journal-text-leak' $deliveredArgs 1 'marker leaked' | Out-Null

    $uncorrelatedLeak = @{ at = '2026-08-08T13:00:01.500Z'; event = 'unrelated_event'; component = 'other'; severity = 'info'; details = @{ commitmentId = 'other'; note = 'TEXTMARKER-UNIQUE' } }
    @($anchorLine, ($dispatch | ConvertTo-Json -Compress -Depth 8), ($uncorrelatedLeak | ConvertTo-Json -Compress -Depth 8)) | Set-Content -LiteralPath (Join-Path $journal 'kai-operations.jsonl') -Encoding UTF8
    Invoke-Case 'uncorrelated-journal-text-leak' $deliveredArgs 1 'marker leaked' | Out-Null
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
