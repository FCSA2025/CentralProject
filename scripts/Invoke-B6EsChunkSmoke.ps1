#Requires -Version 5.1
<#
.SYNOPSIS
  Thorough B6 verification: classic keylist chunking + ES save small + 101/250 chunked StoreKeys + InsertPDF.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.CLOUDMICSDEV.ca/mics/',
    [string]$User = 'rctl1',
    [string]$Password = '',
    [string]$ResultPath = 'E:\AIProjects\CentralProject\tmp-tsjob\b6-es-chunk-smoke.json'
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

function Build-ClassicEsKeylist([string[]]$Checked) {
    $keylist = ''
    $comma = ''
    $subcount = 100
    for ($i = 0; $i -lt $Checked.Count; $i++) {
        $keycount = $i + 1
        if (($keycount % $subcount) -eq 0) { $comma = '.' }
        $keylist += $comma + $Checked[$i]
        $comma = ','
    }
    return $keylist
}

function Invoke-StoreEsKeysChunked($Session, [string]$Base, [string[]]$Checked) {
    $keylist = Build-ClassicEsKeylist $Checked
    $blocks = @($keylist.Split('.'))
    $null = Invoke-Asmx $Session ($Base + 'Tdses/TwsdsES.asmx/ClearCulls') @{ start = '1' }
    $i = 0
    foreach ($block in $blocks) {
        if (-not $block) { continue }
        $i++
        $r = Invoke-Asmx $Session ($Base + 'Tdses/TwsdsES.asmx/StoreKeys') @{ keylist = $block }
        if ($r -match '^ERROR') { throw "StoreKeys block $i/$($blocks.Count): $r" }
    }
    return @{ blocks = $blocks.Count; keylistLen = $keylist.Length; sample = $keylist.Substring(0, [Math]::Min(80, $keylist.Length)) }
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
    Write-Host "$(if($Ok){'PASS'}else{'FAIL'}) $Name - $Detail"
}

# --- Static: live JS has chunk helpers; no double StoreKeys of all keys ---
$live = Get-Content 'D:\inetpub\remicsdev\mics\RemIcsReWrite\js\remics-ds.js' -Raw
Add-Check 'static-helpers' ($live.Contains('buildClassicEsStoreKeylist') -and $live.Contains('storeEsKeysChunked')) 'helpers deployed'
Add-Check 'static-no-all-keys-store' (-not ($live -match "var keylist = keys\.join\(',\'\)")) 'removed all-keys join before StoreKeys'
Add-Check 'static-classic-dot' ($live.Contains("if (keycount % subcount === 0) comma = '.';")) 'classic %100 dot logic'
Add-Check 'static-cache' ((Get-Content 'D:\inetpub\remicsdev\mics\RemIcsReWrite\shell.aspx' -Raw) -match 'remics-ds\.js\?v=2026090805') 'cache bump 2026090805'

# Unit: classic keylist shape for 100 / 101 / 250
$fake = 1..101 | ForEach-Object { "L{0:D4}" -f $_ }
$kl = Build-ClassicEsKeylist $fake
$bl = @($kl.Split('.'))
Add-Check 'unit-101-blocks' ($bl.Count -eq 2) "blocks=$($bl.Count) firstKeys=$((@($bl[0].Split(','))).Count) second=$((@($bl[1].Split(','))).Count)"
$fake250 = 1..250 | ForEach-Object { "L{0:D4}" -f $_ }
$bl250 = @((Build-ClassicEsKeylist $fake250).Split('.'))
Add-Check 'unit-250-blocks' ($bl250.Count -eq 3) "blocks=$($bl250.Count)"

# Pull real locations
$locOut = Sql-Query "SELECT TOP 250 location FROM main.me_site ORDER BY location;"
$locs = @($locOut | Where-Object {
    $_ -and "$_" -notmatch 'location|^-+$|rows affected|^\s*$' -and "$_".Trim().Length -gt 0
} | ForEach-Object { "$_".Trim() })
# SQL helper may return header rows - filter to look like locations
$locs = @($locs | Where-Object { $_ -notmatch '^\d+\|?$' -and $_ -ne 'location' })
Write-Host "locations available=$($locs.Count)"
Add-Check 'have-101-locs' ($locs.Count -ge 101) "count=$($locs.Count)"

