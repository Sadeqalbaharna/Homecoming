$apiKey = Read-Host "Paste OPENAI_API_KEY from GitHub"
[Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $apiKey, "Process")
Write-Host "Set. Running..." -ForegroundColor Green
cd C:\code\homecoming_app
python kai_table_v1_core.py
