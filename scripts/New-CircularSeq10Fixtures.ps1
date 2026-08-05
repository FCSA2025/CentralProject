#Requires -Version 5.1
<#
.SYNOPSIS
    Generate 10 TS + 10 ES circular DbUpdate staging files (delete/add-back pairs).

.DESCRIPTION
    Builds numbered seq10 fixtures from complex masters. Files 01,03,05,07,09 delete
    site chunks; 02,04,06,08,10 restore them. Running all 10 in order yields no net
    database change when sites exist in main.* beforehand.

    Each file contains 15-100 sites (configurable chunk sizes). Outputs live under
    tests/remicsdev/fixtures/files/updates-primary/circular/seq10/.

.PARAMETER InstallToInbox
    Copy TS files to D:\updates\primary\ and ES files to UnprocessedESFiles\.

.PARAMETER ValidateSample
    Run FeImport/FtImport + validate on first delete and first add-back file per type.
#>
[CmdletBinding()]
param(
    [switch]$InstallToInbox,
    [switch]$ValidateSample
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$filesRoot = Join-Path $RepoRoot 'tests\remicsdev\fixtures\files'
$outRoot = Join-Path $filesRoot 'updates-primary\circular\seq10'
$tsOut = Join-Path $outRoot 'ts'
$esOut = Join-Path $outRoot 'es'
$tsInbox = 'D:\updates\primary'
$esInbox = Join-Path $tsInbox 'UnprocessedESFiles'
$Submitter = 'cyc1'
$TsOperator = 'DND'

# Per-file site counts (5 pairs, each 15-100 sites)
$ChunkSizes = @(20, 25, 30, 40, 55)

$TsMaster = Join-Path $filesRoot 'complex\XCI-TAFLI19B.TXT'
$EsMaster = Join-Path $filesRoot 'complex\RCTL-RERT.TXT'

$ftImport = 'D:\develbat\ftImport.exe'
$ftValidate = 'D:\develbat\ftValidate.exe'
$feImport = 'D:\develbat\feImport.exe'
$feValidate = 'D:\develbat\feValidate.exe'
$killTable = 'D:\develbat\KillTable.exe'
$MicsProject = 'fwmda_0'

function Write-JobJson {
    param([string]$Path, [object]$Payload)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Set-Content -Path $Path -Value ($Payload | ConvertTo-Json -Depth 8) -Encoding UTF8
}

function Clear-OldFixtures {
    param([string]$Dir)
    if (-not (Test-Path $Dir)) { return }
    Get-ChildItem $Dir -Filter 'cyc1_*.txt' -File | Remove-Item -Force
}

function Split-TsSiteBlocks {
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

function Split-EsSiteBlocks {
    param([string[]]$Lines)
    $blocks = New-Object System.Collections.Generic.List[object]
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^SK,') {
            if ($start -ge 0) {
                [void]$blocks.Add([object](,$Lines[$start..($i - 1)]))
            }
            $start = $i
            if ($i -gt 0 -and $Lines[$i - 1] -match '^\*-{10,}') { $start = $i - 1 }
        }
    }
    if ($start -ge 0) {
        [void]$blocks.Add([object](,$Lines[$start..($Lines.Count - 1)]))
    }
    return ,@($blocks.ToArray())
}

function Set-TsSdOperator {
    param([string]$Line, [string]$Operator)
    if ($line -notmatch '^SD,') { return $Line }
    return ($Line -replace '^SD,([^,]*),[^,]*,', ("SD,`$1,{0}," -f $Operator))
}

function Set-TsDeleteBlock {
    param($Block)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Get-BlockLines $Block)) {
        if ($line -match '^(SK|AK|CK),') {
            $line = $line -replace '^(SK|AK|CK),([^,]*),', '$1,D,'
        }
        $out.Add((Set-TsSdOperator -Line $line -Operator $TsOperator))
    }
    return $out
}

function Get-BlockLines {
    param($Block)
    if ($null -eq $Block) { return @() }
    if ($Block -is [string]) { return @($Block -split "`r?`n") }
    if ($Block -is [System.Collections.IEnumerable] -and -not ($Block -is [string])) {
        $items = @($Block)
        if ($items.Count -eq 1 -and $items[0] -is [array]) {
            return @($items[0] | ForEach-Object { [string]$_ })
        }
        return @($items | ForEach-Object { [string]$_ })
    }
    return @([string]$Block)
}

function Set-EsDeleteBlock {
    param($Block)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Get-BlockLines $Block)) {
        if ($line -match '^(SK|AK|CK),') {
            $line = $line -replace '^(SK|AK|CK),([^,]*),', '$1,D,'
        }
        $out.Add($line)
    }
    return $out
}

