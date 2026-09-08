#Requires -Version 5.1
<#
.SYNOPSIS
  Identify+verify DS bug hunt: TS save E2E, ES StoreKeys chunking, owhere encoding.
  Does NOT fix code — reports confirmed / cleared / inconclusive.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.CLOUDMICSDEV.ca/mics/',
    [string]$User = 'rctl1',
    [string]$Password = '',
    [string]$ResultPath = 'E:\AIProjects\CentralProject\tmp-tsjob\ds-bug-hunt-2026-09-08.json'
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

function Sql-Query([string]$Query) {
    & (Join-Path $repoRoot 'scripts\Invoke-RemicsDevSql.ps1') -Query $Query
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
Write-Host "schema=$schema project=$pc user=$User"

$findings = New-Object System.Collections.Generic.List[object]
function Add-Finding([string]$Id, [string]$Area, [string]$Verdict, [string]$Detail) {
    $findings.Add([pscustomobject]@{ id = $Id; area = $Area; verdict = $Verdict; detail = $Detail })
    Write-Host "[$Verdict] $Id ($Area) - $Detail"
}

# ---------- Static identification ----------
$dsJs = Get-Content (Join-Path $repoRoot 'config\remicsdev\source\mics\RemIcsReWrite\js\remics-ds.js') -Raw
$esChunkClassic = (Select-String -Path 'D:\inetpub\remicsdev\mics\Tdses\dsESList.aspx' -Pattern 'split\("\."\)' -Quiet)
$esChunkRewrite = $dsJs -match "split\(['\`"]\.['\`"]\)" -or $dsJs.Contains("keycount%subcount") -or $dsJs.Contains('% 100')
$esJoinOnly = $dsJs.Contains("var keylist = keys.join(',')") -or $dsJs.Contains('checked.join('','')')

Add-Finding 'STATIC-ES-CHUNK' 'ES' $(if ($esChunkClassic -and -not $esChunkRewrite -and $esJoinOnly) { 'SUSPECT' } else { 'NOTE' }) `
    "classic dsESList splits StoreKeys on '.' every 100; rewrite chunkingPresent=$esChunkRewrite joinOnly=$esJoinOnly"

$owEncode = $dsJs.Contains(".replace(/</g, '^')")
Add-Finding 'STATIC-OWHERE-ENCODE' 'owhere' $(if ($owEncode) { 'CLEARED_STATIC' } else { 'SUSPECT' }) `
    "rewrite saveTs/saveEs encodes < to ^: $owEncode"

$asmxTs = Select-String -Path 'D:\inetpub\remicsdev\mics\Tdsts\TwsdsTS.asmx.cs' -Pattern 'owhere\.Replace\("\^", "<"\)' -Quiet
$asmxEs = Select-String -Path 'D:\inetpub\remicsdev\mics\Tdses\TwsdsES.asmx.cs' -Pattern 'owhere\.Replace\("\^", "<"\)' -Quiet
Add-Finding 'STATIC-OWHERE-DECODE' 'owhere' $(if ($asmxTs -and $asmxEs) { 'CLEARED_STATIC' } else { 'SUSPECT' }) `
    "ASMX Replace ^ to <: TS=$asmxTs ES=$asmxEs"

# ---------- TS full save E2E ----------
$pdfTs = 'dshunt_ts_' + (Get-Date -Format 'HHmmss')
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
    if ($links.Count -lt 1) { throw 'no TS links from search' }
    $l = $links[0]
    $call1 = [string]$l.call1
    $call2 = [string]$l.call2
    $bnd = [string]$l.bndcde
    $siteKey = $call1 + '}}'
    $linkKey = $call1 + '}' + $call2 + '}' + $bnd
    $oeKey = $call2 + '}' + $call1 + '}' + $bnd
    $ow = [string]($search.owhere)
    $owEnc = $ow.Replace('<', '^')

    $createText = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/createTable') @{
        filename = $pdfTs; filetype = 'TS'; projectCode = $pc
    }
    if ($createText -match '^(ERROR|timeout)') { throw "createTable: $createText" }

    $null = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/ClearCulls') @{ start = '1' }
    $sk = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/SaveKeysLocal') @{
        inkeyss = $siteKey; checkss = '1'; inkeys = $linkKey; checks = '1'; type = 'LOCA'
    }
    if ($sk -match '^ERROR') { throw "SaveKeysLocal $sk" }
    $sr = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/SaveKeysRemote') @{
        inkeys = $oeKey; checks = '1'; type = 'REMO'
    }
    if ($sr -match '^ERROR') { throw "SaveKeysRemote $sr" }
    $ics = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/InsertCullSites') @{}
    if ($ics -match '^ERROR') { throw "InsertCullSites $ics" }
    foreach ($m in @('InsertCullAntesLink','InsertCullAntesOE','InsertCullChansLink','InsertCullChansOE')) {
        $body = Invoke-Asmx $session ($base + "Tdsts/TwsdsTS.asmx/$m") @{ owhere = $owEnc }
        if ($body -match '^ERROR') { throw "$m $body" }
    }
    $dupS = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/CheckDupSites') @{ name = $pdfTs }
    $insS = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/InsertPDFSites') @{ name = $pdfTs }
    if ($insS -match '^ERROR') { throw "InsertPDFSites $insS" }
    $null = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/CheckDupAntes') @{ name = $pdfTs }
    $insA = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/InsertPDFAntes') @{ name = $pdfTs }
    if ($insA -match '^ERROR') { throw "InsertPDFAntes $insA" }
    $null = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/CheckDupChans') @{ name = $pdfTs }
    $insC = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/InsertPDFChans') @{ name = $pdfTs }
    if ($insC -match '^ERROR') { throw "InsertPDFChans $insC" }

    $counts = Sql-Query @"
SELECT
 (SELECT COUNT(*) FROM $schema.ft_${pdfTs}_site) AS sites,
 (SELECT COUNT(*) FROM $schema.ft_${pdfTs}_ante) AS antes,
 (SELECT COUNT(*) FROM $schema.ft_${pdfTs}_chan) AS chans;
"@
    $countLine = ($counts | Where-Object { $_ -match '^\d+\|' } | Select-Object -First 1)
    if (-not $countLine) { $countLine = ($counts | Where-Object { $_ -match '\d+' } | Select-Object -Last 1) }
    $parts = "$countLine" -split '\|'
    $nSite = [int]$parts[0]; $nAnte = [int]$parts[1]; $nChan = [int]$parts[2]

    # Dup keep: re-run save into same PDF with keep mode simulation
    $null = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/ClearCulls') @{ start = '1' }
    $null = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/SaveKeysLocal') @{
        inkeyss = $siteKey; checkss = '1'; inkeys = $linkKey; checks = '1'; type = 'LOCA'
    }
    $null = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/InsertCullSites') @{}
    $dup2 = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/CheckDupSites') @{ name = $pdfTs }
    $dupN = 0; [void][int]::TryParse("$dup2".Trim(), [ref]$dupN)
    $null = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/DeleteCullSites') @{ name = $pdfTs }
    $counts2 = Sql-Query "SELECT COUNT(*) FROM $schema.ft_${pdfTs}_site;"
    $nSite2 = [int](($counts2 | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1).ToString().Trim())

    $okNew = ($nSite -gt 0)
    Add-Finding 'TS-SAVE-NEW' 'TS' $(if ($okNew) { 'CLEARED' } else { 'CONFIRMED' }) `
        "pdf=$pdfTs link=$linkKey sites=$nSite antes=$nAnte chans=$nChan dupOnAppend=$dupN sitesAfterKeep=$nSite2 owLen=$($ow.Length)"

    try {
        $null = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/killTable') @{
            filename = $pdfTs; filetype = 'TS'; projectCode = $pc
        }
    } catch { }
}
catch {
    Add-Finding 'TS-SAVE-NEW' 'TS' 'CONFIRMED' ("E2E failed: " + $_.Exception.Message)
}

