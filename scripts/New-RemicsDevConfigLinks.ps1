#Requires -Version 5.1
<#
.SYNOPSIS
    Wire CentralProject/config/remicsdev/mics to the live remicsdev IIS app.

.DESCRIPTION
    - Tlogin.aspx*: repo symlink -> live files (edit via repo paths; content on D:)
    - web.config: real file IN REPO; live IIS path symlink -> repo (Git tracks content)

.EXAMPLE
    .\scripts\New-RemicsDevConfigLinks.ps1
#>
[CmdletBinding()]
param(
    [string]$LiveMicsRoot = 'D:\inetpub\remicsdev\mics'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$HubRoot = Split-Path $PSScriptRoot -Parent
$LinkDir = Join-Path $HubRoot 'config\remicsdev\mics'

if (-not (Test-Path $LiveMicsRoot)) {
    throw "Live mics path not found: $LiveMicsRoot"
}

New-Item -ItemType Directory -Path $LinkDir -Force | Out-Null

function Set-RepoToLiveSymlink {
    param([string]$Name)
    $target = Join-Path $LiveMicsRoot $Name
    $link = Join-Path $LinkDir $Name

    if (-not (Test-Path $target)) {
        Write-Warning "Skip (live missing): $target"
        return
    }

    if (Test-Path $link) {
        $item = Get-Item $link -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            Write-Host "OK (repo->live): $link"
            return
        }
        throw "Path exists and is not a symlink: $link"
    }

    New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
    Write-Host "Linked repo->live: $link -> $target"
}

function Set-LiveToRepoWebConfig {
    $live = Join-Path $LiveMicsRoot 'web.config'
    $repo = Join-Path $LinkDir 'web.config'

    if (-not (Test-Path $repo) -or ((Get-Item $repo -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        if (-not (Test-Path $live)) {
            throw "Cannot seed web.config: live file missing at $live"
        }
        if (Test-Path $repo) { Remove-Item $repo -Force }
        Copy-Item -Path $live -Destination $repo -Force
        Write-Host "Copied live web.config into repo: $repo"
    }

    if (Test-Path $live) {
        $liveItem = Get-Item $live -Force
        if ($liveItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            if ($liveItem.Target -contains $repo) {
                Write-Host "OK (live->repo): $live"
                return
            }
            Remove-Item $live -Force
        }
        else {
            Remove-Item $live -Force
        }
    }

    New-Item -ItemType SymbolicLink -Path $live -Target $repo | Out-Null
    Write-Host "Linked live->repo: $live -> $repo"
}

foreach ($name in @('Tlogin.aspx', 'Tlogin.aspx.cs', 'Tlogin.aspx.designer.cs')) {
    Set-RepoToLiveSymlink -Name $name
}

Set-LiveToRepoWebConfig

Write-Host "Done. Edit web.config under $LinkDir (tracked in Git). IIS reads it via $LiveMicsRoot\web.config."
