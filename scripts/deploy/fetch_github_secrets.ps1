#!/usr/bin/env pwsh
<#
.SYNOPSIS
Load GitHub secrets using REST API (no CLI needed)

.DESCRIPTION
Fetches your repository secrets from GitHub Actions using your personal access token.
Requires: GITHUB_TOKEN environment variable set to your Personal Access Token

.EXAMPLE
$env:GITHUB_TOKEN = "ghp_..."
.\fetch_github_secrets.ps1

#>

param(
    [string]$Owner = "YOUR_GITHUB_USERNAME",
    [string]$Repo = "homecoming_app",
    [string]$Token = $env:GITHUB_TOKEN
)

if (-not $Token) {
    Write-Host "
❌ GITHUB_TOKEN not set!

To fetch secrets from GitHub, you need a Personal Access Token:

1. Go to: https://github.com/settings/tokens
2. Click 'Generate new token (classic)'
3. Check: 'repo' and 'admin:repo_hook'
4. Copy the token and set it:

    `$env:GITHUB_TOKEN = 'ghp_...'
    .\fetch_github_secrets.ps1

Or pass it:
    .\fetch_github_secrets.ps1 -Token 'ghp_...' -Owner 'your-username'
" -ForegroundColor Red
    exit 1
}

$headers = @{
    "Authorization" = "token $Token"
    "Accept" = "application/vnd.github.v3+json"
}

Write-Host "📡 Fetching secrets from $Owner/$Repo..." -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$Owner/$Repo/actions/secrets" `
        -Headers $headers `
        -Method Get
    
    if ($response.secrets) {
        Write-Host "✓ Found $($response.secrets.Count) secrets:" -ForegroundColor Green
        
        $secrets = @{}
        foreach ($secret in $response.secrets) {
            Write-Host "  • $($secret.name)" -ForegroundColor Yellow
            $secrets[$secret.name] = $secret.name
        }
        
        Write-Host "`n⚠️  Note: GitHub API cannot return secret VALUES (they're encrypted)" -ForegroundColor Yellow
        Write-Host "You need to view them in the GitHub UI or have access to them locally.`n"
        
        Write-Host "Available secrets:" -ForegroundColor Green
        $secrets.Keys | ForEach-Object { Write-Host "  - $_" }
    } else {
        Write-Host "❌ No secrets found" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
