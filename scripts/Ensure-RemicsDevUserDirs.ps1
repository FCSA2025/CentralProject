#Requires -Version 5.1
<#
.SYNOPSIS
    Create userdirs\{company}\{micsid} folders for every MICS account.

.DESCRIPTION
    Prevents missing-workspace failures (reports, import, PCN, TSIP) like the
    rctl3 case. Company comes from t_UserDetails.PrimarySchema when set;
    otherwise the longest matching existing company folder prefix on the micsid.
    Folders inherit NTFS ACLs from userdirs.
#>
[CmdletBinding()]
param(
    [string]$UserDirsRoot = 'D:\Inetpub\remicsdev\mics\userdirs'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $sqlcmd) {
    $fallback = 'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE'
    if (-not (Test-Path $fallback)) { throw 'sqlcmd not found' }
    $sqlcmd = $fallback
} else {
    $sqlcmd = $sqlcmd.Source
}

$query = @"
SET NOCOUNT ON;
SELECT RTRIM(micsId) AS micsId,
       ISNULL(RTRIM(PrimarySchema), '') AS schemaName,
       RTRIM(IsActiveYN) AS active
FROM dbo.t_UserDetails
WHERE micsId IS NOT NULL AND RTRIM(micsId) <> ''
ORDER BY PrimarySchema, micsId
"@

$raw = & $sqlcmd -S 'EC2AMAZ-9DKDM82\REMICS_DEV' -d remicsdev -E -W -s '|' -x -Q $query
if ($LASTEXITCODE -ne 0) { throw "sqlcmd exited with code $LASTEXITCODE" }

$rows = @()
foreach ($line in $raw) {
    if ($line -match '^-' -or $line -match '^micsId\|' -or $line -match '^\s*$') { continue }
    $parts = $line -split '\|', 3
    if ($parts.Count -lt 2) { continue }
    $rows += [pscustomobject]@{
        MicsId = $parts[0].Trim()
        Schema = $parts[1].Trim()
        Active = if ($parts.Count -ge 3) { $parts[2].Trim() } else { '' }
    }
}

if (-not (Test-Path $UserDirsRoot)) {
    throw "userdirs root not found: $UserDirsRoot"
}

$companyDirs = @(Get-ChildItem $UserDirsRoot -Directory | ForEach-Object { $_.Name })
$companyByLower = @{}
foreach ($name in $companyDirs) { $companyByLower[$name.ToLowerInvariant()] = $name }

function Resolve-CompanyFolder {
    param([string]$MicsId, [string]$Schema)
    if ($Schema -and $Schema -ne 'NULL' -and $Schema -ne '') {
        $key = $Schema.ToLowerInvariant()
        if ($companyByLower.ContainsKey($key)) { return $companyByLower[$key] }
        return $key
    }
    $id = $MicsId.ToLowerInvariant()
    $best = $null
    foreach ($name in $companyDirs) {
        $p = $name.ToLowerInvariant()
        if ($id.StartsWith($p) -and ($null -eq $best -or $p.Length -gt $best.Length)) {
            $best = $name
        }
    }
    return $best
}

$created = New-Object System.Collections.Generic.List[string]
$existed = New-Object System.Collections.Generic.List[string]
$skipped = New-Object System.Collections.Generic.List[string]

$rows = @($rows | Sort-Object @{ Expression = { if ($_.Schema) { 0 } else { 1 } } }, Schema, MicsId)

foreach ($row in $rows) {
    $company = Resolve-CompanyFolder -MicsId $row.MicsId -Schema $row.Schema
    if (-not $company) {
        $skipped.Add("$($row.MicsId) (no company)")
        continue
    }
    $companyPath = Join-Path $UserDirsRoot $company
    $userPath = Join-Path $companyPath $row.MicsId
    if (-not (Test-Path $companyPath)) {
        New-Item -ItemType Directory -Path $companyPath | Out-Null
        $companyByLower[$company.ToLowerInvariant()] = $company
        $companyDirs += $company
        $created.Add("$company\  (company)")
    }
    if (Test-Path $userPath) {
        $existed.Add("$company\$($row.MicsId)")
    } else {
        New-Item -ItemType Directory -Path $userPath | Out-Null
        $created.Add("$company\$($row.MicsId)")
    }
}

Write-Host "userdirs root: $UserDirsRoot"
Write-Host "accounts: $($rows.Count)  created: $($created.Count)  already: $($existed.Count)  skipped: $($skipped.Count)"
if ($created.Count) {
    Write-Host ""
    Write-Host "Created:"
    $created | ForEach-Object { Write-Host "  $_" }
}
if ($skipped.Count) {
    Write-Host ""
    Write-Host "Skipped:"
    $skipped | ForEach-Object { Write-Host "  $_" }
}
