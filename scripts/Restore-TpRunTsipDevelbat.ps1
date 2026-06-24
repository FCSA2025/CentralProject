#Requires -Version 5.1
<#
.SYNOPSIS
    Roll back D:\develbat\TpRunTsip.exe to the pre-Phase0 backup.

.DESCRIPTION
    Restores tpRunTsip from .bak-20260623 created before removing the venn Storedef ODBC block.
    Run this if the Phase 0 TSIP fix causes problems.

.EXAMPLE
    .\Restore-TpRunTsipDevelbat.ps1
#>
[CmdletBinding()]
param(
    [string]$BackupPath = 'D:\develbat\tpRunTsip.exe.bak-20260623',
    [string]$DeployPath = 'D:\develbat\TpRunTsip.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $BackupPath)) {
    throw "Backup not found: $BackupPath"
}

Copy-Item -Path $BackupPath -Destination $DeployPath -Force
Write-Host "Restored $DeployPath from $BackupPath"
Get-Item $DeployPath | Format-List Name, Length, LastWriteTime
