#Requires -Version 5.1
<#
.SYNOPSIS
    Gate E: TS/ES create/delete honesty — pre-check exists, create, duplicate reject, delete.

.PARAMETER Users
    Roster logins (default bchy1, rctl1, xci1).

.PARAMETER FileType
    TS or ES (default TS).
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.cloudmicsdev.ca/mics/',
    [string[]]$Users = @('bchy1', 'rctl1', 'xci1'),
    [string]$Password = '',
    [ValidateSet('TS', 'ES')]
    [string]$FileType = 'TS',
    [string]$FileName = 'gatee01'
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

function Get-AsmxString {
    param([object]$Resp)
    if ($Resp.Content -match '"d"\s*:\s*"([^"]*)"') { return $Matches[1] }
    return $Resp.Content.Trim()
}

function Invoke-MicsSession {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,
        [string]$User
    )
    $null = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/login.aspx') -Method POST `
        -Body @{ user = $User; password = $Password } -WebSession $WebSession -MaximumRedirection 10 -UseBasicParsing
    $sess = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/session.ashx') -WebSession $WebSession -UseBasicParsing
    $json = $sess.Content | ConvertFrom-Json
    if (-not $json.ok) { throw "Login failed for $User" }
    return $json
}

function Invoke-TabUtil {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,
        [string]$Method,
        [hashtable]$Params
    )
    $url = $base + 'Tfileactions/TwsTabUtil.asmx/' + $Method
    $resp = Invoke-WebRequest -Uri $url -Method POST -Body ($Params | ConvertTo-Json -Compress) `
        -ContentType 'application/json; charset=utf-8' -WebSession $WebSession -UseBasicParsing
    $body = Get-AsmxString $resp
    $ok = $resp.StatusCode -eq 200 -and $body -notmatch '^(timeout|ERRORSYS:)'
    if ($body -match '^ERROR' -and $body -notmatch '^ERRORS') { $ok = $false }
    return [pscustomobject]@{ ok = $ok; body = $body }
}

function Invoke-FilesExists {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,
        [string]$Name,
        [string]$Ft
    )
    $url = $base + 'RemIcsReWrite/files.ashx?filetype=' + [uri]::EscapeDataString($Ft) +
        '&name=' + [uri]::EscapeDataString($Name)
    $resp = Invoke-WebRequest -Uri $url -WebSession $WebSession -UseBasicParsing
    return $resp.Content | ConvertFrom-Json
}

function Invoke-UserGateE {
    param([string]$User)

    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $sess = Invoke-MicsSession -WebSession $session -User $User
    $schema = [string]$sess.schema
    $project = $User + '_0'
    $failures = @()

    Write-Host "=== Gate E user=$User schema=$schema filetype=$FileType ==="

    $null = Invoke-TabUtil -WebSession $session -Method 'killTable' -Params @{
        filename = $FileName; filetype = $FileType; projectCode = $project
    }

    $ex0 = Invoke-FilesExists -WebSession $session -Name $FileName -Ft $FileType
    if ($ex0.exists) {
        $failures += "pre-check: $FileName should not exist after cleanup"
    } else {
        Write-Host 'OK pre-cleanup absent'
    }

    $create = Invoke-TabUtil -WebSession $session -Method 'createTable' -Params @{
        filename = $FileName; filetype = $FileType; projectCode = $project
    }
    if (-not $create.ok -and $create.body -notmatch '^OK') {
        $failures += "createTable failed: $($create.body)"
        return $failures
    }
    Write-Host 'OK createTable'

    $ex1 = Invoke-FilesExists -WebSession $session -Name $FileName -Ft $FileType
    if (-not $ex1.ok -or -not $ex1.exists) {
        $failures += 'files.ashx should report exists after create'
    } else {
        Write-Host 'OK files.ashx exists after create'
    }

    $dup = Invoke-FilesExists -WebSession $session -Name $FileName -Ft $FileType
    if (-not $dup.exists -or -not $dup.catalogExists) {
        $failures += 'duplicate pre-check: catalogExists missing'
    } else {
        Write-Host 'OK duplicate pre-check (catalogExists)'
    }

    $create2 = Invoke-TabUtil -WebSession $session -Method 'createTable' -Params @{
        filename = $FileName; filetype = $FileType; projectCode = $project
    }
    if ($create2.ok -and $create2.body -match '^OK') {
        $failures += 'second createTable should not succeed'
    } else {
        Write-Host "OK duplicate create rejected ($($create2.body))"
    }

    $kill = Invoke-TabUtil -WebSession $session -Method 'killTable' -Params @{
        filename = $FileName; filetype = $FileType; projectCode = $project
    }
    if (-not $kill.ok -and $kill.body -notmatch '^OK') {
        $failures += "killTable failed: $($kill.body)"
    } else {
        Write-Host 'OK killTable'
    }

    $ex2 = Invoke-FilesExists -WebSession $session -Name $FileName -Ft $FileType
    if ($ex2.exists) {
        $failures += 'files.ashx should report absent after delete'
    } else {
        Write-Host 'OK files.ashx absent after delete'
    }

    return $failures
}

$jsTs = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/js/remics-ts.js?v=gateE') -UseBasicParsing
$jsApi = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/remics-api.js?v=gateE') -UseBasicParsing
$jsFailures = @()
if ($jsTs.Content -notmatch 'function treeHasFile') { $jsFailures += 'remics-ts.js missing treeHasFile' }
if ($jsTs.Content -notmatch 'function createFileFailedMsg') { $jsFailures += 'remics-ts.js missing createFileFailedMsg' }
if ($jsTs.Content -notmatch 'function fileDeleteFailedMsg') { $jsFailures += 'remics-ts.js missing fileDeleteFailedMsg' }
if ($jsApi.Content -notmatch 'Invalid return code from KillTable') { $jsFailures += 'remics-api.js missing KillTable friendly message' }

$allFailures = @($jsFailures)
foreach ($user in $Users) {
    try {
        $userFails = @(Invoke-UserGateE -User $user)
        if ($userFails.Count -gt 0) {
            foreach ($f in $userFails) { $allFailures += "$user : $f" }
        } else {
            Write-Host "PASS Gate E for $user"
        }
    } catch {
        $allFailures += "$user : $($_.Exception.Message)"
    }
}

if ($allFailures.Count -gt 0) {
    Write-Host 'FAIL Gate E file-op test:'
    $allFailures | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

Write-Host ("PASS Gate E file-op ({0} users, {1})" -f $Users.Count, $FileType)
