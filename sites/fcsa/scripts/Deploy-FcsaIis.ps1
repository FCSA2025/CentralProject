#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Deploys FCSA static site to IIS (fcsa site + fcsaapp pool on port 80).
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [string]$SourceDir = '',
    [string]$IisPath = 'D:\inetpub\fcsa',
    [string]$SiteName = 'fcsa',
    [string]$AppPoolName = 'fcsaapp'
)

$ErrorActionPreference = 'Stop'

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $ScriptDir '..\..\..')).Path
}

if (-not $SourceDir) {
    $SourceDir = Join-Path $RepoRoot 'sites\fcsa\dist'
}

if (-not (Test-Path $SourceDir)) {
    throw "Build output not found: $SourceDir - run Build-FcsaSite.ps1 first"
}

$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
if (-not (Test-Path $appcmd)) {
    throw "IIS appcmd not found - is IIS installed?"
}

Write-Host "Creating app pool $AppPoolName..."
Import-Module WebAdministration -ErrorAction SilentlyContinue
& $appcmd list apppool $AppPoolName 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    & $appcmd add apppool /name:$AppPoolName /managedRuntimeVersion:v4.0 /managedPipelineMode:Classic
}
& $appcmd set apppool $AppPoolName /processModel.identityType:ApplicationPoolIdentity
& $appcmd set apppool $AppPoolName /autoStart:true

Write-Host "Stopping Default Web Site and removing *:80 binding..."
& $appcmd stop site "Default Web Site" 2>$null | Out-Null
if (Get-Module WebAdministration) {
    $defaultBinding = Get-WebBinding -Name "Default Web Site" -Protocol http -Port 80 -ErrorAction SilentlyContinue |
        Where-Object { $_.bindingInformation -eq '*:80:' }
    if ($defaultBinding) {
        Remove-WebBinding -Name "Default Web Site" -Protocol http -Port 80 -HostHeader "" -ErrorAction SilentlyContinue
    }
} else {
    Write-Warning "WebAdministration module unavailable; Default Web Site *:80 binding may still exist"
}

Write-Host "Copying files to $IisPath..."
if (-not (Test-Path $IisPath)) {
    New-Item -ItemType Directory -Force -Path $IisPath | Out-Null
}
robocopy $SourceDir $IisPath /MIR /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
if ($LASTEXITCODE -ge 8) {
    throw "robocopy failed with exit code $LASTEXITCODE"
}

Write-Host "Granting read access to IIS AppPool\$AppPoolName..."
icacls $IisPath /grant "IIS AppPool\${AppPoolName}:(OI)(CI)R" /T /Q | Out-Null

Write-Host "Creating/updating IIS site $SiteName..."
& $appcmd list site $SiteName 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    & $appcmd add site /name:$SiteName /physicalPath:$IisPath /bindings:http/*:80:
} else {
    & $appcmd set site $SiteName /physicalPath:$IisPath
}
& $appcmd set app "$SiteName/" /applicationPool:$AppPoolName

# Expose MICS under the public FCSA hostname/IP so external Webmics Login works.
# remicsdev.cloudmicsdev.ca is internal-only DNS; bare IP hits the fcsa site.
$micsPath = 'D:\inetpub\remicsdev\mics'
$micsPool = 'remicsdevapp'
$micsApp = "$SiteName/mics"
if (Test-Path $micsPath) {
    Write-Host "Ensuring /$micsApp application -> $micsPath ($micsPool)..."
    & $appcmd list app $micsApp 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        & $appcmd add app /site.name:$SiteName /path:/mics /physicalPath:$micsPath /applicationPool:$micsPool
    } else {
        & $appcmd set app $micsApp /physicalPath:$micsPath /applicationPool:$micsPool
    }
} else {
    Write-Warning "MICS path missing ($micsPath); Webmics Login /mics will 404 until it exists."
}

if (Get-Module WebAdministration) {
    $fcsaBinding = Get-WebBinding -Name $SiteName -Protocol http -Port 80 -ErrorAction SilentlyContinue |
        Where-Object { $_.bindingInformation -eq '*:80:' }
    if (-not $fcsaBinding) {
        New-WebBinding -Name $SiteName -Protocol http -Port 80 -IPAddress "*"
    }
}

Write-Host "Starting site..."
& $appcmd start apppool $AppPoolName
& $appcmd start site $SiteName

Write-Host ""
Write-Host "Deploy complete."
Write-Host "  Site: $SiteName"
Write-Host "  Path: $IisPath"
Write-Host "  Test: http://localhost/ or http://127.0.0.1/"
Write-Host "  Login: http://localhost/mics/RemIcsReWrite/login.aspx"
