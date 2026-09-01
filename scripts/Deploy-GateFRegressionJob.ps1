#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy Gate F regression DDL + SQL Agent job (nightly + email on failure).

.DESCRIPTION
    Creates web.gate_f_regression_* tables, web.RunGateFRegression, web.SendGateFAlert,
    and SQL Agent job "RemIcs Gate F Regression":
      Step 1 (TSQL): SQL checks + email FCSA team on issues
      Step 2 (CmdExec): HTTP TSIP isolation per test roster

.PARAMETER SkipJob
    Deploy DDL/proc only.

.PARAMETER RepoRoot
    Path to CentralProject on the SQL Agent server (for PowerShell job step).
#>
[CmdletBinding()]
param(
    [switch]$SkipJob,
    [string]$RepoRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path $PSScriptRoot -Parent
}

$InvokeSql = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$LogDdl = Join-Path $RepoRoot 'docs\remicsdev\ddl\web.gate_f_regression_log.sql'
$ProcDdl = Join-Path $RepoRoot 'docs\remicsdev\ddl\web.RunGateFRegression.sql'
$JobSqlFile = Join-Path $RepoRoot 'docs\remicsdev\gate-f-regression-agent-job.sql'
$HttpScript = Join-Path $RepoRoot 'scripts\Invoke-GateFRegressionTest.ps1'
$JobName = 'RemIcs Gate F Regression'
$StepSql = 'Gate F SQL checks'
$StepHttp = 'Gate F HTTP isolation'
$ScheduleName = 'Nightly 0315 local'
$TempSql = Join-Path $env:TEMP 'deploy-gate-f-regression-job.sql'

Write-Host "=== Gate F log tables ==="
& $InvokeSql -InputFile $LogDdl

Write-Host "=== Gate F procedures ==="
& $InvokeSql -InputFile $ProcDdl

if ($SkipJob) {
    Write-Host "=== SkipJob set; DDL/proc only ==="
    return
}

$jobCommand = (Get-Content $JobSqlFile -Raw).Trim()
$escapedSql = $jobCommand.Replace("'", "''")
$httpCmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $HttpScript + '" -HttpOnly -SendEmailOnFailure -Quiet'
$escapedHttp = $httpCmd.Replace("'", "''")

$checkOut = & $InvokeSql -Query "SET NOCOUNT ON; SELECT CAST(COUNT(*) AS VARCHAR(10)) FROM msdb.dbo.sysjobs WHERE name = N'$JobName';"
$jobExists = ($checkOut -match '\|\s*1\s*\|') -or ($checkOut -match '(?m)^\s*1\s*$')

if ($jobExists) {
    Write-Host "=== Updating existing Gate F job ==="
    @"
EXEC msdb.dbo.sp_update_job
    @job_name = N'$JobName',
    @enabled = 1,
    @description = N'remicsdev: RemIcsReWrite Gate F nightly regression (SQL + HTTP); emails FCSA team on failure';

EXEC msdb.dbo.sp_update_jobstep
    @job_name = N'$JobName',
    @step_id = 1,
    @step_name = N'$StepSql',
    @subsystem = N'TSQL',
    @database_name = N'remicsdev',
    @command = N'$escapedSql',
    @on_success_action = 3,
    @on_fail_action = 2;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobsteps WHERE job_id = (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = N'$JobName') AND step_id = 2)
    EXEC msdb.dbo.sp_update_jobstep
        @job_name = N'$JobName',
        @step_id = 2,
        @step_name = N'$StepHttp',
        @subsystem = N'CmdExec',
        @command = N'$escapedHttp',
        @on_success_action = 1,
        @on_fail_action = 2;
ELSE
    EXEC msdb.dbo.sp_add_jobstep
        @job_name = N'$JobName',
        @step_name = N'$StepHttp',
        @step_id = 2,
        @subsystem = N'CmdExec',
        @command = N'$escapedHttp',
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
        @active_start_time = 31500;
END
ELSE
BEGIN
    EXEC msdb.dbo.sp_update_schedule
        @name = @schedName,
        @enabled = 1,
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 1,
        @active_start_time = 31500;
END
"@ | Set-Content -Path $TempSql -Encoding UTF8
} else {
    Write-Host "=== Creating Gate F SQL Agent job ==="
    @"
EXEC msdb.dbo.sp_add_job
    @job_name = N'$JobName',
    @enabled = 1,
    @description = N'remicsdev: RemIcsReWrite Gate F nightly regression (SQL + HTTP); emails FCSA team on failure';

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'$JobName',
    @step_name = N'$StepSql',
    @step_id = 1,
    @subsystem = N'TSQL',
    @database_name = N'remicsdev',
    @command = N'$escapedSql',
    @on_success_action = 3,
    @on_fail_action = 2;

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'$JobName',
    @step_name = N'$StepHttp',
    @step_id = 2,
    @subsystem = N'CmdExec',
    @command = N'$escapedHttp',
    @on_success_action = 1,
    @on_fail_action = 2;

EXEC msdb.dbo.sp_add_jobschedule
    @job_name = N'$JobName',
    @name = N'$ScheduleName',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 1,
    @active_start_time = 31500;

EXEC msdb.dbo.sp_add_jobserver @job_name = N'$JobName';
"@ | Set-Content -Path $TempSql -Encoding UTF8
}

& $InvokeSql -InputFile $TempSql
Remove-Item $TempSql -Force -ErrorAction SilentlyContinue
Write-Host "=== Done. Job: $JobName (nightly 03:15 local) ==="
Write-Host "Manual: .\scripts\Invoke-GateFRegressionTest.ps1"
Write-Host "On-demand SQL: EXEC web.RunGateFRegression @SendEmail=0, @FailJobOnIssues=0;"
