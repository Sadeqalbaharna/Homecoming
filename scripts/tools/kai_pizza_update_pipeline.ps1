param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('ValidateDelta', 'Plan', 'ValidateBuildBinding', 'ValidateRuntimeBinding', 'ValidateCapture')]
    [string]$Mode,
    [string]$DeltaPath,
    [string]$BuildManifestPath,
    [string]$RuntimeManifestPath,
    [string]$CaptureManifestPath,
    [string]$ExpectedCaptureBindingId,
    [string]$AllowedCaptureRoot,
    [string[]]$AllowedEvidenceRoot = @(),
    [switch]$AllowTestFixture,
    [string]$ReceiptPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$script:ReceiptEmitted = $false
$script:ReceiptExitCode = 1

function ConvertTo-CanonicalJsonString {
    param([string]$Value)
    $builder = New-Object System.Text.StringBuilder
    $null = $builder.Append('"')
    foreach ($char in $Value.ToCharArray()) {
        $code = [int]$char
        if ($code -eq 34) { $null = $builder.Append('\"') }
        elseif ($code -eq 92) { $null = $builder.Append('\\') }
        elseif ($code -eq 8) { $null = $builder.Append('\b') }
        elseif ($code -eq 9) { $null = $builder.Append('\t') }
        elseif ($code -eq 10) { $null = $builder.Append('\n') }
        elseif ($code -eq 12) { $null = $builder.Append('\f') }
        elseif ($code -eq 13) { $null = $builder.Append('\r') }
        elseif ($code -lt 32) { $null = $builder.Append('\u{0:x4}' -f $code) }
        else { $null = $builder.Append($char) }
    }
    $null = $builder.Append('"')
    return $builder.ToString()
}

# Receipts are serialised here rather than by ConvertTo-Json because the host
# decides that cmdlet's whitespace: Windows PowerShell 5.1 emits `"key":  value`
# with two spaces while PowerShell 7 emits one. The acceptance suite matches the
# receipt text, so the separator has to be a property of this script, not of the
# interpreter that happens to run it. Two-space indent, one space after the
# colon, invariant number formatting, and sorted keys for unordered maps.
function ConvertTo-CanonicalJson {
    param([object]$Value, [int]$Depth = 0)
    if ($Depth -gt 32) { return '"__depth_limit_exceeded__"' }
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [string]) { return ConvertTo-CanonicalJsonString $Value }
    if ($Value -is [char]) { return ConvertTo-CanonicalJsonString ([string]$Value) }
    $invariant = [Globalization.CultureInfo]::InvariantCulture
    if ($Value -is [sbyte] -or $Value -is [byte] -or $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64]) {
        return $Value.ToString($invariant)
    }
    if ($Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        $number = [double]$Value
        if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { return 'null' }
        return $number.ToString('R', $invariant)
    }
    $childIndent = '  ' * ($Depth + 1)
    $closeIndent = '  ' * $Depth
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys)
        if ($Value -isnot [System.Collections.Specialized.OrderedDictionary]) {
            $keys = @($keys | Sort-Object)
        }
        $entries = @()
        foreach ($key in $keys) {
            $entries += ($childIndent + (ConvertTo-CanonicalJsonString ([string]$key)) + ': ' +
                (ConvertTo-CanonicalJson -Value $Value[$key] -Depth ($Depth + 1)))
        }
        if ($entries.Count -eq 0) { return '{}' }
        return "{`n" + ($entries -join ",`n") + "`n" + $closeIndent + '}'
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $entries = @()
        foreach ($property in $Value.PSObject.Properties) {
            $entries += ($childIndent + (ConvertTo-CanonicalJsonString ([string]$property.Name)) + ': ' +
                (ConvertTo-CanonicalJson -Value $property.Value -Depth ($Depth + 1)))
        }
        if ($entries.Count -eq 0) { return '{}' }
        return "{`n" + ($entries -join ",`n") + "`n" + $closeIndent + '}'
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @()
        foreach ($item in $Value) {
            $items += ($childIndent + (ConvertTo-CanonicalJson -Value $item -Depth ($Depth + 1)))
        }
        if ($items.Count -eq 0) { return '[]' }
        return "[`n" + ($items -join ",`n") + "`n" + $closeIndent + ']'
    }
    return ConvertTo-CanonicalJsonString ([string]$Value)
}

function Write-Receipt {
    param([object]$Value, [int]$ExitCode)
    $json = ConvertTo-CanonicalJson -Value $Value -Depth 0
    if ($ReceiptPath) {
        $parent = Split-Path -Parent $ReceiptPath
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent | Out-Null
        }
        Set-Content -LiteralPath $ReceiptPath -Value $json -Encoding UTF8
    }
    $script:ReceiptEmitted = $true
    $script:ReceiptExitCode = $ExitCode
    Write-Output $json
    exit $ExitCode
}

function Stop-Pipeline {
    param([string]$Code, [string]$Reason, [hashtable]$Evidence = @{})
    Write-Receipt -Value ([ordered]@{
        schemaVersion = 1
        verdict = 'FAIL'
        code = $Code
        reason = $Reason
        evidence = $Evidence
    }) -ExitCode 1
}

