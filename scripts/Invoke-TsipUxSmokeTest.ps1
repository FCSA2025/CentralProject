#Requires -Version 5.1
<#
.SYNOPSIS
    Verify TSIP onboarding UX elements are present in deployed views and shell loads.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.cloudmicsdev.ca/mics/',
    [string]$User = 'bchy1',
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
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/login.aspx') -Method POST -Body @{ user = $User; password = $Password } -WebSession $session -MaximumRedirection 10 -UseBasicParsing

$checks = @(
    @{ Name = 'tsip-parm workflow strip'; Url = 'RemIcsReWrite/views/tsip-parm.html'; Pattern = 'tsip-workflow-strip' },
    @{ Name = 'tsip-parm empty tree'; Url = 'RemIcsReWrite/views/tsip-parm.html'; Pattern = 'tsip-tree-empty' },
    @{ Name = 'tsip-parm badge legend'; Url = 'RemIcsReWrite/views/tsip-parm.html'; Pattern = 'tsip-badge-legend' },
    @{ Name = 'tsip-parm renamed batch btn'; Url = 'RemIcsReWrite/views/tsip-parm.html'; Pattern = 'Run all runs in file' },
    @{ Name = 'tsip-parm Add run btn'; Url = 'RemIcsReWrite/views/tsip-parm.html'; Pattern = 'Add run' },
    @{ Name = 'tsip-run step banner'; Url = 'RemIcsReWrite/views/tsip-run.html'; Pattern = 'tsip-run-step-banner' },
    @{ Name = 'tsip-run field hints'; Url = 'RemIcsReWrite/views/tsip-run.html'; Pattern = 'Proposed system' },
    @{ Name = 'welcome TSIP quick start'; Url = 'RemIcsReWrite/views/welcome.html'; Pattern = 'TSIP quick start' },
    @{ Name = 'shell CSS workflow'; Url = 'RemIcsReWrite/assets/remics-shell.css'; Pattern = 'tsip-workflow-strip' },
    @{ Name = 'remics-tsip.js workflow'; Url = 'RemIcsReWrite/js/remics-tsip.js'; Pattern = 'updateWorkflowStep' }
)

$failures = @()
foreach ($c in $checks) {
    $resp = Invoke-WebRequest -Uri ($base + $c.Url) -WebSession $session -UseBasicParsing
    if ($resp.Content -notmatch $c.Pattern) {
        $failures += "$($c.Name): missing '$($c.Pattern)'"
    } else {
        Write-Host "OK $($c.Name)"
    }
}

# API smoke: files list + session still work on TSIP path
$sess = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/session.ashx') -WebSession $session -UseBasicParsing
$sj = $sess.Content | ConvertFrom-Json
if (-not $sj.ok) { $failures += 'session.ashx failed after login' }
else { Write-Host "OK session schema=$($sj.schema)" }

$files = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/files.ashx?filetype=TsipParm') -WebSession $session -UseBasicParsing
$fj = $files.Content | ConvertFrom-Json
if (-not $fj.ok) { $failures += 'files.ashx TsipParm list failed' }
else { Write-Host "OK TsipParm file count=$($fj.files.Count)" }

if ($failures.Count -gt 0) {
    Write-Host 'FAIL TSIP UX test:'
    $failures | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

Write-Host "PASS TSIP onboarding UX deploy check ($User)"
