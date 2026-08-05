#Requires -Version 5.1
<#
.SYNOPSIS
    Discover complex TS/ES files in remicsdev for Phase 0b fixture harvesting.

.DESCRIPTION
    Ranks ft_* / fe_* PDFs by site/chan/ante counts and optional TSIP history.
    Writes tests/remicsdev/fixtures/complex-candidates.json for manual review.

.PARAMETER MinChans
    Minimum channel count for TS candidates (default 20).

.PARAMETER MinSites
    Minimum site count for TS candidates (default 10).

.PARAMETER MinEsChans
    Minimum channel count for ES candidates (default 15).

.PARAMETER Top
    Max candidates per file type to emit (default 15).

.PARAMETER JsonOnly
    Write JSON only; skip console table.
#>
[CmdletBinding()]
param(
    [int]$MinChans = 20,
    [int]$MinSites = 10,
    [int]$MinEsChans = 15,
    [int]$Top = 15,
    [switch]$JsonOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$outPath = Join-Path $repoRoot 'tests\remicsdev\fixtures\complex-candidates.json'

$excludePattern = '^(cat|testts\d*|testes\d*|cmx[a-z0-9]*|ecomm260|cata|cat_auto)'

function Invoke-MicsSqlRows {
    param([Parameter(Mandatory)][string]$Query)
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $sqlScript -ReadOnly -Query $Query 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "SQL failed:`n$raw" }
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

function Get-ScalarCount {
    param([string]$Schema, [string]$Prefix, [string]$FileName, [string]$Suffix)
    $safeSchema = $Schema.Replace("'", "''")
    $safeFile = $FileName.Replace("'", "''")
    $table = "${Prefix}_${safeFile}_${Suffix}"
    $q = "SELECT COUNT(*) AS c FROM [$safeSchema].[$table]"
    $rows = @(Invoke-MicsSqlRows -Query $q)
    if ($rows.Count -lt 1) { return 0 }
    $val = [string]($rows[0].c)
    if ($val -match '^\d+$') { return [int]$val }
    return 0
}

function Test-ExcludedName {
    param([string]$Name)
    return ($Name -match $excludePattern)
}

$schemaRows = @(Invoke-MicsSqlRows -Query @"
SELECT DISTINCT TABLE_SCHEMA AS schema_name
FROM INFORMATION_SCHEMA.TABLES
WHERE (TABLE_NAME LIKE 'ft[_]%[_]titl' OR TABLE_NAME LIKE 'fe[_]%[_]titl')
  AND TABLE_SCHEMA NOT IN ('sys', 'INFORMATION_SCHEMA', 'dbo', 'web', 'adm')
ORDER BY TABLE_SCHEMA
"@)

$tsCandidates = New-Object System.Collections.Generic.List[object]
$esCandidates = New-Object System.Collections.Generic.List[object]

foreach ($schemaRow in $schemaRows) {
    $schema = [string]$schemaRow.schema_name
    $safeSchema = $schema.Replace("'", "''")

    $tsFiles = @(Invoke-MicsSqlRows -Query @"
SELECT SUBSTRING(TABLE_NAME, 4, LEN(TABLE_NAME) - 8) AS file_name
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '$safeSchema' AND TABLE_NAME LIKE 'ft[_]%[_]titl'
"@)
    foreach ($ts in $tsFiles) {
        $name = [string]$ts.file_name
        if (Test-ExcludedName -Name $name) { continue }
        $chans = Get-ScalarCount -Schema $schema -Prefix 'ft' -FileName $name -Suffix 'chan'
        $sites = Get-ScalarCount -Schema $schema -Prefix 'ft' -FileName $name -Suffix 'site'
        $antes = Get-ScalarCount -Schema $schema -Prefix 'ft' -FileName $name -Suffix 'ante'
        if ($chans -ge $MinChans -or $sites -ge $MinSites) {
            $tsCandidates.Add([pscustomobject]@{
                file_type      = 'TS'
                source_schema  = $schema
                source_file    = $name
                sites          = $sites
                chans          = $chans
                antes          = $antes
                score          = ($chans * 3) + ($sites * 2) + $antes
            })
        }
    }

    $esFiles = @(Invoke-MicsSqlRows -Query @"
SELECT SUBSTRING(TABLE_NAME, 4, LEN(TABLE_NAME) - 8) AS file_name
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '$safeSchema' AND TABLE_NAME LIKE 'fe[_]%[_]titl'
"@)
    foreach ($es in $esFiles) {
        $name = [string]$es.file_name
        if (Test-ExcludedName -Name $name) { continue }
        $chans = Get-ScalarCount -Schema $schema -Prefix 'fe' -FileName $name -Suffix 'chan'
        $sites = Get-ScalarCount -Schema $schema -Prefix 'fe' -FileName $name -Suffix 'site'
        $antes = Get-ScalarCount -Schema $schema -Prefix 'fe' -FileName $name -Suffix 'ante'
        if ($chans -ge $MinEsChans -or $sites -ge 8) {
            $esCandidates.Add([pscustomobject]@{
                file_type      = 'ES'
                source_schema  = $schema
                source_file    = $name
                sites          = $sites
                chans          = $chans
                antes          = $antes
                score          = ($chans * 3) + ($sites * 2) + $antes
            })
        }
    }
}

$tsipRows = @(Invoke-MicsSqlRows -Query @"
SELECT source_schema, parm_file, protype,
       MAX(CAST(num_int_cases AS int)) AS max_cases,
       MAX(CONVERT(varchar(33), run_started_utc, 126)) AS last_run
FROM web.tsip_run
WHERE archive_status = 'complete'
GROUP BY source_schema, parm_file, protype
ORDER BY max_cases DESC
"@)

$tsTop = @($tsCandidates | Sort-Object score -Descending | Select-Object -First $Top)
$esTop = @($esCandidates | Sort-Object score -Descending | Select-Object -First $Top)

if ($tsTop.Count -eq 0 -and $esTop.Count -eq 0) {
    Write-Warning "No files met discovery thresholds. See complex-manifest.yaml for curated selections."
}

$payload = [ordered]@{
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    criteria      = [ordered]@{
        min_chans_ts = $MinChans
        min_sites_ts = $MinSites
        min_chans_es = $MinEsChans
        top          = $Top
    }
    tsip_history  = @($tsipRows | Select-Object -First 20)
    ts_candidates = $tsTop
    es_candidates = $esTop
    recommended_selection = [ordered]@{
        cmxts01 = if ($tsTop.Count -ge 1) { $tsTop[0] } else { $null }
        cmxts02 = if ($tsTop.Count -ge 2) { $tsTop[1] } else { $null }
        cmxts03 = if ($tsTop.Count -ge 3) { $tsTop[2] } else { $null }
        cmxes01 = if ($esTop.Count -ge 1) { $esTop[0] } else { $null }
        cmxes02 = if ($esTop.Count -ge 2) { $esTop[1] } else { $null }
    }
}

$json = $payload | ConvertTo-Json -Depth 6
$dir = Split-Path $outPath -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
[System.IO.File]::WriteAllText($outPath, $json, [System.Text.UTF8Encoding]::new($false))

if (-not $JsonOnly) {
    Write-Host "Wrote $outPath"
    Write-Host "`nTop TS candidates:"
    $tsTop | Format-Table -AutoSize
    Write-Host "Top ES candidates:"
    $esTop | Format-Table -AutoSize
    Write-Host "Recommended selection:"
    $payload.recommended_selection.GetEnumerator() | ForEach-Object { Write-Host ("  {0}: {1}" -f $_.Key, ($_.Value | ConvertTo-Json -Compress)) }
}
