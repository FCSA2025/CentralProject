#Requires -Version 5.1
<#
.SYNOPSIS
    Refresh fwmda spoof MDB tables as exact copies of main.* before MtUpdate -s.

.DESCRIPTION
    Ensures fmda2 (fwmda schema) has the same structure as main MDB tables, then
    replaces all rows with SELECT * FROM main. Used before spoof-first pipeline runs.

.PARAMETER FileType
    TS or ES — selects mt_*+sd_* vs me_* tables.

.PARAMETER TargetSchema
    Default fmda2 (fwmda PrimarySchema).

.PARAMETER Json
    Emit JSON summary on stdout.
#>
[CmdletBinding()]
param(
    [ValidateSet('TS', 'ES')]
    [string]$FileType = 'TS',

    [string]$TargetSchema = 'fmda2',
    [switch]$Json,
    [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$MicsUser = 'fwmda'
$Project = 'fwmda_0'
$mtUpdate = 'D:\develbat\MtUpdate.exe'
$meUpdate = 'D:\develbat\MeUpdate.exe'

$script:TsTables = @('mt_site', 'mt_ante', 'mt_chan', 'sd_town', 'sd_rout')
$script:EsTables = @('me_site', 'me_ante', 'me_azim', 'me_chan')

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

function Invoke-SqlNonQuery {
    param([string]$Query)
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $sqlScript -Query $Query 2>&1 | Out-String
    if ($raw -match '^Msg \d+,') { throw $raw.Trim() }
    return $raw
}

function Invoke-SqlRows {
    param([string]$Query)
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $sqlScript -Query $Query 2>&1 | Out-String
    if ($raw -match '^Msg \d+,') { throw $raw.Trim() }
    $lines = @($raw -split "`r?`n" | Where-Object {
        $_ -and $_ -notmatch '^---' -and $_ -notmatch '^-+$' -and $_ -notmatch '^\(' -and $_ -notmatch 'rows affected'
    })
    if ($lines.Count -lt 2) { return @() }
    $headers = @($lines[0] -split '\|')
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^-+$') { continue }
        $parts = @($lines[$i] -split '\|')
        if ($parts.Count -lt $headers.Count) { continue }
        $obj = @{}
        for ($ci = 0; $ci -lt $headers.Count; $ci++) {
            $key = $headers[$ci].Trim()
            if ([string]::IsNullOrWhiteSpace($key)) { $key = 'c' + $ci }
            $obj[$key] = $parts[$ci].Trim()
        }
        $rows += [pscustomobject]$obj
    }
    return $rows
}

function Get-SyncColumnList {
    param([string]$TargetSchema, [string]$Table)
    $safeTarget = $TargetSchema.Replace("'", "''")
    $safeTable = $Table.Replace("'", "''")
    $query = @"
SELECT mc.name AS c
FROM sys.columns mc
JOIN sys.tables mt ON mt.object_id = mc.object_id
JOIN sys.schemas ms ON ms.schema_id = mt.schema_id AND ms.name = 'main'
JOIN sys.tables ft ON ft.name = mt.name
JOIN sys.schemas fs ON fs.schema_id = ft.schema_id AND fs.name = '$safeTarget'
JOIN sys.columns fc ON fc.object_id = ft.object_id AND fc.name = mc.name AND fc.is_computed = 0
WHERE mt.name = '$safeTable'
ORDER BY mc.column_id
"@
    return @(Invoke-SqlRows -Query $query | ForEach-Object { [string]$_.c })
}

function Invoke-SqlScalar {
    param([string]$Query)
    $rows = @(Invoke-SqlRows -Query $Query)
    if ($rows.Count -lt 1) { return $null }
    $first = $rows[0].PSObject.Properties | Select-Object -First 1
    return [string]$first.Value
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
    if ($ResultPath) { Set-Content -Path $ResultPath -Value $json -Encoding UTF8 }
    if ($Json) { Write-Output $json }
    if ($ExitCode -ne 0) { exit $ExitCode }
}

function Ensure-SpoofStructures {
    param([string]$Schema, [string]$Type, [string]$LogDir)
    $probe = if ($Type -eq 'ES') { 'me_site' } else { 'mt_site' }
    $safeSchema = $Schema.Replace("'", "''")
    $exists = Invoke-SqlScalar "SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='$safeSchema' AND TABLE_NAME='$probe'"
    if ($exists -and [int]$exists -gt 0) { return @{ ok = $true; skipped = $true; message = 'Structures already present' } }

    $boot = ('sync' + (Get-Date -Format 'HHmmss')).Substring(0, 8)
    if ($Type -eq 'ES') {
        $run = Invoke-ExeCapture -FilePath $meUpdate -ArgumentList @('remicsdev', $Project, $boot, '-C') `
            -LogPath (Join-Path $LogDir 'MeUpdate_createSpoof')
    } else {
        $run = Invoke-ExeCapture -FilePath $mtUpdate -ArgumentList @('remicsdev', $Project, $boot, '-C') `
            -LogPath (Join-Path $LogDir 'MtUpdate_createSpoof')
    }
    if ($run.ExitCode -ne 0) { throw "CreateSpoof (-C) failed exit=$($run.ExitCode)" }
    return @{ ok = $true; skipped = $false; message = 'Created spoof structures via -C' }
}

function Sync-TableFromMain {
    param([string]$TargetSchema, [string]$Table)
    $safeTarget = $TargetSchema.Replace("'", "''")
    $safeTable = $Table.Replace("'", "''")
    $cols = Get-SyncColumnList -TargetSchema $TargetSchema -Table $Table
    if (-not $cols -or $cols.Count -lt 1) {
        throw "No sync columns for $TargetSchema.$Table"
    }
    $colList = ($cols | ForEach-Object { "[$_]" }) -join ', '
    $mainCount = Invoke-SqlScalar "SELECT COUNT(*) AS c FROM main.$safeTable"
    Invoke-SqlNonQuery "DELETE FROM $safeTarget.$safeTable" | Out-Null
    Invoke-SqlNonQuery "INSERT INTO $safeTarget.$safeTable ($colList) SELECT $colList FROM main.$safeTable" | Out-Null
    $copyCount = Invoke-SqlScalar "SELECT COUNT(*) AS c FROM $safeTarget.$safeTable"
    return @{
        table = $Table
        columns = $cols.Count
        main_rows = [int]$mainCount
        copied_rows = [int]$copyCount
        ok = ([int]$mainCount -eq [int]$copyCount)
    }
}

if (-not (Test-Path $sqlScript)) {
    Write-Result @{ ok = $false; error = "SQL helper missing: $sqlScript" } -ExitCode 1
}

$schemaRows = Invoke-SqlScalar "SELECT RTRIM(PrimarySchema) AS c FROM dbo.t_UserDetails WHERE RTRIM(micsId)='fwmda'"
if ($schemaRows) { $TargetSchema = $schemaRows }

$workDir = "D:\Inetpub\remicsdev\mics\userdirs\$TargetSchema\$MicsUser\"
if (-not (Test-Path $workDir)) { New-Item -ItemType Directory -Force -Path $workDir | Out-Null }

$userPwdKey = 'MICS_TEST_PASSWORD_FWMDA'
$password = [Environment]::GetEnvironmentVariable($userPwdKey)
if (-not $password) { $password = Get-EnvLocalValue $userPwdKey }
if (-not $password) { $password = $env:MICS_TEST_PASSWORD }
if (-not $password) { $password = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
if (-not $password) { $password = 'x' }

$logDir = Join-Path $env:TEMP ("fwmda-spoof-sync-{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Set-MicsBatchEnv -WorkDir $workDir -Project $Project -Pwd $password -User $MicsUser

$tables = if ($FileType -eq 'ES') { $script:EsTables } else { $script:TsTables }
$tableResults = @()

try {
    $ensure = Ensure-SpoofStructures -Schema $TargetSchema -Type $FileType -LogDir $logDir
    foreach ($t in $tables) {
        $mainExists = Invoke-SqlScalar "SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='main' AND TABLE_NAME='$t'"
        if (-not $mainExists -or [int]$mainExists -lt 1) {
            $tableResults += @{ table = $t; ok = $false; error = 'main table missing' }
            continue
        }
        $tableResults += Sync-TableFromMain -TargetSchema $TargetSchema -Table $t
    }

    # audit_trail if present in both schemas
    $auditMain = Invoke-SqlScalar "SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='main' AND TABLE_NAME='audit_trail'"
    $auditTarget = Invoke-SqlScalar "SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='$TargetSchema' AND TABLE_NAME='audit_trail'"
    if ([int]$auditMain -gt 0 -and [int]$auditTarget -gt 0) {
        $tableResults += Sync-TableFromMain -TargetSchema $TargetSchema -Table 'audit_trail'
    }

    $allOk = -not @($tableResults | Where-Object { -not $_.ok }).Count
    Write-Result @{
        ok = $allOk
        file_type = $FileType
        target_schema = $TargetSchema
        ensure = $ensure
        tables = $tableResults
        log_dir = $logDir
        summary = ($tableResults | ForEach-Object { "{0}: main={1} copied={2}" -f $_.table, $_.main_rows, $_.copied_rows }) -join '; '
    } -ExitCode $(if ($allOk) { 0 } else { 1 })
}
catch {
    Write-Result @{
        ok = $false
        file_type = $FileType
        target_schema = $TargetSchema
        error = $_.Exception.Message
        tables = $tableResults
        log_dir = $logDir
    } -ExitCode 1
}
