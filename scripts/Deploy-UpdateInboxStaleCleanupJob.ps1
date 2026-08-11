#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy adm.t_InboxProcessing_local and SQL Agent job "Inbox Stale Cleanup Local".
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path $PSScriptRoot -Parent
$DdlFile = Join-Path $RepoRoot 'docs\remicsdev\ddl\adm.t_InboxProcessing_local.sql'
$CmdFile = Join-Path $RepoRoot 'docs\remicsdev\update-inbox-stale-cleanup-agent-job.cmd'
$InvokeSql = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$JobName = 'Inbox Stale Cleanup Local'
$StepName = 'Inbox stale error cleanup'
$ScheduleName = 'Daily 02:00 local'
$TempSql = Join-Path $env:TEMP 'deploy-inbox-stale-cleanup-job.sql'

if (-not (Test-Path $CmdFile)) { throw "Cmd file missing: $CmdFile" }

Write-Host "=== Creating table adm.t_InboxProcessing_local ==="
& $InvokeSql -InputFile $DdlFile

$jobCommand = (Get-Content $CmdFile -Raw).Trim()
$escapedCommand = $jobCommand.Replace("'", "''")

$checkOut = & $InvokeSql -Query "SET NOCOUNT ON; SELECT CAST(COUNT(*) AS VARCHAR(10)) AS cnt FROM msdb.dbo.sysjobs WHERE name = N'$JobName';"
$jobExists = ($checkOut -match '\|\s*1\s*\|') -or ($checkOut -match '^\s*1\s*$')

if ($jobExists) {
    Write-Host "=== Updating existing job ==="
    @"
EXEC msdb.dbo.sp_update_jobstep
    @job_name = N'$JobName',
    @step_id = 1,
    @step_name = N'$StepName',
    @subsystem = N'CmdExec',
    @command = N'$escapedCommand',
    @on_success_action = 1,
    @on_fail_action = 2;

DECLARE @schedName sysname;
SELECT TOP (1) @schedName = s.name
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
JOIN msdb.dbo.sysschedules s ON js.schedule_id = s.schedule_id
WHERE j.name = N'$JobName'
ORDER BY s.schedule_id;

IF @schedName IS NULL
BEGIN
    EXEC msdb.dbo.sp_add_jobschedule
        @job_name = N'$JobName',
        @name = N'$ScheduleName',
        @freq_type = 4,
        @freq_interval = 1,
        @active_start_time = 20000;
END
ELSE
BEGIN
    EXEC msdb.dbo.sp_update_schedule
        @name = @schedName,
        @enabled = 1,
        @freq_type = 4,
        @freq_interval = 1,
        @active_start_time = 20000;
END
"@ | Set-Content -Path $TempSql -Encoding UTF8
} else {
    Write-Host "=== Creating new SQL Agent job ==="
    @"
EXEC msdb.dbo.sp_add_job
    @job_name = N'$JobName',
    @enabled = 1,
    @description = N'remicsdev stale error inbox archive (>14 days, validate/queue error)';

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'$JobName',
    @step_name = N'$StepName',
    @subsystem = N'CmdExec',
    @command = N'$escapedCommand',
    @on_success_action = 1,
    @on_fail_action = 2;

EXEC msdb.dbo.sp_add_jobschedule
    @job_name = N'$JobName',
    @name = N'$ScheduleName',
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 20000;

EXEC msdb.dbo.sp_add_jobserver @job_name = N'$JobName';
"@ | Set-Content -Path $TempSql -Encoding UTF8
}

& $InvokeSql -InputFile $TempSql
Remove-Item $TempSql -Force -ErrorAction SilentlyContinue
Write-Host "=== Done. Job: $JobName (daily 02:00) ==="
