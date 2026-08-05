#Requires -Version 5.1
<#
.SYNOPSIS
    Install pinned complex TS/ES fixtures (cmxts*, cmxes*) into rctl/xci/dnd schemas.

.DESCRIPTION
    Imports master exports from tests/remicsdev/fixtures/files/complex/ into each
    target schema under reserved pinned names. Adapts TS operator field per schema.

.PARAMETER Schema
    Optional schema allowlist (default: rctl, xci, dnd from manifest).

.PARAMETER Fixture
    Install a single fixture id.

.PARAMETER IncludeStress
    Also install cmxts02 (very large).

.PARAMETER Force
    Drop and re-import existing pinned tables.

.PARAMETER WhatIf
    Report actions without changing database tables.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Schema = @(),
    [string]$Fixture = '',
    [switch]$IncludeStress,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$manifestPath = Join-Path $repoRoot 'tests\remicsdev\fixtures\complex-manifest.yaml'
$filesRoot = Join-Path $repoRoot 'tests\remicsdev\fixtures\files'
$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$ftImport = 'D:\develbat\FtImport.exe'
$feImport = 'D:\develbat\FeImport.exe'
$ftValidate = 'D:\develbat\FtValidate.exe'
$feValidate = 'D:\develbat\FeValidate.exe'
$userDirsRoot = 'D:\Inetpub\remicsdev\mics\userdirs'

foreach ($required in @($sqlScript, $ftImport, $feImport, $manifestPath)) {
    if (-not (Test-Path $required)) { throw "Required file not found: $required" }
}

function Invoke-MicsSqlRows {
    param([Parameter(Mandatory)][string]$Query)
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $sqlScript -Query $Query 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "SQL query failed:`n$raw" }
    $lines = @($raw -split "`r?`n" | Where-Object {
        $_ -and
        $_ -notmatch '^\(\d+ rows? affected\)$' -and
        $_ -notmatch '^-+$' -and
        $_ -notmatch '^-+\|'
    })
    if ($lines.Count -lt 2) { return @() }
    $headers = @($lines[0] -split '\|' | ForEach-Object { $_.Trim() })
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '\|') { continue }
        $parts = @($lines[$i] -split '\|')
        if ($parts.Count -ne $headers.Count) { continue }
        if ($parts[0] -match '^-+$') { continue }
        $row = [ordered]@{}
        for ($column = 0; $column -lt $headers.Count; $column++) {
            $row[$headers[$column]] = $parts[$column].Trim()
        }
        $rows += [pscustomobject]$row
    }
    return $rows
}