$largeN = [Math]::Min(249, $locs.Count)
Add-Check 'have-large-locs' ($largeN -ge 200) "largeN=$largeN"

# --- Live: chunked StoreKeys 101 ---
if ($locs.Count -ge 101) {
    try {
        $meta = Invoke-StoreEsKeysChunked $session $base @($locs | Select-Object -First 101)
        $pdf = 'b6chk_' + (Get-Date -Format 'HHmmss')
        $ct = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/createTable') @{
            filename = $pdf; filetype = 'ES'; projectCode = $pc
        }
        if ($ct -match '^(ERROR|timeout)') { throw "createTable $ct" }
        $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullAntes') @{ owhere = '' }
        $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullChans') @{ owhere = '' }
        $ins = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertPDFSites') @{ name = $pdf }
        if ($ins -match '^ERROR') { throw "InsertPDFSites $ins" }
        $cnt = Sql-Query "SELECT COUNT(*) FROM $schema.fe_${pdf}_site;"
        $n = [int](($cnt | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1).ToString().Trim())
        Add-Check 'live-101-chunk-save' ($n -eq 101) "pdf=$pdf sites=$n blocks=$($meta.blocks) sample=$($meta.sample)"
        $null = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/killTable') @{
            filename = $pdf; filetype = 'ES'; projectCode = $pc
        }
    } catch {
        Add-Check 'live-101-chunk-save' $false $_.Exception.Message
    }
}

# --- Live: large chunked StoreKeys (up to 249) ---
if ($largeN -ge 200) {
    try {
        $meta = Invoke-StoreEsKeysChunked $session $base @($locs | Select-Object -First $largeN)
        $pdf = 'b6big_' + (Get-Date -Format 'HHmmss')
        $ct = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/createTable') @{
            filename = $pdf; filetype = 'ES'; projectCode = $pc
        }
        if ($ct -match '^(ERROR|timeout)') { throw "createTable $ct" }
        $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullAntes') @{ owhere = '' }
        $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullChans') @{ owhere = '' }
        $ins = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertPDFSites') @{ name = $pdf }
        if ($ins -match '^ERROR') { throw "InsertPDFSites $ins" }
        $cnt = Sql-Query "SELECT COUNT(*) FROM $schema.fe_${pdf}_site;"
        $n = [int](($cnt | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1).ToString().Trim())
        Add-Check 'live-large-chunk-save' ($n -eq $largeN) "pdf=$pdf sites=$n expected=$largeN blocks=$($meta.blocks)"
        $null = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/killTable') @{
            filename = $pdf; filetype = 'ES'; projectCode = $pc
        }
    } catch {
        Add-Check 'live-large-chunk-save' $false $_.Exception.Message
    }
} else {
    Add-Check 'live-large-chunk-save' $true "SKIP only $largeN locs"
}

# --- Small save (1 site) still works ---
try {
    $es = (Invoke-WebRequest -Uri ($rewrite + 'ds-search.ashx') -Method POST -WebSession $session -UseBasicParsing -TimeoutSec 120 `
        -Body @{ action = 'searchEs'; name = 'A'; nameOp = 'LIKE' }).Content | ConvertFrom-Json
    $sites = @()
    if ($es.ok) { $sites = @($es.sites) }
    if ($sites.Count -lt 1) {
        $es = (Invoke-WebRequest -Uri ($rewrite + 'ds-search.ashx') -Method POST -WebSession $session -UseBasicParsing -TimeoutSec 120 `
            -Body @{ action = 'searchEs'; name = '*'; nameOp = 'LIKE' }).Content | ConvertFrom-Json
        $sites = @($es.sites)
    }
    if ($sites.Count -lt 1) { throw 'no ES sites' }
    $loc = [string]$sites[0].location
    $ow = ([string]$es.owhere).Replace('<', '^')
    $pdf = 'b6sm_' + (Get-Date -Format 'HHmmss')
    $ct = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/createTable') @{
        filename = $pdf; filetype = 'ES'; projectCode = $pc
    }
    if ($ct -match '^(ERROR|timeout)') { throw "createTable $ct" }
    $null = Invoke-StoreEsKeysChunked $session $base @($loc)
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullAntes') @{ owhere = $ow }
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullChans') @{ owhere = $ow }
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertPDFSites') @{ name = $pdf }
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertPDFAntes') @{ name = $pdf }
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertPDFChans') @{ name = $pdf }
    $cnt = Sql-Query "SELECT COUNT(*) FROM $schema.fe_${pdf}_site;"
    $n = [int](($cnt | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1).ToString().Trim())
    Add-Check 'live-small-save' ($n -eq 1) "pdf=$pdf loc=$loc sites=$n"
    $null = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/killTable') @{
        filename = $pdf; filetype = 'ES'; projectCode = $pc
    }
} catch {
    Add-Check 'live-small-save' $false $_.Exception.Message
}

