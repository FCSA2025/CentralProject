#Requires -Version 5.1
<#
.SYNOPSIS
    Restore pinned complex fixtures from master repo copies after destructive tests.

.DESCRIPTION
    Thin wrapper around Install-MicsComplexFixtures.ps1 -Force.

.PARAMETER Schema
    Optional schema allowlist (default: all target schemas).

.PARAMETER Fixture
    Restore a single fixture id (e.g. cmxts01).

.PARAMETER IncludeStress
    Also restore cmxts02.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Schema = @(),
    [string]$Fixture = '',
    [switch]$IncludeStress
)

$installScript = Join-Path $PSScriptRoot 'Install-MicsComplexFixtures.ps1'
if (-not (Test-Path $installScript)) { throw "Install script missing: $installScript" }

$params = @{ Force = $true }
if ($Schema.Count -gt 0) { $params['Schema'] = $Schema }
if ($Fixture) { $params['Fixture'] = $Fixture }
if ($IncludeStress) { $params['IncludeStress'] = $true }

& $installScript @params
