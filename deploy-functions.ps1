# Deploy Cloud Functions with Environment Variables
# This script deploys functions using your OpenAI API key from GitHub Secrets

Write-Host "🔥 Deploying Kai Brain Cloud Functions..." -ForegroundColor Cyan

# Check if OPENAI_API_KEY is set
if (-not $env:OPENAI_API_KEY) {
    Write-Host "❌ ERROR: OPENAI_API_KEY environment variable not set" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please set your OpenAI API key:" -ForegroundColor Yellow
    Write-Host '  $env:OPENAI_API_KEY = "sk-proj-YOUR_KEY_HERE"' -ForegroundColor Gray
    Write-Host ""
    Write-Host "Or create functions/.env file with:" -ForegroundColor Yellow
    Write-Host '  OPENAI_API_KEY=sk-proj-YOUR_KEY_HERE' -ForegroundColor Gray
    exit 1
}

# Create .env file for deployment
Write-Host "📝 Creating .env file for Cloud Functions..." -ForegroundColor Yellow
Set-Content -Path "functions\.env" -Value "OPENAI_API_KEY=$env:OPENAI_API_KEY"

# Deploy functions
Write-Host "🚀 Deploying to Firebase..." -ForegroundColor Green
firebase deploy --only functions --project homecoming-74f73

# Cleanup
Write-Host "🧹 Cleaning up..." -ForegroundColor Yellow
Remove-Item "functions\.env" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "✅ Deployment complete!" -ForegroundColor Green
Write-Host "🔍 Check logs with: gcloud functions logs read onTurnWrite --limit=5 --project=homecoming-74f73" -ForegroundColor Cyan
