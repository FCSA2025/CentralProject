#Requires -Version 5.1
<#
.SYNOPSIS
    Drop orphan auto-import ft_* table sets left by remicsdev file-op tests in schema rctl.

.DESCRIPTION
    Scans INFORMATION_SCHEMA for ft_*_titl tables whose roots match allowlisted test
    prefixes (cata*, e2602a*, e2601a*, cat_auto*). Never drops pinned fixtures
    (cat, ecomm2602, ecomm2601b). Uses ftImport -x (drop then exit).

.PARAMETER WhatIf
    List matching roots without dropping.

.PARAMETER Password
    Optional MICS PASSWORD env for ftImport (defaults same as Invoke-MicsFileOpCompare).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Schema = 'rctl',
    [string]$Project = 'rctl1_0',
    [string]$MicsUser = 'rctl1',
    [string]$Password = '',
    [string]$LogDir = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$ftImport = 'D:\develbat\ftImport.exe'
$workDir = "D:\Inetpub\remicsdev\mics\userdirs\$Schema\$MicsUser\"

$TestTablePrefixes = @('cata', 'e2602a', 'e2601a', 'cat_auto')
$PinnedTableRoots = @('cat', 'ecomm2602', 'ecomm2601b')

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

function Invoke-SqlRows {
    param([string]$Query)
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $sqlScript -Query $Query 2>&1 | Out-String
    $lines = @($raw -split "`r?`n" | Where-Object {
        $_ -and
        $_ -notmatch '^---' -and
        $_ -notmatch '^-+$' -and
        $_ -notmatch '^\(' -and
        $_ -notmatch 'rows affected'
    })
    if ($lines.Count -lt 2) { return @() }
    $headers = @($lines[0] -split '\|')
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^-+$') { continue }
        $parts = @($lines[$i] -split '\|')
        if ($parts.Count -lt $headers.Count) { continue }
        $obj = [ordered]@{}
        for ($ci = 0; $ci -lt $headers.Count; $ci++) {
            $obj[$headers[$ci].Trim()] = $parts[$ci].Trim()
        }
        $rows += [pscustomobject]$obj
    }
    return $rows
}

function Test-IsAllowlistedTestTableName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    $n = $Name.Trim().ToLowerInvariant()
    foreach ($pinned in $PinnedTableRoots) {
        if ($n -eq $pinned.ToLowerInvariant()) { return $false }
    }
    foreach ($prefix in $TestTablePrefixes) {
        if ($n.StartsWith($prefix.ToLowerInvariant())) { return $true }
    }
    return $false
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
}

if (-not (Test-Path $sqlScript)) { throw "SQL helper missing: $sqlScript" }
if (-not (Test-Path $ftImport)) { throw "ftImport.exe not found at $ftImport" }
if (-not (Test-Path $workDir)) { throw "Work dir missing: $workDir" }

if (-not $Password) { $Password = $env:MICS_TEST_PASSWORD }
if (-not $Password) { $Password = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
if (-not $Password) { $Password = 'x' }

if (-not $LogDir) {
    $LogDir = Join-Path $env:TEMP ("remicsdev-cleanup-{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Set-MicsBatchEnv -WorkDir $workDir -Project $Project -Pwd $Password -User $MicsUser

$titlRows = @(Invoke-SqlRows -Query @"
SELECT TABLE_NAME AS n
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '$Schema'
  AND TABLE_NAME LIKE 'ft_%_titl'
ORDER BY TABLE_NAME
"@)

$candidates = New-Object System.Collections.Generic.List[string]
foreach ($row in $titlRows) {
    $tn = [string]$row.n
    if ($tn -match '^ft_(.+)_titl$') {
        $root = $Matches[1]
        if (Test-IsAllowlistedTestTableName -Name $root) {
            if (-not $candidates.Contains($root)) { $candidates.Add($root) }
        }
    }
}

$results = @()
foreach ($root in $candidates) {
    $entry = [ordered]@{ name = $root; ok = $false; skipped = $false; message = '' }
    if ($WhatIfPreference -or -not $PSCmdlet.ShouldProcess("ft_${root}_*", 'Drop via ftImport -x')) {
        $entry.ok = $true
        $entry.skipped = $true
        $entry.message = "Would drop ft_${root}_*"
        $results += [pscustomobject]$entry
        continue
    }
    $junk = Join-Path $LogDir ("cleanup_{0}.junk" -f $root)
    Set-Content -Path $junk -Value 'x' -Encoding ASCII
    $stdout = Join-Path $LogDir ("ftImport_cleanup_$root.out.txt")
    $stderr = Join-Path $LogDir ("ftImport_cleanup_$root.err.txt")
    $proc = Start-Process -FilePath $ftImport -ArgumentList @('remicsdev', $Project, $root, $junk, '-x') `
        -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $still = @(Invoke-SqlRows -Query @"
SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA='$Schema' AND TABLE_NAME='ft_${root}_titl'
"@)
    $count = 0
    if ($still.Count -ge 1) {
        $cVal = $still[-1].c
        if ($null -eq $cVal) { $cVal = @($still[-1].PSObject.Properties)[0].Value }
        if ("$cVal" -match '^\d+$') { $count = [int]$cVal }
    }
    if ($count -eq 0) {
        $entry.ok = $true
        $entry.message = "Dropped ft_${root}_* (exit $($proc.ExitCode))"
    } else {
        $entry.ok = $false
        $entry.message = "Still present after cleanup exit=$($proc.ExitCode)"
    }
    $results += [pscustomobject]$entry
}

$dropped = @($results | Where-Object { $_.ok -and -not $_.skipped }).Count
$failed = @($results | Where-Object { -not $_.ok }).Count
$summary = [ordered]@{
    schema = $Schema
    candidates = $candidates.Count
    dropped = $dropped
    failed = $failed
    log_dir = $LogDir
    results = $results
}

if ($Json) {
    $summary | ConvertTo-Json -Depth 5 -Compress
} else {
    Write-Host ("Schema={0} candidates={1} dropped={2} failed={3}" -f $Schema, $candidates.Count, $dropped, $failed)
    Write-Host ("LogDir={0}" -f $LogDir)
    foreach ($r in $results) {
        Write-Host ("  {0}: {1}" -f $r.name, $r.message)
    }
}

if ($failed -gt 0) { exit 1 }
exit 0
