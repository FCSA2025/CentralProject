#Requires -Version 5.1
<#
.SYNOPSIS
    Install six reserved TS/ES fixtures in every schema with an active MICS user.

.DESCRIPTION
    Installs testts1, testts2, testts3, testes1, testes2, and testes3 using
    FtImport/FeImport. Existing table sets are skipped unless -Force is used.
    Only the six reserved roots can be replaced; no other table names are touched.

    One account/project pair is selected per schema. The tables are schema-wide,
    so every MICS ID mapped to that schema can see the same fixtures.

.PARAMETER Schema
    Optional schema allowlist. By default, all schemas referenced by active users.

.PARAMETER WhatIf
    Report intended imports without changing database tables.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Schema = @(),
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$fixtureDir = Join-Path $repoRoot 'tests\remicsdev\fixtures\files'
$ftImport = 'D:\develbat\FtImport.exe'
$feImport = 'D:\develbat\FeImport.exe'
$userDirsRoot = 'D:\Inetpub\remicsdev\mics\userdirs'

foreach ($required in @($sqlScript, $ftImport, $feImport)) {
    if (-not (Test-Path $required)) {
        throw "Required file not found: $required"
    }
}

$fixtures = @(
    [pscustomobject]@{ Kind = 'TS'; Root = 'testts1'; Path = (Join-Path $fixtureDir 'testts1.txt') },
    [pscustomobject]@{ Kind = 'TS'; Root = 'testts2'; Path = (Join-Path $fixtureDir 'testts2.txt') },
    [pscustomobject]@{ Kind = 'TS'; Root = 'testts3'; Path = (Join-Path $fixtureDir 'testts3.txt') },
    [pscustomobject]@{ Kind = 'ES'; Root = 'testes1'; Path = (Join-Path $fixtureDir 'testes1.txt') },
    [pscustomobject]@{ Kind = 'ES'; Root = 'testes2'; Path = (Join-Path $fixtureDir 'testes2.txt') },
    [pscustomobject]@{ Kind = 'ES'; Root = 'testes3'; Path = (Join-Path $fixtureDir 'testes3.txt') }
)

foreach ($fixture in $fixtures) {
    if (-not (Test-Path $fixture.Path)) {
        throw "Fixture file not found: $($fixture.Path)"
    }
}

function Invoke-MicsSqlRows {
    param([Parameter(Mandatory)][string]$Query)

    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $sqlScript -Query $Query 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "SQL query failed:`n$raw"
    }

    $lines = @($raw -split "`r?`n" | Where-Object {
        $_ -and
        $_ -notmatch '^\(\d+ rows? affected\)$'
    })
    if ($lines.Count -lt 2) {
        return @()
    }

    $headers = @($lines[0] -split '\|' | ForEach-Object { $_.Trim() })
    $rows = @()
    for ($i = 2; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '\|') { continue }
        $parts = @($lines[$i] -split '\|')
        if ($parts.Count -ne $headers.Count) { continue }
        $row = [ordered]@{}
        for ($column = 0; $column -lt $headers.Count; $column++) {
            $row[$headers[$column]] = $parts[$column].Trim()
        }
        $rows += [pscustomobject]$row
    }
    return $rows
}

$accountQuery = @"
WITH ActiveSchemas AS (
    SELECT DISTINCT RTRIM(u.PrimarySchema) AS schema_name
    FROM dbo.t_UserDetails u
    INNER JOIN sys.schemas s
      ON s.name = RTRIM(u.PrimarySchema)
    WHERE RTRIM(u.IsActiveYN) = 'Y'
      AND NULLIF(RTRIM(u.PrimarySchema), '') IS NOT NULL
)
SELECT
    a.schema_name,
    RTRIM(candidate.micsid) AS micsid,
    RTRIM(candidate.pcode) AS project
FROM ActiveSchemas a
OUTER APPLY (
    SELECT TOP (1) p.micsid, p.pcode
    FROM adm.project_ids p
    LEFT JOIN dbo.t_UserDetails u
      ON RTRIM(u.micsId) = RTRIM(p.micsid)
    WHERE RTRIM(p.ultrixid) = a.schema_name
    ORDER BY
      CASE WHEN RTRIM(u.IsActiveYN) = 'Y' THEN 0 ELSE 1 END,
      CASE WHEN p.defaultcode = '*' THEN 0 ELSE 1 END,
      RTRIM(p.micsid),
      RTRIM(p.pcode)
) candidate
ORDER BY a.schema_name
"@

$targets = @(Invoke-MicsSqlRows -Query $accountQuery)
if ($Schema.Count -gt 0) {
    $requested = @{}
    foreach ($name in $Schema) { $requested[$name.Trim().ToLowerInvariant()] = $true }
    $targets = @($targets | Where-Object { $requested.ContainsKey($_.schema_name.ToLowerInvariant()) })
}

if ($targets.Count -eq 0) {
    throw 'No target schemas found.'
}

$missingProject = @($targets | Where-Object { -not $_.micsid -or -not $_.project })
if ($missingProject.Count -gt 0) {
    throw "No account/project pair for schemas: $($missingProject.schema_name -join ', ')"
}

