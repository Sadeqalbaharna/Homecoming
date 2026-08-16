[CmdletBinding()]
param(
    [string]$OperationsDirectory = $(Join-Path $env:LOCALAPPDATA 'Homecoming\KaiCore\operations'),
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$resolved = [System.IO.Path]::GetFullPath($OperationsDirectory)
if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
    Write-Host '[UNVERIFIED] Operations directory does not exist.' -ForegroundColor Yellow
    exit 2
}

$files = @(Get-ChildItem -LiteralPath $resolved -File |
    Where-Object { $_.Name -match '^kai-operations(?:\.\d+)?\.jsonl$' })
if ($files.Count -eq 0) {
    Write-Host '[UNVERIFIED] No operations journal files were found.' -ForegroundColor Yellow
    exit 2
}

function Redact-Line {
    param([string]$Line)
    $output = $Line
    $output = [regex]::Replace(
        $output,
        '(?i)([?&;,\s](?:auth|authorization|token|access_token|refresh_token|id_token|api_key|apikey|key|signature|sig)=)([^&#;,\s"\\]+)',
        '$1[REDACTED]'
    )
    $output = [regex]::Replace(
        $output,
        '(?i)(Bearer\s+)[A-Za-z0-9._~+\-/=]+',
        '$1[REDACTED]'
    )
    $output = [regex]::Replace($output, 'AIza[0-9A-Za-z_-]{20,}', '[REDACTED_GOOGLE_KEY]')
    $output = [regex]::Replace($output, '(?:sk-ant-|sk-)[0-9A-Za-z_-]{16,}', '[REDACTED_PROVIDER_KEY]')
    $output = [regex]::Replace($output, 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', '[REDACTED_JWT]')
    return $output
}

$changedFiles = 0
$changedLines = 0
foreach ($file in $files) {
    $lines = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8)
    $sanitized = @()
    $fileChanged = $false
    foreach ($line in $lines) {
        $next = Redact-Line -Line $line
        if ($next -ne $line) {
            $fileChanged = $true
            $changedLines++
        }
        $sanitized += $next
    }
    if (-not $fileChanged) { continue }
    $changedFiles++
    if (-not $Apply) { continue }

    # Validate every line before replacing the source. Never print a malformed
    # line because it may be the very credential-bearing evidence being fixed.
    foreach ($line in $sanitized) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $null = $line | ConvertFrom-Json }
        catch { throw "Sanitized output for $($file.Name) is not valid JSON; source was not replaced." }
    }
    $temp = "$($file.FullName).sanitize.tmp"
    Set-Content -LiteralPath $temp -Value $sanitized -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $file.FullName -Force
}

if ($Apply) {
    Write-Host "[PASS] Sanitized $changedLines line(s) across $changedFiles journal file(s)." -ForegroundColor Green
}
elseif ($changedFiles -gt 0) {
    Write-Host "[DRY RUN] $changedLines line(s) across $changedFiles journal file(s) require sanitization. Re-run with -Apply after approval." -ForegroundColor Yellow
}
else {
    Write-Host '[PASS] No credential-like material was found in operations journals.' -ForegroundColor Green
}
