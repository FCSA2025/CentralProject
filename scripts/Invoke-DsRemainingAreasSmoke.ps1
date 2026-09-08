#Requires -Version 5.1
<#
.SYNOPSIS
  Checks remaining high-yield DS save areas: TS }-keys, ES location keys, SDF detail inserts.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.CLOUDMICSDEV.ca/mics/',
    [string]$User = 'rctl1',
    [string]$Password = '',
    [string]$ResultPath = 'E:\AIProjects\CentralProject\tmp-tsjob\ds-remaining-areas-smoke.json'
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
    $r = Invoke-WebRequest -Uri $Url -Method POST -WebSession $Session -UseBasicParsing -TimeoutSec 180 `
        -ContentType 'application/json; charset=utf-8' -Body ($Body | ConvertTo-Json -Compress)
    $text = $r.Content
    if ($text -match '^\s*\{') {
        $parsed = $text | ConvertFrom-Json
        if ($null -ne $parsed.PSObject.Properties['d']) { $text = [string]$parsed.d }
    }
    return $text
}

if (-not $Password) { $Password = $env:MICS_TEST_PASSWORD }
if (-not $Password) { $Password = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
if (-not $Password) { $Password = 'x' }

$base = $BaseUrl.TrimEnd('/') + '/'
$rewrite = $base + 'RemIcsReWrite/'
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri ($rewrite + 'login.aspx') -Method POST -Body @{ user = $User; password = $Password } `
    -WebSession $session -MaximumRedirection 10 -UseBasicParsing -TimeoutSec 120
$sess = (Invoke-WebRequest -Uri ($rewrite + 'session.ashx') -WebSession $session -UseBasicParsing).Content | ConvertFrom-Json
if (-not $sess.ok) { throw 'session failed' }
$pc = [string]$sess.project
$schema = [string]$sess.schema
Write-Host "schema=$schema project=$pc"

$checks = New-Object System.Collections.Generic.List[object]

function Add-Check([string]$Name, [bool]$Ok, [string]$Detail) {
    $checks.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
    $flag = if ($Ok) { 'PASS' } else { 'FAIL' }
    Write-Host "$flag $Name - $Detail"
}

$dsJs = Get-Content (Join-Path $repoRoot 'config\remicsdev\source\mics\RemIcsReWrite\js\remics-ds.js') -Raw
$liveDs = Get-Content 'D:\inetpub\remicsdev\mics\RemIcsReWrite\js\remics-ds.js' -Raw
$editJs = Get-Content (Join-Path $repoRoot 'config\remicsdev\source\mics\RemIcsReWrite\js\remics-sdf-edit.js') -Raw

Add-Check 'static-ts-brace-keys' `
    (($dsJs.Contains("l.call1 + '}' + l.call2 + '}' + l.bndcde")) -and (-not $dsJs.Contains("l.call1 + ',' + l.call2 + ',' + l.bndcde"))) `
    'link/OE data-key uses } not comma'

Add-Check 'static-ts-link-no-trail' `
    ($dsJs.Contains("links.push(c.getAttribute('data-key'));") -and (-not $dsJs.Contains("links.push(c.getAttribute('data-key') + '}}');"))) `
    'link keys do not append }}'

Add-Check 'static-ts-oe-no-trail' `
    ($dsJs.Contains("remotes.push(c.getAttribute('data-key'));") -and (-not $dsJs.Contains("remotes.push(c.getAttribute('data-key') + '}}');"))) `
    'OE keys do not append }}'

Add-Check 'live-ts-brace-keys' ($liveDs.Contains("l.call1 + '}' + l.call2 + '}' + l.bndcde")) 'live remics-ds.js deployed'
Add-Check 'static-es-storekeys' ($dsJs.Contains("Tdses/TwsdsES.asmx', 'StoreKeys'")) 'ES StoreKeys path present'
Add-Check 'static-sdf-edit-no-twssdssdf' (-not $editJs.Contains('TwsdsSDF.asmx')) 'sdf-edit does not call TwsdsSDF keylist'

$sqlHelper = Join-Path $repoRoot 'scripts\Invoke-RemicsDevSql.ps1'
function Sql-Scalar([string]$Query) {
    $out = & $sqlHelper -Query $Query
    $line = ($out | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1)
    if (-not $line) { $line = ($out | Select-Object -Last 1) }
    return [int]("$line".Trim())
}

# Runtime TS SaveKeysLocal
try {
    $search = (Invoke-WebRequest -Uri ($rewrite + 'ds-search.ashx') -Method POST -WebSession $session -UseBasicParsing -TimeoutSec 120 `
        -Body @{ action = 'searchTs'; call1 = 'A'; call1Op = 'LIKE' }).Content | ConvertFrom-Json
    if (-not $search.ok) { throw "searchTs: $($search.error)" }
    $links = @($search.links)
    if ($links.Count -lt 1) {
        $search = (Invoke-WebRequest -Uri ($rewrite + 'ds-search.ashx') -Method POST -WebSession $session -UseBasicParsing -TimeoutSec 120 `
            -Body @{ action = 'searchTs'; call1 = '*'; call1Op = 'LIKE' }).Content | ConvertFrom-Json
        $links = @($search.links)
    }
    if ($links.Count -lt 1) { throw 'no links in searchTs' }
    $l = $links[0]
    $siteKey = ([string]$l.call1) + '}}'
    $linkKey = ([string]$l.call1) + '}' + ([string]$l.call2) + '}' + ([string]$l.bndcde)
    $null = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/ClearCulls') @{ start = '1' }
    $sk = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/SaveKeysLocal') @{
        inkeyss = $siteKey; checkss = '1'; inkeys = $linkKey; checks = '1'; type = 'LOCA'
    }
    if ($sk -match '^ERROR') { throw "SaveKeysLocal $sk" }
    Add-Check 'runtime-ts-SaveKeysLocal-brace' $true "OK key=$linkKey"
}
catch {
    Add-Check 'runtime-ts-SaveKeysLocal-brace' $false $_.Exception.Message
}

