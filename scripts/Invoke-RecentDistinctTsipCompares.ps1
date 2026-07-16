#Requires -Version 5.1
<#
.SYNOPSIS
    Re-run and compare the latest archive run for up to 10 distinct TSIP files.

.DESCRIPTION
    Takes a point-in-time snapshot of the most recent completed run for each
    distinct (schema, TS/ES type, parm file), newest first, then invokes
    Invoke-LastTsipCompare.ps1 once per captured baseline.

    The selection is queried fresh for every batch. If fewer than Count distinct
    files exist, all available files are tested. Future distinct files are
    automatically included and older ones fall out of the rolling set.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 10)]
    [int]$Count = 10,
    [int]$TimeoutSec = 240,
    [switch]$Json,
    [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$singleScript = Join-Path $PSScriptRoot 'Invoke-LastTsipCompare.ps1'
$batchesRoot = 'D:\inetpub\fcsa\admin\tsip-runs\batches'

foreach ($required in @($sqlScript, $singleScript)) {
    if (-not (Test-Path $required)) { throw "Required script not found: $required" }
}

function Invoke-SqlRows {
    param([Parameter(Mandatory)][string]$Query)
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $sqlScript -Query $Query 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "SQL query failed:`n$raw" }
    $lines = @($raw -split "`r?`n" | Where-Object {
        $_ -and $_ -notmatch '^---' -and $_ -notmatch '^-+$' -and
        $_ -notmatch '^\(' -and $_ -notmatch 'rows affected'
    })
    if ($lines.Count -lt 2) { return @() }
    $headers = @($lines[0] -split '\|' | ForEach-Object { $_.Trim() })
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^-+$') { continue }
        $parts = @($lines[$i] -split '\|')
        if ($parts.Count -lt $headers.Count) { continue }
        $row = [ordered]@{}
        for ($column = 0; $column -lt $headers.Count; $column++) {
            $row[$headers[$column]] = $parts[$column].Trim()
        }
        $rows += [pscustomobject]$row
    }
    return $rows
}

function Write-JsonAtomic {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Data)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $text = $Data | ConvertTo-Json -Depth 8 -Compress
    $temp = "$Path.tmp"
    [System.IO.File]::WriteAllText($temp, $text, [System.Text.UTF8Encoding]::new($false))
    Move-Item $temp $Path -Force
}

function Publish-Result {
    param([Parameter(Mandatory)]$Data)
    if ($ResultPath) { Write-JsonAtomic -Path $ResultPath -Data $Data }
    if ($Json) { $Data | ConvertTo-Json -Depth 8 -Compress }
}

