#Requires -Version 5.1
<#
.SYNOPSIS
    Gate C: end-to-end TSIP run safety path per schema in the test roster.

.DESCRIPTION
    For each MICS user: create parm -> verify empty -> add run -> validateAll ->
    get run -> delete run -> cleanup. Also rejects foreign PDF on save.

.PARAMETER Users
    Roster logins (default: bchy1, rctl1, xci1 — minimum multi-company set).

.PARAMETER ForeignPdf
    PDF from another operator for negative save test.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.cloudmicsdev.ca/mics/',
    [string[]]$Users = @('bchy1', 'rctl1', 'xci1'),
    [string]$Password = '',
    [string]$ForeignPdf = '1c0139c2444',
    [string]$ParmName = 'gatece2',
    [string]$RunName = 'g1'
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
$validPdfFlags = @('U', 'T', 'S', 'K', 'M', 'L')

function Get-AsmxString {
    param([object]$Resp)
    if ($Resp.Content -match '"d"\s*:\s*"([^"]*)"') { return $Matches[1] }
    return $Resp.Content.Trim()
}

function Invoke-MicsSession {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,
        [string]$User
    )
    $loginUrl = $base + 'RemIcsReWrite/login.aspx'
    $null = Invoke-WebRequest -Uri $loginUrl -Method POST -Body @{ user = $User; password = $Password } `
        -WebSession $WebSession -MaximumRedirection 10 -UseBasicParsing
    $sess = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/session.ashx') -WebSession $WebSession -UseBasicParsing
    $json = $sess.Content | ConvertFrom-Json
    if (-not $json.ok) { throw "Login failed for $User" }
    return $json
}

function Invoke-TabUtilAsmx {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,
        [string]$Method,
        [hashtable]$Params
    )
    $url = $base + 'Tfileactions/TwsTabUtil.asmx/' + $Method
    $payload = $Params | ConvertTo-Json -Compress
    $resp = Invoke-WebRequest -Uri $url -Method POST -Body $payload `
        -ContentType 'application/json; charset=utf-8' -WebSession $WebSession -UseBasicParsing
    $body = Get-AsmxString $resp
    $ok = $resp.StatusCode -eq 200 -and $body -notmatch '^(timeout|ERRORSYS:|ERROR)'
    return [pscustomobject]@{ ok = $ok; body = $body; status = $resp.StatusCode }
}

function Invoke-TsipAsmx {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,
        [string]$Service,
        [string]$Method,
        [hashtable]$Params
    )
    $url = $base + $Service + '/' + $Method
    $payload = $Params | ConvertTo-Json -Compress
    $resp = Invoke-WebRequest -Uri $url -Method POST -Body $payload `
        -ContentType 'application/json; charset=utf-8' -WebSession $WebSession -UseBasicParsing
    $body = Get-AsmxString $resp
    $ok = $resp.StatusCode -eq 200 -and $body -notmatch '^(timeout|ERRORSYS:)'
    return [pscustomobject]@{ ok = $ok; body = $body; status = $resp.StatusCode }
}

function Invoke-TsipValidate {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,
        [string]$Type,
        [string]$PdfName
    )
    $r = Invoke-TsipAsmx -WebSession $WebSession -Service 'Ttsipmenu/TwsTsip.asmx' -Method 'tsipValidate' `
        -Params @{ type = $Type; pdfname = $PdfName }
    return $r.body
}

function Invoke-FilesJson {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,
        [string]$FileType,
        [string]$Name = ''
    )
    $url = $base + 'RemIcsReWrite/files.ashx?filetype=' + [uri]::EscapeDataString($FileType)
    if ($Name) { $url += '&name=' + [uri]::EscapeDataString($Name) }
    $resp = Invoke-WebRequest -Uri $url -WebSession $WebSession -UseBasicParsing
    return $resp.Content | ConvertFrom-Json
}

function Find-OwnTsPdf {
    param([Microsoft.PowerShell.Commands.WebRequestSession]$WebSession)
    $candidates = @('testts1', 'testts2', 'testts3', 'cat', 'bbimport2')
    foreach ($name in $candidates) {
        $valid = Invoke-TsipValidate -WebSession $WebSession -Type 'ft_' -PdfName $name
        if ($validPdfFlags -contains $valid) { return $name }
    }
    $list = Invoke-FilesJson -WebSession $WebSession -FileType 'TS'
    if (-not $list.ok) { return $null }
    foreach ($f in @($list.files)) {
        $name = [string]$f.name
        if (-not $name) { continue }
        $valid = Invoke-TsipValidate -WebSession $WebSession -Type 'ft_' -PdfName $name
        if ($validPdfFlags -contains $valid) { return $name }
    }
    return $null
}

