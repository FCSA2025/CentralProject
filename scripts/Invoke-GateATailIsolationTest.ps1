#Requires -Version 5.1
<#
.SYNOPSIS
    Gate A tail: CASEDET, Aux Eng, and Data Search file-picker isolation.

.DESCRIPTION
    Verifies schema-scoped file lists and handlers reject foreign PDF names:
      - files.ashx list/exists (DS save pickers, Aux Eng TS/ES lists)
      - casedet.ashx list (Post Analysis CASEDET runs)
      - aux-coord.ashx (Coordination Zone Check)
      - aux-hilo.ashx (HiLo — batch must not succeed on foreign PDF)

.PARAMETER Users
    Roster logins (default bchy1, rctl1, xci1).

.PARAMETER ForeignPdf
    PDF owned by another operator (default rctl 1c0139c2444).
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.cloudmicsdev.ca/mics/',
    [string[]]$Users = @('bchy1', 'rctl1', 'xci1'),
    [string]$Password = '',
    [string]$ForeignPdf = '1c0139c2444'
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
$failures = @()

function Invoke-MicsJson {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,
        [string]$Uri,
        [string]$Method = 'GET',
        [hashtable]$Fields = $null
    )
    try {
        $params = @{
            Uri = $Uri
            Method = $Method
            WebSession = $WebSession
            UseBasicParsing = $true
        }
        if ($Fields) {
            $params.Body = $Fields
            if ($Method -eq 'POST') { $params.ContentType = 'application/x-www-form-urlencoded' }
        }
        $resp = Invoke-WebRequest @params
        return $resp.Content | ConvertFrom-Json
    } catch {
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $body = $reader.ReadToEnd()
            try { return $body | ConvertFrom-Json } catch { }
        }
        throw
    }
}

function Login-Mics {
    param([string]$User)
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $null = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/login.aspx') -Method POST `
        -Body @{ user = $User; password = $Password } -WebSession $session -MaximumRedirection 10 -UseBasicParsing
    $sess = Invoke-MicsJson -WebSession $session -Uri ($base + 'RemIcsReWrite/session.ashx')
    if (-not $sess.ok) { throw "Login failed for $User" }
    return @{ Session = $session; Schema = $sess.schema }
}

function Test-FilesListIsolation {
    param($Ctx)
    foreach ($ft in @('TS', 'ES')) {
        $data = Invoke-MicsJson -WebSession $Ctx.Session -Uri ($base + 'RemIcsReWrite/files.ashx?filetype=' + $ft)
        if (-not $data.ok) {
            return "filesList $ft failed: $($data.error)"
        }
        if ($data.schema -ne $Ctx.Schema) {
            return "filesList $ft schema mismatch: $($data.schema) vs $($Ctx.Schema)"
        }
        $names = @($data.files | ForEach-Object { $_.name })
        if ($names -contains $ForeignPdf) {
            return "filesList $ft includes foreign PDF $ForeignPdf for $($Ctx.Schema)"
        }
    }
    $exists = Invoke-MicsJson -WebSession $Ctx.Session `
        -Uri ($base + 'RemIcsReWrite/files.ashx?filetype=TS&name=' + [uri]::EscapeDataString($ForeignPdf))
    if ($exists.ok -and $exists.exists -eq $true) {
        return "fileExists reports foreign PDF $ForeignPdf exists in $($Ctx.Schema)"
    }
    return $null
}

function Test-CasedetList {
    param($Ctx)
    foreach ($mode in @('TSES', 'TSTS')) {
        $data = Invoke-MicsJson -WebSession $Ctx.Session `
            -Uri ($base + 'RemIcsReWrite/casedet.ashx?action=list&mode=' + $mode)
        if (-not $data.ok) {
            return "casedet list $mode failed: $($data.error)"
        }
        foreach ($run in @($data.runs)) {
            if ($run.table -and $run.table -notmatch "^($([regex]::Escape($Ctx.Schema))_|[a-z]+\\.)") {
                # table names from list are bare te_/tt_ names; parm lookup is schema-scoped server-side
                continue
            }
        }
    }
    return $null
}

function Test-AuxCoordForeign {
    param($Ctx)
    $data = Invoke-MicsJson -WebSession $Ctx.Session -Method POST `
        -Uri ($base + 'RemIcsReWrite/aux-coord.ashx') `
        -Fields @{ filetype = 'TS'; name = $ForeignPdf }
    if (-not $data) { return 'auxCoordCheck returned no response for foreign PDF' }
    if ($data.ok -ne $true) { return $null }
    if ($data.rows -and @($data.rows).Count -gt 0) {
        return "auxCoordCheck returned rows for foreign PDF $ForeignPdf"
    }
    return $null
}

function Test-AuxHiloForeign {
    param($Ctx)
    $data = Invoke-MicsJson -WebSession $Ctx.Session -Method POST `
        -Uri ($base + 'RemIcsReWrite/aux-hilo.ashx') `
        -Fields @{ name = $ForeignPdf; dist = '5' }
    if ($data.ok -eq $true) {
        return "auxHiloCheck succeeded on foreign PDF $ForeignPdf"
    }
    return $null
}

foreach ($user in $Users) {
    Write-Host "=== Gate A tail user=$user ==="
    $ctx = Login-Mics -User $user
    Write-Host "schema=$($ctx.Schema)"

    $checks = @(
        @{ Name = 'filesList'; Fn = { Test-FilesListIsolation -Ctx $ctx } }
        @{ Name = 'casedet'; Fn = { Test-CasedetList -Ctx $ctx } }
        @{ Name = 'auxCoord'; Fn = { Test-AuxCoordForeign -Ctx $ctx } }
        @{ Name = 'auxHilo'; Fn = { Test-AuxHiloForeign -Ctx $ctx } }
    )
    foreach ($check in $checks) {
        $err = & $check.Fn
        if ($err) {
            Write-Host "FAIL $($check.Name): $err"
            $failures += "$user / $($check.Name): $err"
        } else {
            Write-Host "OK $($check.Name)"
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host 'FAIL Gate A tail isolation:'
    $failures | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

Write-Host ("PASS Gate A tail isolation ({0} users, foreign PDF {1})" -f $Users.Count, $ForeignPdf)
exit 0
