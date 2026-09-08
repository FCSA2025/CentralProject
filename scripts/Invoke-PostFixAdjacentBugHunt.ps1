#Requires -Version 5.1
<#
.SYNOPSIS
  Identify+verify adjacent bug hunt (cats 1-6) after 2026-09-08 fixes.
  Does NOT fix — reports CONFIRMED / CLEARED / INCONCLUSIVE / NOTE.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.CLOUDMICSDEV.ca/mics/',
    [string]$User = 'rctl1',
    [string]$Password = '',
    [string]$ResultPath = 'E:\AIProjects\CentralProject\tmp-tsjob\postfix-adjacent-bughunt-2026-09-08.json'
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

function Invoke-FormPost($Session, [string]$Url, [hashtable]$Body) {
    try {
        $r = Invoke-WebRequest -Uri $Url -Method POST -WebSession $Session -UseBasicParsing -TimeoutSec 180 -Body $Body
        return $r.Content
    } catch {
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { return [string]$_.ErrorDetails.Message }
        $resp = $_.Exception.Response
        if ($resp) {
            try {
                $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
                $bodyTxt = $sr.ReadToEnd()
                $sr.Close()
                if ($bodyTxt) { return $bodyTxt }
            } catch { }
        }
        throw
    }
}

function Get-SqlCount([string]$Query) {
    $out = Sql-Query $Query
    foreach ($line in $out) {
        $t = ("$line").Trim()
        if ($t -match '^\d+$') { return [int]$t }
        if ($t -match '^(\d+)\s*\|') { return [int]$Matches[1] }
        if ($t -match '\|\s*(\d+)\s*$') { return [int]$Matches[1] }
    }
    return -1
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
    foreach ($block in $blocks) {
        if (-not $block) { continue }
        $r = Invoke-Asmx $Session ($Base + 'Tdses/TwsdsES.asmx/StoreKeys') @{ keylist = $block }
        if ($r -match '^ERROR') { throw "StoreKeys: $r" }
    }
    return $blocks.Count
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
function Add-Finding([string]$Id, [string]$Cat, [string]$Verdict, [string]$Detail) {
    $findings.Add([pscustomobject]@{ id = $Id; category = $Cat; verdict = $Verdict; detail = $Detail })
    Write-Host "[$Verdict] $Id (cat$Cat) - $Detail"
}

# =============================================================================
# CAT 1 — Batch email via MicsEmail / queue
# =============================================================================
Write-Host "`n=== CAT 1: batch email ==="

$meSrc = 'D:\MicsBatchProgs\MicsBat\_Utillib\MicsEmail.cs'
$meTxt = if (Test-Path $meSrc) { Get-Content $meSrc -Raw } else { '' }
$sendRoutesSql = $meTxt -match 'public static int Send\(' -and $meTxt -match 'return SendSql\('
Add-Finding 'C1-STATIC-SEND-ROUTES' '1' $(if ($sendRoutesSql) { 'CLEARED' } else { 'CONFIRMED' }) `
    "MicsEmail.Send routes to SendSql=$sendRoutesSql"

$queueConfigs = @('PFDcont.exe.config','SendLAMLreports.exe.config','SMTP.exe.config','TsipInitiator.exe.config')
$missingQ = @()
foreach ($c in $queueConfigs) {
    $p = Join-Path 'D:\develbat' $c
    if (-not (Test-Path $p)) { $missingQ += "$c MISSING"; continue }
    $t = Get-Content $p -Raw
    if ($t -notmatch 't_EmailQueue_local') { $missingQ += "$c no local queue" }
}
Add-Finding 'C1-STATIC-QUEUE-CONFIG' '1' $(if ($missingQ.Count -eq 0) { 'CLEARED' } else { 'CONFIRMED' }) `
    $(if ($missingQ.Count -eq 0) { 'PFD/LAML/SMTP/TsipInitiator all use adm.t_EmailQueue_local' } else { ($missingQ -join '; ') })

# Live SMTP.exe queue insert (CLI: to-address only; fixed subject "SMTP.exe queue test")
$smtpExe = 'D:\develbat\SMTP.exe'
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
if (Test-Path $smtpExe) {
    try {
        $before = Sql-Query "SELECT COUNT(*) FROM adm.t_EmailQueue_local WHERE mailSubject LIKE 'SMTP.exe queue test%';"
        $beforeN = [int](($before | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1).ToString().Trim())
        $psi = Start-Process -FilePath $smtpExe -ArgumentList @("bughunt+$stamp@example.com") `
            -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $env:TEMP 'smtp-out.txt') `
            -RedirectStandardError (Join-Path $env:TEMP 'smtp-err.txt')
        Start-Sleep -Seconds 2
        $after = Sql-Query "SELECT COUNT(*) FROM adm.t_EmailQueue_local WHERE mailSubject LIKE 'SMTP.exe queue test%';"
        $afterN = [int](($after | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1).ToString().Trim())
        $outTxt = ''
        if (Test-Path (Join-Path $env:TEMP 'smtp-out.txt')) { $outTxt = Get-Content (Join-Path $env:TEMP 'smtp-out.txt') -Raw }
        $queued = ($afterN -gt $beforeN) -or ($outTxt -match 'SUCCEEDED')
        Add-Finding 'C1-LIVE-SMTP-QUEUE' '1' $(if ($queued) { 'CLEARED' } else { 'CONFIRMED' }) `
            "exit=$($psi.ExitCode) before=$beforeN after=$afterN out=$($outTxt.Trim().Substring(0,[Math]::Min(160,$outTxt.Trim().Length)))"
    } catch {
        Add-Finding 'C1-LIVE-SMTP-QUEUE' '1' 'INCONCLUSIVE' $_.Exception.Message
    }
} else {
    Add-Finding 'C1-LIVE-SMTP-QUEUE' '1' 'INCONCLUSIVE' 'SMTP.exe missing'
}

# LAML Email.cs uses queue (static)
$lamlEmail = 'D:\MicsBatchProgs\MicsBat\SendLAMLreports\Email.cs'
if (Test-Path $lamlEmail) {
    $lt = Get-Content $lamlEmail -Raw
    $ok = $lt -match 't_EmailQueue' -or $lt -match 'EmailQueueTable' -or $lt -match 'INSERT INTO'
    Add-Finding 'C1-STATIC-LAML-QUEUE' '1' $(if ($ok) { 'CLEARED' } else { 'CONFIRMED' }) `
        "SendLAMLreports Email.cs queues=$ok"
} else {
    Add-Finding 'C1-STATIC-LAML-QUEUE' '1' 'INCONCLUSIVE' 'Email.cs missing'
}

# Ssutil.SendEmail callers outside definition — dead path?
$ssCallers = @(Select-String -Path 'D:\MicsBatchProgs\MicsBat\*\*.cs' -Pattern 'Ssutil\.SendEmail\s*\(' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -notmatch '\\_Utillib\\' })
Add-Finding 'C1-STATIC-SSUTIL-CALLERS' '1' 'NOTE' `
    "Ssutil.SendEmail external callers=$($ssCallers.Count) (PFD uses Products.SendEmail→SendSql)"

# Recent queue health: any stuck N older than 1 day?
try {
    $stuck = Sql-Query @"
SELECT COUNT(*) FROM adm.t_EmailQueue_local
WHERE sentYN='N' AND ISNULL(mailSubject,'') NOT LIKE '%postfix-bughunt%'
  AND mailSubject IS NOT NULL;
"@
    $stuckN = [int](($stuck | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1).ToString().Trim())
    Add-Finding 'C1-LIVE-QUEUE-PENDING' '1' 'NOTE' "pending sentYN=N rows (excl marker)=$stuckN"
} catch {
    Add-Finding 'C1-LIVE-QUEUE-PENDING' '1' 'INCONCLUSIVE' $_.Exception.Message
}

# =============================================================================
# CAT 2 — ES save with filter (owhere) + 100+ + keep/over
# =============================================================================
Write-Host "`n=== CAT 2: ES filtered large save ==="
try {
    $search = (Invoke-WebRequest -Uri ($rewrite + 'ds-search.ashx') -Method POST -WebSession $session -UseBasicParsing -TimeoutSec 180 `
        -Body @{ action = 'searchEs'; name = '*'; nameOp = 'LIKE' }).Content | ConvertFrom-Json
    if (-not $search.ok) { throw "searchEs: $($search.error)" }
    $sites = @($search.sites)
    $ow = [string]($search.owhere)
    if ($sites.Count -lt 101) {
        $locOut = Sql-Query "SELECT TOP 101 location FROM main.me_site ORDER BY location;"
        $locsFromDb = @($locOut | Where-Object {
            $_ -and ("$_" -notmatch 'location|^-+|rows affected|^\s*$')
        } | ForEach-Object { ("$_".Trim() -split '\|')[0].Trim() } | Where-Object { $_ -match '\S' })
        if ($locsFromDb.Count -ge 101) {
            $sites = @($locsFromDb | Select-Object -First 101 | ForEach-Object { [pscustomobject]@{ location = $_ } })
            if (-not $ow) { $ow = '1=1' }
        }
    }
    if ($sites.Count -lt 101) { throw "need 101 ES sites, got $($sites.Count)" }
    $locs = @($sites | Select-Object -First 101 | ForEach-Object { [string]$_.location })
    $owEnc = $ow.Replace('<', '^')
    $blocks = Invoke-StoreEsKeysChunked $session $base $locs
    $pdfKeep = 'bh2k_' + (Get-Date -Format 'HHmmss')
    $pdfOver = 'bh2o_' + (Get-Date -Format 'HHmmss')
    foreach ($nm in @($pdfKeep, $pdfOver)) {
        $ct = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/createTable') @{
            filename = $nm; filetype = 'ES'; projectCode = $pc
        }
        if ($ct -match '^(ERROR|timeout)') { throw "createTable ${nm}: $ct" }
    }
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullAntes') @{ owhere = $owEnc }
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullChans') @{ owhere = $owEnc }
    $ins = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertPDFSites') @{ name = $pdfKeep }
    if ($ins -match '^ERROR') { throw "InsertPDFSites keep: $ins" }
    $n1 = Get-SqlCount "SELECT COUNT(*) FROM $schema.fe_${pdfKeep}_site;"

    $null = Invoke-StoreEsKeysChunked $session $base $locs
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullAntes') @{ owhere = $owEnc }
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullChans') @{ owhere = $owEnc }
    $dup = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/CheckDupSites') @{ name = $pdfKeep }
    $dupN = 0; [void][int]::TryParse(($dup -replace '[^\d]', ''), [ref]$dupN)
    if ($dupN -gt 0) {
        $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/DeleteCullSites') @{ name = $pdfKeep }
    }
    $null = Invoke-StoreEsKeysChunked $session $base $locs
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullAntes') @{ owhere = $owEnc }
    $null = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertCullChans') @{ owhere = $owEnc }
    $ins2 = Invoke-Asmx $session ($base + 'Tdses/TwsdsES.asmx/InsertPDFSites') @{ name = $pdfOver }
    if ($ins2 -match '^ERROR') { throw "InsertPDFSites over: $ins2" }
    $n2 = Get-SqlCount "SELECT COUNT(*) FROM $schema.fe_${pdfOver}_site;"

    $ok = ($n1 -eq 101) -and ($n2 -eq 101)
    Add-Finding 'C2-LIVE-ES-FILTER-101-DUP' '2' $(if ($ok) { 'CLEARED' } else { 'CONFIRMED' }) `
        "owLen=$($ow.Length) blocks=$blocks keepSites=$n1 overSites=$n2 dupOnKeep=$dupN"

    foreach ($n in @($pdfKeep, $pdfOver)) {
        $null = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/killTable') @{
            filename = $n; filetype = 'ES'; projectCode = $pc
        }
    }
} catch {
    Add-Finding 'C2-LIVE-ES-FILTER-101-DUP' '2' 'CONFIRMED' $_.Exception.Message
}

# =============================================================================
# CAT 3 — Aux Eng lat/long cousins
# =============================================================================
Write-Host "`n=== CAT 3: Aux Eng LL ==="

# Static: orbit rewrite vs classic both require full nn-nn-nn.nnN
$orbitSrc = Join-Path $repoRoot 'config\remicsdev\source\mics\RemIcsReWrite\aux-orbit.ashx'
$orbitStrict = (Get-Content $orbitSrc -Raw) -match 'Latitude format must be nn-nn-nn\.nnN'
$classicOrbitStrict = Select-String -Path 'D:\inetpub\remicsdev\mics\auxengmenu\AUXOrbit.aspx.cs' `
    -Pattern 'Latitude format must be nn-nn-nn\.nnN' -Quiet
Add-Finding 'C3-STATIC-ORBIT-STRICT' '3' $(if ($orbitStrict -and $classicOrbitStrict) { 'CLEARED' } else { 'NOTE' }) `
    "rewriteStrict=$orbitStrict classicStrict=$classicOrbitStrict (classic also requires full DMS)"

# Live: orbit rejects abbreviated (expected classic parity)
try {
    $orbRaw = Invoke-FormPost $session ($rewrite + 'aux-orbit.ashx') @{
        action = 'coords'; lat = '45-30N'; lng = '075-30W'; alt = '100'; antHt = '10'
    }
    $orb = $orbRaw | ConvertFrom-Json
    $errOrb = ''
    if ($orb.PSObject.Properties['error']) { $errOrb = [string]$orb.error }
    $rej = (-not $orb.ok) -and ($errOrb -match 'Latitude format|nn-nn')
    Add-Finding 'C3-LIVE-ORBIT-ABBREV' '3' $(if ($rej) { 'CLEARED' } else { 'CONFIRMED' }) `
        "abbrev response ok=$($orb.ok) error=$errOrb"
} catch {
    Add-Finding 'C3-LIVE-ORBIT-ABBREV' '3' 'INCONCLUSIVE' $_.Exception.Message
}

# Live: terrain/pfd/sataze getcoords with abbreviated LL (TokenOk allows; classic uses getcoords)
$auxTools = @(
    [pscustomobject]@{ id = 'C3-LIVE-TERRAIN-ABBREV'; url = 'aux-terrain.ashx'; extra = @{} },
    [pscustomobject]@{ id = 'C3-LIVE-PFD-ABBREV'; url = 'aux-pfd.ashx'; extra = @{} },
    [pscustomobject]@{ id = 'C3-LIVE-SATAZE-ABBREV'; url = 'aux-sataze.ashx'; extra = @{ antHt = '10'; grnd = '100'; satName = 'TEST'; satLng = '100'; refract = '1.0' } }
)
foreach ($tool in $auxTools) {
    try {
        $body = @{ action = 'getcoords'; lat = '45-30N'; lng = '075-30W' }
        if ($tool.extra) {
            foreach ($k in @($tool.extra.Keys)) { $body[$k] = $tool.extra[$k] }
        }
        $raw = Invoke-FormPost $session ($rewrite + $tool.url) $body
        $j = $raw | ConvertFrom-Json
        if ($j.ok) {
            Add-Finding $tool.id '3' 'CLEARED' "abbrev accepted lat84=$($j.lat84) lng84=$($j.lng84)"
        } else {
            $err = [string]$j.error
            if ($err -match 'lat/long|format|specify|Invalid|Token|No Match') {
                Add-Finding $tool.id '3' 'CONFIRMED' "abbrev rejected: $err"
            } else {
                Add-Finding $tool.id '3' 'INCONCLUSIVE' "ok=false error=$err"
            }
        }
    } catch {
        Add-Finding $tool.id '3' 'INCONCLUSIVE' $_.Exception.Message
    }
}

# Passive abbrev (should work after B4)
try {
    $pasRaw = Invoke-FormPost $session ($rewrite + 'aux-passive.ashx') @{
        action = 'run'; mode = 'L'; nPass = '1'
        freq = '6000'; power0 = '30'; again0 = '40'; fsl0 = '0'; power5 = '0'; again5 = '0'; fsl5 = '0'
        lat0 = '45-30N'; lng0 = '075-30W'; alt0 = '100'; ant0 = '10'
        lat5 = '45-40N'; lng5 = '075-40W'; alt5 = '100'; ant5 = '10'
        dst0 = '0'; wd1 = '1'; ht1 = '1'; ang1 = '0'; dst1 = '10'
        lat1 = '45-35N'; lng1 = '075-35W'; alt1 = '100'; ant1 = '10'
    }
    $pas = $pasRaw | ConvertFrom-Json
    $pasErr = ''
    if ($pas.PSObject.Properties['error']) { $pasErr = [string]$pas.error }
    Add-Finding 'C3-LIVE-PASSIVE-ABBREV' '3' $(if ($pas.ok) { 'CLEARED' } else { 'CONFIRMED' }) `
        "ok=$($pas.ok) error=$pasErr"
} catch {
    Add-Finding 'C3-LIVE-PASSIVE-ABBREV' '3' 'INCONCLUSIVE' $_.Exception.Message
}

# PCS client parse (static): optional seconds present
$p675 = Get-Content (Join-Path $repoRoot 'config\remicsdev\source\mics\RemIcsReWrite\js\remics-phase675.js') -Raw
$pcsLoose = $p675 -match 'function pcsParseLl' -and $p675 -match '\(-\[\\d\\\.\]\{0,5\}\)\?'
Add-Finding 'C3-STATIC-PCS-PARSE' '3' $(if ($pcsLoose) { 'CLEARED' } else { 'CONFIRMED' }) `
    "pcsParseLl optional-seconds=$pcsLoose"

# =============================================================================
# CAT 4 — SDF large Ante (>60) with InsertAntd
# =============================================================================
Write-Host "`n=== CAT 4: SDF Ante large ==="
try {
    $search = (Invoke-WebRequest -Uri ($rewrite + 'ds-sdf.ashx') -Method POST -WebSession $session -UseBasicParsing -TimeoutSec 180 `
        -Body @{ action = 'search'; type = 'Ante'; acode = '*' }).Content | ConvertFrom-Json
    if (-not $search.ok) {
        $errS = ''
        if ($search.PSObject.Properties['error']) { $errS = [string]$search.error }
        throw "ds-sdf Ante: $errS"
    }
    $rows = @()
    if ($search.PSObject.Properties['rows'] -and $null -ne $search.rows) { $rows = @($search.rows) }
    $parts = @('acode')
    if ($search.PSObject.Properties['keyParts'] -and $null -ne $search.keyParts) { $parts = @($search.keyParts) }
    if ($rows.Count -lt 61) { throw "need 61 Ante rows, got $($rows.Count)" }
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($r in $rows) {
        $kv = foreach ($p in $parts) {
            if ($r.PSObject.Properties[$p]) { [string]$r.$p } else { '' }
        }
        $k = ($kv -join ':')
        if ($k -and (($k -replace ':', '').Length -gt 0)) { $keys.Add($k) }
    }
    $uniq = @($keys | Select-Object -Unique)
    if ($uniq.Count -lt 61) { throw "unique Ante keys=$($uniq.Count)" }
    $use = @($uniq | Select-Object -First 61)
    $chunks = New-Object System.Collections.Generic.List[string]
    $batch = New-Object System.Collections.Generic.List[string]
    foreach ($k in $use) {
        $batch.Add($k)
        if ($batch.Count -ge 60) {
            $chunks.Add(($batch -join ','))
            $batch.Clear()
        }
    }
    if ($batch.Count) { $chunks.Add(($batch -join ',')) }

    $sdf = 'bh4a_' + (Get-Date -Format 'HHmmss')
    $ct = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/createTable') @{
        filename = $sdf; filetype = 'Ante'; projectCode = $pc
    }
    if ($ct -match '^(ERROR|timeout)') { throw "createTable: $ct" }
    foreach ($chunk in $chunks) {
        $i1 = Invoke-Asmx $session ($base + 'Tdssdf/TwsdsSDF.asmx/InsertAnte') @{ name = $sdf; keylist = $chunk }
        if ($i1 -match '^ERROR') { throw "InsertAnte: $i1" }
        $i2 = Invoke-Asmx $session ($base + 'Tdssdf/TwsdsSDF.asmx/InsertAntd') @{ name = $sdf; keylist = $chunk }
        if ($i2 -match '^ERROR') { throw "InsertAntd: $i2" }
    }
    $nA = Get-SqlCount "SELECT COUNT(*) FROM $schema.su_${sdf}_ante;"
    $nD = Get-SqlCount "SELECT COUNT(*) FROM $schema.su_${sdf}_antd;"
    $ok = ($nA -eq 61) -and ($chunks.Count -ge 2) -and ($nD -gt 0)
    Add-Finding 'C4-LIVE-ANTE-61-CHUNK' '4' $(if ($ok) { 'CLEARED' } else { 'CONFIRMED' }) `
        "chunks=$($chunks.Count) anteRows=$nA antdRows=$nD (tables su_*_ante/antd)"
    $null = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/killTable') @{
        filename = $sdf; filetype = 'Ante'; projectCode = $pc
    }
} catch {
    Add-Finding 'C4-LIVE-ANTE-61-CHUNK' '4' 'CONFIRMED' $_.Exception.Message
}

# Classic uses ';' delimiter quirk vs rewrite equal-60 batches — behavioral note if both work
Add-Finding 'C4-STATIC-CHUNK-SHAPE' '4' 'NOTE' `
    'classic SDF inserts ; before every 60th key (first block ~59); rewrite uses equal batches of 60 — cleared if InsertAnte accepts both'

# =============================================================================
# CAT 5 — TS large multi-select
# =============================================================================
Write-Host "`n=== CAT 5: TS large multi ==="
try {
    $search = (Invoke-WebRequest -Uri ($rewrite + 'ds-search.ashx') -Method POST -WebSession $session -UseBasicParsing -TimeoutSec 180 `
        -Body @{ action = 'searchTs'; call1 = '*'; call1Op = 'LIKE' }).Content | ConvertFrom-Json
    if (-not $search.ok) { throw "searchTs: $($search.error)" }
    $links = @($search.links)
    $need = [Math]::Min(80, $links.Count)
    if ($need -lt 20) { throw "need >=20 links, got $($links.Count)" }
    $siteKeys = New-Object System.Collections.Generic.List[string]
    $linkKeys = New-Object System.Collections.Generic.List[string]
    $oeKeys = New-Object System.Collections.Generic.List[string]
    $chkS = ''; $chkL = ''; $chkO = ''
    $seenSite = @{}
    foreach ($l in ($links | Select-Object -First $need)) {
        $c1 = [string]$l.call1; $c2 = [string]$l.call2; $bnd = [string]$l.bndcde
        $linkKeys.Add("$c1}$c2}$bnd")
        $chkL += '1'
        $oeKeys.Add("$c2}$c1}$bnd")
        $chkO += '1'
        if (-not $seenSite.ContainsKey($c1)) {
            $seenSite[$c1] = $true
            $siteKeys.Add("$c1}}")
            $chkS += '1'
        }
    }
    $pdf = 'bh5t_' + (Get-Date -Format 'HHmmss')
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
    $ow = [string]($search.owhere)
    $owEnc = $ow.Replace('<', '^')
    $ics = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/InsertCullSites') @{}
    if ($ics -match '^ERROR') { throw "InsertCullSites: $ics" }
    foreach ($m in @('InsertCullAntesLink', 'InsertCullAntesOE', 'InsertCullChansLink', 'InsertCullChansOE')) {
        $body = Invoke-Asmx $session ($base + "Tdsts/TwsdsTS.asmx/$m") @{ owhere = $owEnc }
        if ($body -match '^ERROR') { throw "$m $body" }
    }
    $is = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/InsertPDFSites') @{ name = $pdf }
    if ($is -match '^ERROR') { throw "InsertPDFSites: $is" }
    $ia = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/InsertPDFAntes') @{ name = $pdf }
    if ($ia -match '^ERROR') { throw "InsertPDFAntes: $ia" }
    $ic = Invoke-Asmx $session ($base + 'Tdsts/TwsdsTS.asmx/InsertPDFChans') @{ name = $pdf }
    if ($ic -match '^ERROR') { throw "InsertPDFChans: $ic" }
    $nS = Get-SqlCount "SELECT COUNT(*) FROM $schema.ft_${pdf}_site;"
    $nC = Get-SqlCount "SELECT COUNT(*) FROM $schema.ft_${pdf}_chan;"
    $ok = ($nS -gt 0) -and ($nC -gt 0) -and ($need -ge 20)
    Add-Finding 'C5-LIVE-TS-LARGE' '5' $(if ($ok) { 'CLEARED' } else { 'CONFIRMED' }) `
        "requestedLinks=$need sites=$nS chans=$nC siteKeys=$($siteKeys.Count) linkKeys=$($linkKeys.Count)"
    $null = Invoke-Asmx $session ($base + 'Tfileactions/TwsTabUtil.asmx/killTable') @{
        filename = $pdf; filetype = 'TS'; projectCode = $pc
    }
} catch {
    Add-Finding 'C5-LIVE-TS-LARGE' '5' 'CONFIRMED' $_.Exception.Message
}

# Classic TS has no '.' StoreKeys chunking (server SaveKeys* loops)
$tsChunk = Select-String -Path 'D:\inetpub\remicsdev\mics\Tdsts\dsTSList.aspx' -Pattern 'split\("\."\)|subcount\s*=' -Quiet
Add-Finding 'C5-STATIC-TS-NO-DOT-CHUNK' '5' 'NOTE' "classic dsTSList has client dot-chunk=$tsChunk (server SaveKeys loops)"

# =============================================================================
# CAT 6 — Schema ES cull table gaps
# =============================================================================
Write-Host "`n=== CAT 6: schema cull gaps ==="
try {
    # Company schemas = adm.account_details.ultrixid (operator) that exist as SQL schemas
    $missQ = Sql-Query @"
SELECT RTRIM(a.ultrixid) AS op
FROM (SELECT DISTINCT ultrixid FROM adm.account_details) a
WHERE EXISTS (SELECT 1 FROM sys.schemas s WHERE s.name = RTRIM(a.ultrixid))
AND NOT EXISTS (
  SELECT 1 FROM INFORMATION_SCHEMA.TABLES t
  WHERE t.TABLE_SCHEMA = RTRIM(a.ultrixid) AND t.TABLE_NAME = 'cull_temp3_es'
)
ORDER BY 1;
"@
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($line in $missQ) {
        if ($line -match '^\s*-' -or $line -match '^\s*op\s*$' -or $line -match '^\s*$' -or $line -match 'rows affected') { continue }
        $v = ("$line".Trim() -split '\|')[0].Trim()
        if ($v -match '^[A-Za-z][A-Za-z0-9_]*$') { $missing.Add($v) }
    }
    $missing = @($missing | Select-Object -Unique)
    $isBug = $missing.Count -gt 0
    Add-Finding 'C6-LIVE-CULL-ES-GAPS' '6' $(if ($isBug) { 'CONFIRMED' } else { 'CLEARED' }) `
        "accountSchemasMissingCullEs=$($missing.Count) list=$(($missing | Select-Object -First 40) -join ',')"
} catch {
    Add-Finding 'C6-LIVE-CULL-ES-GAPS' '6' 'INCONCLUSIVE' $_.Exception.Message
}

# Also: bchy specifically (known from B6 smoke)
try {
    $bchy = Sql-Query "SELECT CASE WHEN OBJECT_ID('bchy.cull_temp3_es') IS NULL THEN 'MISSING' ELSE 'OK' END;"
    $b = ($bchy | Where-Object { $_ -match 'MISSING|OK' } | Select-Object -First 1)
    Add-Finding 'C6-LIVE-BCHY-CULL' '6' $(if ("$b" -match 'MISSING') { 'CONFIRMED' } else { 'CLEARED' }) `
        "bchy.cull_temp3_es=$b"
} catch {
    Add-Finding 'C6-LIVE-BCHY-CULL' '6' 'INCONCLUSIVE' $_.Exception.Message
}

# =============================================================================
# Summary + write
# =============================================================================
$confirmed = @($findings | Where-Object { $_.verdict -eq 'CONFIRMED' })
$cleared = @($findings | Where-Object { $_.verdict -eq 'CLEARED' })
$incon = @($findings | Where-Object { $_.verdict -eq 'INCONCLUSIVE' })
$notes = @($findings | Where-Object { $_.verdict -eq 'NOTE' })

$out = [ordered]@{
    when = (Get-Date).ToString('s')
    user = $User
    schema = $schema
    summary = [ordered]@{
        confirmed = $confirmed.Count
        cleared = $cleared.Count
        inconclusive = $incon.Count
        notes = $notes.Count
        total = $findings.Count
    }
    confirmedBugs = @(
        $confirmed | ForEach-Object {
            [ordered]@{ id = $_.id; category = $_.category; detail = [string]$_.detail }
        }
    )
    findings = @(
        $findings | ForEach-Object {
            [ordered]@{ id = $_.id; category = $_.category; verdict = $_.verdict; detail = [string]$_.detail }
        }
    )
}
$dir = Split-Path $ResultPath -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
($out | ConvertTo-Json -Depth 8) | Set-Content -Path $ResultPath -Encoding UTF8

Write-Host "`nSUMMARY confirmed=$($confirmed.Count) cleared=$($cleared.Count) inconclusive=$($incon.Count) notes=$($notes.Count)"
Write-Host "Wrote $ResultPath"
if ($confirmed.Count) {
    Write-Host "CONFIRMED:"
    $confirmed | ForEach-Object { Write-Host "  - $($_.id): $($_.detail)" }
}
exit 0