# Second schema with cull_temp3_es (bchy lacks it; use xci1)
try {
    $session2 = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $null = Invoke-WebRequest -Uri ($rewrite + 'login.aspx') -Method POST -Body @{ user = 'xci1'; password = $Password } `
        -WebSession $session2 -MaximumRedirection 10 -UseBasicParsing -TimeoutSec 120
    $sess2 = (Invoke-WebRequest -Uri ($rewrite + 'session.ashx') -WebSession $session2 -UseBasicParsing).Content | ConvertFrom-Json
    if (-not $sess2.ok) { throw 'xci1 session failed' }
    $pc2 = [string]$sess2.project
    $schema2 = [string]$sess2.schema
    $use = @($locs | Select-Object -First 101)
    if ($use.Count -ge 101) {
        $meta = Invoke-StoreEsKeysChunked $session2 $base $use
        $pdf = 'b6xci_' + (Get-Date -Format 'HHmmss')
        $ct = Invoke-Asmx $session2 ($base + 'Tfileactions/TwsTabUtil.asmx/createTable') @{
            filename = $pdf; filetype = 'ES'; projectCode = $pc2
        }
        if ($ct -match '^(ERROR|timeout)') { throw "createTable $ct" }
        $null = Invoke-Asmx $session2 ($base + 'Tdses/TwsdsES.asmx/InsertCullAntes') @{ owhere = '' }
        $null = Invoke-Asmx $session2 ($base + 'Tdses/TwsdsES.asmx/InsertCullChans') @{ owhere = '' }
        $ins = Invoke-Asmx $session2 ($base + 'Tdses/TwsdsES.asmx/InsertPDFSites') @{ name = $pdf }
        if ($ins -match '^ERROR') { throw "InsertPDFSites $ins" }
        $cnt = Sql-Query "SELECT COUNT(*) FROM $schema2.fe_${pdf}_site;"
        $n = [int](($cnt | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1).ToString().Trim())
        Add-Check 'live-xci1-101' ($n -eq 101) "schema=$schema2 pdf=$pdf sites=$n blocks=$($meta.blocks)"
        $null = Invoke-Asmx $session2 ($base + 'Tfileactions/TwsTabUtil.asmx/killTable') @{
            filename = $pdf; filetype = 'ES'; projectCode = $pc2
        }
    } else {
        Add-Check 'live-xci1-101' $true 'SKIP insufficient locs'
    }
} catch {
    Add-Check 'live-xci1-101' $false $_.Exception.Message
}

$pass = @($checks | Where-Object { $_.ok }).Count
$fail = @($checks | Where-Object { -not $_.ok }).Count
Write-Host ""
Write-Host "SUMMARY pass=$pass fail=$fail total=$($checks.Count)"
$result = [pscustomobject]@{ when = (Get-Date).ToString('s'); user = $User; pass = $pass; fail = $fail; checks = $checks }
$result | ConvertTo-Json -Depth 5 | Set-Content $ResultPath -Encoding UTF8
Write-Host "Wrote $ResultPath"
if ($fail -gt 0) { exit 1 }
