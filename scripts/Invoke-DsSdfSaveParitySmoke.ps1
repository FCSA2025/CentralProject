#Requires -Version 5.1
<#
.SYNOPSIS
  Runtime DS-SDF save parity smoke: search → classic key → createTable → Insert(+Insert2) → AppendDup verify → killTable.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.CLOUDMICSDEV.ca/mics/',
    [string]$User = 'rctl1',
    [string]$Password = '',
    [string]$ResultPath = 'E:\AIProjects\CentralProject\tmp-tsjob\ds-sdf-save-smoke.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = 'E:\AIProjects\CentralProject'
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

function Count-Of {
    param($Value)
    # Empty pipeline is $null; @($null).Count is 1 — never wrap bare $null.
    if ($null -eq $Value) { return 0 }
    return @($Value).Count
}

if (-not $Password) { $Password = $env:MICS_TEST_PASSWORD }
if (-not $Password) { $Password = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
if (-not $Password) { $Password = 'x' }

# Search uses first key column with '*' so TOP 500 always has candidates.
$SdfSave = [ordered]@{
    Ante = @{ insert='InsertAnte'; insert2='InsertAntd'; filterCol='acode';    filterVal='*' }
    Band = @{ insert='InsertBand'; insert2=$null;      filterCol='bndcde';   filterVal='*' }
    Ctx  = @{ insert='InsertCtx';  insert2='InsertCtxd'; filterCol='tfci';    filterVal='*' }
    Eqpt = @{ insert='InsertEqpt'; insert2=$null;      filterCol='ecode';    filterVal='*' }
    Oper = @{ insert='InsertOper'; insert2=$null;      filterCol='oper';     filterVal='*' }
    Plan = @{ insert='InsertPlan'; insert2='InsertPlnd'; filterCol='sband';   filterVal='*' }
    Rout = @{ insert='InsertRout'; insert2=$null;      filterCol='rcomp';   filterVal='*' }
    Note = @{ insert='InsertNote'; insert2=$null;      filterCol='oper';     filterVal='*' }
    Towr = @{ insert='InsertTowr'; insert2=$null;      filterCol='twcode';   filterVal='*' }
    Town = @{ insert='InsertTown'; insert2=$null;      filterCol='call1';   filterVal='*' }
    Traf = @{ insert='InsertTraf'; insert2=$null;      filterCol='trafcode'; filterVal='*' }
}

function Invoke-Asmx {
    param($Session, [string]$Url, [hashtable]$Body)
    $json = $Body | ConvertTo-Json -Compress
    $r = Invoke-WebRequest -Uri $Url -Method POST -WebSession $Session -UseBasicParsing -TimeoutSec 180 `
        -ContentType 'application/json; charset=utf-8' -Body $json
    $text = $r.Content
    if ($text -match '^\s*\{') {
        $parsed = $text | ConvertFrom-Json
        if ($null -ne $parsed.PSObject.Properties['d']) { $text = [string]$parsed.d }
    }
    return $text
}

$base = $BaseUrl.TrimEnd('/') + '/'
$rewrite = $base + 'RemIcsReWrite/'
$asmx = $base + 'Tdssdf/TwsdsSDF.asmx/'

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
Write-Host "Login $rewrite"
$null = Invoke-WebRequest -Uri ($rewrite + 'login.aspx') -Method POST -Body @{ user = $User; password = $Password } `
    -WebSession $session -MaximumRedirection 10 -UseBasicParsing -TimeoutSec 120
$sess = (Invoke-WebRequest -Uri ($rewrite + 'session.ashx') -WebSession $session -UseBasicParsing).Content | ConvertFrom-Json
if (-not $sess.ok) { throw "session failed" }
$schema = [string]$sess.schema
$pc = [string]$sess.project
Write-Host "schema=$schema project=$pc"

$stamp = Get-Date -Format 'HHmmss'
$results = @()

foreach ($type in @($SdfSave.Keys)) {
    $cfg = $SdfSave[$type]
    $name = ('z' + $type.ToLower().Substring(0, [Math]::Min(3, $type.Length)) + $stamp)
    if ($name.Length -gt 16) { $name = $name.Substring(0, 16) }

    $row = [ordered]@{
        type = $type; sdf = $name; ok = $false; key = $null; keyParts = $null
        parentVerified = $false; detailOk = $null; insertBody = $null; insert2Body = $null; error = $null
    }
    try {
        $form = @{ action = 'search'; type = $type }
        $form[$cfg.filterCol] = $cfg.filterVal
        $search = (Invoke-WebRequest -Uri ($rewrite + 'ds-sdf.ashx') -Method POST -Body $form `
            -WebSession $session -UseBasicParsing -TimeoutSec 120).Content | ConvertFrom-Json
        if (-not $search.ok) { throw "search failed: $($search.error)" }
        $rows = @($search.rows)
        if ((Count-Of $rows) -lt 1) { throw 'search returned 0 rows' }
        $parts = @($search.keyParts)
        if ((Count-Of $parts) -lt 1) { throw 'missing keyParts' }
        $row.keyParts = ($parts -join ':')
        $first = $rows[0]
        $keyVals = foreach ($p in $parts) { [string]$first.$p }
        $key = ($keyVals -join ':')
        $row.key = $key
        if ([string]::IsNullOrWhiteSpace(($keyVals -join ''))) { throw "empty key parts=$($row.keyParts)" }

        $createText = Invoke-Asmx -Session $session -Url ($base + 'Tfileactions/TwsTabUtil.asmx/createTable') -Body @{
            filename = $name; filetype = $type; projectCode = $pc
        }
        if ($createText -match '^(ERROR|timeout)') { throw "createTable: $createText" }

        $insBody = Invoke-Asmx -Session $session -Url ($asmx + $cfg.insert) -Body @{ name = $name; keylist = $key }
        $row.insertBody = $insBody
        if ($insBody -match '^ERROR') { throw "insert: $insBody" }

        if ($cfg.insert2) {
            $ins2Body = Invoke-Asmx -Session $session -Url ($asmx + $cfg.insert2) -Body @{ name = $name; keylist = $key }
            $row.insert2Body = $ins2Body
            if ($ins2Body -match '^ERROR') { throw "insert2: $ins2Body" }
            $row.detailOk = $true
        } else {
            $row.detailOk = $null
        }

        $dupMethod = 'AppendDup' + $type
        $dup = Invoke-Asmx -Session $session -Url ($asmx + $dupMethod) -Body @{ name = $name; keylist = $key }
        if ($dup -match '^ERROR') { throw "AppendDup: $dup" }
        $dupList = @(($dup -split ',') | Where-Object { $_ -ne '' })
        $parentOk = $false
        if ((Count-Of $dupList) -gt 0) {
            if ($dupList -contains $key) { $parentOk = $true }
            elseif ((Count-Of $parts) -eq 1 -and ($dupList -contains $keyVals[0])) { $parentOk = $true }
            elseif ($dup -eq $key) { $parentOk = $true }
        }
        $row.parentVerified = $parentOk
        if (-not $parentOk) { throw "parent not in AppendDup body='$dup' key='$key'" }

        $row.ok = $true
    }
    catch {
        $row.error = $_.Exception.Message
        $row.ok = $false
    }
    finally {
        try {
            $null = Invoke-Asmx -Session $session -Url ($base + 'Tfileactions/TwsTabUtil.asmx/killTable') -Body @{
                filename = $name; filetype = $type; projectCode = $pc
            }
        } catch { }
    }
    $results += [pscustomobject]$row
    $flag = if ($row.ok) { 'PASS' } else { 'FAIL' }
    Write-Host ("{0} {1} key={2} parts={3} err={4}" -f $flag, $type, $row.key, $row.keyParts, $row.error)
}

$pass = @($results | Where-Object { $_.ok }).Count
$fail = @($results | Where-Object { -not $_.ok }).Count
$summary = [ordered]@{ ok = ($fail -eq 0); pass = $pass; fail = $fail; schema = $schema; base = $base; rows = $results }
[System.IO.File]::WriteAllText($ResultPath, ($summary | ConvertTo-Json -Depth 6))
Write-Host ("SUMMARY pass={0} fail={1} -> {2}" -f $pass, $fail, $ResultPath)
if ($fail -gt 0) { exit 1 }
