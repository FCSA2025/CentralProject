#Requires -Version 5.1
<#
.SYNOPSIS
    Full E2E test: operator DbUpdate submit -> auto queue -> pipeline -> completion email.

.DESCRIPTION
    Repeatable seq10 pair-1 cycle (delete then add-back) for dnd1.
    -Setup: regenerate fixtures if needed, bootstrap main.* when delete passes do not validate yet
    -Cycle: two sequential passes (del + add) per file type; operator re-import between passes

.PARAMETER FileType
    TS, ES, or Both (default ES — most reliable in current env).

.PARAMETER Pair
    seq10 pair number 1-5 (default 1).

.PARAMETER SetupOnly
    Bootstrap main only, no submit/process.

.PARAMETER SkipBootstrap
    Assume main.* already seeded.

.PARAMETER WaitSeconds
    Max wait per pass for queue Y + completion email (default 300).
#>
[CmdletBinding()]
param(
    [ValidateSet('TS', 'ES', 'Both')]
    [string]$FileType = 'ES',
    [ValidateRange(1, 5)]
    [int]$Pair = 1,
    [switch]$SetupOnly,
    [switch]$SkipBootstrap,
    [int]$WaitSeconds = 300,
    [string]$Submitter = 'dnd1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'RemicsDev-SqlHelpers.ps1')
$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$genScript = Join-Path $PSScriptRoot 'New-CircularSeq10Fixtures.ps1'
$initScript = Join-Path $PSScriptRoot 'Initialize-CircularSeq10Main.ps1'
$submitScript = Join-Path $PSScriptRoot 'Submit-RemicsDevDbUpdate.ps1'
$autoScript = Join-Path $PSScriptRoot 'Invoke-RemicsUpdateAutoProcessor.ps1'
$manifestPath = Join-Path $RepoRoot 'tests\remicsdev\fixtures\files\updates-primary\circular\seq10\seq10-manifest.json'

function Invoke-SqlScalar {
    param([string]$Query)
    return Invoke-RemicsDevSqlScalar -Query $Query -SqlScript $sqlScript
}

function Wait-ForPassComplete {
    param(
        [int]$QueueId,
        [datetime]$StartedAfter,
        [int]$TimeoutSec
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $lastStatus = ''
    while ((Get-Date) -lt $deadline) {
        $status = Invoke-SqlScalar "SELECT [status] AS c FROM adm.t_UpdateQueue_local WHERE queue_id = $QueueId"
        $lastStatus = [string]$status
        if ($status -eq 'Y') {
            $sent = Invoke-SqlScalar @"
SELECT TOP 1 sentYN FROM adm.t_EmailQueue_local
WHERE mailSubject LIKE 'DbUpdate complete%'
ORDER BY mail_sequence DESC
"@
            if ($sent -eq 'Y') { return @{ ok = $true; status = 'Y'; email_sent = $true } }
            return @{ ok = $true; status = 'Y'; email_sent = $false; note = 'Processed OK; check Email Queue Local job for completion mail' }
        }
        if ($status -eq 'E') {
            $err = Invoke-SqlScalar "SELECT ErrorMsg AS c FROM adm.t_UpdateQueue_local WHERE queue_id = $QueueId"
            return @{ ok = $false; status = 'E'; error = $err }
        }
        if ($status -eq 'P') {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $autoScript -MaxFiles 1 | Out-Null
        }
        Start-Sleep -Seconds 10
    }
    return @{ ok = $false; status = $lastStatus; error = "Timeout after ${TimeoutSec}s" }
}

function Invoke-Pass {
    param(
        [object]$FileEntry,
        [string]$TypeKey,
        [string]$Label
    )
    $sourcePath = [string]$FileEntry.path
    if (-not (Test-Path $sourcePath)) { throw "Fixture missing: $sourcePath" }

    Write-Host "=== Pass $Label ($TypeKey $($FileEntry.pass)) $($FileEntry.file) ==="
    $passStart = Get-Date

    $submitJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $submitScript `
        -StagingSource $sourcePath -MicsUser $Submitter -FileType $(if ($TypeKey -eq 'es') { 'ES' } else { 'TS' }) 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Submit script failed: $submitJson" }
    $submit = ($submitJson | Out-String).Trim() | ConvertFrom-Json

    $queueId = [int]$submit.queue_id
    Write-Host "Submitted inbox=$($submit.inbox_file) queue_id=$queueId validated=$($submit.validated)"

    # Run auto processor until this row completes (do not rely on agent schedule in test)
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        $st = Invoke-SqlScalar "SELECT [status] AS c FROM adm.t_UpdateQueue_local WHERE queue_id = $queueId"
        if ($st -in @('Y', 'E')) { break }
        & powershell -NoProfile -ExecutionPolicy Bypass -File $autoScript -MaxFiles 1 | Out-Null
        Start-Sleep -Seconds 5
    }

    $result = Wait-ForPassComplete -QueueId $queueId -StartedAfter $passStart -TimeoutSec 60
    if (-not $result.ok) {
        throw "Pass $Label failed: status=$($result.status) error=$($result.error)"
    }
    Write-Host "PASS $Label OK (queue $queueId, email_sent=$($result.email_sent))"
    return @{
        label = $Label
        queue_id = $queueId
        inbox_file = $submit.inbox_file
        pdf_name = $submit.pdf_name
        email_sent = $result.email_sent
    }
}

# ---- setup ----
if (-not (Test-Path $manifestPath)) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $genScript -Submitter $Submitter
}
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

if (-not $SkipBootstrap) {
    Write-Host '=== Bootstrap main.* (seq10) ==='
    $initArgs = @('-Submitter', $Submitter)
    if ($FileType -eq 'ES') { $initArgs += '-SkipTs' }
    if ($FileType -eq 'TS') { $initArgs += '-SkipEs' }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $initScript @initArgs 2>&1
}

if ($SetupOnly) {
    Write-Output (@{ ok = $true; setup_only = $true } | ConvertTo-Json -Compress)
    exit 0
}

$results = @()
$types = @()
if ($FileType -eq 'TS' -or $FileType -eq 'Both') { $types += 'ts' }
if ($FileType -eq 'ES' -or $FileType -eq 'Both') { $types += 'es' }

foreach ($tk in $types) {
    $files = @($manifest.$tk.files | Where-Object { [int]$_.pair -eq $Pair } | Sort-Object { [int]$_.sequence })
    $del = @($files | Where-Object { $_.pass -eq 'del' } | Select-Object -First 1)
    $add = @($files | Where-Object { $_.pass -eq 'add' } | Select-Object -First 1)
    if (-not $del -or -not $add) { throw "Pair $Pair incomplete in manifest for $tk" }

    $results += Invoke-Pass -FileEntry $del[0] -TypeKey $tk -Label "$tk pair$Pair delete"
    $results += Invoke-Pass -FileEntry $add[0] -TypeKey $tk -Label "$tk pair$Pair add-back"
}

Write-Output (@{
    ok = $true
    submitter = $Submitter
    pair = $Pair
    file_type = $FileType
    passes = $results
    message = 'Cycle complete — main.* net-zero when pair finishes; re-run -Cycle for repeat'
} | ConvertTo-Json -Depth 6 -Compress)