$existingQuery = @"
SELECT TABLE_SCHEMA AS schema_name, TABLE_NAME AS table_name
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME IN (
    'ft_testts1_titl', 'ft_testts2_titl', 'ft_testts3_titl',
    'fe_testes1_titl', 'fe_testes2_titl', 'fe_testes3_titl'
)
"@
$existing = @{}
foreach ($row in @(Invoke-MicsSqlRows -Query $existingQuery)) {
    $existing[("$($row.schema_name)|$($row.table_name)").ToLowerInvariant()] = $true
}

$results = New-Object System.Collections.Generic.List[object]

foreach ($target in $targets) {
    $schemaName = [string]$target.schema_name
    $micsId = [string]$target.micsid
    $project = [string]$target.project
    $workDir = Join-Path (Join-Path $userDirsRoot $schemaName) $micsId

    $env:MICSUSER = $micsId
    $env:PASSWORD = 'x'
    $env:Domain = 'CLOUDMICSDEV'
    $env:odbc = 'remicsdev'
    $env:DBName = 'remicsdev'
    $env:SqlInstance = 'EC2AMAZ-9DKDM82\REMICS_DEV'
    $env:MICS_PROJECT = $project
    $env:work_dir = $workDir + '\'
    $env:WORK_DIR = $env:work_dir
    $env:webdrive = 'D:'

    if (-not (Test-Path $workDir) -and $PSCmdlet.ShouldProcess($workDir, 'Create fixture installer work directory')) {
        New-Item -ItemType Directory -Force -Path $workDir | Out-Null
    }

    foreach ($fixture in $fixtures) {
        $label = "$schemaName.$($fixture.Kind.ToLowerInvariant())_$($fixture.Root)"
        $titleTable = if ($fixture.Kind -eq 'TS') {
            "ft_$($fixture.Root)_titl"
        } else {
            "fe_$($fixture.Root)_titl"
        }
        $existingKey = ("$schemaName|$titleTable").ToLowerInvariant()
        if (-not $Force -and $existing.ContainsKey($existingKey)) {
            $results.Add([pscustomobject]@{
                Schema = $schemaName; MicsId = $micsId; Project = $project
                Kind = $fixture.Kind; Root = $fixture.Root; ExitCode = 0; Status = 'Exists'
            })
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($label, 'Replace reserved shared test fixture')) {
            $results.Add([pscustomobject]@{
                Schema = $schemaName; MicsId = $micsId; Project = $project
                Kind = $fixture.Kind; Root = $fixture.Root; ExitCode = $null; Status = 'WhatIf'
            })
            continue
        }

        if ($Force -and $existing.ContainsKey($existingKey)) {
            $schemaSql = $schemaName.Replace("'", "''")
            $prefix = if ($fixture.Kind -eq 'TS') { 'ft' } else { 'fe' }
            $tablePattern = "$prefix[_]$($fixture.Root)[_]%"
            $dropSql = @"
DECLARE @dropSql nvarchar(max) = N'';
SELECT @dropSql += N'DROP TABLE ' + QUOTENAME(TABLE_SCHEMA) + N'.' + QUOTENAME(TABLE_NAME) + N';'
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '$schemaSql'
  AND TABLE_NAME LIKE '$tablePattern';
EXEC sp_executesql @dropSql;
"@
            Invoke-MicsSqlRows -Query $dropSql | Out-Null
        }

        $importPath = $fixture.Path
        if ($fixture.Kind -eq 'TS') {
            # TS SD records embed a six-character operator code. Imports into a
            # different schema otherwise succeed with empty site/ante/chan tables.
            $importPath = Join-Path $workDir ("{0}_shared_fixture.tmp" -f $fixture.Root)
            $operatorCode = $schemaName.ToUpperInvariant()
            Get-Content $fixture.Path | ForEach-Object {
                if ($_ -match '^SD,') {
                    $_ -replace '^SD,([^,]*),[^,]*,', ("SD,`$1,{0}," -f $operatorCode)
                } else {
                    $_
                }
            } | Set-Content $importPath -Encoding ASCII
        }

        $output = if ($fixture.Kind -eq 'TS') {
            & $ftImport 'remicsdev' $project $fixture.Root $importPath '-f' 2>&1 | Out-String
        } else {
            & $feImport '-d' 'remicsdev' $project $fixture.Root $importPath 2>&1 | Out-String
        }
        $exitCode = $LASTEXITCODE
        if ($fixture.Kind -eq 'TS') {
            Remove-Item $importPath -Force -ErrorAction SilentlyContinue
        }
        $status = if ($exitCode -eq 0) { 'Imported' } else { 'Failed' }

        $results.Add([pscustomobject]@{
            Schema = $schemaName; MicsId = $micsId; Project = $project
            Kind = $fixture.Kind; Root = $fixture.Root; ExitCode = $exitCode; Status = $status
        })

        if ($exitCode -ne 0) {
            throw "$label import failed with exit $exitCode`n$output"
        }
    }
}

$results | Sort-Object Schema, Kind, Root | Format-Table -AutoSize
Write-Host ("Installed {0} fixture sets across {1} schemas." -f $results.Count, $targets.Count)
