#Requires -Version 5.1
<#
.SYNOPSIS
    Create symlinks from CentralProject/config/remicsdev/mics to live remicsdev IIS app.

.EXAMPLE
    .\scripts\New-RemicsDevConfigLinks.ps1
    .\scripts\New-RemicsDevConfigLinks.ps1 -LiveMicsRoot "D:\inetpub\remicstest\mics"
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

$files = @(
    'Tlogin.aspx',
    'Tlogin.aspx.cs',
    'Tlogin.aspx.designer.cs',
    'web.config'
)

foreach ($name in $files) {
    $target = Join-Path $LiveMicsRoot $name
    $link = Join-Path $LinkDir $name

    if (-not (Test-Path $target)) {
        Write-Warning "Skip (target missing): $target"
        continue
    }

    if (Test-Path $link) {
        $item = Get-Item $link -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            Write-Host "OK (exists): $link"
            continue
        }
        throw "Path exists and is not a symlink: $link"
    }

    New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
    Write-Host "Linked: $link -> $target"
}

Write-Host "Done. Edit under $LinkDir or follow links to live files."
