[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExpectedExecutablePath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Fa-f0-9]{64}$')]
    [string]$ExpectedExecutableSha256,

    [ValidateRange(5, 60)]
    [int]$TimeoutSeconds = 20,

    [string]$ControlFilePath =
        (Join-Path $env:LOCALAPPDATA 'Homecoming\KaiCore\shutdown-control.json')
)

$ErrorActionPreference = 'Stop'

function Normalize-Path([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Fail([string]$Reason) {
    [pscustomobject]@{
        verdict = 'FAIL'
        reason = $Reason
    } | ConvertTo-Json -Compress
    exit 1
}

if (-not (Test-Path -LiteralPath $ControlFilePath -PathType Leaf)) {
    Fail 'The current coordinator did not publish a shutdown capability.'
}
if (-not (Test-Path -LiteralPath $ExpectedExecutablePath -PathType Leaf)) {
    Fail 'The independently supplied expected executable does not exist.'
}

$expectedPath = Normalize-Path $ExpectedExecutablePath
$expectedHash = $ExpectedExecutableSha256.ToUpperInvariant()
$actualHash = (Get-FileHash -LiteralPath $expectedPath -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
    Fail 'The independently supplied executable hash does not match.'
}

$control = Get-Content -Raw -LiteralPath $ControlFilePath | ConvertFrom-Json
if ([int]$control.version -ne 1 -or [int]$control.pid -le 0 -or
    [int]$control.port -le 0 -or [string]::IsNullOrWhiteSpace($control.runId) -or
    [string]::IsNullOrWhiteSpace($control.capability)) {
    Fail 'The shutdown capability file is malformed.'
}
if ((Normalize-Path ([string]$control.executablePath)) -ne $expectedPath) {
    Fail 'The capability is bound to a different executable path.'
}

$core = Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$control.pid)"
if ($null -eq $core -or (Normalize-Path ([string]$core.ExecutablePath)) -ne $expectedPath -or
    -not ([string]$core.CommandLine).Contains('--coordinator-worker')) {
    Fail 'The capability PID is not the expected coordinator process.'
}

$allKai = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq [IO.Path]::GetFileName($expectedPath)
})
$watchdogs = @($allKai | Where-Object {
    [int]$_.ParentProcessId -eq [int]$control.pid -and
    (Normalize-Path ([string]$_.ExecutablePath)) -eq $expectedPath -and
    ([string]$_.CommandLine) -match "--watchdog\s+--watch-pid=$([int]$control.pid)(?:\s|$)"
})
if ($watchdogs.Count -ne 1) {
    Fail 'The coordinator does not have exactly one matching watchdog.'
}

$owners = @(Get-NetTCPConnection -State Listen -LocalPort 8790 -ErrorAction SilentlyContinue)
if ($owners.Count -ne 1 -or [int]$owners[0].OwningProcess -ne [int]$control.pid) {
    Fail 'Port 8790 is not owned by the capability-bound coordinator.'
}

$headers = @{ Authorization = "Bearer $([string]$control.capability)" }
$body = @{
    runId = [string]$control.runId
    pid = [int]$control.pid
} | ConvertTo-Json -Compress
$uri = "http://127.0.0.1:$([int]$control.port)/v1/shutdown"

try {
    $receipt = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers `
        -ContentType 'application/json' -Body $body -TimeoutSec 5
} finally {
    $headers.Authorization = $null
    $control.capability = $null
}

if (-not $receipt.accepted -or [int]$receipt.pid -ne [int]$core.ProcessId -or
    [string]$receipt.runId -ne [string]$control.runId) {
    Fail 'The shutdown receipt did not match the bound runtime identity.'
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
    Start-Sleep -Milliseconds 250
    $coreAlive = $null -ne (Get-Process -Id ([int]$core.ProcessId) -ErrorAction SilentlyContinue)
    $watchdogAlive = $null -ne (Get-Process -Id ([int]$watchdogs[0].ProcessId) -ErrorAction SilentlyContinue)
} while (($coreAlive -or $watchdogAlive) -and (Get-Date) -lt $deadline)

if ($coreAlive -or $watchdogAlive) {
    Fail 'The coordinator or watchdog did not exit inside the bounded timeout.'
}
if (@(Get-NetTCPConnection -State Listen -LocalPort 8790 -ErrorAction SilentlyContinue).Count -ne 0) {
    Fail 'Port 8790 remained open after the normal coordinator exit.'
}

[pscustomobject]@{
    verdict = 'PASS'
    corePid = [int]$core.ProcessId
    watchdogPid = [int]$watchdogs[0].ProcessId
    executablePath = $expectedPath
    executableSha256 = $actualHash
    exit = 'normal_request_completed'
    port8790Closed = $true
} | ConvertTo-Json -Compress
