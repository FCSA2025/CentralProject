#Requires -Version 5.1
<#
.SYNOPSIS
    Install the remicsdev update-queue processor as a local IIS scheduled task.

.DESCRIPTION
    SQL Agent "Update Queue39" remotes to IIS over WinRM, then sqlcmd -E double-hops
    and fails as NT AUTHORITY\ANONYMOUS LOGON. This task runs the processor on
    IIS-REMICS-PROD so sqlcmd is a single hop.

    Default identity is CLOUDMICSDEV\IISReMicsSer (remicsdev app pool). That
    account already has a Windows password on this box and remicsdev SQL
    read/write. MtUpdate still runs as MICS user fwmda via the pipeline env.

    Pass -TaskPassword, or -UseIisAppPoolCredential to reuse the remicsdevapp
    pool password. Do not commit a password; the script never writes one to disk.
#>
[CmdletBinding()]
param(
    [string]$TaskUser = 'CLOUDMICSDEV\IISReMicsSer',
    [SecureString]$TaskPassword,
    [switch]$UseIisAppPoolCredential,
    [string]$AppPoolName = 'remicsdevapp'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TaskName = 'Remicsdev Update Queue Local'
$TaskPath = '\Remicsdev\'
$ScriptPath = Join-Path $PSScriptRoot 'Invoke-RemicsUpdateAutoProcessor.ps1'
$IntervalMinutes = 10
$InvokeSql = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'

if (-not (Test-Path -LiteralPath $ScriptPath)) { throw "Processor missing: $ScriptPath" }
if ($UseIisAppPoolCredential) {
    $appcmd = Join-Path $env:windir 'system32\inetsrv\appcmd.exe'
    $poolPwd = (& $appcmd list apppool $AppPoolName '/text:processModel.password' | Out-String).Trim()
    $poolUser = (& $appcmd list apppool $AppPoolName '/text:processModel.userName' | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($poolPwd)) { throw "Could not read password for IIS app pool $AppPoolName" }
    if ($poolUser) { $TaskUser = $poolUser }
    $TaskPassword = ConvertTo-SecureString $poolPwd -AsPlainText -Force
    $poolPwd = $null
}
if (-not $TaskPassword) {
    throw 'Provide -TaskPassword or -UseIisAppPoolCredential so the task can run when nobody is logged on.'
}
$plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($TaskPassword)
)

Write-Host "=== Disable SQL Agent remoting job Update Queue39 ==="
& $InvokeSql -Query @"
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Update Queue39')
    EXEC msdb.dbo.sp_update_job @job_name = N'Update Queue39', @enabled = 0;
"@

Write-Host "=== Grant $TaskUser queue-table rights (fwmda mapped user) ==="
& $InvokeSql -Query @"
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'fwmda')
BEGIN
    GRANT SELECT, INSERT, UPDATE ON adm.t_UpdateQueue_local TO [fwmda];
    GRANT SELECT, INSERT, UPDATE ON adm.t_EmailQueue_local TO [fwmda];
    GRANT SELECT, INSERT, UPDATE ON adm.t_InboxProcessing_local TO [fwmda];
END
"@

$arg = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -MaxFiles 1' -f $ScriptPath
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg -WorkingDirectory $PSScriptRoot
$start = (Get-Date).AddMinutes(1)
$trigger = New-ScheduledTaskTrigger -Once -At $start `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
    -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2) -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries

$registerArgs = @{
    TaskName    = $TaskName
    TaskPath    = $TaskPath
    Action      = $action
    Trigger     = $trigger
    Settings    = $settings
    User        = $TaskUser
    Password    = $plain
    RunLevel    = 'Limited'
    Force       = $true
    Description = 'Process adm.t_UpdateQueue_local on IIS (no WinRM hop). Replaces Update Queue39 remoting.'
}

Write-Host "=== Registering scheduled task $TaskPath$TaskName as $TaskUser (Password / batch) ==="
Register-ScheduledTask @registerArgs | Out-Null

$info = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
$info | Select-Object TaskName, TaskPath, State | Format-List
Write-Host ("=== Done. LogonType={0} User={1} every {2} min whether logged on or not. ===" -f `
    $info.Principal.LogonType, $info.Principal.UserId, $IntervalMinutes)
