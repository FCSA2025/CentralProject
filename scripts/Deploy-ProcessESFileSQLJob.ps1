#Requires -Version 5.1
<#
.SYNOPSIS
    Create or replace SQL Agent job ProcessESFileSQL on remicsdev.

.DESCRIPTION
    Clone of ProcessTSFileSQL for ES files dropped in
    \\10.0.0.39\d$\updates\primary\UnprocessedESFiles (IIS inbox; SQL is on EC2AMAZ-9DKDM82).
    Uses dbo.usp_ES* on remicsdev. Skips files already queued in adm.t_UpdateQueue_local
    (N/P) so rewrite MeUpdate and this job do not steal from each other.
    Schedule: every 20 minutes (same as ProcessTSFileSQL). Step 1 fail = quit success
    when the inbox is empty.
#>
[CmdletBinding()]
param(
    [switch]$Disabled
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path $PSScriptRoot -Parent
$StepDir = Join-Path $RepoRoot 'docs\remicsdev\sql\process-es-file-sql'
$InvokeSql = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$JobName = 'ProcessESFileSQL'
$ScheduleName = 'Run Every 20  mins.'
$TempSql = Join-Path $env:TEMP 'deploy-process-es-file-sql-job.sql'
$enabled = if ($Disabled) { 0 } else { 1 }

if (-not (Test-Path $InvokeSql)) { throw "Missing $InvokeSql" }
$stepFiles = 1..8 | ForEach-Object { Join-Path $StepDir ("step{0}.sql" -f $_) }
foreach ($f in $stepFiles) {
    if (-not (Test-Path $f)) { throw "Missing step file: $f" }
}

function Get-EscapedStep {
    param([string]$Path)
    return ((Get-Content -LiteralPath $Path -Raw) -replace "'", "''")
}

Write-Host "=== Updating dbo.usp_ESSelect ==="
& $InvokeSql -Database remicsdev -InputFile (Join-Path $StepDir 'usp_ESSelect.sql')

$s1 = Get-EscapedStep $stepFiles[0]
$s2 = Get-EscapedStep $stepFiles[1]
$s3 = Get-EscapedStep $stepFiles[2]
$s4 = Get-EscapedStep $stepFiles[3]
$s5 = Get-EscapedStep $stepFiles[4]
$s6 = Get-EscapedStep $stepFiles[5]
$s7 = Get-EscapedStep $stepFiles[6]
$s8 = Get-EscapedStep $stepFiles[7]

$ddl = @"
SET NOCOUNT ON;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'$JobName')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'$JobName';
END

EXEC msdb.dbo.sp_add_job
    @job_name = N'$JobName',
    @enabled = $enabled,
    @description = N'Pure T-SQL ES file processor for \\10.0.0.39\d$\updates\primary\UnprocessedESFiles (clone of ProcessTSFileSQL).';

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'$JobName',
    @step_name = N'SelectFile',
    @step_id = 1,
    @subsystem = N'TSQL',
    @database_name = N'remicsdev',
    @command = N'$s1',
    @on_success_action = 3,
    @on_fail_action = 1,
    @on_fail_step_id = 8;

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'$JobName',
    @step_name = N'Load File Raw',
    @step_id = 2,
    @subsystem = N'TSQL',
    @database_name = N'remicsdev',
    @command = N'$s2',
    @on_success_action = 3,
    @on_fail_action = 4,
    @on_fail_step_id = 8;

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'$JobName',
    @step_name = N'Import Data',
    @step_id = 3,
    @subsystem = N'TSQL',
    @database_name = N'remicsdev',
    @command = N'$s3',
    @on_success_action = 3,
    @on_fail_action = 4,
    @on_fail_step_id = 8;

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'$JobName',
    @step_name = N'Validate',
    @step_id = 4,
    @subsystem = N'TSQL',
    @database_name = N'remicsdev',
    @command = N'$s4',
    @on_success_action = 3,
    @on_fail_action = 4,
    @on_fail_step_id = 8;

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'$JobName',
    @step_name = N'Update File',
    @step_id = 5,
    @subsystem = N'TSQL',
    @database_name = N'remicsdev',
    @command = N'$s5',
    @on_success_action = 3,
    @on_fail_action = 4,
    @on_fail_step_id = 8;

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'$JobName',
    @step_name = N'Completed',
    @step_id = 6,
    @subsystem = N'TSQL',
    @database_name = N'remicsdev',
    @command = N'$s6',
    @on_success_action = 3,
    @on_fail_action = 4,
    @on_fail_step_id = 8;

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'$JobName',
    @step_name = N'Completion',
    @step_id = 7,
    @subsystem = N'TSQL',
    @database_name = N'remicsdev',
    @command = N'$s7',
    @on_success_action = 1,
    @on_fail_action = 4,
    @on_fail_step_id = 8;

EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'$JobName',
    @step_name = N'Error',
    @step_id = 8,
    @subsystem = N'TSQL',
    @database_name = N'remicsdev',
    @command = N'$s8',
    @on_success_action = 2,
    @on_fail_action = 2;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name = N'$ScheduleName')
BEGIN
    EXEC msdb.dbo.sp_attach_schedule
        @job_name = N'$JobName',
        @schedule_name = N'$ScheduleName';
END
ELSE
BEGIN
    EXEC msdb.dbo.sp_add_jobschedule
        @job_name = N'$JobName',
        @name = N'$ScheduleName',
        @enabled = 1,
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 4,
        @freq_subday_interval = 20,
        @active_start_time = 0;
END

EXEC msdb.dbo.sp_add_jobserver @job_name = N'$JobName';
"@

Set-Content -Path $TempSql -Value $ddl -Encoding UTF8
Write-Host "=== Deploying $JobName ==="
& $InvokeSql -Database msdb -InputFile $TempSql
Remove-Item $TempSql -Force -ErrorAction SilentlyContinue

$verify = @"
SELECT j.name, j.enabled, s.name AS schedule_name
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
LEFT JOIN msdb.dbo.sysschedules s ON js.schedule_id = s.schedule_id
WHERE j.name = N'$JobName';
SELECT step_id, step_name, database_name, on_success_action, on_fail_action, on_fail_step_id
FROM msdb.dbo.sysjobsteps js
JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id
WHERE j.name = N'$JobName'
ORDER BY step_id;
"@
& $InvokeSql -Database msdb -Query $verify
Write-Host "=== Done. Job: $JobName ==="
