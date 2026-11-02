<#
.SYNOPSIS
  Render the LiteLLM config and start LiteLLM + OpenHands on this PC.
.DESCRIPTION
  Needs kaggle-access.env (CF_ACCESS_CLIENT_ID / CF_ACCESS_CLIENT_SECRET) in this
  directory. Creates .env with a random LiteLLM master key on first run.
  Usage: powershell -ExecutionPolicy Bypass -File start-agent-stack.ps1 [-Down]
#>
param([switch]$Down)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if ($Down) { docker compose down; exit 0 }

function Read-EnvFile([string]$Path) {
    $map = @{}
    foreach ($line in Get-Content $Path) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { $map[$Matches[1]] = $Matches[2].Trim() }
    }
    return $map
}

if (-not (Test-Path 'kaggle-access.env')) { throw 'kaggle-access.env not found (Cloudflare Access service token).' }
$access = Read-EnvFile 'kaggle-access.env'
foreach ($k in 'CF_ACCESS_CLIENT_ID', 'CF_ACCESS_CLIENT_SECRET') {
    if (-not $access[$k]) { throw "$k missing in kaggle-access.env" }
}

if (-not (Test-Path '.env')) { Copy-Item '.env.example' '.env' }
$envText = Get-Content '.env' -Raw
if ($envText -notmatch 'LITELLM_MASTER_KEY=\S') {
    $bytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $key = 'sk-ccc-' + ([BitConverter]::ToString($bytes) -replace '-', '').ToLower()
    $envText = $envText -replace 'LITELLM_MASTER_KEY=.*', "LITELLM_MASTER_KEY=$key"
    Set-Content '.env' $envText -NoNewline
    Write-Host 'Generated LITELLM_MASTER_KEY in .env'
}

$template = Get-Content 'litellm_config.template.yaml' -Raw
$template = $template.Replace('@@CF_ACCESS_CLIENT_ID@@', $access['CF_ACCESS_CLIENT_ID']).Replace('@@CF_ACCESS_CLIENT_SECRET@@', $access['CF_ACCESS_CLIENT_SECRET'])
Set-Content 'litellm_config.rendered.yaml' $template -NoNewline

docker compose up -d
Write-Host ''
$port = (Read-EnvFile '.env')['OPENHANDS_PORT']; if (-not $port) { $port = '3100' }
Write-Host "OpenHands:  http://localhost:$port"
Write-Host 'LiteLLM:    http://localhost:4000  (master key in .env)'
Write-Host 'In OpenHands -> Settings -> LLM (Advanced):'
Write-Host '  Model: openai/ccc-local   Base URL: http://litellm:4000 or http://host.docker.internal:4000'
Write-Host '  API key: the LITELLM_MASTER_KEY from .env'
