#Requires -Version 5.1
<#
.SYNOPSIS
    Gate C (post-run): TSIP reports tree + parm edit load/save per roster user.

.DESCRIPTION
    Complements Invoke-GateCTsipE2ETest.ps1. Catches compile/runtime breaks on
    tsip-reps-*.ashx and edit-run save after archive matching (UserDirUtil lesson).
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.cloudmicsdev.ca/mics/',
    [string[]]$Users = @('bchy1', 'rctl1', 'xci1'),
    [string]$Password = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$repoRoot = 'E:\AIProjects\CentralProject'
$envFile = Join-Path $repoRoot '.env.local'
if (-not $Password) { $Password = $env:MICS_TEST_PASSWORD }
if (-not $Password -and (Test-Path $envFile)) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*MICS_TEST_PASSWORD\s*=\s*(.+)$') {
            $Password = $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
}
if (-not $Password) { $Password = 'x' }

$base = $BaseUrl.TrimEnd('/') + '/'
$failures = New-Object System.Collections.Generic.List[string]

function Get-Http {
    param(
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,
        [string]$Uri,
        [string]$Method = 'GET',
        [object]$Body,
        [string]$ContentType
    )
    try {
        $params = @{
            Uri = $Uri
            Method = $Method
            WebSession = $WebSession
            UseBasicParsing = $true
        }
        if ($PSBoundParameters.ContainsKey('Body')) {
            $params.Body = $Body
            if ($ContentType) { $params.ContentType = $ContentType }
        }
        $resp = Invoke-WebRequest @params
        return @{ Ok = $true; Status = [int]$resp.StatusCode; Body = $resp.Content }
    } catch {
        $status = 0
        $text = $_.Exception.Message
        $resp = $_.Exception.Response
        if ($resp) {
            $status = [int]$resp.StatusCode
            try {
                $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
                $text = $sr.ReadToEnd()
            } catch {}
        }
        return @{ Ok = $false; Status = $status; Body = $text }
    }
}

function Login-User {
    param([string]$User)
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $null = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/login.aspx') -Method POST `
        -Body @{ user = $User; password = $Password } -WebSession $session -MaximumRedirection 10 -UseBasicParsing
    $sess = Get-Http -WebSession $session -Uri ($base + 'RemIcsReWrite/session.ashx')
    $json = $null
    try { $json = $sess.Body | ConvertFrom-Json } catch {}
    if (-not $json -or -not $json.ok) {
        throw ('Login failed for ' + $User + ': ' + $sess.Body)
    }
    return @{ Session = $session; Schema = $json.schema; User = $json.user }
}

