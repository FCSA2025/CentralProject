#Requires -Version 5.1
<#
.SYNOPSIS
    Track selected remicsdev source files in CentralProject without relocating them.

.DESCRIPTION
    Copies (or refreshes) changed source files into config/remicsdev/source/ in the repo,
    then replaces each live path on D: with a symlink -> repo file.

    IIS, MSBuild, and existing paths (e.g. D:\inetpub\...\tsipBatch.aspx,
    D:\MicsBatchProgs\...\TpRunTsip.cs) keep working; Git tracks content under the hub.

    Requires permission to create symbolic links (Developer Mode or elevated PowerShell).

.EXAMPLE
    .\scripts\New-RemicsDevSourceLinks.ps1
#>
[CmdletBinding()]
param(
    [string]$LiveMicsRoot = 'D:\inetpub\remicsdev\mics',
    [string]$LiveBatchRoot = 'D:\MicsBatchProgs\MicsBat',
    [switch]$ForceCopyFromLive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$HubRoot = Split-Path $PSScriptRoot -Parent
$SourceRoot = Join-Path $HubRoot 'config\remicsdev\source'

$Mappings = @(
    @{
        RepoRelative = 'mics\Ttsipmenu\tsipBatch.aspx'
        LiveRelative = 'Ttsipmenu\tsipBatch.aspx'
        LiveRoot     = $LiveMicsRoot
    },
    @{
        RepoRelative = 'MicsBat\TpRunTsip\TsipReportHelper.cs'
        LiveRelative = 'TpRunTsip\TsipReportHelper.cs'
        LiveRoot     = $LiveBatchRoot
    },
    @{
        RepoRelative = 'MicsBat\TpRunTsip\TpRunTsip.cs'
        LiveRelative = 'TpRunTsip\TpRunTsip.cs'
        LiveRoot     = $LiveBatchRoot
    },
    @{
        RepoRelative = 'MicsBat\_Utillib\TsipRunArchive.cs'
        LiveRelative = '_Utillib\TsipRunArchive.cs'
        LiveRoot     = $LiveBatchRoot
    },
    @{
        RepoRelative = 'MicsBat\_Utillib\TsipQ.cs'
        LiveRelative = '_Utillib\TsipQ.cs'
        LiveRoot     = $LiveBatchRoot
    }
)

function Set-LiveToRepoFile {
    param(
        [string]$RepoFile,
        [string]$LiveFile
    )

    $repoDir = Split-Path $RepoFile -Parent
    if (-not (Test-Path $repoDir)) {
        New-Item -ItemType Directory -Path $repoDir -Force | Out-Null
    }

    if (-not (Test-Path $LiveFile)) {
        throw "Live file not found: $LiveFile"
    }

    $liveItem = Get-Item $LiveFile -Force
    if ($liveItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        if ($liveItem.Target -contains $RepoFile) {
            Write-Host "OK (live->repo): $LiveFile"
            return
        }
        throw "Live path is a symlink to unexpected target: $LiveFile -> $($liveItem.Target -join ', ')"
    }

    if (-not (Test-Path $RepoFile) -or $ForceCopyFromLive) {
        Copy-Item -Path $LiveFile -Destination $RepoFile -Force
        Write-Host "Copied into repo: $RepoFile"
    }

    $backup = "$LiveFile.pre-centralproject-link"
    if (-not (Test-Path $backup)) {
        Copy-Item -Path $LiveFile -Destination $backup -Force
        Write-Host "Backup: $backup"
    }

    Remove-Item $LiveFile -Force
    New-Item -ItemType SymbolicLink -Path $LiveFile -Target $RepoFile | Out-Null
    Write-Host "Linked live->repo: $LiveFile -> $RepoFile"
}

foreach ($map in $Mappings) {
    $repoFile = Join-Path $SourceRoot $map.RepoRelative
    $liveFile = Join-Path $map.LiveRoot $map.LiveRelative
    Set-LiveToRepoFile -RepoFile $repoFile -LiveFile $liveFile
}

Write-Host "Done. Edit tracked files under $SourceRoot ; live paths on D: follow symlinks."