function Test-RunListEmpty {
    param([string]$Body)
    $text = [string]$Body
    if (-not $text) { return $true }
    if ($text -eq 'NONE') { return $true }
    if ($text -match '^\s*$') { return $true }
    return $false
}

function Test-RunListHasRun {
    param([string]$Body, [string]$Run)
    $text = [string]$Body
    if (-not $text -or $text -eq 'NONE') { return $false }
    # Classic runList returns dotted tokens like d.gatece2.g1.MDB_TS
    if ($text -match ('\.{0}(\.|$)' -f [regex]::Escape($Run))) { return $true }
    $parts = @($text -split '[.,\s\^]+' | Where-Object { $_ -eq $Run })
    return $parts.Count -gt 0
}

function Invoke-TsipRunAshx {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,
        [string]$Action,
        [hashtable]$Query,
        [hashtable]$Fields = @{}
    )
    $q = 'action=' + [uri]::EscapeDataString($Action)
    foreach ($k in $Query.Keys) {
        $q += '&' + [uri]::EscapeDataString($k) + '=' + [uri]::EscapeDataString([string]$Query[$k])
    }
    $url = $base + 'RemIcsReWrite/tsip-run.ashx?' + $q
    if ($Fields.Count -gt 0) {
        $resp = Invoke-WebRequest -Uri $url -Method POST -Body $Fields -WebSession $WebSession -UseBasicParsing
    } else {
        $resp = Invoke-WebRequest -Uri $url -Method GET -WebSession $WebSession -UseBasicParsing
    }
    return $resp.Content | ConvertFrom-Json
}

