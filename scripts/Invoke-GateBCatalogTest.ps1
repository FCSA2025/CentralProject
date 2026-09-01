#Requires -Version 5.1
<#
.SYNOPSIS
    Gate B catalog integrity checks: drift query, reconcile proc, HTTP reconcile.ashx.

.PARAMETER User
    MICS login for HTTP reconcile test (default rctl1).
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.cloudmicsdev.ca/mics/',
    [string]$User = 'rctl1',
    [string]$Password = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$InvokeSql = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'

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

if (-not $Password) { $Password = $env:MICS_TEST_PASSWORD }
if (-not $Password) { $Password = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
if (-not $Password) { $Password = 'x' }

$driftQuery = @'
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#phys') IS NOT NULL DROP TABLE #phys;
CREATE TABLE #phys (
    operator VARCHAR(8) COLLATE DATABASE_DEFAULT NOT NULL,
    tabletype INT NOT NULL,
    file_name VARCHAR(128) COLLATE DATABASE_DEFAULT NOT NULL,
    PRIMARY KEY (operator, tabletype, file_name)
);
INSERT INTO #phys (operator, tabletype, file_name)
SELECT CAST(RTRIM(t.TABLE_SCHEMA) AS VARCHAR(8)), 0,
       CAST(SUBSTRING(t.TABLE_NAME, 4, LEN(t.TABLE_NAME) - 8) AS VARCHAR(128))
FROM INFORMATION_SCHEMA.TABLES t
WHERE t.TABLE_TYPE = 'BASE TABLE' AND t.TABLE_NAME LIKE 'ft\_%\_titl' ESCAPE '\'
  AND t.TABLE_SCHEMA COLLATE DATABASE_DEFAULT NOT IN ('web','sys','dbo','guest','INFORMATION_SCHEMA','adm');
INSERT INTO #phys (operator, tabletype, file_name)
SELECT CAST(RTRIM(t.TABLE_SCHEMA) AS VARCHAR(8)), 5,
       CAST(SUBSTRING(t.TABLE_NAME, 4, LEN(t.TABLE_NAME) - 8) AS VARCHAR(128))
FROM INFORMATION_SCHEMA.TABLES t
WHERE t.TABLE_TYPE = 'BASE TABLE' AND t.TABLE_NAME LIKE 'fe\_%\_titl' ESCAPE '\'
  AND t.TABLE_SCHEMA COLLATE DATABASE_DEFAULT NOT IN ('web','sys','dbo','guest','INFORMATION_SCHEMA','adm');
INSERT INTO #phys (operator, tabletype, file_name)
SELECT CAST(RTRIM(t.TABLE_SCHEMA) AS VARCHAR(8)), 417,
       CAST(SUBSTRING(t.TABLE_NAME, 4, LEN(t.TABLE_NAME) - 8) AS VARCHAR(128))
FROM INFORMATION_SCHEMA.TABLES t
WHERE t.TABLE_TYPE = 'BASE TABLE' AND t.TABLE_NAME LIKE 'tp\_%\_parm' ESCAPE '\'
  AND t.TABLE_SCHEMA COLLATE DATABASE_DEFAULT NOT IN ('web','sys','dbo','guest','INFORMATION_SCHEMA','adm');

SELECT
    (SELECT COUNT(*) FROM web.user_tables u
     WHERE u.tabletype IN (0,5,417)
       AND NOT EXISTS (
           SELECT 1 FROM #phys p
           WHERE p.operator = RTRIM(u.operator) COLLATE DATABASE_DEFAULT
             AND p.tabletype = u.tabletype
             AND p.file_name = RTRIM(u.file_name) COLLATE DATABASE_DEFAULT)) AS catalog_orphans,
    (SELECT COUNT(*) FROM #phys p
     WHERE NOT EXISTS (
           SELECT 1 FROM web.user_tables u
           WHERE RTRIM(u.operator) COLLATE DATABASE_DEFAULT = p.operator
             AND u.tabletype = p.tabletype
             AND RTRIM(u.file_name) COLLATE DATABASE_DEFAULT = p.file_name)) AS catalog_missing;
'@

Write-Host '=== Gate B: catalog drift (before reconcile) ==='
$before = & $InvokeSql -ReadOnly -Query $driftQuery
Write-Host $before

Write-Host '=== Gate B: live reconcile (all operators) ==='
& $InvokeSql -Query "SET NOCOUNT ON; EXEC web.ReconcileUserTables @Operator = NULL, @DryRun = 0, @SyncValidstat = 1;"

Write-Host '=== Gate B: catalog drift (after reconcile) ==='
$after = & $InvokeSql -ReadOnly -Query $driftQuery
Write-Host $after

$orphansAfter = 0
$missingAfter = 0
foreach ($line in ($after -split "`n")) {
    if ($line -match '^\s*(\d+)\s*\|\s*(\d+)\s*$') {
        $orphansAfter = [int]$Matches[1]
        $missingAfter = [int]$Matches[2]
    }
}

$failures = @()
if ($orphansAfter -gt 0) { $failures += "catalog_orphans=$orphansAfter after reconcile" }
if ($missingAfter -gt 0) { $failures += "catalog_missing=$missingAfter after reconcile" }

$base = $BaseUrl.TrimEnd('/') + '/'
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$loginUrl = $base + 'RemIcsReWrite/login.aspx'
$null = Invoke-WebRequest -Uri $loginUrl -Method POST -Body @{ user = $User; password = $Password } -WebSession $session -MaximumRedirection 10 -UseBasicParsing
$sess = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/session.ashx') -WebSession $session -UseBasicParsing
$json = $sess.Content | ConvertFrom-Json
if (-not $json.ok) { throw "Login failed for $User" }
$schema = $json.schema
Write-Host "=== Gate B: HTTP reconcile.ashx user=$User schema=$schema ==="

$rec = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/reconcile.ashx') -Method POST -WebSession $session -UseBasicParsing
$recJson = $rec.Content | ConvertFrom-Json
Write-Host ($rec.Content)
if (-not $recJson.ok) { $failures += 'reconcile.ashx returned ok=false' }
if ($recJson.schema -ne $schema) { $failures += "reconcile.ashx schema mismatch: $($recJson.schema) vs $schema" }

$existsUrl = $base + 'RemIcsReWrite/files.ashx?filetype=TS&name=testts1'
$ex = Invoke-WebRequest -Uri $existsUrl -WebSession $session -UseBasicParsing
$exJson = $ex.Content | ConvertFrom-Json
Write-Host "files.ashx testts1: exists=$($exJson.exists) catalogExists=$($exJson.catalogExists) catalogDrift=$($exJson.catalogDrift)"
if (-not $exJson.ok) { $failures += 'files.ashx exists check failed' }
if ($null -eq $exJson.PSObject.Properties['catalogExists']) { $failures += 'files.ashx missing catalogExists field' }

if ($failures.Count -gt 0) {
    Write-Host "FAIL Gate B:"
    $failures | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

Write-Host "PASS Gate B catalog integrity (drift orphans=$orphansAfter missing=$missingAfter; HTTP reconcile ok)"
