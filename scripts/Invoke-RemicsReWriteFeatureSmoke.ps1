#Requires -Version 5.1
<#
.SYNOPSIS
    RemIcsReWrite feature smoke: nav-visible ashx/views/wrap URLs + dual-drive validate.

.DESCRIPTION
    Logs in via RemIcsReWrite, loads the visible nav manifest from remics-nav-data.js,
    and exercises every active nav item (views, wrap popups, type-specific ashx).
    Hidden nav sections (Reports, FCC/ISED, Maintenance, etc.) are out of scope.

.PARAMETER BaseUrl
    Site root including /mics/ path.

.PARAMETER User
    MICS user (default rctl1).

.PARAMETER ValidateFixture
    Optional TS PDF for validate / pdf-edit / pdf-extra. Empty (default) = first
    file from files.ashx TS for this login (multi-company; do not assume bbimport2).

.PARAMETER SkipValidate
    Skip valFile dual-drive (faster smoke).

.PARAMETER Json
    Emit compressed JSON on stdout.

.PARAMETER ResultPath
    Atomic JSON result path for admin job polling.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost/mics/',
    [string]$User = 'rctl1',
    [string]$Password = '',
    [string]$ValidateFixture = '',
    [switch]$SkipValidate,
    [switch]$Json,
    [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$startedUtc = (Get-Date).ToUniversalTime().ToString('o')

. (Join-Path $PSScriptRoot 'Get-RemicsVisibleNavManifest.ps1')
$navManifest = Get-RemicsVisibleNavManifest

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

function Write-Result {
    param([hashtable]$Payload)
    $json = $Payload | ConvertTo-Json -Depth 8 -Compress
    if ($ResultPath) {
        $dir = Split-Path -Parent $ResultPath
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($ResultPath, $json)
    }
    if ($Json) { Write-Output $json }
    return $Payload
}

function Invoke-GetJson {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
        [string]$Url,
        [string]$Label
    )
    try {
        $r = Invoke-WebRequest -Uri $Url -WebSession $Session -UseBasicParsing -TimeoutSec 120
        $data = $null
        try { $data = $r.Content | ConvertFrom-Json } catch { $data = $null }
        $ok = ($r.StatusCode -eq 200)
        if ($data -and $null -ne $data.ok) { $ok = $ok -and [bool]$data.ok }
        return [pscustomobject]@{
            name = $Label
            ok = $ok
            status = $r.StatusCode
            detail = if ($data) { ($data | ConvertTo-Json -Compress) } else { $r.Content.Substring(0, [Math]::Min(120, $r.Content.Length)) }
        }
    }
    catch {
        return [pscustomobject]@{ name = $Label; ok = $false; status = 0; detail = $_.Exception.Message }
    }
}

function Invoke-PostForm {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
        [string]$Url,
        [hashtable]$Form,
        [string]$Label
    )
    try {
        $r = Invoke-WebRequest -Uri $Url -Method POST -Body $Form -WebSession $Session -UseBasicParsing -TimeoutSec 120
        $data = $null
        try { $data = $r.Content | ConvertFrom-Json } catch { $data = $null }
        $ok = ($r.StatusCode -eq 200)
        if ($data -and $null -ne $data.ok) { $ok = $ok -and [bool]$data.ok }
        return [pscustomobject]@{
            name = $Label
            ok = $ok
            status = $r.StatusCode
            detail = if ($data) { ($data | ConvertTo-Json -Compress) } else { $r.Content.Substring(0, [Math]::Min(120, $r.Content.Length)) }
        }
    }
    catch {
        return [pscustomobject]@{ name = $Label; ok = $false; status = 0; detail = $_.Exception.Message }
    }
}

