#Requires -Version 5.1
<#
.SYNOPSIS
    Export master copies of complex TS/ES fixtures from live remicsdev into the repo.

.DESCRIPTION
    Reads tests/remicsdev/fixtures/complex-manifest.yaml and runs ftPrint/fePrint
    from each fixture's source account into tests/remicsdev/fixtures/files/complex/.

.PARAMETER IncludeStress
    Also export cmxts02 (fccmnu19b1_8, ~17k channels). Can be very slow/large.

.PARAMETER Fixture
    Export a single fixture id (e.g. cmxts01).
#>
[CmdletBinding()]
param(
    [switch]$IncludeStress,
    [string]$Fixture = '',
    [string]$Password = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$manifestPath = Join-Path $repoRoot 'tests\remicsdev\fixtures\complex-manifest.yaml'
$filesRoot = Join-Path $repoRoot 'tests\remicsdev\fixtures\files'
$complexDir = Join-Path $filesRoot 'complex'
$ftPrint = 'D:\develbat\ftPrint.exe'
$fePrint = 'D:\develbat\FePrint.exe'
$userDirsRoot = 'D:\Inetpub\remicsdev\mics\userdirs'

function Get-EnvLocalValue {
    param([string]$Key)
    $envFile = Join-Path $repoRoot '.env.local'
    if (-not (Test-Path $envFile)) { return $null }
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.+?)\s*$") {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

function Read-ComplexManifest {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "Manifest not found: $Path" }
    $fixtures = @{}
    $current = $null
    $inTsip = $false
    foreach ($rawLine in Get-Content $Path) {
        $line = $rawLine
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^fixtures:\s*$') { continue }
        if ($line -match '^\s{2}([A-Za-z0-9_]+):\s*$') {
            $current = $Matches[1]
            $fixtures[$current] = @{ id = $current; tsip = @{} }
            $inTsip = $false
            continue
        }
        if ($null -eq $current) { continue }
        if ($line -match '^\s{4}tsip:\s*$') { $inTsip = $true; continue }
        if ($inTsip -and $line -match '^\s{6}([A-Za-z0-9_]+):\s*(.+)\s*$') {
            $fixtures[$current].tsip[$Matches[1]] = $Matches[2].Trim().Trim('"')
            continue
        }
        if ($line -match '^\s{4}([A-Za-z0-9_]+):\s*(.+)\s*$') {
            $inTsip = $false
            $key = $Matches[1]
            $val = $Matches[2].Trim()
            if ($val -match '^\[(.*)\]$') {
                $fixtures[$current][$key] = @($Matches[1].Split(',') | ForEach-Object { $_.Trim() })
            } elseif ($val -eq 'true') { $fixtures[$current][$key] = $true }
            elseif ($val -eq 'false') { $fixtures[$current][$key] = $false }
            else { $fixtures[$current][$key] = $val.Trim('"') }
        }
    }
    return $fixtures
}

function Get-MicsPassword {
    param([string]$User)
    $key = 'MICS_TEST_PASSWORD_' + $User.ToUpperInvariant()
    $pwd = $Password
    if (-not $pwd) { $pwd = [Environment]::GetEnvironmentVariable($key) }
    if (-not $pwd) { $pwd = Get-EnvLocalValue $key }
    if (-not $pwd) { $pwd = $env:MICS_TEST_PASSWORD }
    if (-not $pwd) { $pwd = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
    if (-not $pwd) { $pwd = 'x' }
    return $pwd
}

function Set-MicsBatchEnv {
    param([string]$User, [string]$Project, [string]$Schema, [string]$Pwd)
    $workDir = Join-Path (Join-Path $userDirsRoot $Schema) $User
    if (-not (Test-Path $workDir)) { New-Item -ItemType Directory -Force -Path $workDir | Out-Null }
    $env:MICSUSER = $User
    $env:PASSWORD = $Pwd
    $env:Domain = 'CLOUDMICSDEV'
    $env:odbc = 'remicsdev'
    $env:DBName = 'remicsdev'
    $env:SqlInstance = 'EC2AMAZ-9DKDM82\REMICS_DEV'
    $env:MICS_PROJECT = $Project
    $env:work_dir = $workDir + '\'
    $env:WORK_DIR = $env:work_dir
    $env:webdrive = 'D:'
}

if (-not (Test-Path $manifestPath)) { throw "Manifest missing: $manifestPath" }
$manifest = Read-ComplexManifest -Path $manifestPath
New-Item -ItemType Directory -Force -Path $complexDir | Out-Null

$results = New-Object System.Collections.Generic.List[object]
foreach ($id in ($manifest.Keys | Sort-Object)) {
    if ($Fixture -and $id -ne $Fixture) { continue }
    $fx = $manifest[$id]
    if ($fx.ContainsKey('stress') -and $fx.stress -eq $true -and -not $IncludeStress) {
        Write-Host "Skipping stress fixture $id (use -IncludeStress)"
        continue
    }

    $fileType = ([string]$fx.file_type).ToUpperInvariant()
    $sourceUser = [string]$fx.source_mics_user
    $sourceProject = [string]$fx.source_project
    $sourceSchema = [string]$fx.source_schema
    $sourceFile = [string]$fx.source_file
    $masterRel = [string]$fx.master_file
    $outPath = Join-Path $filesRoot ($masterRel -replace '^files/', '')

    $printExe = if ($fileType -eq 'ES') { $fePrint } else { $ftPrint }
    if (-not (Test-Path $printExe)) { throw "Print exe missing: $printExe" }

    Set-MicsBatchEnv -User $sourceUser -Project $sourceProject -Schema $sourceSchema -Pwd (Get-MicsPassword -User $sourceUser)
    $outDir = Split-Path $outPath -Parent
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
    if (Test-Path $outPath) { Remove-Item $outPath -Force }

    Write-Host "Exporting $id from $sourceSchema/$sourceFile as $sourceUser -> $outPath"
    $args = if ($fileType -eq 'ES') {
        @('remicsdev', $sourceProject, ("-o{0}" -f $outPath), $sourceFile)
    } else {
        @('remicsdev', $sourceProject, ("-o{0}" -f $outPath), 'L', $sourceFile)
    }
    $p = Start-Process -FilePath $printExe -ArgumentList $args -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { throw "Export failed for $id exit $($p.ExitCode)" }
    if (-not (Test-Path $outPath)) { throw "Export produced no file: $outPath" }

    $bytes = (Get-Item $outPath).Length
    $results.Add([pscustomobject]@{
        id = $id; source = "$sourceSchema/$sourceFile"; bytes = $bytes; path = $outPath
    })
    Write-Host ("  OK bytes={0}" -f $bytes)
}

$results | Format-Table -AutoSize
Write-Host ("Exported {0} master file(s) to {1}" -f $results.Count, $complexDir)
