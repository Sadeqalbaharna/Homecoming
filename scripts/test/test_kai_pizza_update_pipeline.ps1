$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$pipeline = Join-Path $PSScriptRoot '..\tools\kai_pizza_update_pipeline.ps1'
$captureTool = Join-Path $PSScriptRoot '..\tools\kai_real_pizza_capture.ps1'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$temp = Join-Path ([IO.Path]::GetTempPath()) "kai-pizza-pipeline-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temp | Out-Null
$passed = 0
$failed = 0

function Write-Json([string]$Path, [object]$Value) {
    $Value | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-Case([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        $script:passed++
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    catch {
        $script:failed++
        Write-Host "[FAIL] $Name :: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-Pipeline([object[]]$Arguments, [int]$ExpectedExit, [string]$ExpectedText) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $pipeline @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne $ExpectedExit) { throw "exit $LASTEXITCODE expected $ExpectedExit :: $output" }
    if ($output -notmatch [regex]::Escape($ExpectedText)) { throw "missing '$ExpectedText' :: $output" }
    return $output
}

function Get-StringSha([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-CaptureBinding([object]$Manifest) {
    $labels = @($Manifest.labelRects | Sort-Object name | ForEach-Object { "$($_.name):$($_.left):$($_.top):$($_.right):$($_.bottom)" })
    return Get-StringSha (@(
        'kai-real-pizza-capture-v1', $Manifest.captureId, $Manifest.buildBindingId,
        $Manifest.runtimeBindingId, $Manifest.process.pid,
        ([string]$Manifest.process.executableSha256).ToLowerInvariant(),
        ([string]$Manifest.process.payloadSha256).ToLowerInvariant(),
        $Manifest.process.processCreationUtc, $Manifest.window.hwnd,
        $Manifest.window.dpi, $Manifest.window.clientLeft, $Manifest.window.clientTop,
        $Manifest.window.clientRight, $Manifest.window.clientBottom,
        ([string]$Manifest.imageSha256).ToLowerInvariant(),
        ($labels -join ','), $Manifest.cycleStartedAt, $Manifest.cycleFinishedAt
    ) -join '|')
}

try {
    $head = (& git -C $repo rev-parse HEAD).Trim()
    $sourceFile = Join-Path $repo 'docs\NORTHSTAR_SOURCE_OF_TRUTH.md'
    $sourceSha = (Get-FileHash $sourceFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $validDelta = [ordered]@{
        schemaVersion = 1; deltaId = 'fixture.valid-delta'; createdAt = '2026-08-09T13:23:00+03:00'; sourceOfTruthRef = 'docs/NORTHSTAR_SOURCE_OF_TRUTH.md'
        claims = @([ordered]@{
            claimId = 'homecoming.fixture'; projectId = 'homecoming_northstar'; requestedState = 'verified'; authorityOwner = 'agent'; riskClass = 'local_safe'; sourceOfTruthRef = 'docs/NORTHSTAR_SOURCE_OF_TRUTH.md'; changedSurfaces = @('pizza_hud')
            evidence = @([ordered]@{ id = 'fixture.source'; kind = 'file_sha256'; path = $sourceFile; sha256 = $sourceSha })
        })
    }
    $deltaPath = Join-Path $temp 'delta.json'; Write-Json $deltaPath $validDelta

    Invoke-Case 'valid machine-readable delta and deterministic test selection' {
        $out = Invoke-Pipeline @('-Mode','Plan','-DeltaPath',$deltaPath,'-AllowedEvidenceRoot',$repo) 0 'READY_FOR_LOCAL_RECONCILIATION'
        if ($out -notmatch 'kai_delivery_box_test.dart' -or $out -notmatch 'kai_project_portfolio_test.dart') { throw 'focused test plan missing' }
    }

    Invoke-Case 'unresolved commit cannot support verified promotion' {
        $bad = $validDelta | ConvertTo-Json -Depth 15 | ConvertFrom-Json
        $bad.claims[0].evidence[0] = [pscustomobject]@{ id = 'fixture.missing-commit'; kind = 'git_commit'; repositoryRoot = $repo; commit = 'deadbeef' }
        $path = Join-Path $temp 'missing-commit.json'; Write-Json $path $bad
        Invoke-Pipeline @('-Mode','Plan','-DeltaPath',$path,'-AllowedEvidenceRoot',$repo) 2 'lacks fully resolved primary evidence' | Out-Null
    }

    Invoke-Case 'sponsor-owned verified claim is refused' {
        $bad = $validDelta | ConvertTo-Json -Depth 15 | ConvertFrom-Json
        $bad.claims[0].authorityOwner = 'sponsor'; $bad.claims[0].riskClass = 'product_decision'
        $path = Join-Path $temp 'sponsor.json'; Write-Json $path $bad
        Invoke-Pipeline @('-Mode','Plan','-DeltaPath',$path,'-AllowedEvidenceRoot',$repo) 2 'sponsor or non-local authority boundary' | Out-Null
    }

    Invoke-Case 'evidence path traversal is refused' {
        $bad = $validDelta | ConvertTo-Json -Depth 15 | ConvertFrom-Json
        $bad.claims[0].evidence[0].path = 'C:\Windows\win.ini'
        $path = Join-Path $temp 'traversal.json'; Write-Json $path $bad
        Invoke-Pipeline @('-Mode','ValidateDelta','-DeltaPath',$path,'-AllowedEvidenceRoot',$repo) 1 'evidence_root_refused' | Out-Null
    }

    $exe = Join-Path $repo 'build\windows\x64\runner\Release\Kai.exe'
    $payload = Join-Path $repo 'build\windows\x64\runner\Release\data\app.so'
    if (-not (Test-Path $exe) -or -not (Test-Path $payload)) { throw 'Windows Release fixture artifacts are unavailable' }
    $build = [ordered]@{
        schemaVersion = 1; bindingId = 'build-fixture-001'; governedRoot = $repo; sourceCommit = $head; sourceFingerprint = ('a' * 64)
        executablePath = $exe; executableSha256 = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLowerInvariant()
        payloadPath = $payload; payloadSha256 = (Get-FileHash $payload -Algorithm SHA256).Hash.ToLowerInvariant()
        boundAtUtc = '2026-08-09T12:00:00Z'
    }
    $buildPath = Join-Path $temp 'build.json'; Write-Json $buildPath $build
    $runtime = [ordered]@{
        schemaVersion = 1; testFixture = $true; runtimeBindingId = 'runtime-fixture-001'; runId = 'run-fixture-001'; buildBindingId = $build.bindingId
        roomPid = 101; coordinatorPid = 102; corePid = 103; portOwnerPid = 103
        executablePath = $exe; executableSha256 = $build.executableSha256; payloadPath = $payload; payloadSha256 = $build.payloadSha256
        processCreationUtc = '2026-08-09T12:00:01Z'
    }
    $runtimePath = Join-Path $temp 'runtime.json'; Write-Json $runtimePath $runtime

    Invoke-Case 'build and runtime bind exact payload and fresh OS identity' {
        Invoke-Pipeline @('-Mode','ValidateBuildBinding','-BuildManifestPath',$buildPath) 0 '"verdict": "PASS"' | Out-Null
        Invoke-Pipeline @('-Mode','ValidateRuntimeBinding','-BuildManifestPath',$buildPath,'-RuntimeManifestPath',$runtimePath,'-AllowTestFixture') 0 'TEST_ONLY' | Out-Null
    }

    Invoke-Case 'runtime older than build binding is refused' {
        $bad = $runtime | ConvertTo-Json -Depth 15 | ConvertFrom-Json; $bad.processCreationUtc = '2026-08-09T11:59:59Z'
        $path = Join-Path $temp 'stale-runtime.json'; Write-Json $path $bad
        Invoke-Pipeline @('-Mode','ValidateRuntimeBinding','-BuildManifestPath',$buildPath,'-RuntimeManifestPath',$path,'-AllowTestFixture') 1 'stale_runtime' | Out-Null
    }

    Add-Type -AssemblyName System.Drawing
    $imagePath = Join-Path $temp 'capture.png'
    $bitmap = New-Object Drawing.Bitmap(1000,700); $g = [Drawing.Graphics]::FromImage($bitmap); $g.Clear([Drawing.Color]::Black)
    $names = @('Project Sovereignty Matrix','Homecoming','Hoard','Kingdom','Factory','Verified','Active','Awaiting sponsor','Blocked')
    $rects = @(); for ($i=0; $i -lt $names.Count; $i++) { $x=20; $y=20+($i*60); $g.FillRectangle([Drawing.Brushes]::White,$x,$y,240,24); $rects += [ordered]@{ name=$names[$i]; left=$x; top=$y; right=$x+240; bottom=$y+24 } }
    $g.Dispose(); $bitmap.Save($imagePath,[Drawing.Imaging.ImageFormat]::Png); $bitmap.Dispose()
    $capture = [ordered]@{
        schemaVersion=1; captureId='capture-fixture-001'; proofKind='real_desktop_window'; testFixture=$true; captureMethod='print_window_direct'
        buildBindingId=$build.bindingId; runtimeBindingId=$runtime.runtimeBindingId
        process=[ordered]@{ pid=101; executablePath=$exe; executableSha256=$build.executableSha256; payloadPath=$payload; payloadSha256=$build.payloadSha256; processCreationUtc=$runtime.processCreationUtc }
        window=[ordered]@{ hwnd=111; dpi=144; clientLeft=0; clientTop=0; clientRight=1000; clientBottom=700 }
        imagePath=$imagePath; imageSha256=(Get-FileHash $imagePath -Algorithm SHA256).Hash.ToLowerInvariant(); labelRects=$rects
        visualAssertions=[ordered]@{ clippingPixels=0; overlapPairs=@() }
        cycleStartedAt='2026-08-09T12:00:02Z'; cycleFinishedAt='2026-08-09T12:00:10Z'; failedCaptureFingerprints=@('failure-a'); manualStepsRemoved=@('manual hash')
    }
    $capture.captureBindingId = Get-CaptureBinding $capture
    $capturePath = Join-Path $temp 'capture.json'; Write-Json $capturePath $capture

    Invoke-Case 'real capture fixture is TEST_ONLY and needs an out-of-band pin' {
        Invoke-Pipeline @('-Mode','ValidateCapture','-CaptureManifestPath',$capturePath,'-BuildManifestPath',$buildPath,'-RuntimeManifestPath',$runtimePath,'-ExpectedCaptureBindingId',$capture.captureBindingId,'-AllowedCaptureRoot',$temp,'-AllowTestFixture') 0 'TEST_ONLY' | Out-Null
        Invoke-Pipeline @('-Mode','ValidateCapture','-CaptureManifestPath',$capturePath,'-BuildManifestPath',$buildPath,'-RuntimeManifestPath',$runtimePath,'-ExpectedCaptureBindingId',('0'*64),'-AllowedCaptureRoot',$temp,'-AllowTestFixture') 1 'capture_binding_mismatch' | Out-Null
    }

    Invoke-Case 'synthetic proof kind is refused regardless of image hash' {
        $bad = $capture | ConvertTo-Json -Depth 15 | ConvertFrom-Json; $bad.proofKind='flutter_test_renderer'
        $path=Join-Path $temp 'synthetic.json'; Write-Json $path $bad
        Invoke-Pipeline @('-Mode','ValidateCapture','-CaptureManifestPath',$path,'-BuildManifestPath',$buildPath,'-RuntimeManifestPath',$runtimePath,'-ExpectedCaptureBindingId',$capture.captureBindingId,'-AllowedCaptureRoot',$temp,'-AllowTestFixture') 1 'synthetic_proof_refused' | Out-Null
    }

    Invoke-Case 'duplicate semantic label is refused' {
        $bad = $capture | ConvertTo-Json -Depth 15 | ConvertFrom-Json; $bad.labelRects += $bad.labelRects[1]
        $path=Join-Path $temp 'duplicate-label.json'; Write-Json $path $bad
        Invoke-Pipeline @('-Mode','ValidateCapture','-CaptureManifestPath',$path,'-BuildManifestPath',$buildPath,'-RuntimeManifestPath',$runtimePath,'-ExpectedCaptureBindingId',$capture.captureBindingId,'-AllowedCaptureRoot',$temp,'-AllowTestFixture') 1 'semantic_label_cardinality' | Out-Null
    }

    $captureSource = Get-Content -Raw $captureTool
    Invoke-Case 'capture defaults to non-mutating attended-bound navigation' {
        if ($captureSource -notmatch "NavigationMode = 'attended_bound'") { throw 'default is not attended_bound' }
    }
    Invoke-Case 'failed-attempt ledger and allowed output root are mandatory' {
        if ($captureSource -notmatch '\[Parameter\(Mandatory = \$true\)\]\[string\]\$FailedAttemptLedgerPath') { throw 'failure ledger is optional' }
        if ($captureSource -notmatch '\[Parameter\(Mandatory = \$true\)\]\[string\]\$AllowedOutputRoot') { throw 'allowed output root is absent/optional' }
    }
    Invoke-Case 'DPI awareness failure is checked before capture' {
        if ($captureSource -notmatch 'dpi_awareness_unset') { throw 'DPI awareness return value is not fail-closed' }
    }
    Invoke-Case 'capture tool binds app.so and process freshness' {
        if ($captureSource -notmatch 'payloadSha256' -or $captureSource -notmatch 'processCreationUtc.*boundAtUtc') { throw 'payload/freshness contract missing' }
    }
    Invoke-Case 'no destructive process fallback exists' {
        if ($captureSource -match 'taskkill|Stop-Process|TerminateProcess|kill process') { throw 'destructive process path found' }
    }
}
finally {
    Write-Host "RESULT: $passed passed; $failed failed"
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

if ($failed -gt 0) { exit 1 }
