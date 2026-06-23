#Requires -Version 5.1
<#
.SYNOPSIS
    Run SQL against the remicsdev database via sqlcmd (Windows integrated auth).

.DESCRIPTION
    Wrapper for sqlcmd with remicsdev defaults. Used by agents and humans from CentralProject.
    Connection defaults match D:\inetpub\remicsdev\mics\web.config (SQL_INSTANCE, DBName).

.PARAMETER Query
    Inline SQL to execute.

.PARAMETER InputFile
    Path to a .sql file to execute.

.PARAMETER Server
    SQL Server instance. Default: EC2AMAZ-9DKDM82\REMICS_DEV
    Override with env REMICS_SQL_SERVER or .env.local REMICS_SQL_SERVER.

.PARAMETER Database
    Database name. Default: remicsdev
    Override with env REMICS_SQL_DATABASE or .env.local REMICS_SQL_DATABASE.

.PARAMETER ReadOnly
    Reject queries that appear to modify data or schema (INSERT, UPDATE, DELETE, DDL, EXEC).

.PARAMETER ListSchemas
    List schemas and table counts, then exit.

.PARAMETER ListTables
    List tables in a schema (default: web). Use -Schema to choose.

.PARAMETER Schema
    Schema name for -ListTables (default: web).

.EXAMPLE
    .\Invoke-RemicsDevSql.ps1 -Query "SELECT TOP 5 name FROM sys.tables ORDER BY name"

.EXAMPLE
    .\Invoke-RemicsDevSql.ps1 -ListSchemas

.EXAMPLE
    .\Invoke-RemicsDevSql.ps1 -ListTables -Schema web

.EXAMPLE
    .\Invoke-RemicsDevSql.ps1 -InputFile .\ddl\web.tsip_run.sql
#>
[CmdletBinding(DefaultParameterSetName = 'Query')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Query')]
    [string]$Query,

    [Parameter(Mandatory, ParameterSetName = 'File')]
    [string]$InputFile,

    [Parameter(ParameterSetName = 'ListSchemas')]
    [switch]$ListSchemas,

    [Parameter(ParameterSetName = 'ListTables')]
    [switch]$ListTables,

    [string]$Server,
    [string]$Database,
    [string]$Schema = 'web',
    [switch]$ReadOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EnvLocalValue {
    param([string]$Key)
    $envFile = Join-Path (Split-Path $PSScriptRoot -Parent) '.env.local'
    if (-not (Test-Path $envFile)) { return $null }
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.+?)\s*$") {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

function Resolve-SqlCmdPath {
    $cmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = 'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE'
    if (Test-Path $fallback) { return $fallback }
    throw 'sqlcmd not found. Install SQL Server Command Line Utilities or ODBC tools.'
}

function Test-ReadOnlyQuery {
    param([string]$Sql)
    $patterns = @(
        '^\s*INSERT\b',
        '^\s*UPDATE\b',
        '^\s*DELETE\b',
        '^\s*MERGE\b',
        '^\s*TRUNCATE\b',
        '^\s*DROP\b',
        '^\s*CREATE\b',
        '^\s*ALTER\b',
        '^\s*EXEC\b',
        '^\s*EXECUTE\b'
    )
    foreach ($batch in ($Sql -split '(?i)\bGO\b')) {
        $trimmed = $batch.Trim()
        if (-not $trimmed) { continue }
        foreach ($p in $patterns) {
            if ($trimmed -match $p) {
                throw "ReadOnly mode blocked a statement matching: $p"
            }
        }
    }
}

$Server = if ($Server) { $Server }
          elseif ($env:REMICS_SQL_SERVER) { $env:REMICS_SQL_SERVER }
          elseif (Get-EnvLocalValue 'REMICS_SQL_SERVER') { Get-EnvLocalValue 'REMICS_SQL_SERVER' }
          else { 'EC2AMAZ-9DKDM82\REMICS_DEV' }

$Database = if ($Database) { $Database }
            elseif ($env:REMICS_SQL_DATABASE) { $env:REMICS_SQL_DATABASE }
            elseif (Get-EnvLocalValue 'REMICS_SQL_DATABASE') { Get-EnvLocalValue 'REMICS_SQL_DATABASE' }
            else { 'remicsdev' }

$sqlcmd = Resolve-SqlCmdPath

$commonArgs = @(
    '-S', $Server,
    '-d', $Database,
    '-E',
    '-W',
    '-s', '|'
)

if ($ListSchemas) {
    $Query = @"
SELECT s.name AS schema_name, COUNT(*) AS table_count
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
GROUP BY s.name
ORDER BY table_count DESC, s.name;
"@
}
elseif ($ListTables) {
    $safeSchema = $Schema -replace '[^\w]', ''
    $Query = @"
SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '$safeSchema'
ORDER BY TABLE_NAME;
"@
}
elseif ($InputFile) {
    if (-not (Test-Path $InputFile)) {
        throw "Input file not found: $InputFile"
    }
    if ($ReadOnly) {
        Test-ReadOnlyQuery -Sql (Get-Content $InputFile -Raw)
    }
    & $sqlcmd @commonArgs '-i' (Resolve-Path $InputFile).Path
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd exited with code $LASTEXITCODE" }
    return
}
elseif (-not $Query) {
    throw 'Provide -Query, -InputFile, -ListSchemas, or -ListTables.'
}

if ($ReadOnly) {
    Test-ReadOnlyQuery -Sql $Query
}

& $sqlcmd @commonArgs '-Q' $Query
if ($LASTEXITCODE -ne 0) { throw "sqlcmd exited with code $LASTEXITCODE" }
