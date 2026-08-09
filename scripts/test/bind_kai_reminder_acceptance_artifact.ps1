[CmdletBinding()]
param(
    [string]$GovernedRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$ManifestPath,
    [string]$ForbiddenLiveRoot = 'C:\code\homecoming_app'
)

$ErrorActionPreference = 'Stop'

function Get-StringSha256 {
    param([string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Resolve-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    throw 'ManifestPath is required; acceptance artifacts are never bound implicitly.'
}

$root = Resolve-FullPath $GovernedRoot
$forbidden = Resolve-FullPath $ForbiddenLiveRoot
if ($root.Equals($forbidden, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to build or bind from the live C:\code\homecoming_app runtime root.'
}

$gitRoot = (& git -C $root rev-parse --show-toplevel 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitRoot)) {
    throw 'GovernedRoot is not a Git worktree.'
}
$gitRoot = Resolve-FullPath $gitRoot
if (-not $gitRoot.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'GovernedRoot must be the exact Git worktree root.'
}

$relativeExecutable = 'build\windows\x64\runner\Release\Kai.exe'
$relativePayload = 'build\windows\x64\runner\Release\data\app.so'
$secretsPath = Join-Path $root 'lib\secrets.dart'
if (-not (Test-Path -LiteralPath $secretsPath -PathType Leaf)) {
    throw 'Credential-free lib\secrets.dart build stub is required.'
}
$secretsText = (Get-Content -Raw -LiteralPath $secretsPath -Encoding UTF8).Replace("`r`n", "`n")
foreach ($name in @('kOpenAIKey','kElevenLabsKey','kGoogleApiKey','kGoogleCseId','kElevenLabsVoiceId')) {
    if ($secretsText -notmatch "(?m)^const String $name = '';$") {
        throw "Refusing to bind an artifact whose $name is not empty."
    }
}
$executablePath = Join-Path $root $relativeExecutable
$payloadPath = Join-Path $root $relativePayload
foreach ($path in @($executablePath, $payloadPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Accepted artifact is incomplete: $path"
    }
}

$executable = Get-Item -LiteralPath $executablePath
$payload = Get-Item -LiteralPath $payloadPath
$commit = (& git -C $root rev-parse HEAD 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') {
    throw 'Could not bind the artifact to a source commit.'
}
$runtimeSourceFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $root 'lib'),(Join-Path $root 'windows') -File -Recurse |
        Where-Object {
            -not $_.FullName.Equals($secretsPath, [StringComparison]::OrdinalIgnoreCase) -and
            $_.FullName -notmatch '[\\/]windows[\\/]flutter[\\/]ephemeral[\\/]'
        }
    Get-Item -LiteralPath (Join-Path $root 'pubspec.yaml'),(Join-Path $root 'pubspec.lock')
) | Sort-Object FullName
$runtimeSourceInventory = @($runtimeSourceFiles | ForEach-Object {
    $relative = $_.FullName.Substring($root.Length + 1).Replace('\','/')
    "$relative=$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())"
}) -join [char]31
$maxSourceLastWriteUtc = @($runtimeSourceFiles + (Get-Item -LiteralPath $secretsPath) |
    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc.ToUniversalTime()
if ($payload.LastWriteTimeUtc.ToUniversalTime() -lt $maxSourceLastWriteUtc) {
    throw 'Refusing to bind a payload older than a compiled source input.'
}

$acceptedAt = (Get-Date).ToUniversalTime()
$fields = [ordered]@{
    schemaVersion = 1
    governedRoot = $root
    sourceCommit = $commit.ToLowerInvariant()
    # Exact content fingerprint of every compiled project input. Documentation,
    # tests, build output and the credential stub are bound separately or do
    # not affect app.so.
    sourceStatusSha256 = Get-StringSha256 $runtimeSourceInventory
    maxSourceLastWriteUtc = $maxSourceLastWriteUtc.ToString('o')
    buildCredentialProfile = 'empty-local-build-stub-v1'
    buildCredentialStubSha256 = Get-StringSha256 $secretsText
    executableRelativePath = $relativeExecutable
    executableSha256 = (Get-FileHash -LiteralPath $executablePath -Algorithm SHA256).Hash.ToLowerInvariant()
    executableLength = $executable.Length
    payloadRelativePath = $relativePayload
    payloadSha256 = (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
    payloadLength = $payload.Length
    payloadLastWriteUtc = $payload.LastWriteTimeUtc.ToString('o')
    acceptedAtUtc = $acceptedAt.ToString('o')
}
$canonical = @($fields.Keys | ForEach-Object { "$_=$($fields[$_])" }) -join [char]31
$manifest = [ordered]@{}
foreach ($key in $fields.Keys) { $manifest[$key] = $fields[$key] }
$manifest.bindingId = Get-StringSha256 $canonical

$manifestFullPath = [System.IO.Path]::GetFullPath($ManifestPath)
$parent = Split-Path -Parent $manifestFullPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestFullPath -Encoding UTF8
Write-Output ($manifest | ConvertTo-Json -Depth 5)
