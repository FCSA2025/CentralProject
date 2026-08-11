#Requires -Version 5.1
<#
.SYNOPSIS
    Archive stale error inbox DbUpdate files (>14 days) to failed/stale-{date}/.

.DESCRIPTION
    Only moves files that are still in TS/ES inbox AND have an error signal AND are not
    actively queued (status N/P) or processing in the registry.

.PARAMETER MaxAgeDays
    Minimum age in days before a file is eligible (default 14).

.PARAMETER DryRun
    Report actions without moving files.
#>
[CmdletBinding()]
param(
    [int]$MaxAgeDays = 14,
    [switch]$DryRun,
    [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$helpers = Join-Path $PSScriptRoot 'RemicsDev-InboxProcessing.ps1'
if (-not (Test-Path $helpers)) { throw "Missing $helpers" }
. $helpers

$PrimaryRoot = 'D:\updates\primary'
$EsInbox = Join-Path $PrimaryRoot 'UnprocessedESFiles'
$AdminDir = 'D:\inetpub\fcsa\admin'
$ValidateCachePath = Join-Path $AdminDir 'update-pipeline\validate-cache.json'
$cutoff = (Get-Date).AddDays(-1 * $MaxAgeDays)

function Load-ValidateCacheFiles {
    if (-not (Test-Path $ValidateCachePath)) { return @{} }
    try {
        $root = Get-Content $ValidateCachePath -Raw | ConvertFrom-Json
        $files = @{}
        if ($root.files) {
            foreach ($prop in $root.files.PSObject.Properties) {
                $files[$prop.Name] = @{
                    ok = ($prop.Value.ok -eq $true)
                }
            }
        }
        return $files
    }
    catch {
        Write-Warning "Could not read validate-cache: $($_.Exception.Message)"
        return @{}
    }
}

function Parse-StagingMeta {
    param([string]$FileName, [string]$DirectoryPath)
    $filetype = if ($DirectoryPath -match 'UnprocessedESFiles') { 'ES' } else { 'TS' }
    if ($FileName -match '^([A-Za-z0-9]+)_(\d{10})_(.+)\.txt$') {
        return @{ submitter = $Matches[1]; pdf_name = $Matches[3]; file_type = $filetype }
    }
    if ($FileName -match '^([A-Za-z0-9_]{1,16})\.txt$') {
        return @{ submitter = ''; pdf_name = $Matches[1]; file_type = $filetype }
    }
    return $null
}

$validateFiles = Load-ValidateCacheFiles
$moved = @()
$skipped = @()
$errors = @()

$dirs = @(
    @{ path = $PrimaryRoot; type = 'TS' },
    @{ path = $EsInbox; type = 'ES' }
)

foreach ($entry in $dirs) {
    if (-not (Test-Path $entry.path)) { continue }
    foreach ($fi in Get-ChildItem $entry.path -Filter '*.txt' -File) {
        $name = $fi.Name
        $reason = $null

        if ($fi.LastWriteTime -gt $cutoff) {
            $reason = 'too_recent'
        }
        elseif (-not (Test-InboxFileHasErrorSignal -StagingFile $name -ValidateCacheFiles $validateFiles)) {
            $reason = 'no_error_signal'
        }
        else {
            $skip = Get-InboxProcessingQueueSkipReason -StagingFile $name
            if ($skip) { $reason = $skip }
        }

        if ($reason) {
            $skipped += @{ file = $name; path = $fi.FullName; reason = $reason }
            continue
        }

        $meta = Parse-StagingMeta -FileName $name -DirectoryPath $fi.DirectoryName
        $jobId = [guid]::NewGuid().ToString('N')
        $destDir = Join-Path (Join-Path $PrimaryRoot 'failed') ("stale-{0:yyyyMMdd}" -f (Get-Date))
        $destDir = Join-Path $destDir $jobId
        $destPath = Join-Path $destDir $name

        try {
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path $destDir | Out-Null
                Move-Item -LiteralPath $fi.FullName -Destination $destPath -Force
                if ($meta) {
                    Register-InboxProcessingRow -StagingFile $name -FileType $meta.file_type `
                        -LifecycleStatus 'stale_archived' -Source 'stale_cleanup' `
                        -Submitter $meta.submitter -PdfName $meta.pdf_name -JobId $jobId `
                        -CurrentPath $destPath -ArchiveDir $destDir -ErrorYn $true `
                        -ErrorMessage 'Stale inbox error archive'
                }
            }
            $moved += @{
                file = $name
                from = $fi.FullName
                to = $destPath
                job_id = $jobId
                dry_run = [bool]$DryRun
            }
        }
        catch {
            $errors += @{ file = $name; error = $_.Exception.Message }
        }
    }
}

$result = @{
    ok = ($errors.Count -eq 0)
    dry_run = [bool]$DryRun
    max_age_days = $MaxAgeDays
    cutoff_local = $cutoff.ToString('o')
    moved = $moved
    skipped = $skipped
    errors = $errors
    summary = if ($DryRun) {
        "Dry run: $($moved.Count) would move, $($skipped.Count) skipped"
    } else {
        "Moved $($moved.Count) stale error file(s), skipped $($skipped.Count)"
    }
    completed_utc = (Get-Date).ToUniversalTime().ToString('o')
}

if ($ResultPath) {
    $dir = Split-Path $ResultPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $result | ConvertTo-Json -Depth 8 | Set-Content -Path $ResultPath -Encoding UTF8
}

Write-Output ($result | ConvertTo-Json -Depth 8 -Compress)
if (-not $result.ok) { exit 1 }
exit 0
