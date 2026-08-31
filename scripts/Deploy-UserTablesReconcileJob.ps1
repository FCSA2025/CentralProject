#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy web.ReconcileUserTables + SQL Agent job "User Tables Reconcile" on remicsdev.

.DESCRIPTION
    Creates reconcile log tables and procedure, then creates/updates a nightly
    SQL Agent job (02:30 local) that keeps web.user_tables in sync with physical
    TS (0) / ES (5) / TSIP parm (417) tables.

.PARAMETER SkipJob
    Deploy DDL/proc only; do not create or update the Agent job.
#>
[CmdletBinding()]
param(
    [switch]$SkipJob
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path $PSScriptRoot -Parent
$InvokeSql = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$LogDdl = Join-Path $RepoRoot 'docs\remicsdev\ddl\web.user_tables_reconcile_log.sql'
$ProcDdl = Join-Path $RepoRoot 'docs\remicsdev\ddl\web.ReconcileUserTables.sql'
$JobSqlFile = Join-Path $RepoRoot 'docs\remicsdev\user-tables-reconcile-agent-job.sql'
$JobName = 'User Tables Reconcile'
$StepName = 'Reconcile TS ES TSIP'
$ScheduleName = 'Nightly 0230 local'
$TempSql = Join-Path $env:TEMP 'deploy-user-tables-reconcile-job.sql'

Write-Host "=== Creating reconcile log tables ==="
& $InvokeSql -InputFile $LogDdl

Write-Host "=== Creating/altering web.ReconcileUserTables ==="
& $InvokeSql -InputFile $ProcDdl

if ($SkipJob) {
    Write-Host "=== SkipJob set; DDL/proc only ==="
    return
}

Write-Host "=== Reading job step T-SQL ==="
$jobCommand = (Get-Content $JobSqlFile -Raw).Trim()
$escapedCommand = $jobCommand.Replace("'", "''")

$checkOut = & $InvokeSql -Query "SET NOCOUNT ON; SELECT CAST(COUNT(*) AS VARCHAR(10)) AS cnt FROM msdb.dbo.sysjobs WHERE name = N'$JobName';"
$jobExists = ($checkOut -match '\|\s*1\s*\|') -or ($checkOut -match '(?m)^\s*1\s*$')

if ($jobExists) {
    Write-Host "=== Updating existing job step and schedule ==="
    @"
EXEC msdb.dbo.sp_update_job
    @job_name = N'$JobName',
    @enabled = 1,
    @description = N'remicsdev: reconcile web.user_tables vs physical TS/ES/TSIP tables';

EXEC msdb.dbo.sp_update_jobstep
    @job_name = N'$JobName',
    @step_id = 1,
    @step_name = N'$StepName',
    @subsystem = N'TSQL',
    @database_name = N'remicsdev',
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
        @enabled = 1,
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 1,
        @active_start_time = 23000;
END
ELSE
BEGIN
    EXEC msdb.dbo.sp_update_schedule
        @name = @schedName,
        @enabled = 1,
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 1,
        @active_start_time = 23000;
END
"@ | Set-Content -Path $TempSql -Encoding UTF8
} else {
    Write-Host "=== Creating new SQL Agent job ==="
    @"
EXEC msdb.dbo.sp_add_job
    @job_name = N'$JobName',
    @enabled = 1,
    @description = N'remicsdev: reconcile web.user_tables vs physical TS/ES/TSIP tables';

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'$JobName',
    @step_name = N'$StepName',
    @subsystem = N'TSQL',
    @database_name = N'remicsdev',
    @command = N'$escapedCommand',
    @on_success_action = 1,
    @on_fail_action = 2;

EXEC msdb.dbo.sp_add_jobschedule
    @job_name = N'$JobName',
    @name = N'$ScheduleName',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 1,
    @active_start_time = 23000;

EXEC msdb.dbo.sp_add_jobserver @job_name = N'$JobName';
"@ | Set-Content -Path $TempSql -Encoding UTF8
}

& $InvokeSql -InputFile $TempSql
Remove-Item $TempSql -Force -ErrorAction SilentlyContinue
Write-Host "=== Done. Job: $JobName (nightly 02:30 local) ==="
Write-Host "On-demand: .\scripts\Invoke-RemicsUserTablesReconcile.ps1"
Write-Host "After errors:  EXEC msdb.dbo.sp_start_job @job_name = N'$JobName';"