function Invoke-UserGateC {
    param([string]$User)

    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $sess = Invoke-MicsSession -WebSession $session -User $User
    $schema = [string]$sess.schema
    $project = $User + '_0'
    $failures = @()

    Write-Host "=== Gate C E2E user=$User schema=$schema ==="

    $ownPdf = Find-OwnTsPdf -WebSession $session
    if (-not $ownPdf) {
        return @("No valid TS PDF found for $User ($schema)")
    }
    Write-Host "Using TS PDF: $ownPdf"

    # Cleanup from prior failed run
    $null = Invoke-TabUtilAsmx -WebSession $session -Method 'killTable' -Params @{
        filename = $ParmName; filetype = 'TsipParm'; projectCode = $project
    }

    $create = Invoke-TabUtilAsmx -WebSession $session -Method 'createTable' -Params @{
        filename = $ParmName; filetype = 'TsipParm'; projectCode = $project
    }
    if (-not $create.ok) {
        $failures += "createTable $ParmName failed: $($create.body)"
        return $failures
    }
    Write-Host "OK createTable $ParmName"

    $parms = Invoke-FilesJson -WebSession $session -FileType 'TsipParm'
    if (-not $parms.ok) {
        $failures += 'files.ashx TsipParm list failed'
    } else {
        $entry = @($parms.files | Where-Object { $_.name -eq $ParmName })[0]
        if (-not $entry) {
            $failures += "parm $ParmName missing from files.ashx list"
        } elseif ([int]$entry.runCount -ne 0) {
            $failures += "new parm $ParmName should have runCount=0, got $($entry.runCount)"
        } else {
            Write-Host "OK empty parm runCount=0"
        }
    }

    $runListEmpty = Invoke-TsipAsmx -WebSession $session -Service 'Ttsipmenu/TwsTsipTree.asmx' -Method 'runList' `
        -Params @{ parameter = $ParmName }
    if (-not $runListEmpty.ok) {
        $failures += "runList failed: $($runListEmpty.body)"
    } elseif (-not (Test-RunListEmpty $runListEmpty.body)) {
        $failures += "runList should be empty for new parm, got '$($runListEmpty.body)'"
    } else {
        Write-Host 'OK runList empty'
    }

    $saveForeign = Invoke-TsipRunAshx -WebSession $session -Action 'new' -Query @{ parm = $ParmName } -Fields @{
        runname = $RunName; protype = 'T'; envtype = 'MDB_TS'; proname = $ForeignPdf
        envname = ''; tsorbout = 'N'; spherecalc = '5'; fsep = '300'; coordist = '200'
        analopt = 'CHAN'; margin = '0'; chancodes = '0,1,2,3,4,5,6,7,8,9'; numchan = '10'
        country = 'ALL'; selsites = 'ALL'; numcodes = '0'; codes = ''; reports = '0'
    }
    if ($saveForeign.ok -eq $true) {
        $failures += 'tsip-run save should reject foreign PDF'
    } else {
        Write-Host "OK foreign PDF save rejected: $($saveForeign.error)"
    }

    $fields = @{
        runname = $RunName; protype = 'T'; envtype = 'MDB_TS'; proname = $ownPdf
        envname = ''; tsorbout = 'N'; spherecalc = '5'; fsep = '300'; coordist = '200'
        analopt = 'CHAN'; margin = '0'; chancodes = '0,1,2,3,4,5,6,7,8,9'; numchan = '10'
        country = 'ALL'; selsites = 'ALL'; numcodes = '0'; codes = ''; reports = '0'
    }
    $saveOwn = Invoke-TsipRunAshx -WebSession $session -Action 'new' -Query @{ parm = $ParmName } -Fields $fields
    if ($saveOwn.ok -ne $true) {
        $failures += "tsip-run new failed: $($saveOwn.error)"
        return $failures
    }
    Write-Host "OK tsip-run new run $RunName"

    $parms2 = Invoke-FilesJson -WebSession $session -FileType 'TsipParm'
    $entry2 = @($parms2.files | Where-Object { $_.name -eq $ParmName })[0]
    if (-not $entry2 -or [int]$entry2.runCount -lt 1) {
        $failures += "files.ashx runCount should be >= 1 after save"
    } else {
        Write-Host "OK runCount=$($entry2.runCount)"
    }

    $runList = Invoke-TsipAsmx -WebSession $session -Service 'Ttsipmenu/TwsTsipTree.asmx' -Method 'runList' `
        -Params @{ parameter = $ParmName }
    if (-not (Test-RunListHasRun $runList.body $RunName)) {
        $failures += "runList missing $RunName after save (body='$($runList.body)')"
    } else {
        Write-Host 'OK runList has run'
    }

    $validateAll = Invoke-TsipAsmx -WebSession $session -Service 'Ttsipmenu/TwsTsip.asmx' -Method 'tsipValidateAll' `
        -Params @{ tsipparmname = $ParmName }
    if (-not $validateAll.ok) {
        $failures += "tsipValidateAll failed: $($validateAll.body)"
    } elseif ([string]$validateAll.body) {
        $failures += "tsipValidateAll should be empty when ready, got '$($validateAll.body)'"
    } else {
        Write-Host 'OK tsipValidateAll ready'
    }

    $got = Invoke-TsipRunAshx -WebSession $session -Action 'get' -Query @{ parm = $ParmName; runname = $RunName }
    if ($got.ok -ne $true) {
        $failures += "tsip-run get failed: $($got.error)"
    } elseif ([string]$got.record.proname -ne $ownPdf) {
        $failures += "tsip-run get proname mismatch: $($got.record.proname) vs $ownPdf"
    } else {
        Write-Host 'OK tsip-run get'
    }

    $del = Invoke-TsipRunAshx -WebSession $session -Action 'delete' -Query @{ parm = $ParmName; runname = $RunName }
    if ($del.ok -ne $true) {
        $failures += "tsip-run delete failed: $($del.error)"
    } else {
        Write-Host 'OK tsip-run delete'
    }

    $runListAfter = Invoke-TsipAsmx -WebSession $session -Service 'Ttsipmenu/TwsTsipTree.asmx' -Method 'runList' `
        -Params @{ parameter = $ParmName }
    if (-not (Test-RunListEmpty $runListAfter.body)) {
        $failures += "runList should be empty after delete, got '$($runListAfter.body)'"
    } else {
        Write-Host 'OK runList empty after delete'
    }

    $kill = Invoke-TabUtilAsmx -WebSession $session -Method 'killTable' -Params @{
        filename = $ParmName; filetype = 'TsipParm'; projectCode = $project
    }
    if (-not $kill.ok) {
        $failures += "killTable cleanup failed: $($kill.body)"
    } else {
        Write-Host "OK killTable cleanup $ParmName"
    }

    return $failures
}

$allFailures = @()
foreach ($user in $Users) {
    try {
        $userFails = @(Invoke-UserGateC -User $user)
        if ($userFails.Count -gt 0) {
            foreach ($f in $userFails) { $allFailures += "$user : $f" }
        } else {
            Write-Host "PASS Gate C E2E for $user"
        }
    } catch {
        $allFailures += "$user : $($_.Exception.Message)"
    }
}

if ($allFailures.Count -gt 0) {
    Write-Host 'FAIL Gate C TSIP E2E:'
    $allFailures | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

Write-Host ("PASS Gate C TSIP E2E ({0} users: {1})" -f $Users.Count, ($Users -join ', '))
