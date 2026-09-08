#Requires -Version 5.1
<#
.SYNOPSIS
  B7 verify: ES StoreKeys + InsertPDFSites on a formerly-broken schema (bchy1).
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.CLOUDMICSDEV.ca/mics/',
    [string]$User = 'bchy1',
    [string]$Password = '',
    [string]$ResultPath = 'E:\AIProjects\CentralProject\tmp-tsjob\b7-es-cull-verify.json'
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

function Build-ClassicEsKeylist([string[]]$Checked) {
    $keylist = ''; $comma = ''; $subcount = 100
    for ($i = 0; $i -lt $Checked.Count; $i++) {
        if ((($i + 1) % $subcount) -eq 0) { $comma = '.' }
        $keylist += $comma + $Checked[$i]
        $comma = ','
    }
    return $keylist
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

# Static presence for all B7 schemas
$missing = Sql-Query @"
SELECT RTRIM(a.ultrixid)
FROM (SELECT DISTINCT ultrixid FROM adm.account_details) a
WHERE EXISTS (SELECT 1 FROM sys.schemas s WHERE s.name = RTRIM(a.ultrixid))
AND NOT EXISTS (
  SELECT 1 FROM INFORMATION_SCHEMA.TABLES t
  WHERE t.TABLE_SCHEMA = RTRIM(a.ultrixid) AND t.TABLE_NAME = 'cull_temp3_es'
);
"@
$missList = @($missing | Where-Object { $_ -match '^[A-Za-z]' -and $_ -notmatch 'ultrixid|^-+|rows' } | ForEach-Object { ("$_".Trim() -split '\|')[0].Trim() })
Add-Check 'all-account-schemas-have-cull3es' ($missList.Count -eq 0) "missing=$($missList -join ',')"

foreach ($sch in @('bchy','dnd','aliant')) {
    $n = Get-SqlCount @"
SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA='$sch' AND TABLE_NAME IN ('cull_temp1_es','cull_temp2_es','cull_temp3_es');
"@
    Add-Check "tables-$sch" ($n -eq 3) "esCullTables=$n"
}

# Live bchy1 ES save 101
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri ($rewrite + 'login.aspx') -Method POST -Body @{ user = $User; password = $Password } `
    -WebSession $session -MaximumRedirection 10 -UseBasicParsing -TimeoutSec 120
$sess = (Invoke-WebRequest -Uri ($rewrite + 'session.ashx') -WebSession $session -UseBasicParsing).Content | ConvertFrom-Json
if (-not $sess.ok) { throw "session failed for $User" }
$pc = [string]$sess.project
$schema = [string]$sess.schema
Write-Host "schema=$schema project=$pc user=$User"

$locOut = Sql-Query "SELECT TOP 101 location FROM main.me_site ORDER BY location;"
$locs = @($locOut | Where-Object {
    $_ -and ("$_" -notmatch 'location|^-+|rows affected|^\s*$')
} | ForEach-Object { ("$_".Trim() -split '\|')[0].Trim() } | Where-Object { $_ -match '\S' } | Select-Object -First 101)
Add-Check 'have-101-locs' ($locs.Count -eq 101) "count=$($locs.Count)"

try {
    $keylist = Build-ClassicEsKeylist $locs
    $blocks = @($keylist.Split('.'))
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/ClearCulls') @{ start = '1' }
    foreach ($block in $blocks) {
        if (-not $block) { continue }
        $r = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/StoreKeys') @{ keylist = $block }
        if ($r -match '^ERROR') { throw "StoreKeys: $r" }
    }
    $pdf = 'b7v_' + (Get-Date -Format 'HHmmss')
    $ct = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/createTable') @{
        filename = $pdf; filetype = 'ES'; projectCode = $pc
    }
    if ($ct -match '^(ERROR|timeout)') { throw "createTable: $ct" }
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullAntes') @{ owhere = '' }
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullChans') @{ owhere = '' }
    $ins = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertPDFSites') @{ name = $pdf }
    if ($ins -match '^ERROR') { throw "InsertPDFSites: $ins" }
    $n = Get-SqlCount "SELECT COUNT(*) FROM $schema.fe_${pdf}_site;"
    Add-Check 'live-bchy-101-save' ($n -eq 101) "pdf=$pdf sites=$n blocks=$($blocks.Count)"
    $null = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/killTable') @{
        filename = $pdf; filetype = 'ES'; projectCode = $pc
    }
} catch {
    Add-Check 'live-bchy-101-save' $false $_.Exception.Message
}

$pass = @($checks | Where-Object { $_.ok }).Count
$fail = @($checks | Where-Object { -not $_.ok }).Count
$out = [ordered]@{
    when = (Get-Date).ToString('s')
    user = $User
    schema = $schema
    pass = $pass
    fail = $fail
    checks = @(
        $checks | ForEach-Object {
            [ordered]@{ name = $_.name; ok = [bool]$_.ok; detail = [string]$_.detail }
        }
    )
}
($out | ConvertTo-Json -Depth 6) | Set-Content $ResultPath -Encoding UTF8
Write-Host "SUMMARY pass=$pass fail=$fail -> $ResultPath"
if ($fail -gt 0) { exit 1 }
exit 0
