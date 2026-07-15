#Requires -Version 5.1
<#
.SYNOPSIS
    Refresh tests/remicsdev/fixtures/baselines.yaml from live remicsdev data + fixture files.

.DESCRIPTION
    Re-exports pinned tables via ftPrint into fixtures/files, updates export_bytes and
    site/chan/ante counts, and records latest complete TSIP run_id for ecomm2602 / ecomm2601b.
#>
[CmdletBinding()]
param(
    [string]$Password = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$filesRoot = Join-Path $RepoRoot 'tests\remicsdev\fixtures\files'
$baselinesPath = Join-Path $RepoRoot 'tests\remicsdev\fixtures\baselines.yaml'
$ftPrint = 'D:\develbat\ftPrint.exe'
$work = 'D:\Inetpub\remicsdev\mics\userdirs\rctl\rctl1\'

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
    return $parts[0].Trim()
}

if (-not $Password) { $Password = $env:MICS_TEST_PASSWORD }
if (-not $Password) { $Password = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
if (-not $Password) { $Password = 'x' }

$env:MICSUSER = 'rctl1'
$env:PASSWORD = $Password
$env:Domain = 'CLOUDMICSDEV'
$env:odbc = 'remicsdev'
$env:DBName = 'remicsdev'
$env:SqlInstance = 'EC2AMAZ-9DKDM82\REMICS_DEV'
$env:MICS_PROJECT = 'rctl1_0'
$env:work_dir = $work
$env:WORK_DIR = $work
$env:webdrive = 'D:'

New-Item -ItemType Directory -Force -Path $filesRoot | Out-Null

$meta = @{}
foreach ($name in @('cat', 'ecomm2602', 'ecomm2601b')) {
    $out = Join-Path $filesRoot ("{0}.txt" -f $name)
    $p = Start-Process -FilePath $ftPrint -ArgumentList @('remicsdev', 'rctl1_0', ("-o{0}" -f $out), 'L', $name) -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { throw "ftPrint failed for $name exit $($p.ExitCode)" }
    $bytes = (Get-Item $out).Length
    $sites = [int](Invoke-SqlScalar "SELECT COUNT(*) FROM rctl.ft_${name}_site")
    $chans = [int](Invoke-SqlScalar "SELECT COUNT(*) FROM rctl.ft_${name}_chan")
    $antes = [int](Invoke-SqlScalar "SELECT COUNT(*) FROM rctl.ft_${name}_ante")
    $meta[$name] = @{ bytes = $bytes; sites = $sites; chans = $chans; antes = $antes }
    Write-Host ("{0}: bytes={1} sites={2} chans={3} antes={4}" -f $name, $bytes, $sites, $chans, $antes)
}

$rid2602 = Invoke-SqlScalar "SELECT TOP 1 run_id FROM web.tsip_run WHERE parm_file='ecomm2602' AND run_name='TS1' AND archive_status='complete' ORDER BY run_id DESC"
$rid2601b = Invoke-SqlScalar "SELECT TOP 1 run_id FROM web.tsip_run WHERE parm_file='ecomm2601b' AND run_name='TS1' AND archive_status='complete' ORDER BY run_id DESC"
$updated = (Get-Date).ToUniversalTime().ToString('o')

$yaml = @"
# ReMICS Dev batch-test baselines (rctl1 / remicsdev)
# Refresh with: scripts/Update-RemicsDevTestBaselines.ps1
schema: rctl
mics_user: rctl1
project: rctl1_0
dbname: remicsdev
updated_utc: "$updated"

fixtures:
  cat:
    role: smoke
    table: cat
    export_file: files/cat.txt
    export_bytes: $($meta.cat.bytes)
    min_export_bytes: 1025
    sites: $($meta.cat.sites)
    chans: $($meta.cat.chans)
    antes: $($meta.cat.antes)
    ops: [print, import, validate]

  ecomm2602:
    role: complex
    table: ecomm2602
    export_file: files/ecomm2602.txt
    export_bytes: $($meta.ecomm2602.bytes)
    min_export_bytes: 1025
    sites: $($meta.ecomm2602.sites)
    chans: $($meta.ecomm2602.chans)
    antes: $($meta.ecomm2602.antes)
    ops: [print, import, validate, tsip]
    tsip:
      parm_file: ecomm2602
      run_name: TS1
      baseline_run_id: $(if ($rid2602) { $rid2602 } else { 'null' })

  ecomm2601b:
    role: secondary_tsip
    table: ecomm2601b
    export_file: files/ecomm2601b.txt
    export_bytes: $($meta.ecomm2601b.bytes)
    min_export_bytes: 1025
    sites: $($meta.ecomm2601b.sites)
    chans: $($meta.ecomm2601b.chans)
    antes: $($meta.ecomm2601b.antes)
    ops: [print, import, tsip]
    tsip:
      parm_file: ecomm2601b
      run_name: TS1
      baseline_run_id: $(if ($rid2601b) { $rid2601b } else { 'null' })

defaults:
  default_print_fixture: ecomm2602
  default_import_fixture: ecomm2602
  default_validate_fixture: cat
  default_tsip_fixture: ecomm2601b
"@

[System.IO.File]::WriteAllText($baselinesPath, $yaml, [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote $baselinesPath"
Write-Host ("TSIP baselines: ecomm2602={0} ecomm2601b={1}" -f $rid2602, $rid2601b)