function Pick-ParmRun {
    param($Ctx)
    $list = Get-Http -WebSession $Ctx.Session -Uri ($base + 'RemIcsReWrite/files.ashx?filetype=TsipParm')
    if (-not $list.Ok) { return $null }
    $data = $list.Body | ConvertFrom-Json
    if (-not $data.ok -or -not $data.files) { return $null }
    $usable = @($data.files | Where-Object { $_.usable -ne $false -and $_.runCount -gt 0 })
    if ($usable.Count -eq 0) { return $null }

    foreach ($cand in $usable) {
        $parm = $cand.name
        $rl = Get-Http -WebSession $Ctx.Session -Uri ($base + 'Ttsipmenu/TwsTsipTree.asmx/runList') `
            -Method POST -Body (@{ parameter = $parm } | ConvertTo-Json) -ContentType 'application/json; charset=utf-8'
        if (-not $rl.Ok) { continue }
        $d = ($rl.Body | ConvertFrom-Json).d
        if (-not $d -or $d -eq 'NONE' -or $d -like 'ERROR*') { continue }
        $first = ($d -split ':')[0]
        $parts = $first -split '\.'
        if ($parts.Length -lt 3) { continue }
        $run = $parts[2]
        $getUri = $base + 'RemIcsReWrite/tsip-run.ashx?action=get&parm=' +
            [uri]::EscapeDataString($parm) + '&runname=' + [uri]::EscapeDataString($run)
        $get = Get-Http -WebSession $Ctx.Session -Uri $getUri
        if (-not $get.Ok) { continue }
        $gj = $get.Body | ConvertFrom-Json
        if (-not $gj.ok) { continue }
        $protype = ([string]$gj.record.protype).ToUpperInvariant()
        $proname = [string]$gj.record.proname
        $ft = if ($protype -eq 'E') { 'ES' } else { 'TS' }
        $exists = Get-Http -WebSession $Ctx.Session -Uri (
            $base + 'RemIcsReWrite/files.ashx?filetype=' + $ft + '&name=' + [uri]::EscapeDataString($proname)
        )
        if (-not $exists.Ok) { continue }
        $ej = $exists.Body | ConvertFrom-Json
        # Prefer a run whose proposed PDF actually exists for this company (avoids dirty self-named parms).
        if ($ej.ok -and ($ej.exists -eq $true -or $ej.catalogExists -eq $true)) {
            return @{
                Parm = $parm
                Run = $run
                RunList = $d
                Get = $gj
                Proname = $proname
            }
        }
    }
    return $null
}

foreach ($user in $Users) {
    Write-Host ''
    Write-Host ('======== ' + $user + ' ========')
    try {
        $ctx = Login-User -User $user
        Write-Host ('schema=' + $ctx.Schema + ' sessionUser=' + $ctx.User)

        $root = Get-Http -WebSession $ctx.Session -Uri ($base + 'RemIcsReWrite/tsip-reps-tree.ashx')
        if (-not $root.Ok) {
            [void]$failures.Add($user + ' reps-root HTTP ' + $root.Status + ': ' + $root.Body)
            Write-Host 'FAIL reps-root'
            Write-Host $root.Body
            continue
        }
        $rootJson = $root.Body | ConvertFrom-Json
        if (-not $rootJson.ok) {
            [void]$failures.Add($user + ' reps-root ok=false: ' + $root.Body)
            Write-Host 'FAIL reps-root body'
            continue
        }
        $parmCount = @($rootJson.parms).Count
        Write-Host ('OK reps-root parms=' + $parmCount)

        if ($parmCount -eq 0) {
            Write-Host 'WARN reps-root empty (no disk/archive reports for this user yet)'
        } else {
            foreach ($p in @($rootJson.parms)) {
                $pname = $p.parm
                $expUri = $base + 'RemIcsReWrite/tsip-reps-tree.ashx?mode=parm&parm=' + [uri]::EscapeDataString($pname)
                $exp = Get-Http -WebSession $ctx.Session -Uri $expUri
                if (-not $exp.Ok) {
                    [void]$failures.Add($user + ' reps-parm ' + $pname + ' HTTP ' + $exp.Status + ': ' + $exp.Body)
                    Write-Host ('FAIL reps-parm ' + $pname)
                    Write-Host $exp.Body
                    continue
                }
                $expJson = $exp.Body | ConvertFrom-Json
                if (-not $expJson.ok) {
                    [void]$failures.Add($user + ' reps-parm ' + $pname + ' ok=false: ' + $exp.Body)
                    Write-Host ('FAIL reps-parm body ' + $pname)
                    continue
                }
                $runCount = @($expJson.runs).Count
                Write-Host ('OK reps-parm ' + $pname + ' runs=' + $runCount + ' disk=' + $p.disk + ' archive=' + $p.archive)

                if ($runCount -gt 0 -and @($expJson.runs[0].files).Count -gt 0) {
                    $run = $expJson.runs[0].run
                    $ft = $expJson.runs[0].files[0].type
                    $openBody = @{ parm = $pname; run = $run; fileType = $ft } | ConvertTo-Json
                    $open = Get-Http -WebSession $ctx.Session -Uri ($base + 'RemIcsReWrite/tsip-reps-open.ashx') `
                        -Method POST -Body $openBody -ContentType 'application/json; charset=utf-8'
                    if (-not $open.Ok) {
                        [void]$failures.Add($user + ' reps-open ' + $pname + '/' + $run + '/' + $ft + ' HTTP ' + $open.Status)
                        Write-Host ('FAIL reps-open ' + $pname + '/' + $run + '/' + $ft)
                    } else {
                        $oj = $open.Body | ConvertFrom-Json
                        if (-not $oj.ok) {
                            [void]$failures.Add($user + ' reps-open ' + $pname + '/' + $run + '/' + $ft + ': ' + $open.Body)
                            Write-Host 'FAIL reps-open body'
                        } else {
                            Write-Host ('OK reps-open ' + $pname + '/' + $run + '/' + $ft + ' source=' + $oj.source)
                        }
                    }
                }
            }
        }

        $meta = Get-Http -WebSession $ctx.Session -Uri ($base + 'RemIcsReWrite/tsip-reps-meta.ashx')
        if (-not $meta.Ok) {
            [void]$failures.Add($user + ' reps-meta HTTP ' + $meta.Status + ': ' + $meta.Body)
            Write-Host 'FAIL reps-meta'
        } else {
            $mj = $meta.Body | ConvertFrom-Json
            if (-not $mj.ok) {
                [void]$failures.Add($user + ' reps-meta ok=false')
                Write-Host 'FAIL reps-meta body'
            } else {
                Write-Host ('OK reps-meta runs=' + @($mj.runs).Count)
            }
        }

        $pick = Pick-ParmRun -Ctx $ctx
        if (-not $pick -or -not $pick.Parm) {
            Write-Host 'WARN no usable TsipParm with own PDF - skip edit check'
        } else {
            Write-Host ('OK picked edit target ' + $pick.Parm + '/' + $pick.Run + ' proname=' + $pick.Proname)
            $gj = $pick.Get
            $r = $gj.record
            $fields = @{
                parm = $pick.Parm
                origRunname = $pick.Run
                runname = $r.runname
                protype = $r.protype
                envtype = $r.envtype
                proname = $r.proname
                envname = $r.envname
                tsorbout = $r.tsorbout
                spherecalc = $r.spherecalc
                fsep = $r.fsep
                coordist = $r.coordist
                analopt = $r.analopt
                margin = $r.margin
                numchan = $r.numchan
                chancodes = $r.chancodes
                country = $r.country
                selsites = $r.selsites
                numcodes = $r.numcodes
                codes = $r.codes
                reports = $r.reports
                hilosecs = $r.hilosecs
                cullmarg = $r.cullmarg
                arc = $r.arc
            }
            $saveUri = $base + 'RemIcsReWrite/tsip-run.ashx?action=save&parm=' + [uri]::EscapeDataString($pick.Parm)
            $save = Get-Http -WebSession $ctx.Session -Uri $saveUri -Method POST -Body $fields
            if (-not $save.Ok) {
                [void]$failures.Add($user + ' tsip-run save HTTP ' + $save.Status + ': ' + $save.Body)
                Write-Host 'FAIL tsip-run save'
                Write-Host $save.Body
            } else {
                $sj = $save.Body | ConvertFrom-Json
                if (-not $sj.ok) {
                    [void]$failures.Add($user + ' tsip-run save: ' + $save.Body)
                    Write-Host 'FAIL tsip-run save body'
                    Write-Host $save.Body
                } else {
                    Write-Host ('OK tsip-run save ' + $pick.Parm + '/' + $pick.Run)
                }
            }
        }
    } catch {
        [void]$failures.Add($user + ' exception: ' + $_.Exception.Message)
        Write-Host ('FAIL exception: ' + $_.Exception.Message)
    }
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host 'FAIL Gate C TSIP reports+edit:'
    foreach ($f in $failures) { Write-Host ('  - ' + $f) }
    exit 1
}
Write-Host ('PASS Gate C TSIP reports+edit (' + $Users.Count + ' users)')
exit 0
