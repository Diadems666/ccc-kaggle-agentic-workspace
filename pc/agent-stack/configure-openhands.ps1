<#
.SYNOPSIS
  Pre-configure OpenHands (LLM via LiteLLM + MCP research tools) through its settings API.
.DESCRIPTION
  Idempotent. Reads LITELLM_MASTER_KEY from .env. Run after start-agent-stack.ps1.
  Usage: powershell -ExecutionPolicy Bypass -File configure-openhands.ps1 [-Model ccc-local]
#>
param([string]$Model = 'ccc-local', [string]$Base = 'http://127.0.0.1:3100')
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$key = $null
foreach ($line in Get-Content '.env') {
    if ($line -match '^LITELLM_MASTER_KEY=(\S+)') { $key = $Matches[1] }
}
if (-not $key) { throw 'LITELLM_MASTER_KEY missing in .env' }

$payload = @{
    agent_settings_diff = @{
        llm = @{
            model    = "openai/$Model"
            base_url = 'http://host.docker.internal:4000'
            api_key  = $key
        }
        mcp_config = @{
            mcpServers = @{
                'ccc-research' = @{
                    url       = 'http://host.docker.internal:8775/mcp'
                    transport = 'streamable-http'
                }
            }
        }
    }
} | ConvertTo-Json -Depth 8

Invoke-RestMethod -Method Post -Uri "$Base/api/v1/settings" -ContentType 'application/json' -Body $payload | Out-Null
$s = Invoke-RestMethod -Uri "$Base/api/v1/settings"
Write-Host "model:   $($s.agent_settings.llm.model)"
Write-Host "base:    $($s.agent_settings.llm.base_url)"
Write-Host "mcp:     $(($s.agent_settings.mcp_config.mcpServers.PSObject.Properties.Name) -join ', ')"
Write-Host "api key set: $($s.llm_api_key_set)"
