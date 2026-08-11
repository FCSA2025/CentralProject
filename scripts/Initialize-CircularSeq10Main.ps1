#Requires -Version 5.1
<#
.SYNOPSIS
    One-time bootstrap: seed main.* with seq10 site subset via fwmda pipeline.

.DESCRIPTION
    If delete pass cycts01d already validates (sites present in main.*), bootstrap is
    skipped. Otherwise runs cycts01a / cyces01a add-back through the fwmda pipeline.
#>
[CmdletBinding()]
param(
    [switch]$Regenerate,
    [string]$Submitter = 'dnd1',
    [switch]$SkipEs,
    [switch]$SkipTs,
    [switch]$ForceBootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$genScript = Join-Path $PSScriptRoot 'New-CircularSeq10Fixtures.ps1'
$installScript = Join-Path $PSScriptRoot 'Install-MicsComplexFixtures.ps1'
$pipelineScript = Join-Path $PSScriptRoot 'Invoke-RemicsUpdatePipeline.ps1'
$validateScript = Join-Path $PSScriptRoot 'Invoke-RemicsUpdateValidateAll.ps1'
$manifestPath = Join-Path $RepoRoot 'tests\remicsdev\fixtures\files\updates-primary\circular\seq10\seq10-manifest.json'
$tsInbox = 'D:\updates\primary'
$esInbox = Join-Path $tsInbox 'UnprocessedESFiles'

if ($Regenerate) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $genScript -Submitter $Submitter
} elseif (-not (Test-Path $manifestPath)) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $genScript -Submitter $Submitter
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

Write-Host 'Refreshing operator pinned fixtures on dnd (best-effort)...'
foreach ($fx in @('cycts10', $(if ($SkipEs) { $null } else { 'cyces10' }))) {
    if (-not $fx) { continue }
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $installScript -Schema dnd -Fixture $fx -Force 2>&1 | Out-Null
    } catch {
        Write-Warning "Install dnd.$fx skipped: $($_.Exception.Message)"
    }
}

function Test-DeleteValidates {
    param(
        [string]$DeletePath,
        [string]$InboxDir
    )
    if (-not (Test-Path $DeletePath)) { return $false }
    Get-ChildItem $InboxDir -Filter "${Submitter}_*.txt" -ErrorAction SilentlyContinue | Remove-Item -Force
    Copy-Item -LiteralPath $DeletePath -Destination (Join-Path $InboxDir (Split-Path $DeletePath -Leaf)) -Force
    $rp = Join-Path $env:TEMP ("seq10-seed-check-{0}.json" -f ([guid]::NewGuid().ToString('N')))
    & powershell -NoProfile -ExecutionPolicy Bypass -File $validateScript -ResultPath $rp -MaxFiles 1 | Out-Null
    if (-not (Test-Path $rp)) { return $false }
    $result = Get-Content $rp -Raw | ConvertFrom-Json
    Remove-Item $rp -Force -ErrorAction SilentlyContinue
    $row = @($result.results | Select-Object -First 1)
    return ($row -and $row[0].ok -eq $true)
}

function Invoke-BootstrapAdd {
    param(
        [object[]]$Files,
        [string]$DestDir,
        [string]$Label
    )
    $add = @($Files | Where-Object { $_.pass -eq 'add' } | Sort-Object { [int]$_.sequence } | Select-Object -First 1)
    if (-not $add -or -not $add.Count) { throw "No add-back file found for $Label" }
    $sourcePath = [string]$add[0].path
    if (-not (Test-Path $sourcePath)) { throw "Bootstrap add file missing: $sourcePath" }
    if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Force -Path $DestDir | Out-Null }
    Get-ChildItem $DestDir -Filter "${Submitter}_*.txt" -ErrorAction SilentlyContinue | Remove-Item -Force
    $dest = Join-Path $DestDir ([string]$add[0].file)
    Copy-Item -LiteralPath $sourcePath -Destination $dest -Force
    Write-Host "Bootstrap $Label add-back -> $dest"
    $resultPath = Join-Path $env:TEMP ("seq10-bootstrap-{0}.json" -f ([guid]::NewGuid().ToString('N')))
    & powershell -NoProfile -ExecutionPolicy Bypass -File $pipelineScript `
        -StagingFile $dest -MainOnly -ResultPath $resultPath -FileType $(if ($DestDir -match 'UnprocessedESFiles') { 'ES' } else { 'TS' })
    $result = Get-Content $resultPath -Raw | ConvertFrom-Json
    Remove-Item $resultPath -Force -ErrorAction SilentlyContinue
    if (-not $result.ok) {
        throw "Bootstrap failed for $Label : $($result.error)"
    }
    return [pscustomobject]@{
        label = $Label
        file = Split-Path $dest -Leaf
        ok = $true
        archive_dir = $result.archive_dir
        summary = $result.summary
    }
}

$jobs = @()
if (-not $SkipTs) {
$tsDel = @($manifest.ts.files | Where-Object { $_.pass -eq 'del' } | Sort-Object { [int]$_.sequence } | Select-Object -First 1)
if ($tsDel -and (Test-DeleteValidates -DeletePath $tsDel[0].path -InboxDir $tsInbox) -and -not $ForceBootstrap) {
    Write-Host 'TS main already seeded (cycts01d validates OK).'
    $jobs += [pscustomobject]@{ label = 'TS'; skipped = $true; reason = 'cycts01d already validates' }
} else {
    try {
        $jobs += Invoke-BootstrapAdd -Files @($manifest.ts.files) -DestDir $tsInbox -Label 'TS cycts01a'
    } catch {
        Write-Warning "TS bootstrap skipped: $($_.Exception.Message)"
        $jobs += [pscustomobject]@{ label = 'TS'; skipped = $true; reason = $_.Exception.Message }
    }
}
}

if (-not $SkipEs) {
    $esDel = @($manifest.es.files | Where-Object { $_.pass -eq 'del' } | Sort-Object { [int]$_.sequence } | Select-Object -First 1)
    if ($esDel -and (Test-DeleteValidates -DeletePath $esDel[0].path -InboxDir $esInbox) -and -not $ForceBootstrap) {
        Write-Host 'ES main already seeded (cyces01d validates OK).'
        $jobs += [pscustomobject]@{ label = 'ES'; skipped = $true; reason = 'cyces01d already validates' }
    } else {
        try {
            $jobs += Invoke-BootstrapAdd -Files @($manifest.es.files) -DestDir $esInbox -Label 'ES cyces01a'
        } catch {
            Write-Warning "ES bootstrap skipped: $($_.Exception.Message)"
            $jobs += [pscustomobject]@{ label = 'ES'; skipped = $true; reason = $_.Exception.Message }
        }
    }
}

Write-Output (@{
    ok = $true
    submitter = $manifest.submitter
    bootstrapped = $jobs
    message = 'main.* ready — run delete/add pairs (01d,01a .. 05d,05a) indefinitely'
} | ConvertTo-Json -Depth 6)