# Comma-shaped link key should error in StoreKeys (kp[1] missing after comma-split)
try {
    $null = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/ClearCulls') @{ start = '1' }
    $bad = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/SaveKeysLocal') @{
        inkeyss = 'XSITE}}'; checkss = '1'; inkeys = 'XSITE,YREMOTE,08A'; checks = '1'; type = 'LOCA'
    }
    Add-Check 'runtime-ts-comma-key-rejected' ($bad -match '^ERROR') "body=$bad"
}
catch {
    Add-Check 'runtime-ts-comma-key-rejected' $true ('threw: ' + $_.Exception.Message)
}

# ES StoreKeys (location keys — classic dsESList ks.Append(location))
try {
    $es = (Invoke-WebRequest -Uri ($rewrite + 'ds-search.ashx') -Method POST -WebSession $session -UseBasicParsing -TimeoutSec 120 `
        -Body @{ action = 'searchEs'; name = '*'; nameOp = 'LIKE' }).Content | ConvertFrom-Json
    $sites = @()
    if ($es.ok) { $sites = @($es.sites) }
    if ($sites.Count -lt 1) {
        $locLine = & $sqlHelper -Query "SELECT TOP 1 location FROM main.me_site ORDER BY location" 2>$null
        $loc = ($locLine | Where-Object { $_ -and $_ -notmatch 'location|---|rows affected|^$' } | Select-Object -First 1)
        if ($loc) { $loc = "$loc".Trim() }
    } else {
        $loc = [string]$sites[0].location
    }
    if (-not $loc) { throw 'no ES locations in catalog or me_site' }
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/ClearCulls') @{ start = '1' }
    $ek = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/StoreKeys') @{ keylist = $loc }
    if ($ek -match '^ERROR') { throw "StoreKeys $ek" }
    Add-Check 'runtime-es-StoreKeys' $true "location=$loc"
}
catch {
    Add-Check 'runtime-es-StoreKeys' $false $_.Exception.Message
}

# SDF detail parent/detail counts
$stamp = Get-Date -Format 'HHmmss'
$detailTypes = @(
    @{ type='Ante'; parts=@('acode'); filterCol='acode'; parent='ante'; detail='antd'; insert='InsertAnte'; insert2='InsertAntd' },
    @{ type='Ctx'; parts=@('tfci','tfcr','rxeqp'); filterCol='tfci'; parent='ctx_'; detail='ctxd'; insert='InsertCtx'; insert2='InsertCtxd' },
    @{ type='Plan'; parts=@('sband','splan'); filterCol='sband'; parent='plan'; detail='plnd'; insert='InsertPlan'; insert2='InsertPlnd' }
)
foreach ($dt in $detailTypes) {
    $name = ('zd' + $dt.type.Substring(0, 1).ToLower() + $stamp)
    try {
        $form = @{ action = 'search'; type = $dt.type }
        $form[$dt.filterCol] = '*'
        $search = (Invoke-WebRequest -Uri ($rewrite + 'ds-sdf.ashx') -Method POST -Body $form `
            -WebSession $session -UseBasicParsing -TimeoutSec 120).Content | ConvertFrom-Json
        if (-not $search.ok -or @($search.rows).Count -lt 1) { throw 'search empty' }
        $row = @($search.rows)[0]
        $key = ($dt.parts | ForEach-Object { [string]$row.$_ }) -join ':'
        $ct = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/createTable') @{
            filename = $name; filetype = $dt.type; projectCode = $pc
        }
        if ($ct -match '^ERROR') { throw "create $ct" }
        $i1 = Invoke-Asmx $session ($base + "Tdssdf/TwsdsSDF.asmx/$($dt.insert)") @{ name = $name; keylist = $key }
        if ($i1 -match '^ERROR') { throw "insert $i1" }
        $i2 = Invoke-Asmx $session ($base + "Tdssdf/TwsdsSDF.asmx/$($dt.insert2)") @{ name = $name; keylist = $key }
        if ($i2 -match '^ERROR') { throw "insert2 $i2" }

        $pCnt = Sql-Scalar "SELECT COUNT(*) AS c FROM [$schema].[su_${name}_$($dt.parent)]"
        $dCnt = Sql-Scalar "SELECT COUNT(*) AS c FROM [$schema].[su_${name}_$($dt.detail)]"
        Add-Check ("runtime-sdf-detail-" + $dt.type) ($pCnt -ge 1) "key=$key parent=$pCnt detail=$dCnt"
    }
    catch {
        Add-Check ("runtime-sdf-detail-" + $dt.type) $false $_.Exception.Message
    }
    finally {
        try {
            $null = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/killTable') @{
                filename = $name; filetype = $dt.type; projectCode = $pc
            }
        } catch { }
    }
}

$arr = $checks.ToArray()
$pass = @($arr | Where-Object { $_.ok }).Count
$fail = @($arr | Where-Object { -not $_.ok }).Count
$summary = [ordered]@{ ok = ($fail -eq 0); pass = $pass; fail = $fail; schema = $schema; checks = $arr }
[System.IO.File]::WriteAllText($ResultPath, ($summary | ConvertTo-Json -Depth 6))
Write-Host ("SUMMARY pass={0} fail={1}" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
