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

.PARAMETER Submitter
    Staging filename prefix / audit submitter (default dnd1). Match the MICS account
    used for import, validate, and DbUpdate export.

.PARAMETER TargetOperator
    TS SD operator code on delete/add staging (default DND).

.PARAMETER ValidateSample
    Run import+validate on first delete and first add-back file per type against fwmda.
    Requires sites in main.* (run Initialize-CircularSeq10Main.ps1 once first).
#>
[CmdletBinding()]
param(
    [switch]$InstallToInbox,
    [string]$Submitter = 'dnd1',
    [string]$TargetOperator = 'DND',
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
$Submitter = $Submitter.Trim()
if (-not $Submitter) { throw 'Submitter is required' }
$TsOperator = $TargetOperator.Trim()
if (-not $TsOperator) { throw 'TargetOperator is required' }

# Five delete/add pairs. TS reuses 2-site ecomm2601 block; ES reuses 1-site xci-es140km block.
$PairCount = 5
$TsSitesPerPair = 2
$EsSitesPerPair = 1

# Proven import/validate masters (same families as cmxts03 / cmxes02 smoke fixtures)
$TsMaster = Join-Path $filesRoot 'complex\RCTL-ECOMM2601.TXT'
$EsMaster = Join-Path $filesRoot 'complex\XCI-ES140KM.TXT'

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
    Get-ChildItem $Dir -Filter ("{0}_*.txt" -f $Submitter) -File | Remove-Item -Force
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

function Set-TsAddBackBlock {
    param($Block)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Get-BlockLines $Block)) {
        if ($line -match '^(SK|AK|CK),') {
            $line = $line -replace '^(SK|AK|CK),([^,]*),', '$1,A,'
        }
        $out.Add((Set-TsSdOperator -Line $line -Operator $TsOperator))
    }
    return $out
}

