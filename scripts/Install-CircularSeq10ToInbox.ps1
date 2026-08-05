#Requires -Version 5.1
<#
.SYNOPSIS
    Copy seq10 circular staging fixtures to DbUpdate inbox folders.

.PARAMETER FileType
    TS, ES, or Both (default Both).

.PARAMETER Pair
    Copy only one pair (1-5). Default: all 10 files per type.

.PARAMETER Regenerate
    Run New-CircularSeq10Fixtures.ps1 before copying.
#>
[CmdletBinding()]
param(
    [ValidateSet('TS', 'ES', 'Both')]
    [string]$FileType = 'Both',
    [ValidateRange(1, 5)]
    [int]$Pair = 0,
    [switch]$Regenerate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$seqRoot = Join-Path $RepoRoot 'tests\remicsdev\fixtures\files\updates-primary\circular\seq10'
$manifestPath = Join-Path $seqRoot 'seq10-manifest.json'
$genScript = Join-Path $PSScriptRoot 'New-CircularSeq10Fixtures.ps1'
$tsInbox = 'D:\updates\primary'
$esInbox = Join-Path $tsInbox 'UnprocessedESFiles'

if ($Regenerate) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $genScript
}

if (-not (Test-Path $manifestPath)) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $genScript
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$copied = @()

function Copy-Files {
    param([string]$TypeKey, [string]$DestRoot)
    if (-not (Test-Path $DestRoot)) { New-Item -ItemType Directory -Force -Path $DestRoot | Out-Null }
    $files = @($manifest.$TypeKey.files | Sort-Object { [int]$_.sequence })
    if ($Pair -gt 0) {
        $files = @($files | Where-Object { [int]$_.pair -eq $Pair })
    }
    foreach ($f in $files) {
        if (-not (Test-Path $f.path)) { throw "Missing fixture: $($f.path)" }
        $dest = Join-Path $DestRoot $f.file
        Copy-Item -LiteralPath $f.path -Destination $dest -Force
        $copied += [pscustomobject]@{ type = $TypeKey; file = $f.file; dest = $dest; sites = $f.sites; pass = $f.pass }
    }
}

if ($FileType -eq 'TS' -or $FileType -eq 'Both') { Copy-Files -TypeKey 'ts' -DestRoot $tsInbox }
if ($FileType -eq 'ES' -or $FileType -eq 'Both') { Copy-Files -TypeKey 'es' -DestRoot $esInbox }

Write-Output (@{ ok = $true; copied = $copied; count = $copied.Count } | ConvertTo-Json -Depth 6)
