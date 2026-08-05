#Requires -Version 5.1
<#
.SYNOPSIS
    Generate dnd1 circular DbUpdate staging pairs (delete sites / add sites back) from complex masters.

.PARAMETER Fixture
    cmxts03 (2-site smoke) or cmxts01 (274-site complex, chunked).

.PARAMETER SitesPerFile
    Sites per staging file when chunking (default: 46 for cmxts01, all sites for cmxts03).

.PARAMETER InstallToInbox
    Also copy generated files to D:\updates\primary\
#>
[CmdletBinding()]
param(
    [ValidateSet('cmxts03', 'cmxts01')]
    [string]$Fixture = 'cmxts03',
    [int]$SitesPerFile = 0,
    [switch]$InstallToInbox
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$manifestPath = Join-Path $RepoRoot 'tests\remicsdev\fixtures\complex-manifest.yaml'
$filesRoot = Join-Path $RepoRoot 'tests\remicsdev\fixtures\files'
$outRoot = Join-Path $filesRoot 'updates-primary\circular\dnd1'
$inboxRoot = 'D:\updates\primary'
$Submitter = 'dnd1'
$TargetOperator = 'DND'

function Read-ManifestEntry {
    param([string]$Id)
    $lines = Get-Content $manifestPath
    $inFixture = $false
    $entry = @{}
    foreach ($line in $lines) {
        if ($line -match ("^  {0}:\s*$" -f [regex]::Escape($Id))) { $inFixture = $true; continue }
        if ($inFixture -and $line -match '^  [a-z0-9]+:\s*$') { break }
        if (-not $inFixture) { continue }
        if ($line -match '^\s+master_file:\s*(.+)$') { $entry.master_file = $Matches[1].Trim() }
        if ($line -match '^\s+sites:\s*(\d+)') { $entry.sites = [int]$Matches[1] }
    }
    if (-not $entry.master_file) { throw "Fixture $Id not found in manifest" }
    return $entry
}

function Split-FtPrintSiteBlocks {
    param([string[]]$Lines)
    $blocks = New-Object System.Collections.Generic.List[object]
    $current = $null
    foreach ($line in $Lines) {
        if ($line -match '^\*#{10,}\s*$') {
            if ($null -ne $current -and @($current | Where-Object { $_ -match '^SK,' }).Count -gt 0) {
                [void]$blocks.Add([object]$current)
            }
            $current = New-Object System.Collections.Generic.List[string]
            continue
        }
        if ($null -eq $current) { continue }
        [void]$current.Add($line)
    }
    if ($null -ne $current -and @($current | Where-Object { $_ -match '^SK,' }).Count -gt 0) {
        [void]$blocks.Add([object]$current)
    }
    return ,@($blocks.ToArray())
}

function Set-SdOperator {
    param([string]$Line, [string]$Operator)
    if ($Line -notmatch '^SD,') { return $Line }
    return ($Line -replace '^SD,([^,]*),[^,]*,', ("SD,`$1,{0}," -f $Operator))
}

function Set-DeleteActions {
    param([System.Collections.Generic.List[string]]$Block)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Block) {
        if ($line -match '^(SK|AK|CK),') {
            $line = $line -replace '^(SK|AK|CK),([^,]*),', '$1,D,'
        }
        $out.Add((Set-SdOperator -Line $line -Operator $TargetOperator))
    }
    return $out
}

function Set-AddBackBlock {
    param([System.Collections.Generic.List[string]]$Block)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Block) {
        $out.Add((Set-SdOperator -Line $line -Operator $TargetOperator))
    }
    return $out
}

