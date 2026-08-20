#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy adm.t_UpdateQueue_local and SQL Agent job "Update Queue Local" on remicsdev.

.NOTES
    The Agent remoting step (Invoke-Command to IIS) fails with ANONYMOUS LOGON.
    Live trigger is the IIS scheduled task from Deploy-UpdateQueueIisTask.ps1.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path $PSScriptRoot -Parent
$DdlFile = Join-Path $RepoRoot 'docs\remicsdev\ddl\adm.t_UpdateQueue_local.sql'
$CmdFile = Join-Path $RepoRoot 'docs\remicsdev\update-queue-local-agent-job.cmd'
$InvokeSql = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$JobName = 'Update Queue Local'
$StepName = 'Process Update Queue Local'
$ScheduleName = 'Every 10 minutes local'
$ScheduleIntervalMinutes = 10
$TempSql = Join-Path $env:TEMP 'deploy-update-queue-local-job.sql'

if (-not (Test-Path $CmdFile)) { throw "Cmd file missing: $CmdFile" }

Write-Host "=== Creating table adm.t_UpdateQueue_local ==="
& $InvokeSql -InputFile $DdlFile

$jobCommand = (Get-Content $CmdFile -Raw).Trim()
$escapedCommand = $jobCommand.Replace("'", "''")

$checkOut = & $InvokeSql -Query "SET NOCOUNT ON; SELECT CAST(COUNT(*) AS VARCHAR(10)) AS cnt FROM msdb.dbo.sysjobs WHERE name = N'$JobName';"
$jobExists = ($checkOut -match '\|\s*1\s*\|') -or ($checkOut -match '^\s*1\s*$')

if ($jobExists) {
    Write-Host "=== Updating existing job step and schedule ($ScheduleIntervalMinutes min) ==="
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
        @freq_subday_type = 4,
        @freq_subday_interval = $ScheduleIntervalMinutes;
END
ELSE
BEGIN
    EXEC msdb.dbo.sp_update_schedule
        @name = @schedName,
        @enabled = 1,
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 4,
        @freq_subday_interval = $ScheduleIntervalMinutes;
END
"@ | Set-Content -Path $TempSql -Encoding UTF8
} else {
    Write-Host "=== Creating new SQL Agent job ==="
    @"
EXEC msdb.dbo.sp_add_job
    @job_name = N'$JobName',
    @enabled = 1,
    @description = N'remicsdev auto DbUpdate processor (adm.t_UpdateQueue_local)';

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
    @freq_subday_type = 4,
    @freq_subday_interval = $ScheduleIntervalMinutes;

EXEC msdb.dbo.sp_add_jobserver @job_name = N'$JobName';
"@ | Set-Content -Path $TempSql -Encoding UTF8
}

& $InvokeSql -InputFile $TempSql
Remove-Item $TempSql -Force -ErrorAction SilentlyContinue
Write-Host "=== Done. Job: $JobName on remicsdev ==="
