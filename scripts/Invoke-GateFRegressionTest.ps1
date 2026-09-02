#Requires -Version 5.1
<#
.SYNOPSIS
    Gate F regression: SQL invariants + HTTP TSIP isolation per roster.

.DESCRIPTION
    SQL checks (via web.RunGateFRegression):
      - Zero cross-company TSIP parm runs
      - Zero catalog drift (orphans/missing for types 0/5/417)
      - User Tables Reconcile job ran within MaxStaleHours

    HTTP checks (per roster user):
      - tsipValidate returns 'not found' for foreign PDF
      - tsip-reps-tree.ashx root returns ok=true (compile/runtime death on reports)

    Nightly automation: SQL Agent job "RemIcs Gate F Regression" (Deploy-GateFRegressionJob.ps1).

.PARAMETER Users
    Roster for HTTP isolation (default bchy1, rctl1, xci1).

.PARAMETER SqlOnly
    Skip HTTP checks.

.PARAMETER HttpOnly
    Skip SQL checks (used by SQL Agent job step 2).

.PARAMETER SendEmailOnFailure
    Email FCSA team via web.SendGateFAlert when HTTP checks fail.

.PARAMETER Quiet
    Less console output (for Agent job step).
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.cloudmicsdev.ca/mics/',
    [string[]]$Users = @('bchy1', 'rctl1', 'xci1'),
    [string]$Password = '',
    [string]$ForeignPdf = '1c0139c2444',
    [int]$MaxStaleHours = 36,
    [switch]$SqlOnly,
    [switch]$HttpOnly,
    [switch]$SendEmailOnFailure,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$InvokeSql = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'

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

function Write-Step {
    param([string]$Message)
    if (-not $Quiet) { Write-Host $Message }
}

function Send-GateFAlertSql {
    param([string]$Subject, [string]$Body)
    $tempSql = Join-Path $env:TEMP ('gate-f-alert-' + [guid]::NewGuid().ToString('n') + '.sql')
    @"
EXEC web.SendGateFAlert
    @Subject = N'$($Subject.Replace("'", "''"))',
    @Body    = N'$($Body.Replace("'", "''"))';
"@ | Set-Content -Path $tempSql -Encoding UTF8
    try {
        & $InvokeSql -InputFile $tempSql | Out-Null
    } finally {
        Remove-Item $tempSql -Force -ErrorAction SilentlyContinue
    }
}

if (-not $Password) { $Password = $env:MICS_TEST_PASSWORD }
if (-not $Password) { $Password = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
if (-not $Password) { $Password = 'x' }

$base = $BaseUrl.TrimEnd('/') + '/'
$failures = @()

function Get-AsmxString {
    param([object]$Resp)
    if ($Resp.Content -match '"d"\s*:\s*"([^"]*)"') { return $Matches[1] }
    return $Resp.Content.Trim()
}

function Invoke-HttpIsolation {
    param([string]$User)
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $null = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/login.aspx') -Method POST `
        -Body @{ user = $User; password = $Password } -WebSession $session -MaximumRedirection 10 -UseBasicParsing

    $url = $base + 'Ttsipmenu/TwsTsip.asmx/tsipValidate'
    $payload = @{ type = 'ft_'; pdfname = $ForeignPdf } | ConvertTo-Json
    $resp = Invoke-WebRequest -Uri $url -Method POST -Body $payload `
        -ContentType 'application/json; charset=utf-8' -WebSession $session -UseBasicParsing
    $valid = Get-AsmxString $resp
    if ($valid -ne 'not found') {
        return "tsipValidate foreign PDF => '$valid' (expected 'not found')"
    }

    # Post-run surface: missing Assembly Src / compile errors must fail Gate F (2026-09-02 lesson).
    try {
        $reps = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/tsip-reps-tree.ashx') `
            -WebSession $session -UseBasicParsing
        $repsJson = $reps.Content | ConvertFrom-Json
        if (-not $repsJson.ok) {
            return "tsip-reps-tree root ok=false: $($reps.Content)"
        }
    } catch {
        $detail = $_.Exception.Message
        $resp = $_.Exception.Response
        if ($resp) {
            try {
                $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
                $detail = $sr.ReadToEnd()
            } catch {}
        }
        return "tsip-reps-tree root failed: $detail"
    }
    return $null
}

if (-not $HttpOnly) {
    Write-Step '=== Gate F SQL checks ==='
    try {
        & $InvokeSql -Query "SET NOCOUNT ON; EXEC web.RunGateFRegression @SendEmail = 0, @MaxStaleHours = $MaxStaleHours, @FailJobOnIssues = 0;" | Out-Null
        $latest = & $InvokeSql -Query @"
SET NOCOUNT ON;
SELECT TOP 1 passed = CASE WHEN r.ok = 1 THEN 1 ELSE 0 END,
       r.run_id, r.cross_company_count, r.catalog_orphans, r.catalog_missing, r.reconcile_stale,
       issue_count = (SELECT COUNT(*) FROM web.gate_f_regression_finding f WHERE f.run_id = r.run_id)
FROM web.gate_f_regression_run r
ORDER BY r.run_id DESC;
"@
        if ($latest -match '(?m)^\s*0\s*\|') {
            $failures += "SQL regression failed. Latest run:`n$latest"
            Write-Step "FAIL SQL checks"
        } else {
            Write-Step "OK SQL checks"
        }
    } catch {
        $failures += "SQL regression error: $($_.Exception.Message)"
    }
}

if (-not $SqlOnly) {
    Write-Step '=== Gate F HTTP isolation (roster) ==='
    $httpFails = @()
    foreach ($user in $Users) {
        try {
            $err = Invoke-HttpIsolation -User $user
            if ($err) {
                $httpFails += "$user : $err"
            } else {
                Write-Step "OK HTTP isolation $user"
            }
        } catch {
            $httpFails += "$user : $($_.Exception.Message)"
        }
    }
    if ($httpFails.Count -gt 0) {
        $failures += $httpFails
        if ($SendEmailOnFailure) {
            $body = "RemIcs Gate F HTTP isolation failed on remicsdev.`n`n" + ($httpFails -join "`n") +
                "`n`nRoster tested: $($Users -join ', ')`nForeign PDF: $ForeignPdf"
            Send-GateFAlertSql -Subject 'RemIcs Gate F: TSIP isolation failure (remicsdev)' -Body $body
            Write-Step 'Alert email sent for HTTP failures'
        }
    }
}

if ($failures.Count -gt 0) {
    if (-not $Quiet) {
        Write-Host 'FAIL Gate F regression:'
        $failures | ForEach-Object { Write-Host "  - $_" }
    }
    exit 1
}

if (-not $Quiet) {
    Write-Host ("PASS Gate F regression (SQL={0}, HTTP users={1})" -f $(-not $HttpOnly), $(if ($SqlOnly) { 'skipped' } else { $Users.Count }))
}
exit 0