function Set-EsAddBackBlock {
    param($Block)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Get-BlockLines $Block)) {
        if ($line -match '^(SK|AK|CK),') {
            $line = $line -replace '^(SK|AK|CK),([^,]*),', '$1,A,'
        }
        $out.Add($line)
    }
    return $out
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
    $lines.Add("* TS-PDF: $PdfName, circular seq10 $Submitter $(Get-Date -Format 'yyyy.MM.dd HH:mm:ss')")
    $lines.Add('*')
    $lines.Add("TT,U,$PdfName,,,,")
    foreach ($block in $SiteBlocks) {
        $lines.Add('*##############################################################################')
        $use = if ($DeletePass) { Set-TsDeleteBlock -Block $block } else { Set-TsAddBackBlock -Block $block }
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
    $lines.Add("* ES-PDF: $PdfName, circular seq10 $Submitter $(Get-Date -Format 'yyyy.MM.dd HH:mm:ss')")
    $lines.Add("*===========================================================================")
    $lines.Add('TE,N,ISEDESS23B, , ,')
    $lines.Add('TD,')
    foreach ($block in $SiteBlocks) {
        $use = if ($DeletePass) { Set-EsDeleteBlock -Block $block } else { Set-EsAddBackBlock -Block $block }
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

function Build-TsSeedStaging {
    param(
        [object[]]$SiteBlocks,
        [string]$PdfName
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("* TS-PDF: $PdfName, circular seq10 seed $Submitter $(Get-Date -Format 'yyyy.MM.dd HH:mm:ss')")
    $lines.Add('*')
    $lines.Add("TT,U,$PdfName,,,,")
    foreach ($block in $SiteBlocks) {
        $lines.Add('*##############################################################################')
        $use = Copy-BlockLines -Block $block
        foreach ($line in $use) {
            if ($line -match '^(SK|SD|AK|CK|AQ|AO|CT|CR|CQ|CO),' -or $line -match '^\*====' -or $line -match '^\*----' -or $line -match '^\*\+') {
                $lines.Add((Set-TsSdOperator -Line $line -Operator $TsOperator))
            }
        }
    }
    return @($lines)
}

function Build-EsSeedStaging {
    param(
        [object[]]$SiteBlocks,
        [string]$PdfName
    )
    return Build-EsStaging -SiteBlocks $SiteBlocks -PdfName $PdfName
}

function Write-BootstrapStaging {
    param(
        [ValidateSet('TS', 'ES')][string]$FileType,
        [string[]]$Content,
        [string]$PdfName
    )
    $timestamp = (Get-Date).ToString('yyMMddHHmm')
    $fileName = '{0}_{1}_{2}.txt' -f $Submitter, $timestamp, $PdfName
    $destDir = if ($FileType -eq 'TS') { $tsOut } else { $esOut }
    $destPath = Join-Path $destDir $fileName
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($destPath, ($Content -join "`r`n") + "`r`n", $utf8NoBom)
    return [pscustomobject]@{
        file_type = $FileType
        role = 'bootstrap_main'
        pdfname = $PdfName
        file = $fileName
        path = $destPath
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
        $content = Build-TsSeedStaging -SiteBlocks $AllBlocks -PdfName $pdf
    } else {
        $content = Build-EsSeedStaging -SiteBlocks $AllBlocks -PdfName $pdf
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($destPath, ($content -join "`r`n") + "`r`n", $utf8NoBom)
    $bootstrap = Write-BootstrapStaging -FileType $FileType -Content $content -PdfName $pdf
    return [pscustomobject]@{
        file_type = $FileType
        pdfname = $pdf
        path = $destPath
        bootstrap = $bootstrap
        sites = $AllBlocks.Count
        bytes = (Get-Item $destPath).Length
    }
}

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

function Invoke-SqlScalar {
    param([string]$Query)
    $sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $sqlScript -Query $Query 2>&1 | Out-String
    $lines = @($raw -split "`r?`n" | Where-Object {
        $_ -and $_ -notmatch '^---' -and $_ -notmatch '^-+$' -and $_ -notmatch '^\(' -and $_ -notmatch 'rows affected'
    })
    if ($lines.Count -lt 2) { return $null }
    $parts = @($lines[1] -split '\|')
    if ($parts.Count -lt 1) { return $null }
    return $parts[0].Trim()
}

function Test-ImportValidate {
    param(
        [ValidateSet('TS', 'ES')][string]$FileType,
        [string]$StagingPath,
        [string]$PdfName
    )
    $importExe = if ($FileType -eq 'TS') { $ftImport } else { $feImport }
    $validateExe = if ($FileType -eq 'TS') { $ftValidate } else { $feValidate }
    foreach ($required in @($importExe, $validateExe, $killTable)) {
        if (-not (Test-Path $required)) {
            return @{ ok = $false; skipped = $true; message = "Missing $required"; path = $StagingPath; pdfname = $PdfName }
        }
    }

    $schema = Invoke-SqlScalar "SELECT RTRIM(PrimarySchema) AS c FROM dbo.t_UserDetails WHERE RTRIM(micsId)='fwmda'"
    if (-not $schema) { $schema = 'fmda2' }
    $workDir = "D:\Inetpub\remicsdev\mics\userdirs\$schema\fwmda\"
    if (-not (Test-Path $workDir)) { New-Item -ItemType Directory -Force -Path $workDir | Out-Null }
    $password = [Environment]::GetEnvironmentVariable('MICS_TEST_PASSWORD_FWMDA')
    if (-not $password) { $password = Get-EnvLocalValue 'MICS_TEST_PASSWORD_FWMDA' }
    if (-not $password) { $password = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
    if (-not $password) { $password = 'x' }
    Set-MicsBatchEnv -WorkDir $workDir -Project $MicsProject -Pwd $password -User 'fwmda'

    $logDir = Join-Path $env:TEMP ("seq10-validate-{0}" -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    try {
        $typeArg = if ($FileType -eq 'ES') { 'ES' } else { 'TS' }
        $kill = Start-Process -FilePath $killTable -ArgumentList @('remicsdev', $typeArg, $PdfName, $MicsProject) `
            -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $logDir 'kill.out') `
            -RedirectStandardError (Join-Path $logDir 'kill.err')

        $importArgs = if ($FileType -eq 'TS') {
            @('remicsdev', $MicsProject, $PdfName, $StagingPath, '-f')
        } else {
            @('-d', 'remicsdev', $MicsProject, $PdfName, $StagingPath)
        }
        $proc = Start-Process -FilePath $importExe -ArgumentList $importArgs -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput (Join-Path $logDir 'import.out') -RedirectStandardError (Join-Path $logDir 'import.err')
        if ($proc.ExitCode -ne 0) {
            $err = Get-Content (Join-Path $logDir 'import.err') -Raw -ErrorAction SilentlyContinue
            return @{ ok = $false; failed_step = 'import'; message = "Import exit=$($proc.ExitCode) $err"; path = $StagingPath; pdfname = $PdfName }
        }

        $valOut = Join-Path $workDir ("{0}.txt" -f $PdfName)
        $valArgs = @('remicsdev', $MicsProject, $PdfName, ("-o{0}" -f $valOut))
        $proc2 = Start-Process -FilePath $validateExe -ArgumentList $valArgs -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput (Join-Path $logDir 'validate.out') -RedirectStandardError (Join-Path $logDir 'validate.err')

        $prefix = if ($FileType -eq 'ES') { 'fe' } else { 'ft' }
        $safeSchema = $schema.Replace("'", "''")
        $safePdf = $PdfName.Replace("'", "''")
        $validated = Invoke-SqlScalar "SELECT validated AS c FROM ${safeSchema}.${prefix}_${safePdf}_titl"
        if (-not $validated) { $validated = 'N' }

        $valOk = ($proc2.ExitCode -eq 0) -and ($validated -in @('U', 'M'))
        return @{
            ok = $valOk
            failed_step = if ($valOk) { '' } else { 'validate' }
            validated = $validated
            import_exit = $proc.ExitCode
            validate_exit = $proc2.ExitCode
            kill_exit = $kill.ExitCode
            message = "$($validateExe | Split-Path -Leaf) exit=$($proc2.ExitCode) validated=$validated (need U or M)"
            path = $StagingPath
            pdfname = $PdfName
        }
    }
    finally {
        $typeArg = if ($FileType -eq 'ES') { 'ES' } else { 'TS' }
        $null = Start-Process -FilePath $killTable -ArgumentList @('remicsdev', $typeArg, $PdfName, $MicsProject) `
            -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $logDir 'postkill.out') `
            -RedirectStandardError (Join-Path $logDir 'postkill.err')
        Remove-Item -LiteralPath $logDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-FileSet {
    param(
        [ValidateSet('TS', 'ES')][string]$FileType,
        [string]$MasterPath,
        [object[]]$AllBlocks,
        [int]$SitesPerPair,
        [int]$Pairs = $PairCount
    )
    if (-not (Test-Path $MasterPath)) { throw "Master not found: $MasterPath" }
    if ($AllBlocks.Count -lt $SitesPerPair) {
        throw "$FileType master has $($AllBlocks.Count) sites; need at least $SitesPerPair"
    }

    # Reuse the same proven site block(s) for every pair (repeatable net-zero cycle).
    $pairBlocks = @($AllBlocks[0..($SitesPerPair - 1)])

    $written = @()
    $usedBlocks = New-Object System.Collections.Generic.List[object]
    foreach ($b in $pairBlocks) { [void]$usedBlocks.Add($b) }
    $baseTime = Get-Date
    $seq = 0

    for ($pair = 1; $pair -le $Pairs; $pair++) {
        $chunk = @($pairBlocks)
        $size = $chunk.Count
        if ($size -lt 1) { throw "Pair $pair has no site blocks" }

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

$tsSet = New-FileSet -FileType TS -MasterPath $TsMaster -AllBlocks $tsBlocks -SitesPerPair $TsSitesPerPair -Pairs $PairCount
$esSet = New-FileSet -FileType ES -MasterPath $EsMaster -AllBlocks $esBlocks -SitesPerPair $EsSitesPerPair -Pairs $PairCount

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
    pair_count = $PairCount
    ts_sites_per_pair = $TsSitesPerPair
    es_sites_per_pair = $EsSitesPerPair
    ts = @{
        master_source = 'files/complex/rctl-ecomm2601.txt'
        sites_available = $tsBlocks.Count
        sites_used = $tsSet.sites_used
        master = $tsSet.master
        files = $tsSet.files
        output_dir = $tsOut
        sites_per_pair = $TsSitesPerPair
    }
    es = @{
        master_source = 'files/complex/xci-es140km.txt'
        sites_available = $esBlocks.Count
        sites_used = $esSet.sites_used
        master = $esSet.master
        files = $esSet.files
        output_dir = $esOut
        sites_per_pair = $EsSitesPerPair
    }
    sequence = @($tsSet.files | Sort-Object sequence | ForEach-Object {
        [pscustomobject]@{ order = $_.sequence; type = 'TS'; file = $_.file; pass = $_.pass; sites = $_.sites }
    }) + @($esSet.files | Sort-Object sequence | ForEach-Object {
        [pscustomobject]@{ order = $_.sequence; type = 'ES'; file = $_.file; pass = $_.pass; sites = $_.sites }
    })
    validation = $validation
    workflow = @(
        "Install-MicsComplexFixtures.ps1 -Schema dnd -Fixture cycts10   # operator schema (TS)"
        "Install-MicsComplexFixtures.ps1 -Schema dnd -Fixture cyces10   # operator schema (ES)"
        'Initialize-CircularSeq10Main.ps1   # one-time: seed main.* via bootstrap staging files'
        'Operator (dnd1): import staging -> validate -> DbUpdate export to inbox'
        'Testing inbox: Validate all -> Update all validated (spoof-first)'
        'Repeat delete/add pairs 01d,01a .. 05d,05a in timestamp order'
        'After all 10 files per type: database returns to starting state'
    )
    bootstrap = @{
        ts = $tsSet.master.bootstrap
        es = $esSet.master.bootstrap
    }
}

$manifestPath = Join-Path $outRoot 'seq10-manifest.json'
Write-JobJson -Path $manifestPath -Payload $summary
Write-Output ($summary | ConvertTo-Json -Depth 8)
