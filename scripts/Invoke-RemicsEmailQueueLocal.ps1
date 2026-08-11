#Requires -Version 5.1
<#
.SYNOPSIS
    Drain pending rows from adm.t_EmailQueue_local (same T-SQL as SQL Agent job).

.DESCRIPTION
    Runs docs/remicsdev/email-queue-local-agent-job.sql directly, or starts the
    "Email Queue Local" SQL Agent job when -UseAgentJob is set.

.PARAMETER UseAgentJob
    EXEC sp_start_job instead of inline T-SQL (uses deployed job definition).

.PARAMETER MaxWaitSeconds
    When -UseAgentJob, poll until no pending rows or timeout (default 120).
#>
[CmdletBinding()]
param(
    [switch]$UseAgentJob,
    [int]$MaxWaitSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'RemicsDev-SqlHelpers.ps1')
$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$jobSqlFile = Join-Path $RepoRoot 'docs\remicsdev\email-queue-local-agent-job.sql'

function Get-PendingEmailCount {
    $n = Invoke-RemicsDevSqlScalar -Query "SELECT COUNT(*) AS cnt FROM adm.t_EmailQueue_local WHERE sentYN = 'N'" -SqlScript $sqlScript
    if ($n -match '^\d+$') { return [int]$n }
    return 0
}

if ($UseAgentJob) {
    & $sqlScript -Query "EXEC msdb.dbo.sp_start_job @job_name = N'Email Queue Local';" | Out-Null
    $deadline = (Get-Date).AddSeconds($MaxWaitSeconds)
    while ((Get-Date) -lt $deadline) {
        if ((Get-PendingEmailCount) -eq 0) { break }
        Start-Sleep -Seconds 5
    }
}
else {
    if (-not (Test-Path $jobSqlFile)) { throw "Job SQL missing: $jobSqlFile" }
    & $sqlScript -InputFile $jobSqlFile | Out-Null
}

$pending = Get-PendingEmailCount
Write-Output (@{
    ok = ($pending -eq 0)
    pending = $pending
} | ConvertTo-Json -Compress)

if ($pending -gt 0) { exit 1 }
exit 0