$startedUtc = (Get-Date).ToUniversalTime().ToString('o')
$selection = @(Invoke-SqlRows -Query @"
WITH ranked AS (
    SELECT
        run_id,
        RTRIM(mics_user) AS mics_user,
        RTRIM(source_schema) AS source_schema,
        RTRIM(parm_file) AS parm_file,
        RTRIM(run_name) AS run_name,
        RTRIM(protype) AS protype,
        num_int_cases,
        CONVERT(varchar(33), run_started_utc, 126) AS run_started_utc,
        ROW_NUMBER() OVER (
            PARTITION BY
                LOWER(RTRIM(source_schema)),
                LOWER(RTRIM(protype)),
                LOWER(RTRIM(parm_file))
            ORDER BY run_started_utc DESC, run_id DESC
        ) AS distinct_rank
    FROM web.tsip_run
    WHERE archive_status = 'complete'
      AND NULLIF(RTRIM(parm_file), '') IS NOT NULL
)
SELECT TOP ($Count)
    run_id, mics_user, source_schema, parm_file, run_name, protype,
    num_int_cases, run_started_utc
FROM ranked
WHERE distinct_rank = 1
ORDER BY run_started_utc DESC, run_id DESC;
"@)

if ($selection.Count -lt 1) {
    $empty = [ordered]@{
        ok = $false; match = $false; status = 'complete'
        requested_count = $Count; distinct_count = 0; completed_count = 0
        error = 'No completed distinct TSIP files found in web.tsip_run'
        started_utc = $startedUtc
    }
    Publish-Result -Data $empty
    exit 1
}

$batchId = ('{0}_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8)))
$batchDir = Join-Path $batchesRoot $batchId
New-Item -ItemType Directory -Force -Path $batchDir | Out-Null
$manifestPath = Join-Path $batchDir 'manifest.json'
$resultsPath = Join-Path $batchDir 'results.json'

$manifest = [ordered]@{
    batch_id = $batchId
    captured_utc = $startedUtc
    requested_count = $Count
    distinct_count = $selection.Count
    distinct_key = 'source_schema + protype + parm_file'
    baselines = $selection
}
Write-JsonAtomic -Path $manifestPath -Data $manifest

$results = New-Object System.Collections.Generic.List[object]
for ($index = 0; $index -lt $selection.Count; $index++) {
    $baseline = $selection[$index]
    $ordinal = $index + 1
    $safeParm = ([string]$baseline.parm_file -replace '[^A-Za-z0-9_-]', '_')
    $childResultPath = Join-Path $batchDir ('{0:D2}_{1}_run{2}.json' -f $ordinal, $safeParm, $baseline.run_id)

    $progress = [ordered]@{
        ok = $true; status = 'running'; op = 'tsip-batch'
        requested_count = $Count; distinct_count = $selection.Count
        completed_count = $results.Count
        current_index = $ordinal
        current_parm_file = [string]$baseline.parm_file
        current_baseline_run_id = [int]$baseline.run_id
        batch_dir = $batchDir
        manifest_path = $manifestPath
        started_utc = $startedUtc
    }
    if ($ResultPath) { Write-JsonAtomic -Path $ResultPath -Data $progress }

    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $singleScript `
        -BaselineRunId ([int]$baseline.run_id) `
        -TimeoutSec $TimeoutSec `
        -Json `
        -ResultPath $childResultPath 2>&1 | Out-String
    $childExit = $LASTEXITCODE

    $child = $null
    if (Test-Path $childResultPath) {
        try { $child = Get-Content $childResultPath -Raw | ConvertFrom-Json } catch { }
    }
    if ($null -eq $child) {
        $child = [pscustomobject]@{
            ok = $false
            match = $false
            error = "Child compare exited $childExit without valid result JSON"
            summary = $output.Trim()
            baseline_run_id = [int]$baseline.run_id
            parm_file = [string]$baseline.parm_file
            mics_user = [string]$baseline.mics_user
        }
    }
    $results.Add($child)
}

Write-JsonAtomic -Path $resultsPath -Data $results.ToArray()

$failed = @($results | Where-Object { -not ($_.ok -eq $true -or $_.ok -eq 'True') }).Count
$matched = @($results | Where-Object {
    ($_.ok -eq $true -or $_.ok -eq 'True') -and
    ($_.match -eq $true -or $_.match -eq 'True')
}).Count
$differences = $results.Count - $failed - $matched
$allOk = ($failed -eq 0)
$allMatch = ($failed -eq 0 -and $differences -eq 0 -and $matched -eq $results.Count)

$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add(("Distinct TSIP batch: tested {0} of requested {1} files" -f $selection.Count, $Count))
$summaryLines.Add(("Results: MATCH={0}, DIFFERENCES={1}, FAILED={2}" -f $matched, $differences, $failed))
$summaryLines.Add(("Selection key: source_schema + protype + parm_file (latest completed run per file)"))
$summaryLines.Add(("Manifest: {0}" -f $manifestPath))
$summaryLines.Add('')
for ($i = 0; $i -lt $results.Count; $i++) {
    $r = $results[$i]
    $state = if (-not ($r.ok -eq $true -or $r.ok -eq 'True')) {
        'FAILED'
    } elseif ($r.match -eq $true -or $r.match -eq 'True') {
        'MATCH'
    } else {
        'DIFFERENCES'
    }
    $summaryLines.Add(("[{0}/{1}] {2} | {3}/{4} | baseline {5} -> new {6}" -f
        ($i + 1), $results.Count, $state, $r.mics_user, $r.parm_file,
        $r.baseline_run_id, $r.new_run_id))
}

$final = [ordered]@{
    ok = $allOk
    match = $allMatch
    status = 'complete'
    op = 'tsip-batch'
    requested_count = $Count
    distinct_count = $selection.Count
    completed_count = $results.Count
    matched_count = $matched
    differences_count = $differences
    failed_count = $failed
    baseline_run_ids = (($selection | ForEach-Object { $_.run_id }) -join ',')
    parm_files = (($selection | ForEach-Object { "$($_.source_schema)/$($_.protype)/$($_.parm_file)" }) -join ', ')
    batch_dir = $batchDir
    manifest_path = $manifestPath
    results_path = $resultsPath
    started_utc = $startedUtc
    completed_utc = (Get-Date).ToUniversalTime().ToString('o')
    summary = ($summaryLines -join "`n")
    message = if ($allMatch) {
        "All $($results.Count) distinct TSIP files matched."
    } elseif ($allOk) {
        "$differences of $($results.Count) distinct TSIP files had differences."
    } else {
        "$failed of $($results.Count) distinct TSIP files failed to run."
    }
}
Publish-Result -Data $final
exit $(if ($allOk) { 0 } else { 1 })
