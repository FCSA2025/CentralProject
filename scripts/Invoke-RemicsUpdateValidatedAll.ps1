#Requires -Version 5.1
<#
.SYNOPSIS
    Process all inbox staging files that passed validate-all (from validate-cache.json).

.DESCRIPTION
    Reads validate-cache.json for files with ok=true still present in D:\updates\primary inbox,
    then runs Invoke-RemicsUpdatePipeline.ps1 on each in sort order.

.PARAMETER ResultPath
    Aggregate job JSON for admin polling.

.PARAMETER CachePath
    validate-cache.json path (default: admin update-pipeline folder).

.PARAMETER Mode
    spoof-first | spoof-only | main-only

.PARAMETER MaxFiles
    Limit files processed (0 = all validated inbox files).
#>
[CmdletBinding()]
param(
    [string]$ResultPath = '',
    [string]$CachePath = '',
    [string]$JobId = '',
    [ValidateSet('spoof-first', 'spoof-only', 'main-only')]
    [string]$Mode = 'spoof-first',
    [int]$MaxFiles = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pipelineScript = Join-Path $PSScriptRoot 'Invoke-RemicsUpdatePipeline.ps1'
$PrimaryRoot = 'D:\updates\primary'
$EsInbox = Join-Path $PrimaryRoot 'UnprocessedESFiles'

function Write-JobJson {
    param([object]$Payload)
    if (-not $ResultPath) { return }
    $dir = Split-Path $ResultPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $json = $Payload | ConvertTo-Json -Depth 8 -Compress
    $tmp = "$ResultPath.tmp"
    Set-Content -Path $tmp -Value $json -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $ResultPath -Force
}

function Get-ObjProp {
    param($Obj, [string]$Name)
    if (-not $Obj) { return $null }
    $prop = $Obj.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Get-InboxPathMap {
    $map = @{}
    foreach ($dir in @($PrimaryRoot, $EsInbox)) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($fi in Get-ChildItem $dir -Filter '*.txt' -File) {
            $map[$fi.Name] = $fi.FullName
        }
    }
    return $map
}

function Get-ModeArgs {
    switch ($Mode) {
        'main-only' { return @('-MainOnly') }
        'spoof-only' { return @('-SpoofOnly') }
        default { return @('-SpoofFirst') }
    }
}

if (-not (Test-Path $pipelineScript)) {
    Write-Output (@{ ok = $false; status = 'complete'; error = "Pipeline script missing: $pipelineScript" } | ConvertTo-Json -Compress)
    exit 1
}

if (-not $CachePath -and $ResultPath) {
    $CachePath = Join-Path (Split-Path $ResultPath -Parent) 'validate-cache.json'
}
if (-not $CachePath) {
    $CachePath = Join-Path $RepoRoot 'validate-cache.json'
}

if (-not (Test-Path $CachePath)) {
    Write-Output (@{ ok = $false; status = 'complete'; error = "Validate cache not found: $CachePath (run Validate all first)" } | ConvertTo-Json -Compress)
    exit 1
}

$cache = Get-Content $CachePath -Raw | ConvertFrom-Json
$fileMap = Get-InboxPathMap
$modeArgs = Get-ModeArgs

$targets = @()
if ($cache.files) {
    $props = $cache.files.PSObject.Properties | Sort-Object Name
    foreach ($prop in $props) {
        $name = [string]$prop.Name
        $entry = $prop.Value
        $ok = $false
        if ($entry.ok -eq $true -or [string]$entry.ok -eq 'True') { $ok = $true }
        if (-not $ok) { continue }
        if (-not $fileMap.ContainsKey($name)) { continue }
        $targets += [pscustomobject]@{
            name = $name
            path = $fileMap[$name]
            validated = [string]$entry.validated
            message = [string]$entry.message
        }
    }
}

if ($MaxFiles -gt 0 -and $targets.Count -gt $MaxFiles) {
    $targets = @($targets | Select-Object -First $MaxFiles)
}

$jobId = if ($JobId -match '^[a-fA-F0-9]{32}$') { $JobId } else { [guid]::NewGuid().ToString('N') }
$job = @{
    ok = $true
    status = 'running'
    job_id = $jobId
    jobId = $jobId
    type = 'update_validated_all'
    mode = $Mode
    files_total = $targets.Count
    files_done = 0
    passed = 0
    failed = 0
    skipped = 0
    current_file = ''
    started_utc = (Get-Date).ToUniversalTime().ToString('o')
    results = @()
    summary = ''
}

Write-JobJson -Payload $job

if ($targets.Count -lt 1) {
    $job.status = 'complete'
    $job.completed_utc = (Get-Date).ToUniversalTime().ToString('o')
    $job.summary = 'No validated inbox files to update (run Validate all, or copy fixtures to inbox)'
    Write-JobJson -Payload $job
    Write-Output ($job | ConvertTo-Json -Depth 12 -Compress)
    exit 0
}

$passed = 0
$failed = 0
$idx = 0
$tempDir = Join-Path $env:TEMP ("fwmda-update-validated-{0}" -f $jobId)
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
foreach ($target in $targets) {
    $idx++
    $job.current_file = $target.name
    $job.files_done = $idx - 1
    Write-JobJson -Payload $job

    if (-not (Test-Path -LiteralPath $target.path)) {
        $job.skipped++
        $job.results = @($job.results) + @(@{
            name = $target.name
            path = $target.path
            ok = $false
            skipped = $true
            exit_code = $null
            validated = $target.validated
            pipeline_job_id = ''
            pipeline_error = 'Staging file no longer in inbox'
            failed_step = 'precheck'
            message = 'Skipped — file not found in inbox'
        })
        $job.files_done = $idx
        $job.passed = $passed
        $job.failed = $failed
        Write-JobJson -Payload $job
        continue
    }

    $oneResultPath = Join-Path $tempDir ("{0}.json" -f $idx)
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $pipelineScript,
        '-StagingFile', $target.path, '-ResultPath', $oneResultPath) + $modeArgs
    $nullOut = Join-Path $tempDir ("{0}.stdout.log" -f $idx)
    $nullErr = Join-Path $tempDir ("{0}.stderr.log" -f $idx)

    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $nullOut -RedirectStandardError $nullErr
    $one = $null
    if (Test-Path $oneResultPath) {
        try { $one = Get-Content $oneResultPath -Raw | ConvertFrom-Json } catch { }
    }

    $fileOk = $false
    $fileMsg = "exit=$($proc.ExitCode)"
    if ($one) {
        $fileOk = (Get-ObjProp $one 'ok') -eq $true
        $fileMsg = [string](Get-ObjProp $one 'summary')
        if ([string]::IsNullOrWhiteSpace($fileMsg)) {
            $fileMsg = [string](Get-ObjProp $one 'error')
        }
        if ([string]::IsNullOrWhiteSpace($fileMsg)) {
            $fileMsg = "exit=$($proc.ExitCode)"
        }
    }

    if ($fileOk) { $passed++ } else { $failed++ }

    $job.results = @($job.results) + @(@{
        name = $target.name
        path = $target.path
        ok = $fileOk
        exit_code = $proc.ExitCode
        validated = $target.validated
        pipeline_job_id = [string](Get-ObjProp $one 'job_id')
        pipeline_error = [string](Get-ObjProp $one 'error')
        failed_step = [string](Get-ObjProp $one 'failed_step')
        message = $fileMsg
    })
    $job.files_done = $idx
    $job.passed = $passed
    $job.failed = $failed
    Write-JobJson -Payload $job
}

$job.status = 'complete'
$job.completed_utc = (Get-Date).ToUniversalTime().ToString('o')
$job.current_file = ''
$job.all_passed = ($failed -eq 0 -and $job.skipped -eq 0)
$job.ok = $true
$job.summary = "Update validated: $($targets.Count) file(s), $passed passed, $failed failed, $($job.skipped) skipped (mode=$Mode)"
Write-JobJson -Payload $job
Write-Output ($job | ConvertTo-Json -Depth 8 -Compress)
if (-not $job.all_passed) { exit 1 }
}
catch {
    $job.status = 'complete'
    $job.ok = $false
    $job.completed_utc = (Get-Date).ToUniversalTime().ToString('o')
    $job.current_file = ''
    $job.error = $_.Exception.Message
    if (-not $job.summary) {
        $job.summary = "Update validated aborted: $($_.Exception.Message)"
    }
    Write-JobJson -Payload $job
    Write-Output ($job | ConvertTo-Json -Depth 8 -Compress)
    exit 1
}
finally {
    if ($tempDir -and (Test-Path $tempDir)) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
