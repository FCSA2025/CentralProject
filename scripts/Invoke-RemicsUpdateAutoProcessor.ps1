#Requires -Version 5.1
<#
.SYNOPSIS
    Process pending rows in adm.t_UpdateQueue_local via fwmda DbUpdate pipeline.

.DESCRIPTION
    Called by SQL Agent job "Update Queue Local" on IIS-REMICS-PROD (local or remote Invoke-Command).
    On success emails submitter; on failure emails UpdateQueueFailureNotify (jscott@fcsa.ca during testing).
    Notifications INSERT into adm.t_EmailQueue_local for the existing Email Queue Local job.

.PARAMETER MaxFiles
    Max queue rows to process per invocation (default 1).

.PARAMETER StaleLockMinutes
    Reset status P rows older than this back to N (default 30).
#>
[CmdletBinding()]
param(
    [int]$MaxFiles = 1,
    [int]$StaleLockMinutes = 30,
    [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$pipelineScript = Join-Path $PSScriptRoot 'Invoke-RemicsUpdatePipeline.ps1'
$inboxHelpers = Join-Path $PSScriptRoot 'RemicsDev-InboxProcessing.ps1'
if (Test-Path $inboxHelpers) { . $inboxHelpers }
$PrimaryRoot = 'D:\updates\primary'
$EsInbox = Join-Path $PrimaryRoot 'UnprocessedESFiles'
$AutoLogDir = 'D:\inetpub\fcsa\admin\update-pipeline\auto'
$UpdateQueueTable = 'adm.t_UpdateQueue_local'
$EmailQueueTable = 'adm.t_EmailQueue_local'
$MailFrom = 'mics@fcsa.ca'

function Get-EnvLocalValue {
    param([string]$Key)
    $envFile = Join-Path $RepoRoot '.env.local'
    if (-not (Test-Path $envFile)) { return $null }
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.+?)\s*$") {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

function Get-ConfigValue {
    param([string]$Key, [string]$Default = '')
    $v = [Environment]::GetEnvironmentVariable($Key)
    if (-not [string]::IsNullOrWhiteSpace($v)) { return $v.Trim() }
    $v = Get-EnvLocalValue -Key $Key
    if (-not [string]::IsNullOrWhiteSpace($v)) { return $v.Trim() }
    $webConfig = 'D:\inetpub\remicsdev\mics\web.config'
    if (Test-Path $webConfig) {
        try {
            [xml]$xml = Get-Content $webConfig
            $node = $xml.configuration.appSettings.add | Where-Object { $_.key -eq $Key } | Select-Object -First 1
            if ($node -and -not [string]::IsNullOrWhiteSpace($node.value)) { return $node.value.Trim() }
        } catch { /* ignore */ }
    }
    return $Default
}

function Resolve-NotificationRecipient {
    param(
        [string]$OriginalTo,
        [string]$Body
    )
    $redirect = Get-ConfigValue -Key 'EmailRedirectAllTo' -Default ''
    if ([string]::IsNullOrWhiteSpace($redirect)) {
        return @{ To = $OriginalTo; Body = $Body }
    }
    $newBody = $Body + "`n`n[Testing redirect - original recipient: " + $OriginalTo + "]"
    return @{ To = $redirect; Body = $newBody }
}

function Escape-Sql {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return $Value.Replace("'", "''")
}

function Invoke-SqlNonQuery {
    param([string]$Query)
    & $sqlScript -Query $Query | Out-Null
}

function Invoke-SqlRows {
    param([string]$Query)
    $raw = & $sqlScript -Query $Query
    $rows = @()
    $headers = $null
    foreach ($line in ($raw -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^-+\|-+' -or $line -match '^-+$') { continue }
        $parts = @($line -split '\|' | ForEach-Object { $_.Trim() })
        if (-not $headers) {
            $headers = $parts
            continue
        }
        if ($parts.Count -lt $headers.Count) { continue }
        $row = @{}
        for ($i = 0; $i -lt $headers.Count; $i++) {
            $row[$headers[$i]] = $parts[$i]
        }
        $rows += [pscustomobject]$row
    }
    return @($rows)
}

function Test-UpdateQueueSubmitterAllowed {
    param([string]$Submitter)
    $list = Get-ConfigValue -Key 'UpdateQueueAllowedSubmitters' -Default ''
    if ([string]::IsNullOrWhiteSpace($list) -or $list.Trim() -eq '*') {
        return -not [string]::IsNullOrWhiteSpace($Submitter)
    }
    if ([string]::IsNullOrWhiteSpace($Submitter)) { return $false }
    $allowed = @($list.Split(',', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() })
    return ($allowed -contains $Submitter)
}

function Get-AllowedSubmitters {
    $list = Get-ConfigValue -Key 'UpdateQueueAllowedSubmitters' -Default ''
    if ([string]::IsNullOrWhiteSpace($list) -or $list.Trim() -eq '*') { return @('*') }
    return @($list.Split(',', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-FailureNotifyEmail {
    return Get-ConfigValue -Key 'UpdateQueueFailureNotify' -Default 'jscott@fcsa.ca'
}

function Parse-StagingFileName {
    param([string]$FileName, [string]$DirectoryPath)
    $filetype = if ($DirectoryPath -match 'UnprocessedESFiles') { 'ES' } else { 'TS' }
    if ($FileName -match '^([A-Za-z0-9]+)_(\d{10})_(.+)\.txt$') {
        return @{
            submitter = $Matches[1]
            pdf_name  = $Matches[3]
            file_type = $filetype
        }
    }
    if ($FileName -match '^([A-Za-z0-9_]{1,16})\.txt$') {
        $stem = $Matches[1]
        return @{
            submitter = $stem
            pdf_name  = $stem
            file_type = $filetype
        }
    }
    return $null
}

function Queue-NotificationEmail {
    param(
        [string]$To,
        [string]$Subject,
        [string]$Body
    )
    if ([string]::IsNullOrWhiteSpace($To)) { return }
    $resolved = Resolve-NotificationRecipient -OriginalTo $To -Body $Body
    $To = $resolved.To
    $Body = $resolved.Body
    $q = @"
INSERT INTO $EmailQueueTable (mailFrom, mailTo, mailCC, mailSubject, mailBody, mailBodyFormat, mailAttachments, sentYN)
VALUES ('$(Escape-Sql $MailFrom)', '$(Escape-Sql $To)', NULL, '$(Escape-Sql $Subject)', '$(Escape-Sql $Body)', 'TEXT', NULL, 'N');
"@
    Invoke-SqlNonQuery -Query $q
}

function Enqueue-InboxSafetyNet {
    $dirs = @(
        @{ dir = $PrimaryRoot; type = 'TS' },
        @{ dir = $EsInbox; type = 'ES' }
    )
    foreach ($entry in $dirs) {
        if (-not (Test-Path $entry.dir)) { continue }
        foreach ($fi in Get-ChildItem $entry.dir -Filter '*.txt' -File) {
            $meta = Parse-StagingFileName -FileName $fi.Name -DirectoryPath $entry.dir
            if (-not $meta) { continue }
            if (-not (Test-UpdateQueueSubmitterAllowed -Submitter $meta.submitter)) { continue }
            $exists = @(Invoke-SqlRows -Query @"
SET NOCOUNT ON;
SELECT COUNT(*) AS cnt FROM $UpdateQueueTable
WHERE staging_file = '$(Escape-Sql $fi.Name)' AND [status] IN ('N','P','Y');
"@)
            if ($exists.Count -gt 0 -and [int]$exists[0].cnt -gt 0) { continue }
            $emailRow = @(Invoke-SqlRows -Query @"
SET NOCOUNT ON;
SELECT TOP 1 RTRIM(email) AS email FROM adm.account_details
WHERE RTRIM(micsid) = '$(Escape-Sql $meta.submitter)';
"@)
            $email = if ($emailRow.Count -gt 0 -and $emailRow[0].email) { [string]$emailRow[0].email } else { '' }
            $mode = Get-ConfigValue -Key 'UpdateQueueMode' -Default 'spoof-first'
            Invoke-SqlNonQuery -Query @"
INSERT INTO $UpdateQueueTable (staging_file, staging_path, submitter, pdf_name, file_type, submitter_email, [status], [mode])
VALUES ('$(Escape-Sql $fi.Name)', '$(Escape-Sql $fi.FullName)', '$(Escape-Sql $meta.submitter)', '$(Escape-Sql $meta.pdf_name)', '$(Escape-Sql $meta.file_type)', $(if ($email) { "'$(Escape-Sql $email)'" } else { 'NULL' }), 'N', '$(Escape-Sql $mode)');
"@
        }
    }
}

function Reset-StaleLocks {
    Invoke-SqlNonQuery -Query @"
UPDATE $UpdateQueueTable
SET [status] = 'N', ErrorMsg = ISNULL(ErrorMsg,'') + '; stale lock reset'
WHERE [status] = 'P'
  AND DATEDIFF(MINUTE, Created, GETDATE()) >= $StaleLockMinutes
  AND (Processed IS NULL OR DATEDIFF(MINUTE, Processed, GETDATE()) >= $StaleLockMinutes);
"@
}

function Get-PendingRows {
    param([int]$Limit)
    return @(Invoke-SqlRows -Query @"
SET NOCOUNT ON;
SELECT TOP ($Limit)
    queue_id, staging_file, staging_path, submitter, pdf_name, file_type,
    submitter_email, [mode]
FROM $UpdateQueueTable
WHERE [status] = 'N'
ORDER BY queue_id ASC;
"@)
}

function Claim-Row {
    param([int]$QueueId)
    Invoke-SqlNonQuery -Query @"
UPDATE $UpdateQueueTable
SET [status] = 'P', AttemptCount = AttemptCount + 1, Processed = GETDATE()
WHERE queue_id = $QueueId AND [status] = 'N';
"@
    $check = @(Invoke-SqlRows -Query "SELECT [status] AS s FROM $UpdateQueueTable WHERE queue_id = $QueueId;")
    return ($check.Count -gt 0 -and $check[0].s -eq 'P')
}

function Complete-Row {
    param(
        [int]$QueueId,
        [string]$Status,
        [string]$JobId,
        [string]$ErrorMsg
    )
    $errSql = if ([string]::IsNullOrWhiteSpace($ErrorMsg)) { 'NULL' } else { "'$(Escape-Sql $ErrorMsg)'" }
    $jobSql = if ([string]::IsNullOrWhiteSpace($JobId)) { 'NULL' } else { "'$(Escape-Sql $JobId)'" }
    Invoke-SqlNonQuery -Query @"
UPDATE $UpdateQueueTable
SET [status] = '$Status', job_id = $jobSql, ErrorMsg = $errSql, Processed = GETDATE()
WHERE queue_id = $QueueId;
"@
}

function Get-ModeArgs {
    param([string]$Mode)
    switch ($Mode) {
        'main-only' { return @('-MainOnly') }
        'spoof-only' { return @('-SpoofOnly') }
        default { return @('-SpoofFirst') }
    }
}

function Write-RunJson {
    param([object]$Payload)
    if (-not $ResultPath) { return }
    $dir = Split-Path $ResultPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $Payload | ConvertTo-Json -Depth 8 | Set-Content -Path $ResultPath -Encoding UTF8
}

if (-not (Test-Path $sqlScript)) { throw "SQL helper missing: $sqlScript" }
if (-not (Test-Path $pipelineScript)) { throw "Pipeline script missing: $pipelineScript" }
if (-not (Test-Path $AutoLogDir)) { New-Item -ItemType Directory -Force -Path $AutoLogDir | Out-Null }

$runId = [guid]::NewGuid().ToString('N')
if (-not $ResultPath) { $ResultPath = Join-Path $AutoLogDir ("run_{0}.json" -f $runId) }

$run = @{
    ok = $true
    run_id = $runId
    started_utc = (Get-Date).ToUniversalTime().ToString('o')
    processed = @()
}

try {
    Reset-StaleLocks
    Enqueue-InboxSafetyNet

    $pending = @(Get-PendingRows -Limit $MaxFiles)
    if ($pending.Count -lt 1) {
        $run.summary = 'No pending update queue rows'
        Write-RunJson -Payload $run
        Write-Output ($run | ConvertTo-Json -Depth 6 -Compress)
        exit 0
    }

    foreach ($row in $pending) {
        $queueId = [int]$row.queue_id
        if (-not (Claim-Row -QueueId $queueId)) { continue }

        if (Get-Command Invoke-SafeInboxRegistry -ErrorAction SilentlyContinue) {
            Invoke-SafeInboxRegistry {
                Register-InboxProcessingRow -StagingFile [string]$row.staging_file `
                    -FileType [string]$row.file_type -LifecycleStatus 'queued' `
                    -Source 'auto_queue' -Submitter [string]$row.submitter `
                    -PdfName [string]$row.pdf_name -QueueId $queueId `
                    -InboxPath [string]$row.staging_path -CurrentPath [string]$row.staging_path `
                    -Mode [string]$row.mode
            }
        }

        $item = @{
            queue_id = $queueId
            staging_file = [string]$row.staging_file
            ok = $false
        }

        if (-not (Test-Path -LiteralPath $row.staging_path)) {
            $err = "Staging file not found: $($row.staging_path)"
            Complete-Row -QueueId $queueId -Status 'E' -JobId '' -ErrorMsg $err
            Queue-NotificationEmail -To (Get-FailureNotifyEmail) -Subject ("DbUpdate auto-processing FAILED - $($row.staging_file)") -Body @"
DbUpdate auto-processing FAILED for $($row.staging_file) (submitter $($row.submitter), PDF $($row.pdf_name)).

Error: $err
"@
            $item.error = $err
            $run.processed += $item
            continue
        }

        $jobResultPath = Join-Path $env:TEMP ("update-auto-{0}-{1}.json" -f $runId, $queueId)
        $modeArgs = Get-ModeArgs -Mode ([string]$row.mode)
        $pipeArgs = @(
            '-StagingFile', $row.staging_path,
            '-ResultPath', $jobResultPath,
            '-FileType', [string]$row.file_type,
            '-ProcessingSource', 'auto_queue',
            '-QueueId', $queueId
        ) + $modeArgs

        $pipeOk = $false
        $jobId = ''
        $archiveDir = ''
        $pipeError = ''
        try {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $pipelineScript @pipeArgs
            $pipeExit = $LASTEXITCODE
            if (Test-Path $jobResultPath) {
                $payload = Get-Content $jobResultPath -Raw | ConvertFrom-Json
                $jobId = [string]$payload.job_id
                $archiveDir = [string]$payload.archive_dir
                $pipeOk = ($payload.ok -eq $true) -and ([string]$payload.status -eq 'complete')
                if ($pipeOk -and $payload.steps) {
                    foreach ($step in @($payload.steps)) {
                        if ($null -ne $step.ok -and $step.ok -eq $false) {
                            $pipeOk = $false
                            if ([string]::IsNullOrWhiteSpace($pipeError)) {
                                $pipeError = [string]$step.message
                            }
                            break
                        }
                    }
                }
                if (-not $pipeOk -and [string]::IsNullOrWhiteSpace($pipeError)) {
                    $pipeError = [string]$payload.error
                }
                if ($pipeExit -ne 0) { $pipeOk = $false }
            } else {
                $pipeError = 'Pipeline did not write result JSON'
            }
        }
        catch {
            $pipeError = $_.Exception.Message
        }

        if ($pipeOk) {
            Complete-Row -QueueId $queueId -Status 'Y' -JobId $jobId -ErrorMsg ''
            $successTo = [string]$row.submitter_email
            if ([string]::IsNullOrWhiteSpace($successTo)) { $successTo = Get-FailureNotifyEmail }
            $body = @"
Your $($row.file_type) file $($row.pdf_name) has been processed successfully.

Staging file: $($row.staging_file)
Queue ID: $queueId
Job ID: $jobId
Mode: $($row.mode)
"@
            Queue-NotificationEmail -To $successTo -Subject ("DbUpdate complete - $($row.file_type) file $($row.pdf_name)") -Body $body
            $item.ok = $true
            $item.job_id = $jobId
        }
        else {
            if ([string]::IsNullOrWhiteSpace($pipeError)) { $pipeError = 'Pipeline failed (unknown error)' }
            Complete-Row -QueueId $queueId -Status 'E' -JobId $jobId -ErrorMsg $pipeError
            $failBody = @"
DbUpdate auto-processing FAILED for $($row.staging_file) (submitter $($row.submitter), PDF $($row.pdf_name)).

Error: $pipeError
Job ID: $jobId
Log: $archiveDir
"@
            Queue-NotificationEmail -To (Get-FailureNotifyEmail) -Subject ("DbUpdate auto-processing FAILED - $($row.staging_file)") -Body $failBody
            $item.error = $pipeError
            $item.job_id = $jobId
        }

        $run.processed += $item
    }

    $run.completed_utc = (Get-Date).ToUniversalTime().ToString('o')
    $run.summary = "Processed $($run.processed.Count) row(s)"
    Write-RunJson -Payload $run
    Write-Output ($run | ConvertTo-Json -Depth 8 -Compress)
    exit 0
}
catch {
    $run.ok = $false
    $run.error = $_.Exception.Message
    Write-RunJson -Payload $run
    Write-Output ($run | ConvertTo-Json -Depth 6 -Compress)
    exit 1
}
