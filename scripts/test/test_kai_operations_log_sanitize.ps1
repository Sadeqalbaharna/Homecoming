$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'kai_operations_log_sanitize.ps1'
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "kai-ops-sanitize-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temp | Out-Null
$log = Join-Path $temp 'kai-operations.jsonl'
$secret = 'eyJhbGciOiJub25lIn0.eyJzdWIiOiJrYWkifQ.signature'
$record = [ordered]@{
    at = '2026-08-08T09:30:00.000Z'
    event = 'request_stream_unavailable'
    component = 'coordinator'
    severity = 'warning'
    details = @{ error = "https://example.test/data?auth=$secret" }
} | ConvertTo-Json -Compress -Depth 6
Set-Content -LiteralPath $log -Value $record -Encoding UTF8

try {
    $dry = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script `
        -OperationsDirectory $temp 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $dry -notmatch '\[DRY RUN\]') {
        throw "Dry run failed: $dry"
    }
    if ((Get-Content -Raw -LiteralPath $log) -notmatch [regex]::Escape($secret)) {
        throw 'Dry run modified the journal.'
    }

    $apply = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script `
        -OperationsDirectory $temp -Apply 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $apply -notmatch '\[PASS\]') {
        throw "Apply failed: $apply"
    }
    $sanitized = Get-Content -Raw -LiteralPath $log
    if ($sanitized -match [regex]::Escape($secret)) {
        throw 'Credential remained after sanitization.'
    }
    $null = $sanitized | ConvertFrom-Json
    Write-Host '[PASS] operations log sanitizer dry-run and apply modes' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