function Copy-BlockLines {
    param($Block)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Get-BlockLines $Block)) { $out.Add($line) }
    return $out
}

function Build-TsStaging {
    param(
        [object[]]$SiteBlocks,
        [string]$PdfName,
        [switch]$DeletePass
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("* TS-PDF: $PdfName, circular seq10 cyc1 $(Get-Date -Format 'yyyy.MM.dd HH:mm:ss')")
    $lines.Add('*')
    $lines.Add("TT,U,$PdfName,,,,")
    foreach ($block in $SiteBlocks) {
        $lines.Add('*##############################################################################')
        $use = if ($DeletePass) { Set-TsDeleteBlock -Block $block } else { Copy-BlockLines -Block $block }
        foreach ($line in $use) {
            if ($line -match '^(SK|SD|AK|CK|AQ|AO|CT|CR|CQ|CO),' -or $line -match '^\*====' -or $line -match '^\*----' -or $line -match '^\*\+') {
                $lines.Add($line)
            }
        }
    }
    return @($lines)
}

function Build-EsStaging {
    param(
        [object[]]$SiteBlocks,
        [string]$PdfName,
        [switch]$DeletePass
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("*===========================================================================")
    $lines.Add("* ES-PDF: $PdfName, circular seq10 cyc1 $(Get-Date -Format 'yyyy.MM.dd HH:mm:ss')")
    $lines.Add("*===========================================================================")
    $lines.Add('TE,N,ISEDESS23B, , ,')
    $lines.Add('TD,')
    foreach ($block in $SiteBlocks) {
        $use = if ($DeletePass) { Set-EsDeleteBlock -Block $block } else { Copy-BlockLines -Block $block }
        foreach ($line in $use) {
            if ($line -match '^(SK|SD|AK|AT|AR|AS|CK|CT|CR|ZK),' -or $line -match '^\*-{10,}') {
                $lines.Add($line)
            }
        }
    }
    return @($lines)
}

function Get-PdfName {
    param([ValidateSet('TS', 'ES')][string]$FileType, [int]$Pair, [ValidateSet('del', 'add')][string]$Pass)
    $prefix = if ($FileType -eq 'TS') { 'cycts' } else { 'cyces' }
    $letter = if ($Pass -eq 'del') { 'd' } else { 'a' }
    return ('{0}{1:D2}{2}' -f $prefix, $Pair, $letter)
}

function Write-StagingFile {
    param(
        [ValidateSet('TS', 'ES')][string]$FileType,
        [string[]]$Content,
        [int]$Sequence,
        [int]$Pair,
        [ValidateSet('del', 'add')][string]$Pass,
        [int]$SiteCount,
        [string]$Timestamp
    )
    $pdf = Get-PdfName -FileType $FileType -Pair $Pair -Pass $Pass
    $fileName = '{0}_{1}_{2}.txt' -f $Submitter, $Timestamp, $pdf
    $destDir = if ($FileType -eq 'TS') { $tsOut } else { $esOut }
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $destPath = Join-Path $destDir $fileName
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($destPath, ($Content -join "`r`n") + "`r`n", $utf8NoBom)

    $installed = $null
    if ($InstallToInbox) {
        $inbox = if ($FileType -eq 'TS') { $tsInbox } else { $esInbox }
        if (-not (Test-Path $inbox)) { New-Item -ItemType Directory -Force -Path $inbox | Out-Null }
        $installed = Join-Path $inbox $fileName
        Copy-Item -LiteralPath $destPath -Destination $installed -Force
    }

    return [pscustomobject]@{
        sequence = $Sequence
        file_type = $FileType
        pass = $Pass
        pair = $Pair
        pdfname = $pdf
        file = $fileName
        path = $destPath
        installed = $installed
        sites = $SiteCount
        bytes = (Get-Item $destPath).Length
    }
}

function Write-MasterExport {
    param(
        [ValidateSet('TS', 'ES')][string]$FileType,
        [object[]]$AllBlocks
    )
    $pdf = if ($FileType -eq 'TS') { 'cycts10' } else { 'cyces10' }
    $destDir = if ($FileType -eq 'TS') { $tsOut } else { $esOut }
    $destPath = Join-Path $destDir ("{0}-master.txt" -f $pdf)
    if ($FileType -eq 'TS') {
        $content = Build-TsStaging -SiteBlocks $AllBlocks -PdfName $pdf
    } else {
        $content = Build-EsStaging -SiteBlocks $AllBlocks -PdfName $pdf
    }
    if (Test-Path $destPath) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($destPath, ($content -join "`r`n") + "`r`n", $utf8NoBom)
    }
    return [pscustomobject]@{
        file_type = $FileType
        pdfname = $pdf
        path = $destPath
        sites = $AllBlocks.Count
        bytes = (Get-Item $destPath).Length
    }
}

function Test-ImportValidate {
    param(
        [ValidateSet('TS', 'ES')][string]$FileType,
        [string]$StagingPath,
        [string]$PdfName
    )
    $importExe = if ($FileType -eq 'TS') { $ftImport } else { $feImport }
    $validateExe = if ($FileType -eq 'TS') { $ftValidate } else { $feValidate }
    foreach ($required in @($importExe, $validateExe)) {
        if (-not (Test-Path $required)) {
            return @{ ok = $false; skipped = $true; message = "Missing $required" }
        }
    }
    $workDir = Join-Path $env:TEMP ("cyc1-validate-{0}" -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Force -Path $workDir | Out-Null
    try {
        $dropExe = if ($FileType -eq 'TS') { $ftImport } else { $feImport }
        $dropArgs = @('remicsdev', $MicsProject, $PdfName, 'junk', '-x')
        $null = Start-Process -FilePath $dropExe -ArgumentList $dropArgs `
            -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $workDir 'drop.out') `
            -RedirectStandardError (Join-Path $workDir 'drop.err')
        $importArgs = if ($FileType -eq 'TS') {
            @('-f', 'remicsdev', $MicsProject, $PdfName, $StagingPath)
        } else {
            @('-d', 'remicsdev', $MicsProject, $PdfName, $StagingPath)
        }
        $proc = Start-Process -FilePath $importExe -ArgumentList $importArgs -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput (Join-Path $workDir 'import.out') -RedirectStandardError (Join-Path $workDir 'import.err')
        if ($proc.ExitCode -ne 0) {
            $err = Get-Content (Join-Path $workDir 'import.err') -Raw -ErrorAction SilentlyContinue
            return @{ ok = $false; message = "Import exit=$($proc.ExitCode) $err"; path = $StagingPath }
        }
        $valArgs = @('remicsdev', $MicsProject, $PdfName)
        $proc2 = Start-Process -FilePath $validateExe -ArgumentList $valArgs -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput (Join-Path $workDir 'validate.out') -RedirectStandardError (Join-Path $workDir 'validate.err')
        $validated = 'unknown'
        $valOut = Get-Content (Join-Path $workDir 'validate.out') -Raw -ErrorAction SilentlyContinue
        if ($valOut -match 'validated\s*=\s*(\S+)') { $validated = $Matches[1] }
        return @{
            ok = ($proc2.ExitCode -eq 0)
            validated = $validated
            message = "Import exit=0 Validate exit=$($proc2.ExitCode) validated=$validated"
            path = $StagingPath
        }
    }
    finally {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-FileSet {
    param(
        [ValidateSet('TS', 'ES')][string]$FileType,
        [string]$MasterPath,
        [object[]]$AllBlocks
    )
    if (-not (Test-Path $MasterPath)) { throw "Master not found: $MasterPath" }
    if ($AllBlocks.Count -lt ($ChunkSizes | Measure-Object -Sum).Sum) {
        throw "$FileType master has $($AllBlocks.Count) sites; need at least $(($ChunkSizes | Measure-Object -Sum).Sum)"
    }

    $written = @()
    $usedBlocks = New-Object System.Collections.Generic.List[object]
    $offset = 0
    $baseTime = Get-Date
    $seq = 0

    for ($pair = 1; $pair -le $ChunkSizes.Count; $pair++) {
        $size = $ChunkSizes[$pair - 1]
        if ($size -lt 15 -or $size -gt 100) { throw "Chunk size $size out of range 15-100" }
        $chunk = @($AllBlocks[$offset..($offset + $size - 1)])
        $offset += $size
        foreach ($b in $chunk) { [void]$usedBlocks.Add($b) }

        $seq++
        $tsDel = $baseTime.AddMinutes($seq).ToString('yyMMddHHmm')
        $delContent = if ($FileType -eq 'TS') {
            Build-TsStaging -SiteBlocks $chunk -PdfName (Get-PdfName -FileType $FileType -Pair $pair -Pass 'del') -DeletePass
        } else {
            Build-EsStaging -SiteBlocks $chunk -PdfName (Get-PdfName -FileType $FileType -Pair $pair -Pass 'del') -DeletePass
        }
        $written += Write-StagingFile -FileType $FileType -Content $delContent -Sequence $seq -Pair $pair -Pass 'del' -SiteCount $chunk.Count -Timestamp $tsDel

        $seq++
        $tsAdd = $baseTime.AddMinutes($seq).ToString('yyMMddHHmm')
        $addContent = if ($FileType -eq 'TS') {
            Build-TsStaging -SiteBlocks $chunk -PdfName (Get-PdfName -FileType $FileType -Pair $pair -Pass 'add')
        } else {
            Build-EsStaging -SiteBlocks $chunk -PdfName (Get-PdfName -FileType $FileType -Pair $pair -Pass 'add')
        }
        $written += Write-StagingFile -FileType $FileType -Content $addContent -Sequence $seq -Pair $pair -Pass 'add' -SiteCount $chunk.Count -Timestamp $tsAdd
    }

    $master = Write-MasterExport -FileType $FileType -AllBlocks @($usedBlocks.ToArray())
    return @{
        files = $written
        master = $master
        sites_used = $usedBlocks.Count
    }
}

if (-not (Test-Path $TsMaster)) { throw "TS master not found: $TsMaster" }
if (-not (Test-Path $EsMaster)) { throw "ES master not found: $EsMaster" }

Clear-OldFixtures -Dir $tsOut
Clear-OldFixtures -Dir $esOut

$tsBlocks = Split-TsSiteBlocks -Lines @(Get-Content $TsMaster)
$esBlocks = Split-EsSiteBlocks -Lines @(Get-Content $EsMaster)

$tsSet = New-FileSet -FileType TS -MasterPath $TsMaster -AllBlocks $tsBlocks
$esSet = New-FileSet -FileType ES -MasterPath $EsMaster -AllBlocks $esBlocks

$validation = @()
if ($ValidateSample) {
    $tsDel = @($tsSet.files | Where-Object { $_.pass -eq 'del' } | Select-Object -First 1)
    $tsAdd = @($tsSet.files | Where-Object { $_.pass -eq 'add' } | Select-Object -First 1)
    $esDel = @($esSet.files | Where-Object { $_.pass -eq 'del' } | Select-Object -First 1)
    $esAdd = @($esSet.files | Where-Object { $_.pass -eq 'add' } | Select-Object -First 1)
    if ($tsDel) { $validation += (Test-ImportValidate -FileType TS -StagingPath $tsDel.path -PdfName $tsDel.pdfname) }
    if ($tsAdd) { $validation += (Test-ImportValidate -FileType TS -StagingPath $tsAdd.path -PdfName $tsAdd.pdfname) }
    if ($esDel) { $validation += (Test-ImportValidate -FileType ES -StagingPath $esDel.path -PdfName $esDel.pdfname) }
    if ($esAdd) { $validation += (Test-ImportValidate -FileType ES -StagingPath $esAdd.path -PdfName $esAdd.pdfname) }
}

$summary = @{
    ok = $true
    fixture = 'seq10'
    submitter = $Submitter
    chunk_sizes = $ChunkSizes
    ts = @{
        master_source = 'files/complex/xci-tafli19b.txt'
        sites_available = $tsBlocks.Count
        sites_used = $tsSet.sites_used
        master = $tsSet.master
        files = $tsSet.files
        output_dir = $tsOut
    }
    es = @{
        master_source = 'files/complex/rctl-rert.txt'
        sites_available = $esBlocks.Count
        sites_used = $esSet.sites_used
        master = $esSet.master
        files = $esSet.files
        output_dir = $esOut
    }
    sequence = @($tsSet.files | Sort-Object sequence | ForEach-Object {
        [pscustomobject]@{ order = $_.sequence; type = 'TS'; file = $_.file; pass = $_.pass; sites = $_.sites }
    }) + @($esSet.files | Sort-Object sequence | ForEach-Object {
        [pscustomobject]@{ order = $_.sequence; type = 'ES'; file = $_.file; pass = $_.pass; sites = $_.sites }
    })
    validation = $validation
    workflow = @(
        'Install-MicsComplexFixtures.ps1 -Schema dnd -Fixture cycts10   # TS master subset'
        'Install-MicsComplexFixtures.ps1 -Schema dnd -Fixture cyces10   # ES master subset'
        'Copy ts/*.txt (odd=delete, even=add-back) to D:\updates\primary\ in numeric order'
        'Copy es/*.txt to D:\updates\primary\UnprocessedESFiles\ in numeric order'
        'Admin: Validate all -> Update all validated (repeat per file or batch)'
        'After files 01-10: database returns to starting state'
    )
}

$manifestPath = Join-Path $outRoot 'seq10-manifest.json'
Write-JobJson -Path $manifestPath -Payload $summary
Write-Output ($summary | ConvertTo-Json -Depth 8)
