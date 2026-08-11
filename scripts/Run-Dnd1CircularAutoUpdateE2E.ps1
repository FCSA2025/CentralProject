#Requires -Version 5.1
<#
.SYNOPSIS
    Repeatable dnd1 cmxts03 E2E: operator submit -> auto queue -> completion email (delete then add-back).

.DESCRIPTION
    Uses proven cmxts03 circular pair (2 TS sites). Net-zero after both passes.
    Pass 1 (delete): removes sites from main.
    Pass 2 (add-back): restores sites - ready to run again.

.PARAMETER SetupOnly
    Best-effort Install-MicsComplexFixtures + bootstrap add if delete does not validate.

.PARAMETER SkipBootstrap
    Skip bootstrap check (main already has sites for delete pass).
#>
[CmdletBinding()]
param(
    [switch]$SetupOnly,
    [switch]$SkipBootstrap,
    [string]$Submitter = 'dnd1',
    [int]$WaitSeconds = 360
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'RemicsDev-SqlHelpers.ps1')
$manifestPath = Join-Path $RepoRoot 'tests\remicsdev\fixtures\files\updates-primary\circular\dnd1\cmxts03-manifest.json'
$installFx = Join-Path $PSScriptRoot 'Install-MicsComplexFixtures.ps1'
$pipelineScript = Join-Path $PSScriptRoot 'Invoke-RemicsUpdatePipeline.ps1'
$submitScript = Join-Path $PSScriptRoot 'Submit-RemicsDevDbUpdate.ps1'
$autoScript = Join-Path $PSScriptRoot 'Invoke-RemicsUpdateAutoProcessor.ps1'
$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$validateScript = Join-Path $PSScriptRoot 'Invoke-RemicsUpdateValidateAll.ps1'

function Invoke-SqlScalar {
    param([string]$Query)
    return Invoke-RemicsDevSqlScalar -Query $Query -SqlScript $sqlScript
}

