#Requires -Version 5.1
<#
.SYNOPSIS
    Run web.ReconcileUserTables on remicsdev (dry-run or live).

.PARAMETER Operator
    Limit to one company schema (e.g. bchy). Default: all.

.PARAMETER DryRun
    Log planned actions only; do not change web.user_tables.

.PARAMETER StartAgentJob
    Start the SQL Agent job "User Tables Reconcile" instead of calling the proc directly.
#>
[CmdletBinding()]
param(
    [string]$Operator,
    [switch]$DryRun,
    [switch]$StartAgentJob
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$InvokeSql = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'

if ($StartAgentJob) {
    Write-Host "=== Starting SQL Agent job: User Tables Reconcile ==="
    & $InvokeSql -Query "EXEC msdb.dbo.sp_start_job @job_name = N'User Tables Reconcile';"
    Write-Host "Started. Check web.user_tables_reconcile_run for results."
    return
}

$opSql = if ([string]::IsNullOrWhiteSpace($Operator)) { 'NULL' } else { "'" + ($Operator.Trim().Replace("'", "''")) + "'" }
$dry = if ($DryRun) { '1' } else { '0' }

Write-Host "=== ReconcileUserTables Operator=$opSql DryRun=$dry ==="
& $InvokeSql -Query @"
SET NOCOUNT ON; SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;
EXEC web.ReconcileUserTables @Operator = $opSql, @DryRun = $dry, @SyncValidstat = 1;

SELECT TOP 1 run_id, mode, operator_filter, deleted_orphans, inserted_missing, updated_validstat, started_at, finished_at, notes
FROM web.user_tables_reconcile_run
ORDER BY run_id DESC;
"@
