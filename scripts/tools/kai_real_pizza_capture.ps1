param(
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [Parameter(Mandatory = $true)][string]$AuthorityManifestPath,
    [Parameter(Mandatory = $true)][string]$BuildManifestPath,
    [Parameter(Mandatory = $true)][string]$RuntimeManifestPath,
    [Parameter(Mandatory = $true)][string]$AllowedOutputRoot,
    [Parameter(Mandatory = $true)][string]$FailedAttemptLedgerPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$CaptureManifestPath,
    [ValidateSet('ui_automation', 'attended_bound')][string]$NavigationMode = 'attended_bound',
    [string]$StrategyId = 'uia-direct-window-v1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$cycleStarted = [DateTimeOffset]::UtcNow

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "missing_file:$Path" }
    return Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json
}

function Get-Sha([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringSha([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Resolve-PathUnderRoot([string]$Path, [string]$Root, [string]$Label) {
    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    if ($resolvedPath -ne $resolvedRoot -and -not $resolvedPath.StartsWith($resolvedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "${Label}_outside_allowed_root:$resolvedPath"
    }
    return $resolvedPath
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

function Get-FailureFingerprint([string]$Code, [string]$Detail, [int]$Dpi) {
    $normalized = "$Code|$ProcessId|$Dpi|$($Detail -replace '[0-9a-fA-F]{8,}', '<id>')"
    $bytes = [Text.Encoding]::UTF8.GetBytes($normalized)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Record-Failure([string]$Code, [string]$Detail, [int]$Dpi = 0) {
    $fingerprint = Get-FailureFingerprint $Code $Detail $Dpi
    $entries = @()
    if (Test-Path -LiteralPath $FailedAttemptLedgerPath) {
        $entries = @(Read-Json $FailedAttemptLedgerPath)
    }
    if (@($entries | Where-Object { $_.fingerprint -eq $fingerprint }).Count -gt 0) {
        throw "identical_retry_suppressed:$fingerprint"
    }
    $entries += [ordered]@{
        atUtc = [DateTimeOffset]::UtcNow.ToString('o')
        code = $Code
        strategyId = $StrategyId
        fingerprint = $fingerprint
    }
    $entries | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $FailedAttemptLedgerPath -Encoding UTF8
    throw "$Code`:$Detail`:$fingerprint"
}

$allowedRoot = [IO.Path]::GetFullPath($AllowedOutputRoot)
if (-not (Test-Path -LiteralPath $allowedRoot -PathType Container)) { throw "allowed_output_root_missing:$allowedRoot" }
$OutputPath = Resolve-PathUnderRoot $OutputPath $allowedRoot 'output'
$CaptureManifestPath = Resolve-PathUnderRoot $CaptureManifestPath $allowedRoot 'capture_manifest'
$FailedAttemptLedgerPath = Resolve-PathUnderRoot $FailedAttemptLedgerPath $allowedRoot 'failure_ledger'
$ledgerParent = Split-Path -Parent $FailedAttemptLedgerPath
if ($ledgerParent -and -not (Test-Path -LiteralPath $ledgerParent)) { New-Item -ItemType Directory -Path $ledgerParent | Out-Null }

$authority = Read-Json $AuthorityManifestPath
if ($authority.schemaVersion -ne 1 -or [string]$authority.scope -ne 'local_real_pizza_navigation_capture') {
    Record-Failure 'authority_scope_refused' 'authority scope does not match'
}
if ([int]$authority.targetPid -ne $ProcessId) {
    Record-Failure 'authority_pid_mismatch' 'authority targets another process'
}
if ([string]::IsNullOrWhiteSpace([string]$authority.authorityId)) {
    Record-Failure 'authority_id_missing' 'authority identity is absent'
}
$expires = [DateTimeOffset]::Parse([string]$authority.expiresAtUtc)
if ($expires -le [DateTimeOffset]::UtcNow) { Record-Failure 'authority_expired' 'authority is stale' }
$actions = @($authority.actions | ForEach-Object { [string]$_ })
foreach ($required in @('navigate_real_hud', 'capture_direct_window')) {
    if ($actions -notcontains $required) { Record-Failure 'authority_action_missing' $required }
}

$build = Read-Json $BuildManifestPath
$runtime = Read-Json $RuntimeManifestPath
$process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
if ($null -eq $process -or $process.MainWindowHandle -eq 0) {
    Record-Failure 'window_missing' 'target process has no main window'
}
$exePath = [IO.Path]::GetFullPath($process.Path)
if ($exePath -ne [IO.Path]::GetFullPath([string]$build.executablePath)) {
    Record-Failure 'process_path_mismatch' 'live executable differs from build binding'
}
if ((Get-Sha $exePath) -ne ([string]$build.executableSha256).ToLowerInvariant()) {
    Record-Failure 'process_hash_mismatch' 'live executable hash differs from build binding'
}
$governedRoot = [IO.Path]::GetFullPath([string]$build.governedRoot).TrimEnd('\')
if (-not $exePath.StartsWith($governedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    Record-Failure 'process_root_mismatch' 'live executable is outside governed root'
}
$payloadPath = [IO.Path]::GetFullPath([string]$build.payloadPath)
if (-not $payloadPath.StartsWith($governedRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
    Record-Failure 'payload_path_mismatch' 'authoritative app.so is missing or outside governed root'
}
$payloadSha256 = Get-Sha $payloadPath
if ($payloadSha256 -ne ([string]$build.payloadSha256).ToLowerInvariant() -or
    $payloadSha256 -ne ([string]$runtime.payloadSha256).ToLowerInvariant()) {
    Record-Failure 'payload_hash_mismatch' 'live app.so differs from build/runtime binding'
}
if ([string]$runtime.buildBindingId -ne [string]$build.bindingId) {
    Record-Failure 'runtime_build_mismatch' 'runtime references another build binding'
}
if ([string]$authority.buildBindingId -ne [string]$build.bindingId -or
    [string]$authority.runtimeBindingId -ne [string]$runtime.runtimeBindingId -or
    [string]$authority.runId -ne [string]$runtime.runId) {
    Record-Failure 'authority_binding_mismatch' 'authority does not bind this exact build/runtime/run'
}
if ($ProcessId -notin @([int]$runtime.roomPid, [int]$runtime.corePid, [int]$runtime.portOwnerPid)) {
    Record-Failure 'runtime_pid_mismatch' 'capture PID is absent from runtime identity bundle'
}
$processCreationUtc = ([DateTimeOffset]$process.StartTime).ToUniversalTime()
$runtimeCreationUtc = [DateTimeOffset]::Parse([string]$runtime.processCreationUtc).ToUniversalTime()
$boundAtUtc = [DateTimeOffset]::Parse([string]$build.boundAtUtc).ToUniversalTime()
if ($processCreationUtc -lt $boundAtUtc -or [Math]::Abs(($processCreationUtc - $runtimeCreationUtc).TotalSeconds) -gt 1) {
    Record-Failure 'stale_process_identity' "processCreationUtc=$($processCreationUtc.ToString('o'));boundAtUtc=$($boundAtUtc.ToString('o'))"
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class KaiPizzaNativeCapture {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint flags);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}
'@

if (-not [KaiPizzaNativeCapture]::SetProcessDpiAwarenessContext([IntPtr](-4))) {
    Record-Failure 'dpi_awareness_unset' 'Per-monitor-v2 DPI awareness could not be established'
}
$hwnd = [IntPtr]$process.MainWindowHandle
$dpi = [int][KaiPizzaNativeCapture]::GetDpiForWindow($hwnd)
if ($dpi -lt 96 -or $dpi -gt 768) { Record-Failure 'invalid_dpi' "dpi=$dpi" $dpi }

$root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
if ($null -eq $root) { Record-Failure 'uia_root_missing' 'UI Automation root unavailable' $dpi }
$all = $root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition
)

if ($NavigationMode -eq 'ui_automation') {
    $target = $null
    foreach ($element in $all) {
        if ($element.Current.Name -in @('Project Sovereignty Matrix', 'Pizza', 'Project Sovereignty')) {
            $target = $element; break
        }
    }
    if ($null -eq $target) { Record-Failure 'navigation_target_missing' 'Pizza navigation semantic target unavailable' $dpi }
    $pattern = $null
    if (-not $target.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        Record-Failure 'navigation_not_invocable' 'Pizza target has no supported Invoke pattern' $dpi
    }
    ([System.Windows.Automation.InvokePattern]$pattern).Invoke()
    Start-Sleep -Milliseconds 500
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
}

$requiredLabels = @('Project Sovereignty Matrix', 'Homecoming', 'Hoard', 'Kingdom', 'Factory', 'Verified', 'Active', 'Awaiting sponsor', 'Blocked')
$semanticLabels = @()
$screenLabelRects = @{}
$labelCounts = @{}
foreach ($element in $all) {
    $name = [string]$element.Current.Name
    if ($requiredLabels -contains $name) {
        $semanticLabels += $name
        $labelCounts[$name] = 1 + [int]$labelCounts[$name]
        $rect = $element.Current.BoundingRectangle
        $screenLabelRects[$name] = [ordered]@{ left = $rect.Left; top = $rect.Top; right = $rect.Right; bottom = $rect.Bottom }
    }
}
$invalidCardinality = @($requiredLabels | Where-Object { [int]$labelCounts[$_] -ne 1 })
if ($invalidCardinality.Count -gt 0) { Record-Failure 'semantic_label_cardinality' ($invalidCardinality -join ',') $dpi }
$semanticLabels = @($requiredLabels)

$clientRect = New-Object KaiPizzaNativeCapture+RECT
$clientOrigin = New-Object KaiPizzaNativeCapture+POINT
if (-not [KaiPizzaNativeCapture]::GetClientRect($hwnd, [ref]$clientRect) -or
    -not [KaiPizzaNativeCapture]::ClientToScreen($hwnd, [ref]$clientOrigin)) {
    Record-Failure 'client_rect_failed' 'Client-space geometry could not be resolved' $dpi
}
$width = $clientRect.Right - $clientRect.Left
$height = $clientRect.Bottom - $clientRect.Top
if ($width -lt 900 -or $height -lt 600) { Record-Failure 'window_too_small' "${width}x${height}" $dpi }

$clipping = 0
$labelRectsByName = @{}
foreach ($name in $requiredLabels) {
    $screenRect = $screenLabelRects[$name]
    $r = [ordered]@{
        left = [Math]::Round($screenRect.left - $clientOrigin.X)
        top = [Math]::Round($screenRect.top - $clientOrigin.Y)
        right = [Math]::Round($screenRect.right - $clientOrigin.X)
        bottom = [Math]::Round($screenRect.bottom - $clientOrigin.Y)
    }
    $labelRectsByName[$name] = $r
    if ($r.left -lt 0) { $clipping += [Math]::Ceiling(-$r.left) }
    if ($r.top -lt 0) { $clipping += [Math]::Ceiling(-$r.top) }
    if ($r.right -gt $width) { $clipping += [Math]::Ceiling($r.right - $width) }
    if ($r.bottom -gt $height) { $clipping += [Math]::Ceiling($r.bottom - $height) }
}

$overlapPairs = @()
$keys = @($requiredLabels)
for ($i = 0; $i -lt $keys.Count; $i++) {
    for ($j = $i + 1; $j -lt $keys.Count; $j++) {
        $a = $labelRectsByName[$keys[$i]]; $b = $labelRectsByName[$keys[$j]]
        $overlapWidth = [Math]::Min($a.right, $b.right) - [Math]::Max($a.left, $b.left)
        $overlapHeight = [Math]::Min($a.bottom, $b.bottom) - [Math]::Max($a.top, $b.top)
        if ($overlapWidth -gt 2 -and $overlapHeight -gt 2) { $overlapPairs += "$($keys[$i])|$($keys[$j])" }
    }
}
if ($clipping -ne 0 -or $overlapPairs.Count -ne 0) {
    Record-Failure 'layout_assertion_failed' "clipping=$clipping;overlaps=$($overlapPairs -join ',')" $dpi
}

$outputParent = Split-Path -Parent $OutputPath
if ($outputParent -and -not (Test-Path -LiteralPath $outputParent)) { New-Item -ItemType Directory -Path $outputParent | Out-Null }
$bitmap = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$hdc = $graphics.GetHdc()
try {
    if (-not [KaiPizzaNativeCapture]::PrintWindow($hwnd, $hdc, 3)) {
        Record-Failure 'print_window_failed' 'PrintWindow returned false' $dpi
    }
}
finally {
    $graphics.ReleaseHdc($hdc)
    $graphics.Dispose()
}
$readability = @()
foreach ($name in $requiredLabels) {
    $r = $labelRectsByName[$name]
    $labelHeight = [int]($r.bottom - $r.top)
    if ($labelHeight -lt 12) { Record-Failure 'label_too_small' "$name height=$labelHeight" $dpi }
    $minLum = 255.0; $maxLum = 0.0; $sum = 0.0; $sumSq = 0.0; $samples = 0
    $left = [Math]::Max(0, [int]$r.left); $top = [Math]::Max(0, [int]$r.top)
    $right = [Math]::Min($width, [int]$r.right); $bottom = [Math]::Min($height, [int]$r.bottom)
    for ($y = $top; $y -lt $bottom; $y += 2) {
        for ($x = $left; $x -lt $right; $x += 2) {
            $pixel = $bitmap.GetPixel($x, $y)
            $lum = (0.2126 * $pixel.R) + (0.7152 * $pixel.G) + (0.0722 * $pixel.B)
            $minLum = [Math]::Min($minLum, $lum); $maxLum = [Math]::Max($maxLum, $lum)
            $sum += $lum; $sumSq += $lum * $lum; $samples++
        }
    }
    if ($samples -eq 0) { Record-Failure 'label_unreadable' "$name has no sampleable pixels" $dpi }
    $mean = $sum / $samples
    $stdDev = [Math]::Sqrt([Math]::Max(0, ($sumSq / $samples) - ($mean * $mean)))
    $contrast = ($maxLum + 12.75) / ($minLum + 12.75)
    if ($contrast -lt 4.5 -or $stdDev -lt 8) { Record-Failure 'label_unreadable' "$name contrast=$contrast stdDev=$stdDev" $dpi }
    $readability += [ordered]@{ name = $name; heightPx = $labelHeight; contrastRatio = [Math]::Round($contrast, 3); luminanceStdDev = [Math]::Round($stdDev, 3) }
}
$bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()

$previousFingerprints = @()
if (Test-Path -LiteralPath $FailedAttemptLedgerPath) {
    $previousFingerprints = @(Read-Json $FailedAttemptLedgerPath | ForEach-Object { [string]$_.fingerprint })
}
$labelRects = @($requiredLabels | ForEach-Object {
    $r = $labelRectsByName[$_]
    [ordered]@{ name = $_; left = $r.left; top = $r.top; right = $r.right; bottom = $r.bottom }
})
$cycleFinished = [DateTimeOffset]::UtcNow
$manifest = [ordered]@{
    schemaVersion = 1
    captureId = "real-pizza-$([DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ'))"
    proofKind = 'real_desktop_window'
    testFixture = $false
    captureMethod = 'print_window_direct'
    buildBindingId = $build.bindingId
    runtimeBindingId = $runtime.runtimeBindingId
    runId = $runtime.runId
    governedRoot = $governedRoot
    authorityId = $authority.authorityId
    process = [ordered]@{
        pid = $ProcessId
        executablePath = $exePath
        executableSha256 = Get-Sha $exePath
        payloadPath = $payloadPath
        payloadSha256 = $payloadSha256
        processCreationUtc = $processCreationUtc.ToString('o')
    }
    window = [ordered]@{
        hwnd = [long]$hwnd
        title = $process.MainWindowTitle
        dpi = $dpi
        clientLeft = 0; clientTop = 0; clientRight = $width; clientBottom = $height
    }
    navigation = [ordered]@{ target = 'Project Sovereignty Matrix'; mode = $NavigationMode; strategyId = $StrategyId }
    imagePath = [IO.Path]::GetFullPath($OutputPath)
    imageSha256 = Get-Sha $OutputPath
    semanticLabels = $semanticLabels
    labelRects = $labelRects
    visualAssertions = [ordered]@{ clippingPixels = $clipping; overlapPairs = $overlapPairs; readability = $readability }
    cycleStartedAt = $cycleStarted.ToString('o')
    cycleFinishedAt = $cycleFinished.ToString('o')
    failedCaptureFingerprints = $previousFingerprints
    manualStepsRemoved = @('manual process-path transcription', 'manual DPI lookup', 'manual direct-window crop', 'manual image hash calculation', 'manual label-boundary comparison')
}
$manifest.captureBindingId = Get-CaptureBinding $manifest
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $CaptureManifestPath -Encoding UTF8
Write-Output ([ordered]@{
    verdict = 'CAPTURED_PENDING_PIPELINE_VALIDATION'
    captureBindingId = $manifest.captureBindingId
    captureManifestPath = [IO.Path]::GetFullPath($CaptureManifestPath)
    imageSha256 = $manifest.imageSha256
} | ConvertTo-Json -Depth 4)
