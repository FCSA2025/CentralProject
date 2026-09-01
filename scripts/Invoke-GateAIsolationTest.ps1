#Requires -Version 5.1
<#
.SYNOPSIS
    Gate A isolation checks: foreign PDF must not validate or save under wrong schema.

.PARAMETER User
    MICS login (default bchy1).

.PARAMETER ForeignPdf
    PDF owned by another operator (default rctl-only 1c0139c2444).

.PARAMETER OwnPdf
    PDF valid for this user's schema when set; skipped if empty.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.cloudmicsdev.ca/mics/',
    [string]$User = 'bchy1',
    [string]$Password = '',
    [string]$ForeignPdf = '1c0139c2444',
    [string]$OwnPdf = 'tcomm2601_8g',
    [string]$Parm = 'testts1',
    [string]$RunName = 'gatea'
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

function Login-Mics {
    $loginUrl = $base + 'RemIcsReWrite/login.aspx'
    $body = @{ user = $User; password = $Password }
    $null = Invoke-WebRequest -Uri $loginUrl -Method POST -Body $body -WebSession $session -MaximumRedirection 10 -UseBasicParsing
    $sess = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/session.ashx') -WebSession $session -UseBasicParsing
    $json = $sess.Content | ConvertFrom-Json
    if (-not $json.ok) { throw "Login failed for $User" }
    return $json.schema
}

function Invoke-TsipValidate {
    param([string]$Type, [string]$PdfName)
    $url = $base + 'Ttsipmenu/TwsTsip.asmx/tsipValidate'
    $payload = @{ type = $Type; pdfname = $PdfName } | ConvertTo-Json
    $resp = Invoke-WebRequest -Uri $url -Method POST -Body $payload -ContentType 'application/json; charset=utf-8' -WebSession $session -UseBasicParsing
    if ($resp.Content -match '"d"\s*:\s*"([^"]*)"') { return $Matches[1] }
    return $resp.Content.Trim()
}

function Invoke-TsipRunSave {
    param([string]$ProName)
    $url = $base + 'RemIcsReWrite/tsip-run.ashx?action=save&parm=' + [uri]::EscapeDataString($Parm)
    $fields = @{
        runname = $RunName
        protype = 'T'
        envtype = 'MDB_TS'
        proname = $ProName
        envname = ''
        tsorbout = 'N'
        spherecalc = '5'
        fsep = '300'
        coordist = '200'
        analopt = 'CHAN'
        margin = '0'
        chancodes = '0,1,2,3,4,5,6,7,8,9'
        numchan = '10'
        country = 'ALL'
        selsites = 'ALL'
        numcodes = '0'
        codes = ''
        reports = '0'
    }
    $resp = Invoke-WebRequest -Uri $url -Method POST -Body $fields -WebSession $session -UseBasicParsing
    return $resp.Content | ConvertFrom-Json
}

$schema = Login-Mics
Write-Host "=== Gate A test user=$User schema=$schema ==="

$failures = @()

$foreignValid = Invoke-TsipValidate -Type 'ft_' -PdfName $ForeignPdf
Write-Host "tsipValidate foreign $ForeignPdf => $foreignValid"
if ($foreignValid -ne 'not found') {
    $failures += "Foreign PDF $ForeignPdf should be 'not found', got '$foreignValid'"
}

if ($OwnPdf) {
    $ownValid = Invoke-TsipValidate -Type 'ft_' -PdfName $OwnPdf
    Write-Host "tsipValidate own $OwnPdf => $ownValid"
    if ($ownValid -eq 'not found' -or $ownValid -like 'ERRORSYS:*') {
        $failures += "Own PDF $OwnPdf should validate for $schema, got '$ownValid'"
    }
}

$saveForeign = Invoke-TsipRunSave -ProName $ForeignPdf
Write-Host "tsip-run save foreign => ok=$($saveForeign.ok) error=$($saveForeign.error)"
if ($saveForeign.ok -eq $true) {
    $failures += 'tsip-run save should reject foreign PDF'
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL Gate A ($User):"
    $failures | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

Write-Host "PASS Gate A isolation for $User ($schema)"
