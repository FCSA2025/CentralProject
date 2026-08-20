#Requires -Version 5.1
<#
.SYNOPSIS
    Simulate production ES files arriving in the remicsdev ES inbox.

.DESCRIPTION
    Copies one or more ES fixtures into D:\updates\primary\UnprocessedESFiles using
    the same username_timestamp_pdf.txt naming the SQL job and auto-processor expect.
    Does not INSERT adm.t_UpdateQueue_local (prod copy does not enqueue). ProcessESFileSQL
    picks the file on its 20-minute cycle, or immediately with -StartJob.

.PARAMETER Source
    Fixture .txt to copy. Default: seq10 cyces01d.

.PARAMETER Count
    How many uniquely named copies to drop (default 1).

.PARAMETER Submitter
    Filename prefix / usp_ESSelect username (must exist before the first underscore).

.PARAMETER StartJob
    Start ProcessESFileSQL once after the copy (does not wait for completion).

.PARAMETER StartAutoProcessor
    Run the rewrite MeUpdate processor after copy. That path requires an explicit
    adm.t_UpdateQueue_local row; the auto-processor no longer safety-nets ES files.
#>
[CmdletBinding()]
param(
    [string]$Source = '',
    [ValidateRange(1, 20)]
    [int]$Count = 1,
    [string]$Submitter = 'cyc1',
    [string]$PdfName = 'cyces01d',
    [switch]$StartJob,
    [switch]$StartAutoProcessor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path $PSScriptRoot -Parent
$Inbox = 'D:\updates\primary\UnprocessedESFiles'
$Completed = Join-Path $Inbox 'RelCompleted'
$DefaultSource = Join-Path $RepoRoot 'tests\remicsdev\fixtures\files\updates-primary\circular\seq10\es\cyc1_2608061112_cyces01d.txt'
$InvokeSql = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'

if (-not $Source) { $Source = $DefaultSource }
if (-not (Test-Path -LiteralPath $Source)) { throw "ES fixture not found: $Source" }
if ($Submitter -notmatch '^[A-Za-z0-9]+$') { throw "Submitter must be alphanumeric (usp_ESSelect parses left of first underscore)." }
if ($PdfName -notmatch '^[A-Za-z0-9_.-]+$') { throw "PdfName contains unsupported characters." }

if (-not (Test-Path $Inbox)) { New-Item -ItemType Directory -Force -Path $Inbox | Out-Null }
if (-not (Test-Path $Completed)) { New-Item -ItemType Directory -Force -Path $Completed | Out-Null }

$dropped = New-Object System.Collections.Generic.List[string]
$stampBase = Get-Date
for ($i = 0; $i -lt $Count; $i++) {
    $stamp = $stampBase.AddMinutes($i).ToString('yyMMddHHmm')
    $destName = '{0}_{1}_{2}.txt' -f $Submitter, $stamp, $PdfName
    $dest = Join-Path $Inbox $destName
    Copy-Item -LiteralPath $Source -Destination $dest -Force
    [void]$dropped.Add($dest)
    Write-Host "Dropped $dest"
}

if ($StartJob) {
    Write-Host 'Starting SQL Agent job ProcessESFileSQL'
    & $InvokeSql -Database msdb -Query "EXEC msdb.dbo.sp_start_job @job_name = N'ProcessESFileSQL';"
}

if ($StartAutoProcessor) {
    $auto = Join-Path $PSScriptRoot 'Invoke-RemicsUpdateAutoProcessor.ps1'
    Write-Host 'Starting rewrite auto-processor (MeUpdate path)'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $auto -MaxFiles $Count
}

Write-Output ($dropped | ConvertTo-Json -Compress)