function Build-StagingContent {
    param(
        [object[]]$SiteBlocks,
        [string]$PdfName,
        [switch]$DeletePass
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("* TS-PDF: $PdfName, circular dnd1 fixture $(Get-Date -Format 'yyyy.MM.dd HH:mm:ss')")
    $lines.Add('*')
    $lines.Add("TT,U,$PdfName,,,,")
    foreach ($block in $SiteBlocks) {
        $lines.Add('*##############################################################################')
        $use = if ($DeletePass) { Set-DeleteActions -Block $block } else { Set-AddBackBlock -Block $block }
        foreach ($line in $use) {
            if ($line -match '^(SK|SD|AK|CK|AQ|AO|CT|CR|CQ|CO),' -or $line -match '^\*====' -or $line -match '^\*----' -or $line -match '^\*\+') {
                $lines.Add($line)
            }
        }
    }
    return @($lines)
}

function Get-PdfName {
    param([string]$Pass, [int]$Chunk, [int]$ChunkCount)
    if ($Fixture -eq 'cmxts03') {
        return $(if ($Pass -eq 'del') { 'dndc03del' } else { 'dndc03add' })
    }
    $letter = if ($Pass -eq 'del') { 'd' } else { 'a' }
    return ('dndc01{0}{1:D2}' -f $letter, $Chunk)
}

function Write-StagingFile {
    param(
        [string[]]$Content,
        [string]$Pass,
        [int]$Chunk,
        [int]$ChunkCount,
        [int]$SiteCount,
        [string]$Timestamp
    )
    $pdf = Get-PdfName -Pass $Pass -Chunk $Chunk -ChunkCount $ChunkCount
    $fileName = '{0}_{1}_{2}.txt' -f $Submitter, $Timestamp, $pdf
    $destDir = Join-Path $outRoot $Fixture
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $destPath = Join-Path $destDir $fileName
    Set-Content -Path $destPath -Value (($Content -join "`r`n") + "`r`n") -Encoding UTF8
    $installed = $null
    if ($InstallToInbox) {
        if (-not (Test-Path $inboxRoot)) { New-Item -ItemType Directory -Force -Path $inboxRoot | Out-Null }
        $installed = Join-Path $inboxRoot $fileName
        Copy-Item -LiteralPath $destPath -Destination $installed -Force
    }
    return [pscustomobject]@{
        pass = $Pass
        chunk = $Chunk
        pdfname = $pdf
        file = $fileName
        path = $destPath
        installed = $installed
        sites = $SiteCount
        bytes = (Get-Item $destPath).Length
    }
}

$entry = Read-ManifestEntry -Id $Fixture
$masterPath = Join-Path $filesRoot ($entry.master_file.Replace('files/', '').Replace('/', '\'))
if (-not (Test-Path $masterPath)) { throw "Master not found: $masterPath" }
if ($SitesPerFile -le 0) { $SitesPerFile = if ($Fixture -eq 'cmxts01') { 46 } else { 9999 } }

$allBlocks = Split-FtPrintSiteBlocks -Lines @(Get-Content $masterPath)
if ($allBlocks.Count -lt 1) { throw "No site blocks in $masterPath" }

$chunks = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $allBlocks.Count; $i += $SitesPerFile) {
    $end = [Math]::Min($i + $SitesPerFile - 1, $allBlocks.Count - 1)
    $chunk = New-Object System.Collections.Generic.List[object]
    for ($j = $i; $j -le $end; $j++) { $chunk.Add($allBlocks[$j]) | Out-Null }
    $chunks.Add(@($chunk.ToArray())) | Out-Null
}

$written = @()
$chunkNum = 0
$baseTime = Get-Date
foreach ($chunk in $chunks) {
    $chunkNum++
    $siteBlocks = @($chunk)
    $tsDel = $baseTime.AddMinutes($chunkNum * 2 - 1).ToString('yyMMddHHmm')
    $tsAdd = $baseTime.AddMinutes($chunkNum * 2).ToString('yyMMddHHmm')
    $delContent = Build-StagingContent -SiteBlocks $siteBlocks -PdfName (Get-PdfName -Pass 'del' -Chunk $chunkNum -ChunkCount $chunks.Count) -DeletePass
    $addContent = Build-StagingContent -SiteBlocks $siteBlocks -PdfName (Get-PdfName -Pass 'add' -Chunk $chunkNum -ChunkCount $chunks.Count)
    $written += Write-StagingFile -Content $delContent -Pass 'del' -Chunk $chunkNum -ChunkCount $chunks.Count -SiteCount $siteBlocks.Count -Timestamp $tsDel
    $written += Write-StagingFile -Content $addContent -Pass 'add' -Chunk $chunkNum -ChunkCount $chunks.Count -SiteCount $siteBlocks.Count -Timestamp $tsAdd
}

$summary = @{
    ok = $true
    fixture = $Fixture
    master = $entry.master_file
    sites = $allBlocks.Count
    sites_per_file = $SitesPerFile
    chunks = $chunks.Count
    files = $written
    output_dir = (Join-Path $outRoot $Fixture)
    workflow = @(
        ('Install-MicsComplexFixtures.ps1 -Schema dnd -Fixture ' + $Fixture)
        'Seed main MDB (run add-back or full update once if sites missing from main)'
        'Copy delete pass (dndc*d*.txt) to D:\updates\primary\ then Validate all then Update validated'
        'Copy add-back pass (dndc*a*.txt) to inbox then Validate all then Update validated'
        ('Restore-MicsComplexFixtures.ps1 -Schema dnd -Fixture ' + $Fixture)
    )
}
$manifestOut = Join-Path $outRoot "$Fixture-manifest.json"
Set-Content -Path $manifestOut -Value ($summary | ConvertTo-Json -Depth 8) -Encoding UTF8
Write-Output ($summary | ConvertTo-Json -Depth 8)