function Invoke-PostJson {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
        [string]$Url,
        [string]$BodyJson,
        [string]$Label
    )
    try {
        $r = Invoke-WebRequest -Uri $Url -Method POST -WebSession $Session -UseBasicParsing -TimeoutSec 300 `
            -ContentType 'application/json; charset=utf-8' -Body $BodyJson
        $text = $r.Content
        $ok = $r.StatusCode -eq 200
        if ($text -match '^\s*\{' ) {
            $parsed = $text | ConvertFrom-Json
            if ($parsed.d) { $text = [string]$parsed.d }
        }
        if ($text -match '^OK|^FILENAME:|^1$|^true$' ) { $ok = $true }
        elseif ($text -match '^ERROR|^timeout' ) { $ok = $false }
        return [pscustomobject]@{
            name = $Label
            ok = $ok
            status = $r.StatusCode
            detail = $text.Substring(0, [Math]::Min(200, $text.Length))
        }
    }
    catch {
        return [pscustomobject]@{ name = $Label; ok = $false; status = 0; detail = $_.Exception.Message }
    }
}

function Invoke-GetPage {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
        [string]$Url,
        [string]$Label,
        [string]$TitlePattern = ''
    )
    try {
        $r = Invoke-WebRequest -Uri $Url -WebSession $Session -UseBasicParsing -TimeoutSec 120
        $ok = ($r.StatusCode -eq 200) -and ($r.Content.Length -gt 100)
        if ($TitlePattern -and $r.Content -notmatch $TitlePattern) { $ok = $false }
        return [pscustomobject]@{
            name = $Label
            ok = $ok
            status = $r.StatusCode
            detail = "len=$($r.Content.Length)"
        }
    }
    catch {
        return [pscustomobject]@{ name = $Label; ok = $false; status = 0; detail = $_.Exception.Message }
    }
}

if (-not $Password) { $Password = $env:MICS_TEST_PASSWORD }
if (-not $Password) { $Password = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
if (-not $Password) { $Password = 'x' }

$base = $BaseUrl.TrimEnd('/') + '/'
$rewrite = $base + 'RemIcsReWrite/'
$checks = @()

try {
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $loginUrl = $rewrite + 'login.aspx'
    Write-Host "POST $loginUrl"
    $null = Invoke-WebRequest -Uri $loginUrl -Method POST -Body @{ user = $User; password = $Password } `
        -WebSession $session -MaximumRedirection 10 -UseBasicParsing -TimeoutSec 120

    $sess = Invoke-GetJson -Session $session -Url ($rewrite + 'session.ashx') -Label 'session.ashx'
    $checks += $sess
    if (-not $sess.ok) { throw "session.ashx failed: $($sess.detail)" }

    $shell = Invoke-GetPage -Session $session -Url ($rewrite + 'shell.aspx') -Label 'shell.aspx' -TitlePattern 'remics-phase675'
    $checks += $shell

    $checks += Invoke-GetJson -Session $session -Url ($rewrite + 'projects.ashx') -Label 'projects.ashx'
    $tsFilesCheck = Invoke-GetJson -Session $session -Url ($rewrite + 'files.ashx?filetype=TS') -Label 'files.ashx TS'
    $checks += $tsFilesCheck
    $checks += Invoke-GetJson -Session $session -Url ($rewrite + 'files.ashx?filetype=ES') -Label 'files.ashx ES'

    # Pick a company-owned TS PDF for pdf/validate checks (Gate G — no rctl-only fixtures).
    $tsPdfName = $ValidateFixture
    if (-not $tsPdfName -and $tsFilesCheck.ok) {
        try {
            $tsData = $tsFilesCheck.detail | ConvertFrom-Json
            if ($tsData.ok -and $tsData.files -and $tsData.files.Count -gt 0) {
                $tsPdfName = [string]$tsData.files[0].name
            }
        } catch { }
    }
    if ($tsPdfName) {
        Write-Host ("Using TS PDF for smoke: $tsPdfName")
    } else {
        Write-Host 'WARN: no TS PDF available for pdf-extra / validate / pdf-edit'
    }
    $checks += Invoke-GetJson -Session $session -Url ($rewrite + 'tsip-status.ashx') -Label 'tsip-status.ashx'
    $checks += Invoke-GetJson -Session $session -Url ($rewrite + 'tsip-reps-meta.ashx') -Label 'tsip-reps-meta.ashx'
    $checks += Invoke-GetJson -Session $session -Url ($rewrite + 'tsip-reps-tree.ashx?mode=root') -Label 'tsip-reps-tree.ashx root'

    foreach ($t in $navManifest.sdfTypes) {
        $checks += Invoke-GetJson -Session $session -Url ($rewrite + "sdf-files.ashx?type=$t") -Label "sdf-files $t"
    }
    if (-not $navManifest.sdfTypes.Count) {
        $checks += Invoke-GetJson -Session $session -Url ($rewrite + 'sdf-files.ashx?type=Ante') -Label 'sdf-files Ante'
    }

    $checks += Invoke-PostForm -Session $session -Url ($rewrite + 'casedet.ashx') `
        -Form @{ action = 'list'; mode = 'TSES' } -Label 'casedet list TSES'
    $checks += Invoke-PostForm -Session $session -Url ($rewrite + 'casedet.ashx') `
        -Form @{ action = 'list'; mode = 'TSTS' } -Label 'casedet list TSTS'
    try {
        $cdList = Invoke-WebRequest -Uri ($rewrite + 'casedet.ashx') -Method POST `
            -Body @{ action = 'list'; mode = 'TSTS' } -WebSession $session -UseBasicParsing -TimeoutSec 60
        $cdData = $cdList.Content | ConvertFrom-Json
        if ($cdData.ok -and $cdData.runs -and $cdData.runs.Count -gt 0) {
            $run = $cdData.runs[0]
            $checks += Invoke-PostForm -Session $session -Url ($rewrite + 'casedet.ashx') `
                -Form @{ action = 'generate'; mode = 'TSTS'; kind = 'csv'; parm = $run.parm; run = $run.run } `
                -Label ('casedet generate TSTS ' + $run.parm + ' ' + $run.run)
        }
    }
    catch {
        $checks += [pscustomobject]@{ name = 'casedet generate TSTS'; ok = $false; status = 0; detail = $_.Exception.Message }
    }

    foreach ($t in $navManifest.dsSdfTypes) {
        $checks += Invoke-PostForm -Session $session -Url ($rewrite + 'ds-sdf.ashx') `
            -Form @{ action = 'search'; type = $t; q = 'A' } -Label "ds-sdf $t"
    }
    if (-not $navManifest.dsSdfTypes.Count) {
        $checks += Invoke-PostForm -Session $session -Url ($rewrite + 'ds-sdf.ashx') `
            -Form @{ action = 'search'; type = 'Ante'; q = 'A' } -Label 'ds-sdf Ante'
    }

    if ($navManifest.views -contains 'ds-ts') {
        $checks += Invoke-PostForm -Session $session -Url ($rewrite + 'ds-search.ashx') `
            -Form @{ action = 'searchTs'; call1 = 'A*' } -Label 'ds-search TS'
    }
    if ($navManifest.views -contains 'ds-es') {
        $checks += Invoke-PostForm -Session $session -Url ($rewrite + 'ds-search.ashx') `
            -Form @{ action = 'searchEs'; call1 = 'A*' } -Label 'ds-search ES'
    }
    if ($tsPdfName) {
        $checks += Invoke-PostForm -Session $session -Url ($rewrite + 'pdf-extra.ashx') `
            -Form @{ action = 'chnglist'; name = $tsPdfName; filetype = 'TS' } -Label 'pdf-extra chnglist'
    } else {
        $checks += [pscustomobject]@{ name = 'pdf-extra chnglist'; ok = $false; status = 0; detail = 'no TS PDF for this user' }
    }
    $checks += Invoke-PostForm -Session $session -Url ($rewrite + 'password.ashx') `
        -Form @{ action = 'change'; oldPassword = 'wrong'; newPassword = 'NewPass1!' } -Label 'password bad-old'
    # Negative test: expect badold, not ok=true
    $pwdIdx = $checks.Count - 1
    if ($checks[$pwdIdx].detail -match 'badold') {
        $checks[$pwdIdx] = [pscustomobject]@{
            name = 'password bad-old'
            ok = $true
            status = 200
            detail = 'expected badold rejection'
        }
    }

    # Shell views for every unique active nav view (except tsip-post popups)
    if ($navManifest.views -notcontains 'welcome') {
        $navManifest.views = @('welcome') + @($navManifest.views)
    }
    foreach ($v in $navManifest.views) {
        $checks += Invoke-GetPage -Session $session -Url ($rewrite + "views/$v.html") -Label "view $v"
    }

    # Classic wrap pages for tsip-post and aux-eng nav items
    foreach ($w in $navManifest.wrapChecks) {
        $checks += Invoke-GetPage -Session $session -Url ($base + $w.path) -Label ('wrap ' + $w.label)
    }

    $checks += Invoke-GetPage -Session $session -Url ($rewrite + 'pwd-reset.aspx?id=' + [uri]::EscapeDataString($User)) `
        -Label 'pwd-reset anonymous page'

    $sessObj = $null
    try { $sessObj = $sess.detail | ConvertFrom-Json } catch { }
    $userDir = if ($sessObj -and $sessObj.user_dir) {
        [string]$sessObj.user_dir
    } else {
        $schemaGuess = if ($User -match '^([a-zA-Z]+)\d*$') { $Matches[1].ToLowerInvariant() } else { 'unknown' }
        "D:\inetpub\remicsdev\mics\userdirs\$schemaGuess\$User"
    }

    # Dual-drive: valFile on a company-owned TS PDF
    if (-not $SkipValidate -and $tsPdfName) {
        $asmxBase = $base + 'Tfileactions/TwsTabUtil.asmx/'
        $projectCode = $User + '_0'

        $valBody = (@{
            filename = $tsPdfName
            filetype = 'TS'
            projectCode = $projectCode
            hilorep = '0'
            verbose = '0'
        } | ConvertTo-Json -Compress)
        $val = Invoke-PostJson -Session $session -Url ($asmxBase + 'valFile') `
            -BodyJson $valBody -Label "dual-drive valFile $tsPdfName"
        $checks += $val

        $reportPath = Join-Path $userDir ($tsPdfName + '.txt')
        $reportOk = Test-Path $reportPath
        $reportLen = if ($reportOk) { (Get-Item $reportPath).Length } else { 0 }
        $checks += [pscustomobject]@{
            name = "validate report file $tsPdfName"
            ok = ($val.ok -and $reportOk -and ($reportLen -gt 0))
            status = if ($reportOk) { 200 } else { 404 }
            detail = "path=$reportPath len=$reportLen val=$($val.detail)"
        }
    }

    # pdf-edit title get (non-mutating)
    if ($tsPdfName) {
        $checks += Invoke-PostForm -Session $session -Url ($rewrite + 'pdf-edit.ashx') `
            -Form @{ action = 'titleget'; name = $tsPdfName; filetype = 'TS' } -Label 'pdf-edit titleget'
    } else {
        $checks += [pscustomobject]@{ name = 'pdf-edit titleget'; ok = $false; status = 0; detail = 'no TS PDF for this user' }
    }

    $failed = @($checks | Where-Object { -not $_.ok })
    $passed = @($checks | Where-Object { $_.ok }).Count
    Write-Host ("Nav scope: {0} visible entries, {1} active, {2} wrap checks" -f `
        $navManifest.totalEntries, $navManifest.activeEntries, $navManifest.wrapChecks.Count)
    $payload = @{
        ok = ($failed.Count -eq 0)
        status = 'complete'
        op = 'rewrite-feature-smoke'
        mics_user = $User
        started_utc = $startedUtc
        finished_utc = (Get-Date).ToUniversalTime().ToString('o')
        passed = $passed
        failed = $failed.Count
        total = $checks.Count
        match = ($failed.Count -eq 0)
        nav_visible = @{
            total = $navManifest.totalEntries
            active = $navManifest.activeEntries
            disabled_visible = $navManifest.disabledVisible
            views = @($navManifest.views)
            wrap_count = $navManifest.wrapChecks.Count
        }
        summary = ($checks | ForEach-Object {
            ($_.name + ': ' + $(if ($_.ok) { 'PASS' } else { 'FAIL' }) + ' (' + $_.detail + ')')
        }) -join "`n"
        checks = @($checks | ForEach-Object {
            @{ name = $_.name; ok = $_.ok; status = $_.status; detail = $_.detail }
        })
    }

    Write-Result -Payload $payload | Out-Null

    foreach ($c in $checks) {
        $mark = if ($c.ok) { 'PASS' } else { 'FAIL' }
        Write-Host ("{0} {1} - {2}" -f $mark, $c.name, $c.detail)
    }

    if ($failed.Count -gt 0) {
        Write-Error ("RemIcsReWrite feature smoke FAILED: {0}/{1}" -f $failed.Count, $checks.Count)
    }
    Write-Host ("PASS: RemIcsReWrite feature smoke {0}/{1}" -f $passed, $checks.Count)
}
catch {
    $errPayload = @{
        ok = $false
        status = 'complete'
        op = 'rewrite-feature-smoke'
        mics_user = $User
        started_utc = $startedUtc
        finished_utc = (Get-Date).ToUniversalTime().ToString('o')
        match = $false
        error = $_.Exception.Message
        checks = @($checks | ForEach-Object {
            @{ name = $_.name; ok = $_.ok; status = $_.status; detail = $_.detail }
        })
    }
    Write-Result -Payload $errPayload | Out-Null
    Write-Error $_.Exception.Message
}