function Clear-SubmitterInbox {
    param([string]$Pattern = "${Submitter}_*.txt")
    foreach ($dir in @('D:\updates\primary', 'D:\updates\primary\UnprocessedESFiles')) {
        if (-not (Test-Path $dir)) { continue }
        Get-ChildItem $dir -Filter $Pattern -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-DrainEmailQueue {
    param([int]$TimeoutSec = 90)
    $emailScript = Join-Path $PSScriptRoot 'Invoke-RemicsEmailQueueLocal.ps1'
    if (-not (Test-Path $emailScript)) { return $false }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $emailScript -UseAgentJob -MaxWaitSeconds $TimeoutSec | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Test-DeleteReady {
    param([string]$DeletePath)
    Get-ChildItem 'D:\updates\primary' -Filter "${Submitter}_*.txt" -ErrorAction SilentlyContinue | Remove-Item -Force
    Copy-Item -LiteralPath $DeletePath -Destination (Join-Path 'D:\updates\primary' (Split-Path $DeletePath -Leaf)) -Force
    $rp = Join-Path $env:TEMP ("cmxts03-seed-{0}.json" -f ([guid]::NewGuid().ToString('N')))
    & powershell -NoProfile -ExecutionPolicy Bypass -File $validateScript -ResultPath $rp -MaxFiles 1 | Out-Null
    if (-not (Test-Path $rp)) { return $false }
    $r = Get-Content $rp -Raw | ConvertFrom-Json
    Remove-Item $rp -Force -ErrorAction SilentlyContinue
    $row = @($r.results | Where-Object { $_.name -like '*dndc03del*' } | Select-Object -First 1)
    if (-not $row) { $row = @($r.results | Select-Object -First 1) }
    return ($row -and $row[0].ok -eq $true)
}

function Invoke-BootstrapAdd {
    param([string]$AddPath)
    Get-ChildItem 'D:\updates\primary' -Filter "${Submitter}_*.txt" -ErrorAction SilentlyContinue | Remove-Item -Force
    Copy-Item -LiteralPath $AddPath -Destination (Join-Path 'D:\updates\primary' (Split-Path $AddPath -Leaf)) -Force
    $rp = Join-Path $env:TEMP ("cmxts03-boot-{0}.json" -f ([guid]::NewGuid().ToString('N')))
    & powershell -NoProfile -ExecutionPolicy Bypass -File $pipelineScript -StagingFile (Join-Path 'D:\updates\primary' (Split-Path $AddPath -Leaf)) -SpoofFirst -ResultPath $rp
    $r = Get-Content $rp -Raw | ConvertFrom-Json
    Remove-Item $rp -Force -ErrorAction SilentlyContinue
    if (-not $r.ok) { throw "Bootstrap add-back failed: $($r.error)" }
}

function Invoke-SubmitAndProcess {
    param(
        [string]$SourcePath,
        [string]$Label
    )
    Write-Host "=== $Label ==="
    Clear-SubmitterInbox
    $passStart = Get-Date
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $submitScript -StagingSource $SourcePath -MicsUser $Submitter -FileType TS 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Submit failed: $out" }
    $submit = ($out | Out-String).Trim() | ConvertFrom-Json
    $queueId = [int]$submit.queue_id
    Write-Host "Queued $($submit.inbox_file) queue_id=$queueId"

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        $st = Invoke-SqlScalar "SELECT [status] AS c FROM adm.t_UpdateQueue_local WHERE queue_id = $queueId"
        if ($st -in @('Y', 'E')) { break }
        & powershell -NoProfile -ExecutionPolicy Bypass -File $autoScript -MaxFiles 1 | Out-Null
        Start-Sleep -Seconds 8
    }

    $status = Invoke-SqlScalar "SELECT [status] AS c FROM adm.t_UpdateQueue_local WHERE queue_id = $queueId"
    if ($status -ne 'Y') {
        $err = Invoke-SqlScalar "SELECT ErrorMsg AS c FROM adm.t_UpdateQueue_local WHERE queue_id = $queueId"
        throw "$Label failed: status=$status error=$err"
    }

    Start-Sleep -Seconds 15
    Invoke-DrainEmailQueue -TimeoutSec 90 | Out-Null
    $sent = Invoke-SqlScalar "SELECT TOP 1 sentYN FROM adm.t_EmailQueue_local WHERE mailSubject LIKE 'DbUpdate complete%' ORDER BY mail_sequence DESC"
    Write-Host "$Label OK queue=$queueId email_sentYN=$sent"
    return @{
        label = $Label
        queue_id = $queueId
        inbox_file = $submit.inbox_file
        email_sent = ($sent -eq 'Y')
    }
}

if (-not (Test-Path $manifestPath)) { throw "Manifest missing: $manifestPath" }
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$del = @($manifest.files | Where-Object { $_.pass -eq 'del' } | Select-Object -First 1)
$add = @($manifest.files | Where-Object { $_.pass -eq 'add' } | Select-Object -First 1)

if (Test-Path $installFx) {
    Write-Host '=== Best-effort operator fixture install (dnd.cmxts03) ==='
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $installFx -Schema dnd -Fixture cmxts03 -Force 2>&1 | Out-Null
    } catch { Write-Warning $_.Exception.Message }
}

if (-not $SkipBootstrap) {
    if (-not (Test-DeleteReady -DeletePath $del[0].path)) {
        Write-Host '=== Bootstrap main.* via add-back pipeline ==='
        Invoke-BootstrapAdd -AddPath $add[0].path
    } else {
        Write-Host 'Delete pass already validates (main seeded).'
    }
}

if ($SetupOnly) {
    Write-Output (@{ ok = $true; setup_only = $true } | ConvertTo-Json -Compress)
    exit 0
}

$results = @()
$results += Invoke-SubmitAndProcess -SourcePath $del[0].path -Label 'Pass 1 delete (dndc03del)'
$results += Invoke-SubmitAndProcess -SourcePath $add[0].path -Label 'Pass 2 add-back (dndc03add)'

Write-Output (@{
    ok = $true
    fixture = 'cmxts03'
    submitter = $Submitter
    passes = $results
    message = 'Cycle complete - re-run script for another delete/add cycle'
} | ConvertTo-Json -Depth 5 -Compress)
