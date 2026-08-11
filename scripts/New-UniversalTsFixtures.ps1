#Requires -Version 5.1
<#
.SYNOPSIS
    Generate universal TS ADD + DELETE fixture pairs for operator import.

.DESCRIPTION
    Builds operator-import files (NOT DbUpdate staging/inbox format) using reserved
    Q9U* site codes. ADD files validate on any account while sites are absent from
    main.*. Matching DELETE files (SK/A/CK -> D) validate once sites exist in main.*
    after running Initialize-UniversalTsMain.ps1 or posting the ADD through fwmda.

    Output: tests/remicsdev/fixtures/files/operator-import/universal/

.PARAMETER Validate
    Import + validate ADD files on dnd1, rctl1, and xci1.

.PARAMETER ValidateDelete
    With -Validate: bootstrap main if needed, then validate DELETE files on all accounts.
#>
[CmdletBinding()]
param(
    [switch]$Validate,
    [switch]$ValidateDelete
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$masterPath = Join-Path $RepoRoot 'tests\remicsdev\fixtures\files\complex\rctl-ecomm2601.txt'
$outDir = Join-Path $RepoRoot 'tests\remicsdev\fixtures\files\operator-import\universal'

$ftImport = 'D:\develbat\ftImport.exe'
$ftValidate = 'D:\develbat\ftValidate.exe'
$killTable = 'D:\develbat\KillTable.exe'
$pipelineScript = Join-Path $PSScriptRoot 'Invoke-RemicsUpdatePipeline.ps1'
$validateAllScript = Join-Path $PSScriptRoot 'Invoke-RemicsUpdateValidateAll.ps1'
$tsInbox = 'D:\updates\primary'
$Submitter = 'dnd1'

$AccountMap = [ordered]@{
    dnd1  = @{ schema = 'dnd';  project = 'dnd1_0';  user = 'dnd1' }
    rctl1 = @{ schema = 'rctl'; project = 'rctl1_0'; user = 'rctl1' }
    xci1  = @{ schema = 'xci';  project = 'xci1_0';  user = 'xci1' }
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

function Get-MicsPassword {
    param([string]$User)
    $key = "MICS_TEST_PASSWORD_$($User.ToUpperInvariant())"
    $pwd = [Environment]::GetEnvironmentVariable($key)
    if (-not $pwd) { $pwd = Get-EnvLocalValue $key }
    if (-not $pwd) { $pwd = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
    if (-not $pwd) { $pwd = 'x' }
    return $pwd
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
    return ($lines[1] -split '\|')[0].Trim()
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

function Remap-TsSiteBlock {
    param(
        [string[]]$BlockLines,
        [string]$FromA,
        [string]$FromB,
        [string]$ToA,
        [string]$ToB,
        [string]$NameA,
        [string]$NameB,
        [string]$LatA,
        [string]$LonA,
        [string]$LatB,
        [string]$LonB
    )
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $BlockLines) {
        $t = $line.Replace($FromA, $ToA).Replace($FromB, $ToB)
        if ($t -match '^SK,A,') {
            if ($t -match ",$([regex]::Escape($ToA)),") {
                $t = "SK,A, ,$ToA,$NameA,$LatA,$LonA,7.0, ,"
            }
            elseif ($t -match ",$([regex]::Escape($ToB)),") {
                $t = "SK,A, ,$ToB,$NameB,$LatB,$LonB,2.3, ,"
            }
        }
        if ($t -match '^SD,') {
            $t = 'SD,ON,RCTL,5, , , , , , , , ,FT'
        }
        [void]$out.Add($t)
    }
    return ,@($out.ToArray())
}

function New-UniversalTsFile {
    param(
        [string]$PdfName,
        [string]$Title,
        [object[]]$Pairs
    )
    if (-not (Test-Path $masterPath)) { throw "Master not found: $masterPath" }
    $masterLines = @(Get-Content $masterPath)
    $blocks = Split-TsSiteBlocks -Lines $masterLines
    if ($blocks.Count -lt 2) { throw 'Master must contain at least two site blocks' }

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("* TS-PDF: $PdfName, $Title")
    [void]$lines.Add('*')
    [void]$lines.Add("TT,U,$PdfName,,,,")

    foreach ($pair in $Pairs) {
        [void]$lines.Add('*##############################################################################')
        $remapped = Remap-TsSiteBlock -BlockLines $blocks[0] `
            -FromA 'VDY444' -FromB 'VDY445' -ToA $pair.SiteA -ToB $pair.SiteB `
            -NameA $pair.NameA -NameB $pair.NameB -LatA $pair.LatA -LonA $pair.LonA -LatB $pair.LatB -LonB $pair.LonB
        foreach ($line in $remapped) { [void]$lines.Add($line) }
        [void]$lines.Add('*##############################################################################')
        $remapped2 = Remap-TsSiteBlock -BlockLines $blocks[1] `
            -FromA 'VDY444' -FromB 'VDY445' -ToA $pair.SiteA -ToB $pair.SiteB `
            -NameA $pair.NameA -NameB $pair.NameB -LatA $pair.LatA -LonA $pair.LonA -LatB $pair.LatB -LonB $pair.LonB
        foreach ($line in $remapped2) { [void]$lines.Add($line) }
    }

    return ,@($lines.ToArray())
}

function Convert-AddLinesToDelete {
    param(
        [string[]]$AddLines,
        [string]$DelPdfName,
        [string]$Title
    )
    $out = New-Object System.Collections.Generic.List[string]
    $headerDone = $false
    foreach ($line in $AddLines) {
        if (-not $headerDone) {
            if ($line -match '^\* TS-PDF:') {
                [void]$out.Add("* TS-PDF: $DelPdfName, $Title")
                continue
            }
            if ($line -match '^TT,U,') {
                [void]$out.Add("TT,U,$DelPdfName,,,,")
                $headerDone = $true
                continue
            }
        }
        if ($line -match '^(SK|AK|CK),') {
            $line = $line -replace '^(SK|AK|CK),([^,]*),', '$1,D,'
        }
        [void]$out.Add($line)
    }
    return ,@($out.ToArray())
}

function Test-SitesInMain {
    param([string[]]$SiteCodes)
    if (-not $SiteCodes -or $SiteCodes.Count -lt 1) { return $false }
    $quoted = ($SiteCodes | ForEach-Object { "'$($_.Replace("'", "''"))'" }) -join ','
    $count = Invoke-SqlScalar "SELECT COUNT(*) AS c FROM main.mt_site WHERE RTRIM(call1) IN ($quoted)"
    if (-not $count) { return $false }
    return ([int]$count -ge $SiteCodes.Count)
}

function Copy-StagingToInbox {
    param(
        [string]$SourcePath,
        [string]$PdfName
    )
    if (-not (Test-Path $tsInbox)) { New-Item -ItemType Directory -Force -Path $tsInbox | Out-Null }
    $stamp = Get-Date -Format 'yyMMddHHmm'
    $destName = '{0}_{1}_{2}.txt' -f $Submitter, $stamp, $PdfName
    $dest = Join-Path $tsInbox $destName
    Copy-Item -LiteralPath $SourcePath -Destination $dest -Force
    return $dest
}

function Test-StagingDeleteValidates {
    param([string]$DeletePath)
    if (-not (Test-Path $DeletePath)) { return $false }
    Get-ChildItem $tsInbox -Filter "${Submitter}_*.txt" -ErrorAction SilentlyContinue | Remove-Item -Force
    Copy-Item -LiteralPath $DeletePath -Destination (Join-Path $tsInbox (Split-Path $DeletePath -Leaf)) -Force
    $rp = Join-Path $env:TEMP ("univ-del-check-{0}.json" -f ([guid]::NewGuid().ToString('N')))
    & powershell -NoProfile -ExecutionPolicy Bypass -File $validateAllScript -ResultPath $rp -MaxFiles 1 | Out-Null
    if (-not (Test-Path $rp)) { return $false }
    $result = Get-Content $rp -Raw | ConvertFrom-Json
    Remove-Item $rp -Force -ErrorAction SilentlyContinue
    $row = @($result.results | Select-Object -First 1)
    return ($row -and $row[0].ok -eq $true)
}

function Invoke-BootstrapAddToMain {
    param(
        [string]$AddPath,
        [string]$PdfName,
        [string]$Label
    )
    if (-not (Test-Path $pipelineScript)) { throw "Missing $pipelineScript" }
    $staging = Copy-StagingToInbox -SourcePath $AddPath -PdfName $PdfName
    Write-Host "Bootstrap $Label -> $staging"
    $resultPath = Join-Path $env:TEMP ("univ-bootstrap-{0}.json" -f ([guid]::NewGuid().ToString('N')))
    & powershell -NoProfile -ExecutionPolicy Bypass -File $pipelineScript `
        -StagingFile (Split-Path $staging -Leaf) -SpoofFirst -ResultPath $resultPath
    if (-not (Test-Path $resultPath)) { throw "Bootstrap produced no result for $Label" }
    $result = Get-Content $resultPath -Raw | ConvertFrom-Json
    Remove-Item $resultPath -Force -ErrorAction SilentlyContinue
    if (-not $result.ok) {
        throw "Bootstrap failed for ${Label}: $($result.error)"
    }
    return $result
}

function Test-UniversalImportValidate {
    param(
        [string]$FilePath,
        [string]$PdfName,
        [string]$MicsUser,
        [string]$Schema,
        [string]$Project
    )
    foreach ($required in @($ftImport, $ftValidate, $killTable)) {
        if (-not (Test-Path $required)) {
            return @{ ok = $false; skipped = $true; message = "Missing $required"; user = $MicsUser; pdfname = $PdfName }
        }
    }

    $workDir = "D:\Inetpub\remicsdev\mics\userdirs\$Schema\$MicsUser\"
    if (-not (Test-Path $workDir)) { New-Item -ItemType Directory -Force -Path $workDir | Out-Null }
    Set-MicsBatchEnv -WorkDir $workDir -Project $Project -Pwd (Get-MicsPassword -User $MicsUser) -User $MicsUser

    $logDir = Join-Path $env:TEMP ("univ-ts-{0}-{1}" -f $MicsUser, ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    try {
        $null = Start-Process -FilePath $killTable -ArgumentList @('remicsdev', 'TS', $PdfName, $Project) `
            -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $logDir 'kill.out') `
            -RedirectStandardError (Join-Path $logDir 'kill.err')

        $proc = Start-Process -FilePath $ftImport -ArgumentList @('remicsdev', $Project, $PdfName, $FilePath, '-f') `
            -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $logDir 'import.out') `
            -RedirectStandardError (Join-Path $logDir 'import.err')
        if ($proc.ExitCode -ne 0) {
            $err = Get-Content (Join-Path $logDir 'import.err') -Raw -ErrorAction SilentlyContinue
            return @{ ok = $false; failed_step = 'import'; user = $MicsUser; import_exit = $proc.ExitCode; message = $err; pdfname = $PdfName }
        }

        $valOut = Join-Path $workDir ("{0}.txt" -f $PdfName)
        $proc2 = Start-Process -FilePath $ftValidate -ArgumentList @('remicsdev', $Project, $PdfName, ("-o{0}" -f $valOut)) `
            -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $logDir 'validate.out') `
            -RedirectStandardError (Join-Path $logDir 'validate.err')

        $safeSchema = $Schema.Replace("'", "''")
        $safePdf = $PdfName.Replace("'", "''")
        $validated = Invoke-SqlScalar "SELECT validated AS c FROM ${safeSchema}.ft_${safePdf}_titl"
        if (-not $validated) { $validated = 'N' }

        $valOk = ($proc2.ExitCode -eq 0) -and ($validated -in @('U', 'M'))
        $valLog = Join-Path $logDir 'validate.out'
        $errorHint = ''
        if (-not $valOk -and (Test-Path $valLog)) {
            $errorHint = (Get-Content $valLog -Raw | Select-String -Pattern 'already exists|ERRORS' -AllMatches | Select-Object -First 3 | ForEach-Object { $_.Line }) -join '; '
        }
        return @{
            ok = $valOk
            failed_step = if ($valOk) { '' } else { 'validate' }
            user = $MicsUser
            validated = $validated
            import_exit = $proc.ExitCode
            validate_exit = $proc2.ExitCode
            message = "validate_exit=$($proc2.ExitCode) validated=$validated $errorHint"
            pdfname = $PdfName
            log_dir = $logDir
        }
    }
    finally {
        $null = Start-Process -FilePath $killTable -ArgumentList @('remicsdev', 'TS', $PdfName, $Project) `
            -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $logDir 'postkill.out') `
            -RedirectStandardError (Join-Path $logDir 'postkill.err')
    }
}

# Remote Arctic coordinates — far from populated MDB sites to minimize HiLo conflicts.
$fileDefs = @(
    @{
        pdf = 'univts01'
        delPdf = 'univts01d'
        addFile = 'univts01-add.txt'
        delFile = 'univts01-del.txt'
        addTitle = 'universal ADD fixture A (4 sites, 20 channels) 2026.08.06'
        delTitle = 'universal DELETE fixture A (4 sites, 20 channels) 2026.08.06'
        siteCodes = @('Q9UA01', 'Q9UA02', 'Q9UA03', 'Q9UA04')
        pairs = @(
            @{ SiteA = 'Q9UA01'; SiteB = 'Q9UA02'; NameA = 'UNIV-A1'; NameB = 'UNIV-A2'; LatA = '70-00-00.00N'; LonA = '130-00-00.00W'; LatB = '69-58-00.00N'; LonB = '129-55-00.00W' }
            @{ SiteA = 'Q9UA03'; SiteB = 'Q9UA04'; NameA = 'UNIV-A3'; NameB = 'UNIV-A4'; LatA = '70-02-00.00N'; LonA = '130-05-00.00W'; LatB = '70-00-00.00N'; LonB = '130-10-00.00W' }
        )
    }
    @{
        pdf = 'univts02'
        delPdf = 'univts02d'
        addFile = 'univts02-add.txt'
        delFile = 'univts02-del.txt'
        addTitle = 'universal ADD fixture B (4 sites, 20 channels) 2026.08.06'
        delTitle = 'universal DELETE fixture B (4 sites, 20 channels) 2026.08.06'
        siteCodes = @('Q9UB01', 'Q9UB02', 'Q9UB03', 'Q9UB04')
        pairs = @(
            @{ SiteA = 'Q9UB01'; SiteB = 'Q9UB02'; NameA = 'UNIV-B1'; NameB = 'UNIV-B2'; LatA = '65-00-00.00N'; LonA = '110-00-00.00W'; LatB = '64-58-00.00N'; LonB = '109-55-00.00W' }
            @{ SiteA = 'Q9UB03'; SiteB = 'Q9UB04'; NameA = 'UNIV-B3'; NameB = 'UNIV-B4'; LatA = '65-02-00.00N'; LonA = '110-05-00.00W'; LatB = '65-00-00.00N'; LonB = '110-10-00.00W' }
        )
    }
)

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$written = @()
foreach ($def in $fileDefs) {
    $lines = New-UniversalTsFile -PdfName $def.pdf -Title $def.addTitle -Pairs $def.pairs
    $addPath = Join-Path $outDir $def.addFile
    Set-Content -Path $addPath -Value $lines -Encoding ASCII
    $delLines = Convert-AddLinesToDelete -AddLines $lines -DelPdfName $def.delPdf -Title $def.delTitle
    $delPath = Join-Path $outDir $def.delFile
    Set-Content -Path $delPath -Value $delLines -Encoding ASCII
    $written += [pscustomobject]@{
        kind = 'add'
        file = $def.addFile
        path = $addPath
        pdf = $def.pdf
        sites = @($lines | Where-Object { $_ -match '^SK,A,' }).Count
        channels = @($lines | Where-Object { $_ -match '^CK,A,' }).Count
        bytes = (Get-Item $addPath).Length
    }
    $written += [pscustomobject]@{
        kind = 'del'
        file = $def.delFile
        path = $delPath
        pdf = $def.delPdf
        sites = @($delLines | Where-Object { $_ -match '^SK,D,' }).Count
        channels = @($delLines | Where-Object { $_ -match '^CK,D,' }).Count
        bytes = (Get-Item $delPath).Length
    }
}

$manifest = @{
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    output_dir = $outDir
    pairs = @($fileDefs | ForEach-Object {
        @{
            add = @{ file = $_.addFile; pdf = $_.pdf; path = (Join-Path $outDir $_.addFile) }
            del = @{ file = $_.delFile; pdf = $_.delPdf; path = (Join-Path $outDir $_.delFile) }
            site_codes = $_.siteCodes
        }
    })
    cycle = @(
        'ADD while sites absent from main.* (validates on any account)'
        'POST ADD via DbUpdate / Initialize-UniversalTsMain.ps1'
        'DELETE while sites present in main.* (validates on any account)'
        'POST DELETE to restore; re-run ADD'
    )
}
Set-Content -Path (Join-Path $outDir 'universal-ts-manifest.json') -Value ($manifest | ConvertTo-Json -Depth 6) -Encoding UTF8

Write-Host "Wrote universal TS fixtures to $outDir"
$written | Format-Table -AutoSize

if (-not $Validate) {
    Write-Host 'Run with -Validate to import+validate ADD files on dnd1, rctl1, xci1.'
    Write-Host 'Add -ValidateDelete to bootstrap main and validate DELETE files too.'
    exit 0
}

$results = @()
foreach ($def in $fileDefs) {
    $path = Join-Path $outDir $def.addFile
    foreach ($acct in $AccountMap.Keys) {
        $info = $AccountMap[$acct]
        Write-Host "Validating ADD $($def.pdf) as $acct ..."
        $r = Test-UniversalImportValidate -FilePath $path -PdfName $def.pdf -MicsUser $info.user -Schema $info.schema -Project $info.project
        $results += [pscustomobject]@{
            kind = 'add'
            file = $def.addFile
            pdf = $def.pdf
            account = $acct
            ok = $r.ok
            validated = $r.validated
            validate_exit = $r.validate_exit
            failed_step = $r.failed_step
            message = $r.message
        }
        if (-not $r.ok) {
            Write-Host "FAIL ADD: $($def.addFile) on $acct - $($r.message)" -ForegroundColor Red
        }
        else {
            Write-Host "OK ADD: $($def.addFile) on $acct validated=$($r.validated)" -ForegroundColor Green
        }
    }
}

$failures = @($results | Where-Object { -not $_.ok })
if ($failures.Count -gt 0) {
    Write-Host "`nADD validation failed for $($failures.Count) account/file combinations." -ForegroundColor Red
    $failures | Format-Table -AutoSize
    exit 1
}

if (-not $ValidateDelete) {
    Write-Host "`nAll ADD fixtures validated on dnd1, rctl1, and xci1." -ForegroundColor Green
    exit 0
}

Write-Host "`nPreparing main.* for DELETE validation ..."
foreach ($def in $fileDefs) {
    $delPath = Join-Path $outDir $def.delFile
    $addPath = Join-Path $outDir $def.addFile
    if (Test-StagingDeleteValidates -DeletePath $delPath) {
        Write-Host "SKIP bootstrap $($def.pdf): $($def.delFile) already validates in fwmda inbox."
        continue
    }
    if (Test-SitesInMain -SiteCodes $def.siteCodes) {
        Write-Host "Sites present in main for $($def.pdf) but inbox delete check failed; continuing bootstrap."
    }
    Invoke-BootstrapAddToMain -AddPath $addPath -PdfName $def.pdf -Label $def.pdf | Out-Null
}

foreach ($def in $fileDefs) {
    $path = Join-Path $outDir $def.delFile
    foreach ($acct in $AccountMap.Keys) {
        $info = $AccountMap[$acct]
        Write-Host "Validating DELETE $($def.delPdf) as $acct ..."
        $r = Test-UniversalImportValidate -FilePath $path -PdfName $def.delPdf -MicsUser $info.user -Schema $info.schema -Project $info.project
        $results += [pscustomobject]@{
            kind = 'del'
            file = $def.delFile
            pdf = $def.delPdf
            account = $acct
            ok = $r.ok
            validated = $r.validated
            validate_exit = $r.validate_exit
            failed_step = $r.failed_step
            message = $r.message
        }
        if (-not $r.ok) {
            Write-Host "FAIL DEL: $($def.delFile) on $acct - $($r.message)" -ForegroundColor Red
        }
        else {
            Write-Host "OK DEL: $($def.delFile) on $acct validated=$($r.validated)" -ForegroundColor Green
        }
    }
}

$failures = @($results | Where-Object { $_.kind -eq 'del' -and -not $_.ok })
if ($failures.Count -gt 0) {
    Write-Host "`nDELETE validation failed for $($failures.Count) account/file combinations." -ForegroundColor Red
    $failures | Format-Table -AutoSize
    exit 1
}

Write-Host "`nAll ADD and DELETE universal TS fixtures validated on dnd1, rctl1, and xci1." -ForegroundColor Green
exit 0