function Read-ComplexManifest {
    param([string]$Path)
    $fixtures = @{}
    $targetSchemas = @()
    $current = $null
    $inTsip = $false
    $inTargets = $false
    foreach ($rawLine in Get-Content $Path) {
        $line = $rawLine
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^target_schemas:\s*$') { $inTargets = $true; $current = $null; continue }
        if ($line -match '^fixtures:\s*$') { $inTargets = $false; continue }
        if ($inTargets -and $line -match '^\s{2}-\s+(\S+)') {
            $targetSchemas += $Matches[1]
            continue
        }
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
    return @{ fixtures = $fixtures; target_schemas = $targetSchemas }
}

function Get-MicsPassword {
    param([string]$User)
    $key = 'MICS_TEST_PASSWORD_' + $User.ToUpperInvariant()
    $pwd = [Environment]::GetEnvironmentVariable($key)
    if (-not $pwd) { $pwd = $env:MICS_TEST_PASSWORD }
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

function Ensure-TsCatalogRow {
    param([string]$Schema, [string]$FileName, [string]$MicsId, [string]$Project)
    $schemaSql = $Schema.Replace("'", "''")
    $fileSql = $FileName.Replace("'", "''")
    $micsSql = $MicsId.Replace("'", "''")
    $projSql = $Project.Replace("'", "''")
    $q = @"
IF NOT EXISTS (
    SELECT 1 FROM web.user_tables
    WHERE operator = '$schemaSql' AND tabletype = 0 AND file_name = '$fileSql'
)
BEGIN
    INSERT INTO web.user_tables (operator, tabletype, file_name, micsid, project_code, validstat, create_date)
    VALUES ('$schemaSql', 0, '$fileSql', '$micsSql', '$projSql', 'N', CURRENT_TIMESTAMP);
END
"@
    Invoke-MicsSqlRows -Query $q | Out-Null
}

function Ensure-EsCatalogRow {
    param([string]$Schema, [string]$FileName, [string]$MicsId, [string]$Project)
    $schemaSql = $Schema.Replace("'", "''")
    $fileSql = $FileName.Replace("'", "''")
    $micsSql = $MicsId.Replace("'", "''")
    $projSql = $Project.Replace("'", "''")
    $q = @"
IF NOT EXISTS (
    SELECT 1 FROM web.user_tables
    WHERE operator = '$schemaSql' AND tabletype = 5 AND file_name = '$fileSql'
)
BEGIN
    INSERT INTO web.user_tables (operator, tabletype, file_name, micsid, project_code, validstat, create_date)
    VALUES ('$schemaSql', 5, '$fileSql', '$micsSql', '$projSql', 'N', CURRENT_TIMESTAMP);
END
"@
    Invoke-MicsSqlRows -Query $q | Out-Null
}

function Drop-PinnedTables {
    param([string]$Schema, [string]$Root, [string]$FileType)
    $schemaSql = $Schema.Replace("'", "''")
    $prefix = if ($FileType -eq 'ES') { 'fe' } else { 'ft' }
    $dropSql = @"
DECLARE @dropSql nvarchar(max) = N'';
SELECT @dropSql += N'DROP TABLE ' + QUOTENAME(TABLE_SCHEMA) + N'.' + QUOTENAME(TABLE_NAME) + N';'
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '$schemaSql'
  AND TABLE_NAME LIKE '${prefix}[_]$Root[_]%';
IF LEN(@dropSql) > 0 EXEC sp_executesql @dropSql;
"@
    Invoke-MicsSqlRows -Query $dropSql | Out-Null
}

$doc = Read-ComplexManifest -Path $manifestPath
$fixtures = $doc.fixtures
$defaultSchemas = @($doc.target_schemas)
if ($defaultSchemas.Count -eq 0) { $defaultSchemas = @('rctl', 'xci', 'dnd') }

$accountQuery = @"
WITH TargetSchemas AS (
    SELECT value AS schema_name
    FROM (VALUES ('rctl'), ('xci'), ('dnd')) AS v(value)
)
SELECT
    t.schema_name,
    RTRIM(candidate.micsid) AS micsid,
    RTRIM(candidate.pcode) AS project
FROM TargetSchemas t
OUTER APPLY (
    SELECT TOP (1) p.micsid, p.pcode
    FROM adm.project_ids p
    LEFT JOIN dbo.t_UserDetails u ON RTRIM(u.micsId) = RTRIM(p.micsid)
    WHERE RTRIM(p.ultrixid) = t.schema_name
      AND RTRIM(p.pcode) LIKE '%_0'
    ORDER BY
      CASE WHEN RTRIM(u.IsActiveYN) = 'Y' THEN 0 ELSE 1 END,
      CASE WHEN RTRIM(p.micsid) IN ('rctl1','xci1','dnd1') THEN 0 ELSE 1 END,
      RTRIM(p.micsid)
) candidate
ORDER BY t.schema_name
"@

$targets = @(Invoke-MicsSqlRows -Query $accountQuery)
if ($Schema.Count -gt 0) {
    $requested = @{}
    foreach ($name in $Schema) { $requested[$name.Trim().ToLowerInvariant()] = $true }
    $targets = @($targets | Where-Object { $requested.ContainsKey($_.schema_name.ToLowerInvariant()) })
}
if ($targets.Count -eq 0) { throw 'No target schemas found.' }

$fixtureIds = @($fixtures.Keys | Sort-Object)
if ($Fixture) { $fixtureIds = @($Fixture) }

$results = New-Object System.Collections.Generic.List[object]

foreach ($target in $targets) {
    $schemaName = ([string]$target.schema_name).Trim()
    $micsId = ([string]$target.micsid).Trim()
    $project = ([string]$target.project).Trim()
    if (-not $micsId -or -not $project) {
        throw "No account/project for schema $schemaName"
    }

    Set-MicsBatchEnv -User $micsId -Project $project -Schema $schemaName -Pwd (Get-MicsPassword -User $micsId)
    $workDir = $env:work_dir

    foreach ($id in $fixtureIds) {
        $fx = $fixtures[$id]
        if ($fx.ContainsKey('stress') -and $fx.stress -eq $true -and -not $IncludeStress) { continue }

        $fileType = ([string]$fx.file_type).ToUpperInvariant()
        $pinned = [string]$fx.pinned_name
        $masterRel = [string]$fx.master_file
        $masterPath = Join-Path $filesRoot ($masterRel -replace '^files/', '')
        if (-not (Test-Path $masterPath)) {
            throw "Master export missing for $id : $masterPath (run Export-RemicsDevComplexMasters.ps1 first)"
        }

        $titleTable = if ($fileType -eq 'ES') { "fe_${pinned}_titl" } else { "ft_${pinned}_titl" }
        $exists = @(Invoke-MicsSqlRows -Query @"
SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA='$($schemaName.Replace("'","''"))' AND TABLE_NAME='$titleTable'
"@)
        $already = ($exists.Count -ge 1 -and [string]$exists[0].c -match '^\d+$' -and [int]$exists[0].c -gt 0)

        if ($already -and -not $Force) {
            $results.Add([pscustomobject]@{
                Schema = $schemaName; Fixture = $id; Pinned = $pinned; Status = 'Exists'
            })
            continue
        }

        $label = "$schemaName.$pinned"
        if (-not $PSCmdlet.ShouldProcess($label, 'Install complex pinned fixture')) {
            $results.Add([pscustomobject]@{
                Schema = $schemaName; Fixture = $id; Pinned = $pinned; Status = 'WhatIf'
            })
            continue
        }

        if ($Force -and $already) {
            Drop-PinnedTables -Schema $schemaName -Root $pinned -FileType $fileType
        }

        $importPath = $masterPath
        $valStatus = 'Installed'
        if ($fileType -eq 'TS') {
            $importPath = Join-Path ($workDir.TrimEnd('\')) ("{0}_install.tmp" -f $pinned)
            $operatorCode = $schemaName.ToUpperInvariant()
            Get-Content $masterPath | ForEach-Object {
                if ($_ -match '^SD,') {
                    $_ -replace '^SD,([^,]*),[^,]*,', ("SD,`$1,{0}," -f $operatorCode)
                } else { $_ }
            } | Set-Content $importPath -Encoding ASCII
        }

        if ($fileType -eq 'TS') {
            $proc = Start-Process -FilePath $ftImport -ArgumentList @('remicsdev', $project, $pinned, $importPath, '-f') -Wait -PassThru -NoNewWindow
            Remove-Item $importPath -Force -ErrorAction SilentlyContinue
            if ($proc.ExitCode -ne 0) { throw "$label import failed exit $($proc.ExitCode)" }
            Ensure-TsCatalogRow -Schema $schemaName -FileName $pinned -MicsId $micsId -Project $project
            $valOut = Join-Path $workDir ("{0}_validate.txt" -f $pinned)
            $val = Start-Process -FilePath $ftValidate -ArgumentList @('remicsdev', $project, $pinned, ("-o{0}" -f $valOut)) -Wait -PassThru -NoNewWindow
            $valStatus = if ($val.ExitCode -eq 0) { 'Installed' } else { "Installed (validate exit $($val.ExitCode))" }
            if ($val.ExitCode -ne 0) { Write-Warning ("{0} validate exit {1} - tables imported; review {2}" -f $label, $val.ExitCode, $valOut) }
        } else {
            $proc = Start-Process -FilePath $feImport -ArgumentList @('-d', 'remicsdev', $project, $pinned, $importPath) -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -ne 0) { throw "$label import failed exit $($proc.ExitCode)" }
            $titleTable = "fe_${pinned}_titl"
            $schemaSql = $schemaName.Replace("'", "''")
            $checkSql = "SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='$schemaSql' AND TABLE_NAME='$titleTable'"
            $check = @(Invoke-MicsSqlRows -Query $checkSql)
            $titlOk = ($check.Count -ge 1 -and [string]$check[0].c -match '^\d+$' -and [int]$check[0].c -gt 0)
            if (-not $titlOk) { throw "$label import reported success but $titleTable missing in $schemaName" }
            Ensure-EsCatalogRow -Schema $schemaName -FileName $pinned -MicsId $micsId -Project $project
            $valOut = Join-Path $workDir ("{0}_validate.txt" -f $pinned)
            $val = Start-Process -FilePath $feValidate -ArgumentList @('remicsdev', $project, $pinned, ("-o{0}" -f $valOut)) -Wait -PassThru -NoNewWindow
            $valStatus = if ($val.ExitCode -eq 0) { 'Installed' } else { "Installed (validate exit $($val.ExitCode))" }
            if ($val.ExitCode -ne 0) { Write-Warning ("{0} validate exit {1} - tables imported; review {2}" -f $label, $val.ExitCode, $valOut) }
        }

        $results.Add([pscustomobject]@{
            Schema = $schemaName; Fixture = $id; Pinned = $pinned; Status = $valStatus
        })
    }
}

$results | Sort-Object Schema, Fixture | Format-Table -AutoSize
Write-Host ("Processed {0} fixture operations across {1} schema(s)." -f $results.Count, $targets.Count)
