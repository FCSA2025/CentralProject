#Requires -Version 5.1
<#
.SYNOPSIS
  Verify TS cull_temp{1,2,3} on formerly-broken schema (bchy1) with a multi-link save.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.CLOUDMICSDEV.ca/mics/',
    [string]$User = 'bchy1',
    [string]$Password = '',
    [string]$ResultPath = 'E:\AIProjects\CentralProject\tmp-tsjob\b7-ts-cull-verify.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = 'E:\AIProjects\CentralProject'

function Get-EnvLocalValue([string]$Key) {
    $envFile = Join-Path $repoRoot '.env.local'
    if (-not (Test-Path $envFile)) { return $null }
    foreach ($line in Get-Content $envFile) {
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.+?)\s*$") {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

function Invoke-Asmx($Session, [string]$Url, [hashtable]$Body) {
    $r = Invoke-WebRequest -Uri $Url -Method POST -WebSession $Session -UseBasicParsing -TimeoutSec 300 `
        -ContentType 'application/json; charset=utf-8' -Body ($Body | ConvertTo-Json -Compress)
    $text = $r.Content
    if ($text -match '^\s*\{') {
        $parsed = $text | ConvertFrom-Json
        if ($null -ne $parsed.PSObject.Properties['d']) { $text = [string]$parsed.d }
    }
    return $text
}

function Sql-Query([string]$Query) {
    & (Join-Path $repoRoot 'scripts\Invoke-RemicsDevSql.ps1') -Query $Query
}

function Get-SqlCount([string]$Query) {
    foreach ($line in (Sql-Query $Query)) {
        $t = ("$line").Trim()
        if ($t -match '^\d+$') { return [int]$t }
        if ($t -match '^(\d+)\s*\|') { return [int]$Matches[1] }
    }
    return -1
}

if (-not $Password) { $Password = $env:MICS_TEST_PASSWORD }
if (-not $Password) { $Password = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
if (-not $Password) { $Password = 'x' }

$base = $BaseUrl.TrimEnd('/') + '/'
$rewrite = $base + 'RemIcsReWrite/'
$checks = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Name, [bool]$Ok, [string]$Detail) {
    $checks.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
    Write-Host "$(if ($Ok) { 'PASS' } else { 'FAIL' }) $Name - $Detail"
}

# All nine schemas have full TS+ES cull set
$mat = Sql-Query @"
SELECT sch.name,
  CASE WHEN OBJECT_ID(QUOTENAME(sch.name)+'.cull_temp1','U') IS NULL THEN 0 ELSE 1 END +
  CASE WHEN OBJECT_ID(QUOTENAME(sch.name)+'.cull_temp2','U') IS NULL THEN 0 ELSE 1 END +
  CASE WHEN OBJECT_ID(QUOTENAME(sch.name)+'.cull_temp3','U') IS NULL THEN 0 ELSE 1 END +
  CASE WHEN OBJECT_ID(QUOTENAME(sch.name)+'.cull_temp1_es','U') IS NULL THEN 0 ELSE 1 END +
  CASE WHEN OBJECT_ID(QUOTENAME(sch.name)+'.cull_temp2_es','U') IS NULL THEN 0 ELSE 1 END +
  CASE WHEN OBJECT_ID(QUOTENAME(sch.name)+'.cull_temp3_es','U') IS NULL THEN 0 ELSE 1 END AS n
FROM (VALUES
  ('aliant'),('bchy'),('bell'),('bmce'),('bragg'),
  ('dnd'),('tbay'),('tels'),('terago')
) sch(name);
"@
$bad = @()
foreach ($line in $mat) {
    if ($line -match '^\s*([A-Za-z]+)\|(\d+)\s*$') {
        if ([int]$Matches[2] -ne 6) { $bad += "$($Matches[1])=$($Matches[2])" }
    } elseif ($line -match '^\s*([A-Za-z]+)\s+(\d+)\s*$') {
        if ([int]$Matches[2] -ne 6) { $bad += "$($Matches[1])=$($Matches[2])" }
    }
}
Add-Check 'all-nine-have-6-culls' ($bad.Count -eq 0) $(if ($bad.Count) { $bad -join ',' } else { '9 schemas x 6 tables' })

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri ($rewrite + 'login.aspx') -Method POST -Body @{ user = $User; password = $Password } `
    -WebSession $session -MaximumRedirection 10 -UseBasicParsing -TimeoutSec 120
$sess = (Invoke-WebRequest -Uri ($rewrite + 'session.ashx') -WebSession $session -UseBasicParsing).Content | ConvertFrom-Json
if (-not $sess.ok) { throw "session failed for $User" }
$pc = [string]$sess.project
$schema = [string]$sess.schema
Write-Host "schema=$schema project=$pc user=$User"

try {
    $search = (Invoke-WebRequest -Uri ($rewrite + 'ds-search.ashx') -Method POST -WebSession $session -UseBasicParsing -TimeoutSec 180 `
        -Body @{ action = 'searchTs'; call1 = '*'; call1Op = 'LIKE' }).Content | ConvertFrom-Json
    if (-not $search.ok) { throw "searchTs: $($search.error)" }
    $links = @($search.links)
    $need = [Math]::Min(20, $links.Count)
    if ($need -lt 5) { throw "need >=5 links, got $($links.Count)" }

    $siteKeys = New-Object System.Collections.Generic.List[string]
    $linkKeys = New-Object System.Collections.Generic.List[string]
    $oeKeys = New-Object System.Collections.Generic.List[string]
    $chkS = ''; $chkL = ''; $chkO = ''
    $seenSite = @{}
    foreach ($l in ($links | Select-Object -First $need)) {
        $c1 = [string]$l.call1; $c2 = [string]$l.call2; $bnd = [string]$l.bndcde
        $linkKeys.Add("$c1}$c2}$bnd"); $chkL += '1'
        $oeKeys.Add("$c2}$c1}$bnd"); $chkO += '1'
        if (-not $seenSite.ContainsKey($c1)) {
            $seenSite[$c1] = $true
            $siteKeys.Add("$c1}}"); $chkS += '1'
        }
    }

    $pdf = 'b7ts_' + (Get-Date -Format 'HHmmss')
    $ct = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/createTable') @{
        filename = $pdf; filetype = 'TS'; projectCode = $pc
    }
    if ($ct -match '^(ERROR|timeout)') { throw "createTable: $ct" }

    $null = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/ClearCulls') @{ start = '1' }
    $sk = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/SaveKeysLocal') @{
        inkeyss = ($siteKeys -join ','); checkss = $chkS
        inkeys = ($linkKeys -join ','); checks = $chkL; type = 'LOCA'
    }
    if ($sk -match '^ERROR') { throw "SaveKeysLocal: $sk" }
    $sr = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/SaveKeysRemote') @{
        inkeys = ($oeKeys -join ','); checks = $chkO; type = 'REMO'
    }
    if ($sr -match '^ERROR') { throw "SaveKeysRemote: $sr" }

    $owEnc = ([string]$search.owhere).Replace('<', '^')
    $ics = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/InsertCullSites') @{}
    if ($ics -match '^ERROR') { throw "InsertCullSites: $ics" }
    foreach ($m in @('InsertCullAntesLink', 'InsertCullAntesOE', 'InsertCullChansLink', 'InsertCullChansOE')) {
        $body = Invoke-Asmx $session ($base + "Tdsts/TwsdsTS.asmx/$m") @{ owhere = $owEnc }
        if ($body -match '^ERROR') { throw "$m $body" }
    }
    foreach ($m in @('InsertPDFSites', 'InsertPDFAntes', 'InsertPDFChans')) {
        $body = Invoke-Asmx $session ($base + "Tdsts/TwsdsTS.asmx/$m") @{ name = $pdf }
        if ($body -match '^ERROR') { throw "$m $body" }
    }

    $nS = Get-SqlCount "SELECT COUNT(*) FROM $schema.ft_${pdf}_site;"
    $nC = Get-SqlCount "SELECT COUNT(*) FROM $schema.ft_${pdf}_chan;"
    Add-Check 'live-bchy-ts-save' (($nS -gt 0) -and ($nC -gt 0)) "links=$need sites=$nS chans=$nC pdf=$pdf"

    $null = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/killTable') @{
        filename = $pdf; filetype = 'TS'; projectCode = $pc
    }
} catch {
    Add-Check 'live-bchy-ts-save' $false $_.Exception.Message
}

$pass = @($checks | Where-Object { $_.ok }).Count
$fail = @($checks | Where-Object { -not $_.ok }).Count
$out = [ordered]@{
    when = (Get-Date).ToString('s')
    user = $User
    schema = $schema
    pass = $pass
    fail = $fail
    checks = @($checks | ForEach-Object {
        [ordered]@{ name = $_.name; ok = [bool]$_.ok; detail = [string]$_.detail }
    })
}
($out | ConvertTo-Json -Depth 6) | Set-Content $ResultPath -Encoding UTF8
Write-Host "SUMMARY pass=$pass fail=$fail -> $ResultPath"
if ($fail -gt 0) { exit 1 }
exit 0
