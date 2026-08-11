#Requires -Version 5.1
<#
.SYNOPSIS
    Registry helpers for adm.t_InboxProcessing_local (non-blocking audit layer).
#>
Set-StrictMode -Version Latest

$script:InboxProcessingRepoRoot = if ($PSScriptRoot) {
    (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
} else {
    'E:\AIProjects\CentralProject'
}
$script:InboxProcessingSqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$script:InboxProcessingCachePath = 'D:\inetpub\fcsa\admin\update-pipeline\registry-cache.json'

function Get-InboxProcessingTable {
    $webConfig = 'D:\inetpub\remicsdev\mics\web.config'
    if (Test-Path $webConfig) {
        try {
            [xml]$xml = Get-Content $webConfig
            $node = $xml.configuration.appSettings.add | Where-Object { $_.key -eq 'InboxProcessingTable' } | Select-Object -First 1
            if ($node -and -not [string]::IsNullOrWhiteSpace($node.value)) {
                return $node.value.Trim()
            }
        } catch { }
    }
    return 'adm.t_InboxProcessing_local'
}

function Escape-InboxSql {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return $Value.Replace("'", "''")
}

function Invoke-InboxProcessingSql {
    param([string]$Query)
    if (-not (Test-Path $script:InboxProcessingSqlScript)) {
        Write-Warning "InboxProcessing: SQL helper missing"
        return $null
    }
    try {
        return & $script:InboxProcessingSqlScript -Query $Query 2>&1 | Out-String
    }
    catch {
        Write-Warning "InboxProcessing SQL failed: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-InboxProcessingNonQuery {
    param([string]$Query)
    if ([string]::IsNullOrWhiteSpace($Query)) { return }
    Invoke-InboxProcessingSql -Query $Query | Out-Null
}

function Write-InboxProcessingCache {
    $table = Get-InboxProcessingTable
    $raw = Invoke-InboxProcessingSql -Query @"
SET NOCOUNT ON;
SELECT TOP 50
    processing_id, file_type, staging_file, lifecycle_status, error_yn,
    queue_id, job_id, submitter, pdf_name, failed_step, [source],
    CONVERT(VARCHAR(23), created, 126) AS created,
    CONVERT(VARCHAR(23), completed, 126) AS completed
FROM $table
ORDER BY processing_id DESC;
"@
    if (-not $raw) { return }
    $lines = @($raw -split "`r?`n" | Where-Object {
        $_ -and $_ -notmatch '^---' -and $_ -notmatch '^-+$' -and $_ -notmatch '^\(' -and $_ -notmatch 'rows affected'
    })
    if ($lines.Count -lt 2) { return }
    $headers = @($lines[0] -split '\|' | ForEach-Object { $_.Trim() })
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^-+$') { continue }
        $parts = @($lines[$i] -split '\|')
        if ($parts.Count -lt $headers.Count) { continue }
        $obj = @{}
        for ($ci = 0; $ci -lt $headers.Count; $ci++) {
            $obj[$headers[$ci]] = $parts[$ci].Trim()
        }
        $rows += $obj
    }
    $payload = @{
        ok = $true
        updated_utc = (Get-Date).ToUniversalTime().ToString('o')
        rows = $rows
    }
    $dir = Split-Path $script:InboxProcessingCachePath -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    try {
        $payload | ConvertTo-Json -Depth 6 | Set-Content -Path $script:InboxProcessingCachePath -Encoding UTF8
    } catch {
        Write-Warning "InboxProcessing cache write failed: $($_.Exception.Message)"
    }
}

function Register-InboxProcessingRow {
    param(
        [Parameter(Mandatory)]
        [string]$StagingFile,
        [Parameter(Mandatory)]
        [string]$FileType,
        [Parameter(Mandatory)]
        [string]$LifecycleStatus,
        [Parameter(Mandatory)]
        [string]$Source,
        [string]$Submitter = '',
        [string]$PdfName = '',
        [int]$QueueId = 0,
        [string]$JobId = '',
        [string]$InboxPath = '',
        [string]$CurrentPath = '',
        [string]$Mode = '',
        [string]$ExecutionUser = 'fwmda',
        [string]$ValidatedCode = '',
        [bool]$ErrorYn = $false,
        [string]$ErrorMessage = '',
        [string]$FailedStep = '',
        [string]$ArchiveDir = ''
    )
    $table = Get-InboxProcessingTable
    $sf = Escape-InboxSql $StagingFile
    $ft = Escape-InboxSql $FileType
    $ls = Escape-InboxSql $LifecycleStatus
    $src = Escape-InboxSql $Source
    $sub = Escape-InboxSql $Submitter
    $pdf = Escape-InboxSql $PdfName
    $jobSql = if ([string]::IsNullOrWhiteSpace($JobId)) { 'NULL' } else { "'$(Escape-InboxSql $JobId)'" }
    $queueSql = if ($QueueId -gt 0) { "$QueueId" } else { 'NULL' }
    $inboxSql = if ([string]::IsNullOrWhiteSpace($InboxPath)) { 'NULL' } else { "'$(Escape-InboxSql $InboxPath)'" }
    $curSql = if ([string]::IsNullOrWhiteSpace($CurrentPath)) { 'NULL' } else { "'$(Escape-InboxSql $CurrentPath)'" }
    $modeSql = if ([string]::IsNullOrWhiteSpace($Mode)) { 'NULL' } else { "'$(Escape-InboxSql $Mode)'" }
    $execSql = if ([string]::IsNullOrWhiteSpace($ExecutionUser)) { 'NULL' } else { "'$(Escape-InboxSql $ExecutionUser)'" }
    $valSql = if ([string]::IsNullOrWhiteSpace($ValidatedCode)) { 'NULL' } else { "'$(Escape-InboxSql $ValidatedCode)'" }
    $errSql = if ([string]::IsNullOrWhiteSpace($ErrorMessage)) { 'NULL' } else { "'$(Escape-InboxSql $ErrorMessage)'" }
    $stepSql = if ([string]::IsNullOrWhiteSpace($FailedStep)) { 'NULL' } else { "'$(Escape-InboxSql $FailedStep)'" }
    $archSql = if ([string]::IsNullOrWhiteSpace($ArchiveDir)) { 'NULL' } else { "'$(Escape-InboxSql $ArchiveDir)'" }
    $errBit = if ($ErrorYn) { 1 } else { 0 }
    $startedSet = if ($LifecycleStatus -eq 'processing') { ', started = COALESCE(started, GETDATE())' } else { '' }

    Invoke-InboxProcessingNonQuery -Query @"
SET QUOTED_IDENTIFIER ON;
IF EXISTS (
    SELECT 1 FROM $table
    WHERE staging_file = '$sf' AND lifecycle_status IN ('inbox','queued','processing')
)
BEGIN
    UPDATE $table SET
        file_type = '$ft',
        lifecycle_status = '$ls',
        submitter = NULLIF('$sub',''),
        pdf_name = NULLIF('$pdf',''),
        queue_id = COALESCE($queueSql, queue_id),
        job_id = COALESCE($jobSql, job_id),
        inbox_path = COALESCE($inboxSql, inbox_path),
        current_path = COALESCE($curSql, current_path),
        archive_dir = COALESCE($archSql, archive_dir),
        [mode] = COALESCE($modeSql, [mode]),
        execution_user = COALESCE($execSql, execution_user),
        validated_code = COALESCE($valSql, validated_code),
        error_yn = CASE WHEN $errBit = 1 THEN 1 ELSE error_yn END,
        error_message = COALESCE($errSql, error_message),
        failed_step = COALESCE($stepSql, failed_step),
        [source] = '$src'
        $startedSet
    WHERE staging_file = '$sf' AND lifecycle_status IN ('inbox','queued','processing');
END
ELSE
BEGIN
    INSERT INTO $table (
        file_type, processing_kind, staging_file, submitter, pdf_name, queue_id, job_id,
        lifecycle_status, validated_code, error_yn, error_message, failed_step,
        inbox_path, current_path, archive_dir, [mode], execution_user, [source], started
    ) VALUES (
        '$ft', 'dbupdate', '$sf', NULLIF('$sub',''), NULLIF('$pdf',''), $queueSql, $jobSql,
        '$ls', $valSql, $errBit, $errSql, $stepSql,
        $inboxSql, $curSql, $archSql, $modeSql, $execSql, '$src',
        CASE WHEN '$ls' = 'processing' THEN GETDATE() ELSE NULL END
    );
END
"@
    Write-InboxProcessingCache
}

function Complete-InboxProcessingRow {
    param(
        [Parameter(Mandatory)]
        [string]$StagingFile,
        [Parameter(Mandatory)]
        [string]$LifecycleStatus,
        [string]$JobId = '',
        [string]$ValidatedCode = '',
        [bool]$ErrorYn = $false,
        [string]$ErrorMessage = '',
        [string]$FailedStep = '',
        [string]$ArchiveDir = '',
        [string]$CurrentPath = '',
        [string]$Source = ''
    )
    $table = Get-InboxProcessingTable
    $sf = Escape-InboxSql $StagingFile
    $ls = Escape-InboxSql $LifecycleStatus
    $jobFilter = if ([string]::IsNullOrWhiteSpace($JobId)) { '' } else { " AND (job_id = '$(Escape-InboxSql $JobId)' OR job_id IS NULL)" }
    $valSet = if ([string]::IsNullOrWhiteSpace($ValidatedCode)) {
        'validated_code = validated_code'
    } else {
        "validated_code = '$(Escape-InboxSql $ValidatedCode)'"
    }
    $errSet = if ([string]::IsNullOrWhiteSpace($ErrorMessage)) {
        'error_message = error_message'
    } else {
        "error_message = '$(Escape-InboxSql $ErrorMessage)'"
    }
    $stepSet = if ([string]::IsNullOrWhiteSpace($FailedStep)) {
        'failed_step = failed_step'
    } else {
        "failed_step = '$(Escape-InboxSql $FailedStep)'"
    }
    $archSet = if ([string]::IsNullOrWhiteSpace($ArchiveDir)) {
        'archive_dir = archive_dir'
    } else {
        "archive_dir = '$(Escape-InboxSql $ArchiveDir)'"
    }
    $curSet = if ([string]::IsNullOrWhiteSpace($CurrentPath)) {
        'current_path = current_path'
    } else {
        "current_path = '$(Escape-InboxSql $CurrentPath)'"
    }
    $srcSet = if ([string]::IsNullOrWhiteSpace($Source)) { '' } else { ", [source] = '$(Escape-InboxSql $Source)'" }
    $errBit = if ($ErrorYn) { 1 } else { 0 }
    $completedSet = if ($LifecycleStatus -in @('completed', 'failed', 'stale_archived')) {
        ', completed = COALESCE(completed, GETDATE())'
    } else { '' }
    $archivedSet = if ($LifecycleStatus -eq 'stale_archived') {
        ', archived = COALESCE(archived, GETDATE())'
    } else { '' }

    Invoke-InboxProcessingNonQuery -Query @"
SET QUOTED_IDENTIFIER ON;
UPDATE $table SET
    lifecycle_status = '$ls',
    job_id = COALESCE(NULLIF('$(Escape-InboxSql $JobId)',''), job_id),
    $valSet,
    error_yn = CASE WHEN $errBit = 1 THEN 1 ELSE error_yn END,
    $errSet,
    $stepSet,
    $archSet,
    $curSet
    $srcSet
    $completedSet
    $archivedSet
WHERE staging_file = '$sf'
  AND lifecycle_status IN ('inbox','queued','processing','completed','failed')
  $jobFilter;
"@
    Write-InboxProcessingCache
}

function Get-InboxProcessingQueueSkipReason {
    param(
        [Parameter(Mandatory)]
        [string]$StagingFile
    )
    $table = Get-InboxProcessingTable
    $UpdateQueueTable = 'adm.t_UpdateQueue_local'
    $sf = Escape-InboxSql $StagingFile
    $q = Invoke-InboxProcessingSql -Query @"
SET NOCOUNT ON;
SELECT TOP 1 [status] AS st FROM $UpdateQueueTable
WHERE staging_file = '$sf' AND [status] IN ('N','P')
ORDER BY queue_id DESC;
"@
    if ($q -and $q -match '\|\s*([NP])\s*') { return 'queue_active' }
    if ($q -match '(?m)^\s*([NP])\s*$') { return 'queue_active' }

    $r = Invoke-InboxProcessingSql -Query @"
SET NOCOUNT ON;
SELECT TOP 1 lifecycle_status AS st FROM $table
WHERE staging_file = '$sf' AND lifecycle_status IN ('queued','processing')
ORDER BY processing_id DESC;
"@
    if ($r -and $r -match 'processing') { return 'registry_processing' }
    if ($r -and $r -match 'queued') { return 'registry_queued' }
    return $null
}

function Test-InboxFileHasErrorSignal {
    param(
        [Parameter(Mandatory)]
        [string]$StagingFile,
        [hashtable]$ValidateCacheFiles = $null
    )
    if ($ValidateCacheFiles -and $ValidateCacheFiles.ContainsKey($StagingFile)) {
        $entry = $ValidateCacheFiles[$StagingFile]
        if ($entry -is [hashtable]) {
            if ($entry.ContainsKey('ok') -and -not $entry['ok']) { return $true }
        }
        elseif ($entry.ok -eq $false) { return $true }
    }
    $UpdateQueueTable = 'adm.t_UpdateQueue_local'
    $sf = Escape-InboxSql $StagingFile
    $table = Get-InboxProcessingTable
    $q = Invoke-InboxProcessingSql -Query @"
SET NOCOUNT ON;
SELECT TOP 1 [status] AS st FROM $UpdateQueueTable
WHERE staging_file = '$sf'
ORDER BY queue_id DESC;
"@
    if ($q -match '\|\s*E\s*' -or $q -match '(?m)^\s*E\s*$') { return $true }

    $r = Invoke-InboxProcessingSql -Query @"
SET NOCOUNT ON;
SELECT TOP 1 error_yn AS ey FROM $table
WHERE staging_file = '$sf' AND lifecycle_status = 'inbox' AND error_yn = 1
ORDER BY processing_id DESC;
"@
    if ($r -match '\|\s*1\s*' -or $r -match '(?m)^\s*1\s*$') { return $true }
    return $false
}

function Invoke-SafeInboxRegistry {
    param([scriptblock]$Action)
    try {
        & $Action
    }
    catch {
        Write-Warning "InboxProcessing registry skipped: $($_.Exception.Message)"
    }
}