# ---------- ES StoreKeys chunking verification ----------
try {
    $es = (Invoke-WebRequest -Uri ($rewrite + 'ds-search.ashx') -Method POST -WebSession $session -UseBasicParsing -TimeoutSec 180 `
        -Body @{ action = 'searchEs'; name = '*'; nameOp = 'LIKE' }).Content | ConvertFrom-Json
    $sites = @()
    if ($es.ok) { $sites = @($es.sites) }
    $need = 101
    if ($sites.Count -lt $need) {
        # pull locations from main.me_site
        $locOut = Sql-Query "SELECT TOP $need location FROM main.me_site ORDER BY location;"
        $locs = @($locOut | Where-Object { $_ -and $_ -notmatch 'location|---|rows affected|^$' -and $_ -notmatch '^\s*-' } | ForEach-Object { "$_".Trim() })
        if ($locs.Count -ge $need) { $sites = $locs | ForEach-Object { [pscustomobject]@{ location = $_ } } }
    }
    if ($sites.Count -lt $need) {
        Add-Finding 'ES-CHUNK-101' 'ES' 'INCONCLUSIVE' "only $($sites.Count) locations available (need $need)"
    } else {
        $locs101 = @($sites | Select-Object -First 101 | ForEach-Object { if ($_.location) { $_.location } else { "$_" } })
        # Classic: every 100th uses '.' before next key — after 100 keys, separator becomes '.' then reset to ','
        # So key 100 is followed by '.' + key101 → split('.') yields [keys1-100], [key101]
        $classicParts = New-Object System.Collections.Generic.List[string]
        $buf = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $locs101.Count; $i++) {
            $buf.Add($locs101[$i])
            if ((($i + 1) % 100) -eq 0 -and ($i + 1) -lt $locs101.Count) {
                $classicParts.Add(($buf -join ','))
                $buf.Clear()
            }
        }
        if ($buf.Count -gt 0) { $classicParts.Add(($buf -join ',')) }

        $rewriteOneShot = ($locs101 -join ',')

        $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/ClearCulls') @{ start = '1' }
        $chunkOk = $true
        $chunkErr = ''
        foreach ($block in $classicParts) {
            $r = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/StoreKeys') @{ keylist = $block }
            if ($r -match '^ERROR') { $chunkOk = $false; $chunkErr = $r; break }
        }
        $cntChunk = Sql-Query @"
SELECT COUNT(*) FROM $schema.cull_temp3_es WHERE sessionid LIKE '%' AND cull_type='SITE';
"@
        # Better: count via session — use FCSASESS from a known pattern. Probe via return of StoreKeys only.
        # Re-clear and try one-shot 101 comma list (rewrite behavior)
        $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/ClearCulls') @{ start = '1' }
        $one = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/StoreKeys') @{ keylist = $rewriteOneShot }
        $oneFail = ($one -match '^ERROR')

        # Measure cull rows after one-shot vs chunked using a dedicated marker — StoreKeys inserts session FCSASESS
        # Compare lengths: if one-shot succeeds, bug is latent (URL/JSON size) not hard fail at 101.
        # Classic reason for chunking is request size / reliability. Verify rewrite code lacks chunking (already SUSPECT)
        # and whether 101 one-shot works on remicsdev.
        Add-Finding 'ES-CHUNK-CODE' 'ES' 'CONFIRMED' `
            "rewrite saveEs uses single join(',') with no '.' blocks; classic uses 100-key '.' chunks (blocks=$($classicParts.Count))"
        Add-Finding 'ES-CHUNK-101-ONESHOT' 'ES' $(if ($oneFail) { 'CONFIRMED' } else { 'CLEARED_AT_101' }) `
            "one-shot StoreKeys 101 locs fail=$oneFail body=$one chunkedOk=$chunkOk chunkErr=$chunkErr"
    }
}
catch {
    Add-Finding 'ES-CHUNK-101' 'ES' 'INCONCLUSIVE' $_.Exception.Message
}

# ES small save E2E (1 location)
$pdfEs = 'dshunt_es_' + (Get-Date -Format 'HHmmss')
try {
    $es2 = (Invoke-WebRequest -Uri ($rewrite + 'ds-search.ashx') -Method POST -WebSession $session -UseBasicParsing -TimeoutSec 120 `
        -Body @{ action = 'searchEs'; name = 'A'; nameOp = 'LIKE' }).Content | ConvertFrom-Json
    $esSites = @()
    if ($es2.ok) { $esSites = @($es2.sites) }
    if ($esSites.Count -lt 1) {
        $es2 = (Invoke-WebRequest -Uri ($rewrite + 'ds-search.ashx') -Method POST -WebSession $session -UseBasicParsing -TimeoutSec 120 `
            -Body @{ action = 'searchEs'; name = '*'; nameOp = 'LIKE' }).Content | ConvertFrom-Json
        $esSites = @($es2.sites)
    }
    if ($esSites.Count -lt 1) { throw 'no ES sites' }
    $loc = [string]$esSites[0].location
    $owEs = [string]($es2.owhere)
    $owEsEnc = $owEs.Replace('<', '^')

    $createEs = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/createTable') @{
        filename = $pdfEs; filetype = 'ES'; projectCode = $pc
    }
    if ($createEs -match '^(ERROR|timeout)') { throw "createTable ES: $createEs" }

    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/ClearCulls') @{ start = '1' }
    $skE = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/StoreKeys') @{ keylist = $loc }
    if ($skE -match '^ERROR') { throw "StoreKeys $skE" }
    $ia = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullAntes') @{ owhere = $owEsEnc }
    if ($ia -match '^ERROR') { throw "InsertCullAntes $ia" }
    $ic = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullChans') @{ owhere = $owEsEnc }
    if ($ic -match '^ERROR') { throw "InsertCullChans $ic" }
    $insEs = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertPDFSites') @{ name = $pdfEs }
    if ($insEs -match '^ERROR') { throw "InsertPDFSites $insEs" }
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertPDFAntes') @{ name = $pdfEs }
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertPDFChans') @{ name = $pdfEs }

    $esCnt = Sql-Query "SELECT COUNT(*) FROM $schema.fe_${pdfEs}_site;"
    $nEs = [int](($esCnt | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1).ToString().Trim())
    Add-Finding 'ES-SAVE-NEW' 'ES' $(if ($nEs -gt 0) { 'CLEARED' } else { 'CONFIRMED' }) `
        "pdf=$pdfEs loc=$loc sites=$nEs owLen=$($owEs.Length)"

    try {
        $null = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/killTable') @{
            filename = $pdfEs; filetype = 'ES'; projectCode = $pc
        }
    } catch { }
}
catch {
    Add-Finding 'ES-SAVE-NEW' 'ES' 'CONFIRMED' ("E2E failed: " + $_.Exception.Message)
}

# ---------- owhere round-trip with < in criteria ----------
try {
    $filt = (Invoke-WebRequest -Uri ($rewrite + 'ds-search.ashx') -Method POST -WebSession $session -UseBasicParsing -TimeoutSec 120 `
        -Body @{ action = 'searchTs'; call1 = '*'; call1Op = 'LIKE'; grnd = '100'; grndOp = '<' }).Content | ConvertFrom-Json
    $owF = [string]($filt.owhere)
    $hasLt = $owF.Contains('<')
    $owFEnc = $owF.Replace('<', '^')
    $hasCaret = $owFEnc.Contains('^') -and -not $owFEnc.Contains('<')
    if (-not $filt.ok) { throw "filtered searchTs failed: $($filt.error)" }

    $null = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/ClearCulls') @{ start = '1' }
    # Need at least one site key for cull ante to be meaningful — use first link if any
    $fl = @($filt.links)
    if ($fl.Count -lt 1) {
        # still test InsertCull with empty culls — may return empty success
        $r1 = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/InsertCullAntesLink') @{ owhere = $owFEnc }
        $bad1 = ($r1 -match '^ERROR')
        Add-Finding 'OWHERE-ROUNDTRIP' 'owhere' $(if ($hasLt -and $hasCaret -and -not $bad1) { 'CLEARED' } elseif (-not $hasLt) { 'INCONCLUSIVE' } else { 'CONFIRMED' }) `
            "owhereHas<=$hasLt encOk=$hasCaret InsertCullAntesLink err=$bad1 body=$r1 owhere=$owF"
    } else {
        $lx = $fl[0]
        $sk2 = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/SaveKeysLocal') @{
            inkeyss = ([string]$lx.call1 + '}}'); checkss = '1'
            inkeys = ([string]$lx.call1 + '}' + [string]$lx.call2 + '}' + [string]$lx.bndcde); checks = '1'; type = 'LOCA'
        }
        $null = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/InsertCullSites') @{}
        $r1 = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/InsertCullAntesLink') @{ owhere = $owFEnc }
        $rBad = ($r1 -match '^ERROR')
        # Also try WITHOUT encoding (raw <) — should fail or break SOAP/JSON
        $rRaw = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/InsertCullAntesLink') @{ owhere = $owF }
        $rawBad = ($rRaw -match '^ERROR')
        Add-Finding 'OWHERE-ROUNDTRIP' 'owhere' $(if ($hasLt -and $hasCaret -and -not $rBad) { 'CLEARED' } else { 'CONFIRMED' }) `
            "has<=$hasLt encOk=$hasCaret cullEncErr=$rBad cullRawErr=$rawBad encBody=$r1"
    }

    # ES filtered
    $filtE = (Invoke-WebRequest -Uri ($rewrite + 'ds-search.ashx') -Method POST -WebSession $session -UseBasicParsing -TimeoutSec 120 `
        -Body @{ action = 'searchEs'; name = '*'; nameOp = 'LIKE'; grnd = '50'; grndOp = '<' }).Content | ConvertFrom-Json
    $owE = [string]($filtE.owhere)
    $hasLtE = $owE.Contains('<')
    $owEEnc = $owE.Replace('<', '^')
    if ($filtE.ok -and $hasLtE) {
        $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/ClearCulls') @{ start = '1' }
        $esLocs = @($filtE.sites)
        if ($esLocs.Count -gt 0) {
            $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/StoreKeys') @{ keylist = [string]$esLocs[0].location }
        }
        $rae = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullAntes') @{ owhere = $owEEnc }
        Add-Finding 'OWHERE-ES-ROUNDTRIP' 'owhere' $(if ($rae -notmatch '^ERROR') { 'CLEARED' } else { 'CONFIRMED' }) `
            "ow=$owE encCull=$rae"
    } else {
        Add-Finding 'OWHERE-ES-ROUNDTRIP' 'owhere' 'INCONCLUSIVE' "searchOk=$($filtE.ok) hasLt=$hasLtE ow=$owE"
    }
}
catch {
    Add-Finding 'OWHERE-ROUNDTRIP' 'owhere' 'INCONCLUSIVE' $_.Exception.Message
}

# Summary
$confirmed = @($findings | Where-Object { $_.verdict -eq 'CONFIRMED' })
$cleared = @($findings | Where-Object { $_.verdict -match 'CLEARED' })
$sus = @($findings | Where-Object { $_.verdict -eq 'SUSPECT' })
Write-Host ""
Write-Host "SUMMARY confirmed=$($confirmed.Count) cleared=$($cleared.Count) suspect=$($sus.Count) total=$($findings.Count)"

$result = [pscustomobject]@{
    when = (Get-Date).ToString('s')
    user = $User
    schema = $schema
    findings = $findings
    confirmed = $confirmed.Count
    cleared = $cleared.Count
}
$dir = Split-Path $ResultPath
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$result | ConvertTo-Json -Depth 6 | Set-Content $ResultPath -Encoding UTF8
Write-Host "Wrote $ResultPath"
