#Requires -Version 5.1
<#
.SYNOPSIS
    Tier-1 smoke test: RemIcsReWrite login + session.ashx JSON health.

.DESCRIPTION
    POSTs to login.aspx, follows TloginValidate bootstrap, then GETs session.ashx.
    Pass when session reports ok=true with schema and FCSASESS.

.PARAMETER BaseUrl
    Site root including /mics/ path, e.g. http://remicsdev.cloudmicsdev.ca/mics/

.PARAMETER User
    MICS user id (default rctl1).

.PARAMETER Password
    Password; falls back to MICS_TEST_PASSWORD / .env.local.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.cloudmicsdev.ca/mics/',
    [string]$User = 'rctl1',
    [string]$Password = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-EnvLocalValue {
    param([string]$Key)
    $envFile = Join-Path $repoRoot '.env.local'
    if (-not (Test-Path $envFile)) { return $null }
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.+?)\s*$") {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

if (-not $Password) { $Password = $env:MICS_TEST_PASSWORD }
if (-not $Password) { $Password = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
if (-not $Password) { $Password = 'x' }

$base = $BaseUrl.TrimEnd('/') + '/'
$loginUrl = $base + 'RemIcsReWrite/login.aspx'
$sessionUrl = $base + 'RemIcsReWrite/session.ashx'
$shellUrl = $base + 'RemIcsReWrite/shell.aspx'

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$body = @{ user = $User; password = $Password }

Write-Host "POST $loginUrl"
$loginResp = Invoke-WebRequest -Uri $loginUrl -Method POST -Body $body -WebSession $session -MaximumRedirection 10 -UseBasicParsing
Write-Host ("Login final URL: {0} status={1}" -f $loginResp.BaseResponse.ResponseUri.AbsoluteUri, $loginResp.StatusCode)

Write-Host "GET $sessionUrl"
$sessionResp = Invoke-WebRequest -Uri $sessionUrl -WebSession $session -UseBasicParsing
$json = $sessionResp.Content | ConvertFrom-Json

Write-Host ($json | ConvertTo-Json -Compress)

$pass = ($json.ok -eq $true) -and $json.schema -and $json.fcsasess
if (-not $pass) {
    Write-Error "RemIcsReWrite session smoke FAILED"
}

Write-Host "GET $shellUrl (expect 200)"
$shellResp = Invoke-WebRequest -Uri $shellUrl -WebSession $session -UseBasicParsing
if ($shellResp.StatusCode -ne 200) {
    Write-Error "shell.aspx returned $($shellResp.StatusCode)"
}

Write-Host "PASS: RemIcsReWrite Tier-1 session smoke"