# Strict mode 2 turns any absent property into a terminating error, which the
# parent acceptance harness then sees as native stderr rather than a verdict.
# Every optional read goes through Get-Prop so a missing field becomes data.
function Get-Prop {
    param([object]$Object, [string]$Name, [object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        # Key existence is not uniformly callable across dictionary types.
        # Dictionary<string,object> from the raw JSON reader implements
        # IDictionary.Contains explicitly and only surfaces the KeyValuePair
        # overload by name; OrderedDictionary has Contains but no ContainsKey;
        # Hashtable has both. Keys and the indexer are public on all three, so
        # match the key here and read the value back with the real key object
        # rather than the requested name, which keeps the lookup correct even
        # when the underlying dictionary is case-sensitive.
        foreach ($key in $Object.Keys) {
            if ([string]$key -eq $Name) { return $Object[$key] }
        }
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function ConvertTo-NativeArgument {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return '""' }
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

# Native git is invoked through Process directly. PowerShell's native-command
# plumbing turns any git stderr line into a terminating NativeCommandError under
# $ErrorActionPreference = 'Stop', which escapes the child and contaminates the
# strict parent harness. Here exit code, stdout and stderr are captured as data.
function Invoke-GitCommand {
    param([string]$RepositoryRoot, [string[]]$GitArguments)
    $arguments = @('-C', $RepositoryRoot) + $GitArguments
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'git'
    $startInfo.Arguments = (($arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    if (Test-Path -LiteralPath $RepositoryRoot -PathType Container) {
        $startInfo.WorkingDirectory = $RepositoryRoot
    }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        $null = $process.Start()
    }
    catch {
        return [ordered]@{ exitCode = -1; stdout = ''; stderr = "git could not be started: $($_.Exception.Message)"; launched = $false }
    }
    try {
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdoutTask.Wait()
        $stderrTask.Wait()
        return [ordered]@{
            exitCode = $process.ExitCode
            stdout = [string]$stdoutTask.Result
            stderr = [string]$stderrTask.Result
            launched = $true
        }
    }
    finally { $process.Dispose() }
}

function Get-GitFirstLine {
    param([object]$Result)
    $lines = @(([string]$Result.stdout) -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 })
    if ($lines.Count -eq 0) { return '' }
    return $lines[0].Trim()
}

function Read-Json {
    param([string]$Path, [string]$Label)
    if (-not $Path) { Stop-Pipeline 'missing_path' "$Label path is required." }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-Pipeline 'missing_file' "$Label file does not exist." @{ path = $Path }
    }
    try { return Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json }
    catch { Stop-Pipeline 'invalid_json' "$Label is not valid JSON." @{ path = $Path; error = $_.Exception.Message } }
}

function Get-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Test-UnderRoot {
    param([string]$Path, [string[]]$Roots)
    $full = Get-FullPath $Path
    foreach ($root in $Roots) {
        $base = Get-FullPath $root
        if ($full.Equals($base, [System.StringComparison]::OrdinalIgnoreCase) -or
            $full.StartsWith($base + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Assert-String {
    param([object]$Value, [string]$Label, [string]$Pattern = '.+')
    if ($null -eq $Value -or ([string]$Value) -notmatch $Pattern) {
        Stop-Pipeline 'invalid_schema' "$Label is missing or invalid." @{ label = $Label }
    }
}

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringSha256 {
    param([string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

# ConvertFrom-Json rewrites any ISO-8601 string into a [DateTime], which then
# renders in the current culture rather than as the text that was signed. The
# capture binding covers processCreationUtc, cycleStartedAt and cycleFinishedAt,
# so it must be computed from the manifest's source text. JavaScriptSerializer
# only special-cases the "\/Date(n)\/" form and leaves ISO strings alone.
function ConvertFrom-JsonPreservingText {
    param([string]$Path, [string]$Label)
    if (-not $Path) { Stop-Pipeline 'missing_path' "$Label path is required." }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-Pipeline 'missing_file' "$Label file does not exist." @{ path = $Path }
    }
    try { Add-Type -AssemblyName System.Web.Extensions }
    catch {
        Stop-Pipeline 'raw_json_reader_unavailable' 'The capture binding cannot be computed without a text-preserving JSON reader.' @{ error = $_.Exception.Message }
    }
    try {
        $text = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
        $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $serializer.MaxJsonLength = [int]::MaxValue
        return $serializer.DeserializeObject($text)
    }
    catch { Stop-Pipeline 'invalid_json' "$Label is not valid JSON." @{ path = $Path; error = $_.Exception.Message } }
}

# Match the capture producer's frozen binding contract exactly. Its label
# collection is piped through literal `Sort-Object name`; using an explicit
# Get-Prop sort key produces a different order for dictionary-backed JSON and
# therefore a different digest.
function Get-CaptureBindingCanonicalString {
    param([object]$Manifest)
    $process = Get-Prop $Manifest 'process'
    $window = Get-Prop $Manifest 'window'
    $labelParts = @(Get-Prop $Manifest 'labelRects' @() | Sort-Object name | ForEach-Object {
        "$(Get-Prop $_ 'name'):$(Get-Prop $_ 'left'):$(Get-Prop $_ 'top'):$(Get-Prop $_ 'right'):$(Get-Prop $_ 'bottom')"
    })
    $canonical = @(
        'kai-real-pizza-capture-v1',
        (Get-Prop $Manifest 'captureId'),
        (Get-Prop $Manifest 'buildBindingId'),
        (Get-Prop $Manifest 'runtimeBindingId'),
        (Get-Prop $process 'pid'),
        ([string](Get-Prop $process 'executableSha256')).ToLowerInvariant(),
        ([string](Get-Prop $process 'payloadSha256')).ToLowerInvariant(),
        (Get-Prop $process 'processCreationUtc'),
        (Get-Prop $window 'hwnd'),
        (Get-Prop $window 'dpi'),
        (Get-Prop $window 'clientLeft'),
        (Get-Prop $window 'clientTop'),
        (Get-Prop $window 'clientRight'),
        (Get-Prop $window 'clientBottom'),
        ([string](Get-Prop $Manifest 'imageSha256')).ToLowerInvariant(),
        ($labelParts -join ','),
        (Get-Prop $Manifest 'cycleStartedAt'),
        (Get-Prop $Manifest 'cycleFinishedAt')
    ) -join '|'
    return Get-StringSha256 $canonical
}

function Resolve-Evidence {
    param([object]$Evidence, [string[]]$Roots)
    $id = Get-Prop $Evidence 'id'
    $kindValue = Get-Prop $Evidence 'kind'
    Assert-String $id 'evidence.id' '^[a-z0-9][a-z0-9._-]{2,127}$'
    Assert-String $kindValue 'evidence.kind' '^(git_commit|file_sha256|test_result|reported_external|sponsor_decision)$'
    $kind = [string]$kindValue
    if ($kind -eq 'reported_external') {
        return [ordered]@{ id = $id; kind = $kind; verified = $false; reason = 'reported evidence is not a locally resolved primary identity' }
    }
    if ($kind -eq 'sponsor_decision') {
        $authorityId = Get-Prop $Evidence 'authorityId'
        Assert-String $authorityId 'evidence.authorityId' '^[A-Za-z0-9._:-]{6,160}$'
        return [ordered]@{ id = $id; kind = $kind; verified = $true; authorityId = $authorityId }
    }
    if ($kind -eq 'git_commit') {
        $repositoryRoot = Get-Prop $Evidence 'repositoryRoot'
        $commit = Get-Prop $Evidence 'commit'
        Assert-String $repositoryRoot 'evidence.repositoryRoot'
        Assert-String $commit 'evidence.commit' '^[0-9a-fA-F]{7,40}$'
        $root = Get-FullPath ([string]$repositoryRoot)
        if (-not (Test-UnderRoot $root $Roots)) {
            Stop-Pipeline 'evidence_root_refused' 'Git evidence root is outside the allowed roots.' @{ evidenceId = $id; root = $root }
        }
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            return [ordered]@{ id = $id; kind = $kind; verified = $false; reason = 'repository root is unavailable'; root = $root }
        }
        $git = Invoke-GitCommand -RepositoryRoot $root -GitArguments @('rev-parse', '--verify', ([string]$commit + '^{commit}'))
        $resolved = Get-GitFirstLine $git
        if ($git.exitCode -ne 0 -or $resolved -notmatch '^[0-9a-fA-F]{40}$') {
            return [ordered]@{
                id = $id; kind = $kind; verified = $false
                reason = 'commit object is unavailable'
                root = $root; requested = $commit
                gitExitCode = $git.exitCode
                gitStderr = ([string]$git.stderr).Trim()
            }
        }
        return [ordered]@{ id = $id; kind = $kind; verified = $true; root = $root; commit = $resolved.ToLowerInvariant() }
    }
    $evidencePath = Get-Prop $Evidence 'path'
    $evidenceSha = Get-Prop $Evidence 'sha256'
    Assert-String $evidencePath 'evidence.path'
    Assert-String $evidenceSha 'evidence.sha256' '^[0-9a-fA-F]{64}$'
    $path = Get-FullPath ([string]$evidencePath)
    if (-not (Test-UnderRoot $path $Roots)) {
        Stop-Pipeline 'evidence_root_refused' 'File evidence path is outside the allowed roots.' @{ evidenceId = $id; path = $path }
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [ordered]@{ id = $id; kind = $kind; verified = $false; reason = 'file is unavailable'; path = $path }
    }
    $actual = Get-FileSha256 $path
    $expected = ([string]$evidenceSha).ToLowerInvariant()
    return [ordered]@{
        id = $id
        kind = $kind
        verified = ($actual -eq $expected)
        path = $path
        expectedSha256 = $expected
        actualSha256 = $actual
        reason = if ($actual -eq $expected) { '' } else { 'file hash mismatch' }
    }
}

function Validate-Delta {
    param([object]$Delta)
    if ((Get-Prop $Delta 'schemaVersion') -ne 1) { Stop-Pipeline 'unsupported_schema' 'Tracker delta schemaVersion must be 1.' }
    Assert-String (Get-Prop $Delta 'deltaId') 'deltaId' '^[a-z0-9][a-z0-9._-]{5,127}$'
    Assert-String (Get-Prop $Delta 'sourceOfTruthRef') 'sourceOfTruthRef'
    try { $null = [DateTimeOffset]::Parse([string](Get-Prop $Delta 'createdAt')) }
    catch { Stop-Pipeline 'invalid_schema' 'createdAt must be an ISO-8601 timestamp.' }
    $claims = @(Get-Prop $Delta 'claims' @())
    if ($claims.Count -eq 0) {
        Stop-Pipeline 'invalid_schema' 'At least one claim is required.'
    }
    $roots = @($AllowedEvidenceRoot)
    if ($roots.Count -eq 0) { $roots = @((Get-Location).Path) }
    $claimIds = @{}
    $evidenceIds = @{}
    $resolvedEvidence = @()
    $projects = @{}
    $surfaces = @{}
    $promotionStops = @()
    foreach ($claim in $claims) {
        $claimId = Get-Prop $claim 'claimId'
        Assert-String $claimId 'claim.claimId' '^[a-z0-9][a-z0-9._-]{3,127}$'
        if ($claimIds.ContainsKey([string]$claimId)) {
            Stop-Pipeline 'duplicate_identity' 'claimId must be unique.' @{ claimId = $claimId }
        }
        $claimIds[[string]$claimId] = $true
        $projectId = Get-Prop $claim 'projectId'
        $requestedState = Get-Prop $claim 'requestedState'
        $authorityOwner = Get-Prop $claim 'authorityOwner'
        $riskClass = Get-Prop $claim 'riskClass'
        Assert-String $projectId 'claim.projectId' '^(homecoming_northstar|hoard_northstar|kingdom_northstar|factory_northstar|tiktok_portfolio_manager)$'
        Assert-String $requestedState 'claim.requestedState' '^(queued|ready|active|repairing|evidence_review|verified|awaiting_sponsor|blocked|deferred)$'
        Assert-String $authorityOwner 'claim.authorityOwner' '^(agent|sponsor)$'
        Assert-String $riskClass 'claim.riskClass' '^(local_safe|product_decision|live_external|destructive|security_sensitive|costly)$'
        Assert-String (Get-Prop $claim 'sourceOfTruthRef') 'claim.sourceOfTruthRef'
        $projects[[string]$projectId] = $true
        foreach ($surface in @(Get-Prop $claim 'changedSurfaces' @())) {
            if ($surface) { $surfaces[[string]$surface] = $true }
        }
        $claimEvidence = @()
        foreach ($evidence in @(Get-Prop $claim 'evidence' @())) {
            $evidenceId = [string](Get-Prop $evidence 'id')
            if ($evidenceIds.ContainsKey($evidenceId)) {
                Stop-Pipeline 'duplicate_identity' 'evidence.id must be unique across the delta.' @{ evidenceId = $evidenceId }
            }
            $evidenceIds[$evidenceId] = $true
            $resolved = Resolve-Evidence -Evidence $evidence -Roots $roots
            $resolvedEvidence += $resolved
            $claimEvidence += $resolved
        }
        if ([string]$requestedState -eq 'verified') {
            if ([string]$authorityOwner -ne 'agent' -or [string]$riskClass -ne 'local_safe') {
                $promotionStops += "claim $claimId crosses a sponsor or non-local authority boundary"
            }
            if ($claimEvidence.Count -eq 0 -or @($claimEvidence | Where-Object { -not $_.verified }).Count -gt 0) {
                $promotionStops += "claim $claimId lacks fully resolved primary evidence"
            }
            if (@($claimEvidence | Where-Object { $_.kind -eq 'sponsor_decision' }).Count -gt 0) {
                $promotionStops += "claim $claimId cannot auto-complete a sponsor decision"
            }
        }
    }
    $tests = @('test/kai_delivery_box_test.dart', 'test/kai_project_portfolio_test.dart')
    if ($projects.ContainsKey('factory_northstar') -or $surfaces.ContainsKey('factory_conveyor')) {
        $tests += 'test/kai_factory_conveyor_test.dart'
    }
    return [ordered]@{
        deltaId = Get-Prop $Delta 'deltaId'
        projects = @($projects.Keys | Sort-Object)
        changedSurfaces = @($surfaces.Keys | Sort-Object)
        evidence = @($resolvedEvidence | Sort-Object id)
        focusedTests = @($tests | Select-Object -Unique)
        promotionAllowed = ($promotionStops.Count -eq 0)
        promotionStops = $promotionStops
    }
}

# Readability is measured per label against its own local background. A label
# rectangle sampled in isolation is uniform by construction, so foreground-only
# statistics can neither prove nor disprove contrast; the padded ring is what
# carries the signal. Global image heuristics are deliberately absent.
function Get-PngMetrics {
    param([string]$Path, [object[]]$LabelRects, [object]$ClientRect)
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap($Path)
    try {
        $width = $bitmap.Width
        $height = $bitmap.Height
        $lockRect = New-Object System.Drawing.Rectangle(0, 0, $width, $height)
        $data = $bitmap.LockBits($lockRect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $stride = $data.Stride
            if ($stride -le 0) {
                Stop-Pipeline 'capture_decode_failed' 'Capture image could not be locked in a top-down layout.' @{ stride = $stride }
            }
            $pixels = [byte[]]::new($stride * $height)
            [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $pixels, 0, $pixels.Length)
        }
        finally { $bitmap.UnlockBits($data) }

        $clientLeft = [int](Get-Prop $ClientRect 'left' 0)
        $clientTop = [int](Get-Prop $ClientRect 'top' 0)
        $clientRight = [int](Get-Prop $ClientRect 'right' 0)
        $clientBottom = [int](Get-Prop $ClientRect 'bottom' 0)

        $readability = @()
        foreach ($rect in $LabelRects) {
            $name = [string](Get-Prop $rect 'name')
            $left = [int][Math]::Floor([double](Get-Prop $rect 'left' 0))
            $top = [int][Math]::Floor([double](Get-Prop $rect 'top' 0))
            $right = [int][Math]::Ceiling([double](Get-Prop $rect 'right' 0))
            $bottom = [int][Math]::Ceiling([double](Get-Prop $rect 'bottom' 0))
            if ($left -lt $clientLeft -or $top -lt $clientTop -or $right -gt $clientRight -or $bottom -gt $clientBottom) {
                Stop-Pipeline 'visual_clipping' 'A required label escapes the captured client area.' @{ label = $name }
            }
            if ($left -lt 0 -or $top -lt 0 -or $right -gt $width -or $bottom -gt $height -or $right -le $left -or $bottom -le $top) {
                Stop-Pipeline 'visual_clipping' 'A required label escapes the captured image bounds.' @{ label = $name }
            }
            $labelHeight = $bottom - $top
            if ($labelHeight -lt 8) {
                Stop-Pipeline 'label_too_small' 'A required label is below the 8px readability floor.' @{ label = $name; height = $labelHeight }
            }

            $pad = [Math]::Max(2, [int][Math]::Round($labelHeight / 4.0))
            $sampleLeft = [Math]::Max([Math]::Max(0, $clientLeft), $left - $pad)
            $sampleTop = [Math]::Max([Math]::Max(0, $clientTop), $top - $pad)
            $sampleRight = [Math]::Min([Math]::Min($width, $clientRight), $right + $pad)
            $sampleBottom = [Math]::Min([Math]::Min($height, $clientBottom), $bottom + $pad)

            [double]$minLum = 255; [double]$maxLum = 0; [double]$sum = 0; [double]$sumSq = 0; [int]$samples = 0
            for ($y = $sampleTop; $y -lt $sampleBottom; $y++) {
                $row = $y * $stride
                for ($x = $sampleLeft; $x -lt $sampleRight; $x++) {
                    $offset = $row + ($x * 4)
                    $lum = (0.2126 * $pixels[$offset + 2]) + (0.7152 * $pixels[$offset + 1]) + (0.0722 * $pixels[$offset])
                    if ($lum -lt $minLum) { $minLum = $lum }
                    if ($lum -gt $maxLum) { $maxLum = $lum }
                    $sum += $lum; $sumSq += ($lum * $lum); $samples++
                }
            }
            if ($samples -le 0) {
                Stop-Pipeline 'low_readability_contrast' 'A required label has no sampleable pixels.' @{ label = $name }
            }
            $mean = $sum / $samples
            $stdDev = [Math]::Sqrt([Math]::Max(0, ($sumSq / $samples) - ($mean * $mean)))
            $contrast = ($maxLum + 12.75) / ($minLum + 12.75)
            if ($contrast -lt 4.5 -or $stdDev -lt 8) {
                Stop-Pipeline 'low_readability_contrast' 'A required label lacks per-rect contrast/non-uniformity.' @{ label = $name; contrastRatio = $contrast; stdDev = $stdDev }
            }
            $readability += [ordered]@{
                name = $name
                heightPx = $labelHeight
                samplePadPx = $pad
                sampledPixels = $samples
                contrastRatio = [Math]::Round($contrast, 3)
                luminanceStdDev = [Math]::Round($stdDev, 3)
            }
        }
        return [ordered]@{
            width = $width
            height = $height
            labels = $readability
        }
    }
    finally { $bitmap.Dispose() }
}

function Validate-Capture {
    param([object]$Manifest, [object]$Build, [object]$Runtime)
    if ((Get-Prop $Manifest 'schemaVersion') -ne 1) { Stop-Pipeline 'unsupported_schema' 'Capture schemaVersion must be 1.' }
    Assert-String (Get-Prop $Manifest 'captureId') 'captureId' '^[a-z0-9][a-z0-9._-]{5,127}$'
    $proofKind = Get-Prop $Manifest 'proofKind'
    if ([string]$proofKind -ne 'real_desktop_window') {
        Stop-Pipeline 'synthetic_proof_refused' 'Only real_desktop_window can satisfy real HUD proof.' @{ proofKind = $proofKind }
    }
    $isTestFixture = [bool](Get-Prop $Manifest 'testFixture' $false)
    if ($isTestFixture -and -not $AllowTestFixture) {
        Stop-Pipeline 'test_fixture_refused' 'A test fixture cannot satisfy real HUD proof.'
    }
    $captureMethod = Get-Prop $Manifest 'captureMethod'
    if ([string]$captureMethod -ne 'print_window_direct') {
        Stop-Pipeline 'non_direct_capture_refused' 'Capture method must be print_window_direct.' @{ captureMethod = $captureMethod }
    }
    $process = Get-Prop $Manifest 'process'
    $window = Get-Prop $Manifest 'window'
    Assert-String (Get-Prop $Manifest 'imagePath') 'imagePath'
    Assert-String (Get-Prop $Manifest 'imageSha256') 'imageSha256' '^[0-9a-fA-F]{64}$'
    Assert-String (Get-Prop $Manifest 'buildBindingId') 'buildBindingId' '^[A-Za-z0-9._:-]{8,160}$'
    Assert-String (Get-Prop $Manifest 'runtimeBindingId') 'runtimeBindingId' '^[A-Za-z0-9._:-]{8,160}$'
    Assert-String (Get-Prop $Manifest 'captureBindingId') 'captureBindingId' '^[0-9a-fA-F]{64}$'
    Assert-String $ExpectedCaptureBindingId 'ExpectedCaptureBindingId' '^[0-9a-fA-F]{64}$'
    if ([string](Get-Prop $Manifest 'buildBindingId') -ne [string]$Build.bindingId -or
        [string](Get-Prop $Manifest 'runtimeBindingId') -ne [string]$Runtime.runtimeBindingId) {
        Stop-Pipeline 'capture_runtime_mismatch' 'Capture does not reference the validated build/runtime bindings.'
    }
    Assert-String (Get-Prop $process 'executablePath') 'process.executablePath'
    Assert-String (Get-Prop $process 'executableSha256') 'process.executableSha256' '^[0-9a-fA-F]{64}$'
    Assert-String (Get-Prop $process 'payloadPath') 'process.payloadPath'
    Assert-String (Get-Prop $process 'payloadSha256') 'process.payloadSha256' '^[0-9a-fA-F]{64}$'
    Assert-String (Get-Prop $process 'processCreationUtc') 'process.processCreationUtc'
    if ([int](Get-Prop $process 'pid' 0) -le 0 -or [long](Get-Prop $window 'hwnd' 0) -le 0) {
        Stop-Pipeline 'invalid_process_identity' 'Capture requires positive PID and HWND.'
    }
    $dpi = [int](Get-Prop $window 'dpi' 0)
    if ($dpi -lt 96 -or $dpi -gt 768) {
        Stop-Pipeline 'invalid_dpi' 'Window DPI is outside the supported range.' @{ dpi = $dpi }
    }
    if ([string](Get-Prop $process 'processCreationUtc') -ne [string]$Runtime.processCreationUtc) {
        try {
            $captureCreated = [DateTimeOffset]::Parse([string](Get-Prop $process 'processCreationUtc'))
            $runtimeCreated = [DateTimeOffset]::Parse([string]$Runtime.processCreationUtc)
        }
        catch { Stop-Pipeline 'invalid_runtime_time' 'Capture process creation time must be ISO-8601.' }
        if ($captureCreated -ne $runtimeCreated) {
            Stop-Pipeline 'capture_runtime_mismatch' 'Capture process creation differs from the runtime binding.'
        }
    }
    $image = Get-FullPath ([string](Get-Prop $Manifest 'imagePath'))
    if (-not $AllowedCaptureRoot -or -not (Test-UnderRoot $image @($AllowedCaptureRoot))) {
        Stop-Pipeline 'capture_root_refused' 'Capture image is outside the explicitly allowed capture root.' @{ imagePath = $image }
    }
    if (-not (Test-Path -LiteralPath $image -PathType Leaf)) {
        Stop-Pipeline 'missing_capture' 'Capture image is unavailable.' @{ imagePath = $image }
    }
    $actualImageSha = Get-FileSha256 $image
    if ($actualImageSha -ne ([string](Get-Prop $Manifest 'imageSha256')).ToLowerInvariant()) {
        Stop-Pipeline 'capture_hash_mismatch' 'Capture image hash does not match the manifest.' @{ actual = $actualImageSha }
    }
    $exe = Get-FullPath ([string](Get-Prop $process 'executablePath'))
    if ($exe -ne (Get-FullPath ([string]$Build.executablePath))) {
        Stop-Pipeline 'executable_path_mismatch' 'Capture executable path differs from the build binding.' @{ executablePath = $exe }
    }
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        Stop-Pipeline 'missing_executable' 'Bound executable is unavailable.' @{ executablePath = $exe }
    }
    if ((Get-FileSha256 $exe) -ne ([string](Get-Prop $process 'executableSha256')).ToLowerInvariant() -or
        ([string](Get-Prop $process 'executableSha256')).ToLowerInvariant() -ne ([string]$Build.executableSha256).ToLowerInvariant()) {
        Stop-Pipeline 'executable_hash_mismatch' 'Running/build executable hash binding is stale.'
    }
    $payload = Get-FullPath ([string](Get-Prop $process 'payloadPath'))
    if ($payload -ne (Get-FullPath ([string]$Build.payloadPath)) -or -not (Test-Path -LiteralPath $payload -PathType Leaf) -or
        (Get-FileSha256 $payload) -ne ([string](Get-Prop $process 'payloadSha256')).ToLowerInvariant() -or
        ([string](Get-Prop $process 'payloadSha256')).ToLowerInvariant() -ne ([string]$Build.payloadSha256).ToLowerInvariant()) {
        Stop-Pipeline 'payload_hash_mismatch' 'Capture runtime payload does not match the build binding.'
    }
    $requiredLabels = @('Project Sovereignty Matrix', 'Homecoming', 'Hoard', 'Kingdom', 'Factory', 'Verified', 'Active', 'Awaiting sponsor', 'Blocked')
    $rects = @(Get-Prop $Manifest 'labelRects' @())
    foreach ($required in $requiredLabels) {
        $found = @($rects | Where-Object { [string](Get-Prop $_ 'name') -eq $required })
        if ($found.Count -ne 1) {
            Stop-Pipeline 'semantic_label_cardinality' 'Every required label must appear exactly once.' @{ label = $required; count = $found.Count }
        }
    }
    $visualAssertions = Get-Prop $Manifest 'visualAssertions'
    if ([int](Get-Prop $visualAssertions 'clippingPixels' (-1)) -ne 0) {
        Stop-Pipeline 'visual_clipping' 'The Pizza card is clipped.' @{ clippingPixels = (Get-Prop $visualAssertions 'clippingPixels') }
    }
    for ($i = 0; $i -lt $rects.Count; $i++) {
        for ($j = $i + 1; $j -lt $rects.Count; $j++) {
            $a = $rects[$i]; $b = $rects[$j]
            $ow = [Math]::Min([double](Get-Prop $a 'right' 0), [double](Get-Prop $b 'right' 0)) - [Math]::Max([double](Get-Prop $a 'left' 0), [double](Get-Prop $b 'left' 0))
            $oh = [Math]::Min([double](Get-Prop $a 'bottom' 0), [double](Get-Prop $b 'bottom' 0)) - [Math]::Max([double](Get-Prop $a 'top' 0), [double](Get-Prop $b 'top' 0))
            if ($ow -gt 2 -and $oh -gt 2) {
                Stop-Pipeline 'visual_overlap' 'Required HUD labels overlap.' @{ first = (Get-Prop $a 'name'); second = (Get-Prop $b 'name') }
            }
        }
    }
    $clientRect = [ordered]@{
        left = (Get-Prop $window 'clientLeft' 0)
        top = (Get-Prop $window 'clientTop' 0)
        right = (Get-Prop $window 'clientRight' 0)
        bottom = (Get-Prop $window 'clientBottom' 0)
    }
    $metrics = Get-PngMetrics -Path $image -LabelRects $rects -ClientRect $clientRect
    if ($metrics.width -lt 900 -or $metrics.height -lt 600) {
        Stop-Pipeline 'capture_too_small' 'Capture is too small for normal-width review.' @{ metrics = $metrics }
    }
    $fingerprints = @(Get-Prop $Manifest 'failedCaptureFingerprints' @() | ForEach-Object { [string]$_ })
    # Select-Object returns a bare scalar for a single match, and strict mode 2
    # refuses the synthesised .Count on a scalar. Collect before counting.
    $distinctFingerprints = @($fingerprints | Select-Object -Unique)
    if ($distinctFingerprints.Count -ne $fingerprints.Count) {
        Stop-Pipeline 'identical_retry_detected' 'Failed capture fingerprints must be unique; an identical retry is suppressed.'
    }
    try {
        $start = [DateTimeOffset]::Parse([string](Get-Prop $Manifest 'cycleStartedAt'))
        $finish = [DateTimeOffset]::Parse([string](Get-Prop $Manifest 'cycleFinishedAt'))
    }
    catch { Stop-Pipeline 'invalid_cycle_time' 'Cycle timestamps must be ISO-8601.' }
    if ($finish -lt $start) { Stop-Pipeline 'invalid_cycle_time' 'cycleFinishedAt precedes cycleStartedAt.' }
    $rawManifest = ConvertFrom-JsonPreservingText -Path $CaptureManifestPath -Label 'capture manifest'
    $computedBinding = Get-CaptureBindingCanonicalString $rawManifest
    $declaredBinding = ([string](Get-Prop $Manifest 'captureBindingId')).ToLowerInvariant()
    $expectedBinding = $ExpectedCaptureBindingId.ToLowerInvariant()
    if ($computedBinding -ne $declaredBinding -or $computedBinding -ne $expectedBinding) {
        Stop-Pipeline 'capture_binding_mismatch' 'Capture manifest does not match the out-of-band binding ID.' @{
            computed = $computedBinding
            declared = $declaredBinding
            expected = $expectedBinding
        }
    }
    $verdict = if ($isTestFixture) { 'TEST_ONLY' } else { 'PASS' }
    return [ordered]@{
        schemaVersion = 1
        verdict = $verdict
        captureId = Get-Prop $Manifest 'captureId'
        proofKind = $proofKind
        imageSha256 = $actualImageSha
        metrics = $metrics
        dpi = $dpi
        captureBindingId = $computedBinding
        cycleSeconds = [Math]::Round(($finish - $start).TotalSeconds, 3)
        failedCaptureFingerprints = $fingerprints
        manualStepsRemoved = @(Get-Prop $Manifest 'manualStepsRemoved' @())
    }
}

function Validate-BuildBinding {
    param([object]$Manifest)
    if ((Get-Prop $Manifest 'schemaVersion') -ne 1) { Stop-Pipeline 'unsupported_schema' 'Build binding schemaVersion must be 1.' }
    $bindingId = Get-Prop $Manifest 'bindingId'
    $governedRoot = Get-Prop $Manifest 'governedRoot'
    $sourceCommit = Get-Prop $Manifest 'sourceCommit'
    $executablePath = Get-Prop $Manifest 'executablePath'
    $executableSha256 = Get-Prop $Manifest 'executableSha256'
    $payloadPath = Get-Prop $Manifest 'payloadPath'
    $payloadSha256 = Get-Prop $Manifest 'payloadSha256'
    Assert-String $bindingId 'bindingId' '^[A-Za-z0-9._:-]{8,160}$'
    Assert-String $governedRoot 'governedRoot'
    Assert-String $sourceCommit 'sourceCommit' '^[0-9a-fA-F]{40}$'
    Assert-String (Get-Prop $Manifest 'sourceFingerprint') 'sourceFingerprint' '^[0-9a-fA-F]{64}$'
    Assert-String $executablePath 'executablePath'
    Assert-String $executableSha256 'executableSha256' '^[0-9a-fA-F]{64}$'
    Assert-String $payloadPath 'payloadPath'
    Assert-String $payloadSha256 'payloadSha256' '^[0-9a-fA-F]{64}$'
    $root = Get-FullPath ([string]$governedRoot)
    $exe = Get-FullPath ([string]$executablePath)
    $payload = Get-FullPath ([string]$payloadPath)
    if (-not (Test-UnderRoot $exe @($root)) -or -not (Test-UnderRoot $payload @($root))) {
        Stop-Pipeline 'build_path_mismatch' 'Build artifacts escape the governed root.' @{ governedRoot = $root }
    }
    foreach ($pair in @(@($exe, $executableSha256, 'executable'), @($payload, $payloadSha256, 'payload'))) {
        if (-not (Test-Path -LiteralPath $pair[0] -PathType Leaf)) {
            Stop-Pipeline 'missing_build_artifact' "Bound $($pair[2]) is unavailable." @{ path = $pair[0] }
        }
        if ((Get-FileSha256 $pair[0]) -ne ([string]$pair[1]).ToLowerInvariant()) {
            Stop-Pipeline 'build_hash_mismatch' "Bound $($pair[2]) hash is stale." @{ path = $pair[0] }
        }
    }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        Stop-Pipeline 'build_source_mismatch' 'Governed root is unavailable.' @{ governedRoot = $root }
    }
    # A linked worktree resolves commits through its .git file; the resolution is
    # done with captured exit/stdout/stderr so a worktree problem is reported as
    # evidence instead of terminating the validator.
    $git = Invoke-GitCommand -RepositoryRoot $root -GitArguments @('rev-parse', '--verify', ([string]$sourceCommit + '^{commit}'))
    $resolvedCommit = Get-GitFirstLine $git
    if ($git.exitCode -ne 0 -or $resolvedCommit -notmatch '^[0-9a-fA-F]{40}$' -or
        $resolvedCommit.ToLowerInvariant() -ne ([string]$sourceCommit).ToLowerInvariant()) {
        $gitDir = Invoke-GitCommand -RepositoryRoot $root -GitArguments @('rev-parse', '--absolute-git-dir')
        Stop-Pipeline 'build_source_mismatch' 'Build source commit is unavailable at the governed root.' @{
            governedRoot = $root
            requested = $sourceCommit
            resolved = $resolvedCommit
            gitExitCode = $git.exitCode
            gitStderr = ([string]$git.stderr).Trim()
            gitDir = (Get-GitFirstLine $gitDir)
            gitDirExitCode = $gitDir.exitCode
        }
    }
    try { $bound = [DateTimeOffset]::Parse([string](Get-Prop $Manifest 'boundAtUtc')) }
    catch { Stop-Pipeline 'invalid_binding_time' 'boundAtUtc must be ISO-8601.' }
    return [ordered]@{
        schemaVersion = 1
        verdict = 'PASS'
        bindingId = $bindingId
        governedRoot = $root
        sourceCommit = $resolvedCommit.ToLowerInvariant()
        executablePath = $exe
        executableSha256 = (Get-FileSha256 $exe)
        payloadPath = $payload
        payloadSha256 = (Get-FileSha256 $payload)
        boundAtUtc = $bound.ToUniversalTime().ToString('o')
    }
}

function Validate-RuntimeBinding {
    param([object]$Runtime, [object]$Build)
    if ((Get-Prop $Runtime 'schemaVersion') -ne 1) { Stop-Pipeline 'unsupported_schema' 'Runtime binding schemaVersion must be 1.' }
    Assert-String (Get-Prop $Runtime 'runtimeBindingId') 'runtimeBindingId' '^[A-Za-z0-9._:-]{8,160}$'
    Assert-String (Get-Prop $Runtime 'runId') 'runId' '^[A-Za-z0-9._:-]{8,160}$'
    if ([string](Get-Prop $Runtime 'buildBindingId') -ne [string]$Build.bindingId) {
        Stop-Pipeline 'runtime_build_mismatch' 'Runtime does not reference the accepted build binding.'
    }
    $roomPid = [int](Get-Prop $Runtime 'roomPid' 0)
    $coordinatorPid = [int](Get-Prop $Runtime 'coordinatorPid' 0)
    $corePid = [int](Get-Prop $Runtime 'corePid' 0)
    $portOwnerPid = [int](Get-Prop $Runtime 'portOwnerPid' 0)
    if ($roomPid -le 0 -or $coordinatorPid -le 0 -or $portOwnerPid -le 0) {
        Stop-Pipeline 'invalid_runtime_identity' 'Room, coordinator, and port-owner PIDs must be positive.'
    }
    if ($portOwnerPid -ne $corePid) {
        Stop-Pipeline 'port_owner_mismatch' 'Port owner does not match the bound Core PID.'
    }
    $runtimeExecutablePath = Get-Prop $Runtime 'executablePath'
    $runtimeExecutableSha = Get-Prop $Runtime 'executableSha256'
    $runtimePayloadPath = Get-Prop $Runtime 'payloadPath'
    $runtimePayloadSha = Get-Prop $Runtime 'payloadSha256'
    Assert-String $runtimeExecutablePath 'runtime.executablePath'
    Assert-String $runtimeExecutableSha 'runtime.executableSha256' '^[0-9a-fA-F]{64}$'
    Assert-String $runtimePayloadPath 'runtime.payloadPath'
    Assert-String $runtimePayloadSha 'runtime.payloadSha256' '^[0-9a-fA-F]{64}$'
    if ((Get-FullPath ([string]$runtimeExecutablePath)) -ne (Get-FullPath ([string]$Build.executablePath)) -or
        ([string]$runtimeExecutableSha).ToLowerInvariant() -ne ([string]$Build.executableSha256).ToLowerInvariant()) {
        Stop-Pipeline 'runtime_executable_mismatch' 'Runtime executable path/hash differs from the build binding.'
    }
    # Kai.exe equality alone is not runtime identity; data/app.so is the
    # authoritative Flutter payload and is bound here as well as at capture time.
    if ((Get-FullPath ([string]$runtimePayloadPath)) -ne (Get-FullPath ([string]$Build.payloadPath)) -or
        ([string]$runtimePayloadSha).ToLowerInvariant() -ne ([string]$Build.payloadSha256).ToLowerInvariant()) {
        Stop-Pipeline 'runtime_payload_mismatch' 'Runtime payload path/hash differs from the build binding.' @{
            runtimePayloadPath = $runtimePayloadPath
            buildPayloadPath = $Build.payloadPath
        }
    }
    try {
        $created = [DateTimeOffset]::Parse([string](Get-Prop $Runtime 'processCreationUtc'))
        $bound = [DateTimeOffset]::Parse([string]$Build.boundAtUtc)
    }
    catch { Stop-Pipeline 'invalid_runtime_time' 'Runtime creation and build binding times must be ISO-8601.' }
    if ($created -le $bound) {
        Stop-Pipeline 'stale_runtime' 'Runtime process creation is not later than build binding.'
    }
    $isTestFixture = [bool](Get-Prop $Runtime 'testFixture' $false)
    if ($isTestFixture -and -not $AllowTestFixture) {
        Stop-Pipeline 'test_fixture_refused' 'A fixture runtime cannot satisfy real runtime binding.'
    }
    if (-not $isTestFixture) {
        $process = Get-Process -Id $roomPid -ErrorAction SilentlyContinue
        if ($null -eq $process) { Stop-Pipeline 'runtime_process_missing' 'Bound room process is not running.' }
        if ((Get-FullPath $process.Path) -ne (Get-FullPath ([string]$Build.executablePath))) {
            Stop-Pipeline 'runtime_process_path_mismatch' 'OS room process path differs from the build binding.'
        }
        $deltaSeconds = [Math]::Abs((([DateTimeOffset]$process.StartTime) - $created.ToLocalTime()).TotalSeconds)
        if ($deltaSeconds -gt 1) {
            Stop-Pipeline 'runtime_process_time_mismatch' 'OS room process time differs from the runtime binding.'
        }
        if (([DateTimeOffset]$process.StartTime) -le $bound.ToLocalTime()) {
            Stop-Pipeline 'stale_runtime' 'OS process creation is not later than the build artifact binding.'
        }
    }
    return [ordered]@{
        schemaVersion = 1
        verdict = if ($isTestFixture) { 'TEST_ONLY' } else { 'PASS' }
        runtimeBindingId = Get-Prop $Runtime 'runtimeBindingId'
        runId = Get-Prop $Runtime 'runId'
        buildBindingId = $Build.bindingId
        roomPid = $roomPid
        coordinatorPid = $coordinatorPid
        corePid = $corePid
        portOwnerPid = $portOwnerPid
        executablePath = Get-FullPath ([string]$runtimeExecutablePath)
        executableSha256 = ([string]$runtimeExecutableSha).ToLowerInvariant()
        payloadPath = Get-FullPath ([string]$runtimePayloadPath)
        payloadSha256 = ([string]$runtimePayloadSha).ToLowerInvariant()
        processCreationUtc = $created.ToUniversalTime().ToString('o')
    }
}

function Invoke-PipelineMode {
    if ($Mode -eq 'ValidateCapture') {
        $manifest = Read-Json -Path $CaptureManifestPath -Label 'capture manifest'
        $build = Read-Json -Path $BuildManifestPath -Label 'build binding'
        $runtime = Read-Json -Path $RuntimeManifestPath -Label 'runtime binding'
        $validBuild = Validate-BuildBinding -Manifest $build
        $validRuntime = Validate-RuntimeBinding -Runtime $runtime -Build $validBuild
        $captureResult = Validate-Capture -Manifest $manifest -Build $validBuild -Runtime $validRuntime
        Write-Receipt -Value $captureResult -ExitCode 0
    }

    if ($Mode -eq 'ValidateBuildBinding') {
        $build = Read-Json -Path $BuildManifestPath -Label 'build binding'
        Write-Receipt -Value (Validate-BuildBinding -Manifest $build) -ExitCode 0
    }

    if ($Mode -eq 'ValidateRuntimeBinding') {
        $build = Read-Json -Path $BuildManifestPath -Label 'build binding'
        $runtime = Read-Json -Path $RuntimeManifestPath -Label 'runtime binding'
        $validBuild = Validate-BuildBinding -Manifest $build
        Write-Receipt -Value (Validate-RuntimeBinding -Runtime $runtime -Build $validBuild) -ExitCode 0
    }

    $delta = Read-Json -Path $DeltaPath -Label 'tracker delta'
    $deltaResult = Validate-Delta -Delta $delta
    if ($Mode -eq 'ValidateDelta') {
        Write-Receipt -Value ([ordered]@{ schemaVersion = 1; verdict = 'PASS'; result = $deltaResult }) -ExitCode 0
    }

    $plan = [ordered]@{
        schemaVersion = 1
        verdict = if ($deltaResult.promotionAllowed) { 'READY_FOR_LOCAL_RECONCILIATION' } else { 'STOPPED' }
        delta = $deltaResult
        commands = [ordered]@{
            focusedTests = "flutter test --no-pub $($deltaResult.focusedTests -join ' ')"
            windowsBuild = 'flutter build windows --release'
        }
        buildBindingRequired = @('governedRoot', 'sourceCommit', 'sourceFingerprint', 'executablePath', 'executableSha256', 'payloadPath', 'payloadSha256', 'boundAtUtc', 'bindingId')
        runtimeBindingRequired = @('runtimeBindingId', 'runId', 'buildBindingId', 'roomPid', 'coordinatorPid', 'corePid', 'portOwnerPid', 'executablePath', 'executableSha256', 'payloadPath', 'payloadSha256', 'processCreationUtc')
        handover = [ordered]@{
            requiresCurrentAuthorityId = $true
            requiresSupportedGracefulRoomExit = $true
            requiresSupportedGracefulCoordinatorExit = $true
            forceKillFallback = $false
            stopIfMissing = $true
        }
        realHud = [ordered]@{
            requiresCurrentAuthorityId = $true
            navigationMode = 'attended_bound'
            mutatingNavigationDefault = $false
            uiAutomationInvokeRequiresFreshAuthority = $true
            navigationTarget = 'Project Sovereignty Matrix'
            captureMethod = 'print_window_direct'
            dpiAware = $true
            requiresDpiAwarenessContext = $true
            requiresAllowedOutputRoot = $true
            requiresFailedAttemptLedger = $true
            requiresOutOfBandCaptureBindingId = $true
            acceptsSyntheticRenderer = $false
            requiredManifest = 'real desktop capture manifest schemaVersion 1'
        }
        sponsorGates = @('process handover/restart', 'GUI navigation and capture', 'sponsor-owned box decisions', 'live/external/security/destructive/costly actions')
    }
    Write-Receipt -Value $plan -ExitCode $(if ($deltaResult.promotionAllowed) { 0 } else { 2 })
}

# Any unexpected error becomes a FAIL receipt on stdout. Letting it reach stderr
# would surface in the strict parent harness as a native error record instead of
# a verdict, hiding the real cause of the failing gate.
try {
    Invoke-PipelineMode
}
catch {
    if ($script:ReceiptEmitted) { exit $script:ReceiptExitCode }
    $failure = [ordered]@{
        schemaVersion = 1
        verdict = 'FAIL'
        code = 'unhandled_exception'
        reason = 'The validator terminated before producing a verdict.'
        evidence = [ordered]@{
            mode = $Mode
            message = [string]$_.Exception.Message
            type = [string]$_.Exception.GetType().FullName
            location = [string]$_.InvocationInfo.PositionMessage
        }
    }
    try { Write-Output (ConvertTo-CanonicalJson -Value $failure -Depth 0) }
    catch { Write-Output '{ "schemaVersion": 1, "verdict": "FAIL", "code": "unhandled_exception", "reason": "The validator terminated and its receipt could not be serialised." }' }
    exit 1
}
