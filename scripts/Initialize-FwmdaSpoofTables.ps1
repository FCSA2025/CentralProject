#Requires -Version 5.1
<#
.SYNOPSIS
    One-time bootstrap of fwmda spoof MDB tables (MtUpdate/MeUpdate -C -s).

.DESCRIPTION
    Creates fmda2.mt_*, fmda2.sd_*, fmda2.audit_trail (and ES equivalents) by running
    MtUpdate -C -s against a disposable imported PDF name. Requires a minimal TS table
    set to exist briefly; uses fixture cat.txt when no boot name is supplied.

.PARAMETER BootPdfName
    Optional disposable PDF root (max 16 chars). Default: upipboot + HHmmss suffix.

.PARAMETER Json
    Emit JSON result on stdout.
#>
[CmdletBinding()]
param(
    [string]$BootPdfName = '',
    [switch]$Json,
    [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$MicsUser = 'fwmda'
$Project = 'fwmda_0'
$ftImport = 'D:\develbat\ftImport.exe'
$mtUpdate = 'D:\develbat\MtUpdate.exe'
$killTable = 'D:\develbat\KillTable.exe'
$fixtureCat = Join-Path $RepoRoot 'tests\remicsdev\fixtures\files\cat.txt'

function Get-EnvLocalValue {
    param([string]$Key)
    $envFile = Join-Path $RepoRoot '.env.local'
    if (-not (Test-Path $envFile)) { return $null }
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.+?)\s*$") {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

function Invoke-SqlScalar {
    param([string]$Query)
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $sqlScript -Query $Query 2>&1 | Out-String
    $lines = @($raw -split "`r?`n" | Where-Object {
        $_ -and $_ -notmatch '^---' -and $_ -notmatch '^-+$' -and $_ -notmatch '^\(' -and $_ -notmatch 'rows affected'
    })
    if ($lines.Count -lt 2) { return $null }
    $parts = @($lines[1] -split '\|')
    if ($parts.Count -lt 1) { return $null }
    return $parts[0].Trim()
}

function Set-MicsBatchEnv {
    param([string]$WorkDir, [string]$Project, [string]$Pwd, [string]$User)
    $env:MICSUSER = $User
    $env:PASSWORD = $Pwd
    $env:Domain = 'CLOUDMICSDEV'
    $env:odbc = 'remicsdev'
    $env:DBName = 'remicsdev'
    $env:SqlInstance = 'EC2AMAZ-9DKDM82\REMICS_DEV'
    $env:MICS_PROJECT = $Project
    $env:work_dir = $WorkDir
    $env:WORK_DIR = $WorkDir
    $env:webdrive = 'D:'
    $env:ProgDir = 'D:\develbat\'
}

function Invoke-ExeCapture {
    param([string]$FilePath, [string[]]$ArgumentList, [string]$LogPath)
    $stdout = "$LogPath.out.txt"
    $stderr = "$LogPath.err.txt"
    $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    return @{
        ExitCode = $proc.ExitCode
        StdOut   = if (Test-Path $stdout) { Get-Content $stdout -Raw } else { '' }
        StdErr   = if (Test-Path $stderr) { Get-Content $stderr -Raw } else { '' }
    }
}

function Write-Result {
    param([hashtable]$Payload, [int]$ExitCode = 0)
    $json = ($Payload | ConvertTo-Json -Depth 8 -Compress)
    if ($ResultPath) {
        $dir = Split-Path $ResultPath -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Set-Content -Path $ResultPath -Value $json -Encoding UTF8
    }
    if ($Json) { Write-Output $json }
    if ($ExitCode -ne 0) { exit $ExitCode }
}

if (-not (Test-Path $sqlScript)) { Write-Result @{ ok = $false; error = "SQL helper missing: $sqlScript" } -ExitCode 1 }
if (-not (Test-Path $fixtureCat)) { Write-Result @{ ok = $false; error = "Fixture missing: $fixtureCat" } -ExitCode 1 }

$schema = Invoke-SqlScalar "SELECT RTRIM(PrimarySchema) AS c FROM dbo.t_UserDetails WHERE RTRIM(micsId)='fwmda'"
if (-not $schema) { $schema = 'fmda2' }

$workDir = "D:\Inetpub\remicsdev\mics\userdirs\$schema\$MicsUser\"
if (-not (Test-Path $workDir)) { New-Item -ItemType Directory -Force -Path $workDir | Out-Null }

$userPwdKey = 'MICS_TEST_PASSWORD_FWMDA'
$password = [Environment]::GetEnvironmentVariable($userPwdKey)
if (-not $password) { $password = Get-EnvLocalValue $userPwdKey }
if (-not $password) { $password = $env:MICS_TEST_PASSWORD }
if (-not $password) { $password = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
if (-not $password) { $password = 'x' }

if (-not $BootPdfName) {
    $BootPdfName = ('upip' + (Get-Date -Format 'HHmmss'))
}
if ($BootPdfName.Length -gt 16) { $BootPdfName = $BootPdfName.Substring(0, 16) }

$logDir = Join-Path $env:TEMP ("fwmda-spoof-init-{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Set-MicsBatchEnv -WorkDir $workDir -Project $Project -Pwd $password -User $MicsUser

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("Initialize fwmda spoof tables: user=$MicsUser schema=$schema project=$Project boot=$BootPdfName")

try {
    $existing = Invoke-SqlScalar "SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='$schema' AND TABLE_NAME='mt_site'"
    if ($existing -and [int]$existing -gt 0) {
        Write-Result @{
            ok = $true
            skipped = $true
            schema = $schema
            mics_user = $MicsUser
            message = 'Spoof MDB tables already present (mt_site exists)'
            summary = ($summary -join "`n")
        }
    }

    $tmpPath = Join-Path $workDir ("{0}.tmp" -f $BootPdfName)
    Copy-Item $fixtureCat $tmpPath -Force
    $imp = Invoke-ExeCapture -FilePath $ftImport -ArgumentList @('remicsdev', $Project, $BootPdfName, $tmpPath, '-f') `
        -LogPath (Join-Path $logDir 'FtImport_boot')
    $summary.Add("FtImport boot exit=$($imp.ExitCode)")
    if ($imp.ExitCode -ne 0) { throw "FtImport boot failed exit=$($imp.ExitCode)" }

    $valOut = Join-Path $workDir ("{0}.txt" -f $BootPdfName)
    $val = Invoke-ExeCapture -FilePath 'D:\develbat\ftValidate.exe' `
        -ArgumentList @('remicsdev', $Project, $BootPdfName, ("-o{0}" -f $valOut)) `
        -LogPath (Join-Path $logDir 'FtValidate_boot')
    $summary.Add("FtValidate boot exit=$($val.ExitCode)")

    $upd = Invoke-ExeCapture -FilePath $mtUpdate -ArgumentList @('remicsdev', $Project, $BootPdfName, '-C', '-s') `
        -LogPath (Join-Path $logDir 'MtUpdate_createSpoof')
    $summary.Add("MtUpdate -C -s exit=$($upd.ExitCode)")
    if ($upd.ExitCode -ne 0) { throw "MtUpdate -C -s failed exit=$($upd.ExitCode)" }

    $kt = Invoke-ExeCapture -FilePath $killTable -ArgumentList @('remicsdev', 'TS', $BootPdfName, $Project) `
        -LogPath (Join-Path $logDir 'KillTable_boot')
    $summary.Add("KillTable boot exit=$($kt.ExitCode)")

    $mtCount = Invoke-SqlScalar "SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='$schema' AND TABLE_NAME='mt_site'"
    Write-Result @{
        ok = $true
        schema = $schema
        mics_user = $MicsUser
        boot_pdf = $BootPdfName
        mt_site_exists = ([int]$mtCount -gt 0)
        log_dir = $logDir
        summary = ($summary -join "`n")
    }
}
catch {
    Write-Result @{
        ok = $false
        schema = $schema
        mics_user = $MicsUser
        error = $_.Exception.Message
        log_dir = $logDir
        summary = ($summary -join "`n")
    } -ExitCode 1
}
