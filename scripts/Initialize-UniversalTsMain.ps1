#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap main.* with universal TS ADD fixtures (Q9UA / Q9UB sites).

.DESCRIPTION
    Posts univts01-add and univts02-add through the fwmda DbUpdate pipeline so
    matching DELETE files validate on any operator account.
#>
[CmdletBinding()]
param(
    [switch]$ForceBootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$genScript = Join-Path $PSScriptRoot 'New-UniversalTsFixtures.ps1'
$outDir = Join-Path $RepoRoot 'tests\remicsdev\fixtures\files\operator-import\universal'
$manifestPath = Join-Path $outDir 'universal-ts-manifest.json'

if (-not (Test-Path $manifestPath)) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $genScript
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $genScript -Validate -ValidateDelete
