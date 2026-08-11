#Requires -Version 5.1
<#
.SYNOPSIS
    Copy seq10 circular staging fixtures to DbUpdate inbox folders.

.PARAMETER FileType
    TS, ES, or Both (default Both).

.PARAMETER Pair
    Copy only one pair (1-5). Default: all 10 files per type.

.PARAMETER Regenerate
    Run New-CircularSeq10Fixtures.ps1 before copying.

.PARAMETER Submitter
    Submitter prefix when regenerating fixtures (default dnd1).
#>
[CmdletBinding()]
param(
    [ValidateSet('TS', 'ES', 'Both')]
    [string]$FileType = 'Both',
    [ValidateRange(1, 5)]
    [int]$Pair = 0,
    [switch]$Regenerate,
    [string]$Submitter = 'dnd1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$seqRoot = Join-Path $RepoRoot 'tests\remicsdev\fixtures\files\updates-primary\circular\seq10'
$manifestPath = Join-Path $seqRoot 'seq10-manifest.json'
$genScript = Join-Path $PSScriptRoot 'New-CircularSeq10Fixtures.ps1'
$tsInbox = 'D:\updates\primary'
$esInbox = Join-Path $tsInbox 'UnprocessedESFiles'

if ($Regenerate) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $genScript -Submitter $Submitter
}

if (-not (Test-Path $manifestPath)) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $genScript -Submitter $Submitter
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$copied = New-Object System.Collections.Generic.List[object]
$enqueued = New-Object System.Collections.Generic.List[string]

function Copy-Files {
    param([string]$TypeKey, [string]$DestRoot)
    if (-not (Test-Path $DestRoot)) { New-Item -ItemType Directory -Force -Path $DestRoot | Out-Null }
    $files = @($manifest.$TypeKey.files | Sort-Object { [int]$_.sequence })
    if ($Pair -gt 0) {
        $files = @($files | Where-Object { [int]$_.pair -eq $Pair })
    }
    foreach ($f in $files) {
        if (-not (Test-Path $f.path)) { throw "Missing fixture: $($f.path)" }
        $dest = Join-Path $DestRoot $f.file
        Copy-Item -LiteralPath $f.path -Destination $dest -Force
        [void]$copied.Add([pscustomobject]@{ type = $TypeKey; file = $f.file; dest = $dest; sites = $f.sites; pass = $f.pass })
    }
}

if ($FileType -eq 'TS' -or $FileType -eq 'Both') { Copy-Files -TypeKey 'ts' -DestRoot $tsInbox }
if ($FileType -eq 'ES' -or $FileType -eq 'Both') { Copy-Files -TypeKey 'es' -DestRoot $esInbox }

$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
if (Test-Path $sqlScript) {
    function Escape-SqlLocal {
        param([string]$Value)
        if ($null -eq $Value) { return '' }
        return $Value.Replace("'", "''")
    }
    $emailRow = & $sqlScript -Query "SET NOCOUNT ON; SELECT TOP 1 RTRIM(email) AS email FROM adm.account_details WHERE RTRIM(micsid) = '$(Escape-SqlLocal $Submitter)';"
    $submitterEmail = ''
    foreach ($line in ($emailRow -split "`r?`n")) {
        if ($line -match '@') { $submitterEmail = ($line -split '\|' | Select-Object -Last 1).Trim(); break }
    }
    $mode = 'spoof-first'
    foreach ($item in $copied) {
        $ft = if ($item.type -eq 'es') { 'ES' } else { 'TS' }
        $meta = $null
        if ($item.file -match '^([A-Za-z0-9]+)_(\d{10})_(.+)\.txt$') {
            $pdf = $Matches[3]
            $exists = & $sqlScript -Query "SET NOCOUNT ON; SELECT COUNT(*) AS cnt FROM adm.t_UpdateQueue_local WHERE staging_file = '$(Escape-SqlLocal $item.file)' AND [status] IN ('N','P');"
            if ($exists -match '\|\s*0\s*' -or $exists -match '^\s*0\s*$') {
                $emailSql = if ($submitterEmail) { "'$(Escape-SqlLocal $submitterEmail)'" } else { 'NULL' }
                & $sqlScript -Query @"
INSERT INTO adm.t_UpdateQueue_local (staging_file, staging_path, submitter, pdf_name, file_type, submitter_email, [status], [mode])
VALUES ('$(Escape-SqlLocal $item.file)', '$(Escape-SqlLocal $item.dest)', '$(Escape-SqlLocal $Submitter)', '$(Escape-SqlLocal $pdf)', '$ft', $emailSql, 'N', '$mode');
"@ | Out-Null
                [void]$enqueued.Add($item.file)
            }
        }
    }
}

Write-Output (@{ ok = $true; copied = $copied.ToArray(); count = $copied.Count; enqueued = $enqueued.ToArray(); enqueued_count = $enqueued.Count } | ConvertTo-Json -Depth 6)
