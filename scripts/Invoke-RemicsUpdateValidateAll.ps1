#Requires -Version 5.1
<#
.SYNOPSIS
    Import and validate all DbUpdate staging inbox files as fwmda (no MtUpdate).

.DESCRIPTION
    Reads every .txt in D:\updates\primary and UnprocessedESFiles, runs pre-clean,
    import, validate, and post-clean for each without moving inbox files.
    Writes incremental progress to ResultPath and a validate-cache.json for the admin list.

.PARAMETER ResultPath
    Job JSON path for admin polling.

.PARAMETER CachePath
    Persistent per-file validation cache (default: sibling validate-cache.json).

.PARAMETER MaxFiles
    Limit files processed (0 = all inbox files).
#>
[CmdletBinding()]
param(
    [string]$ResultPath = '',
    [string]$CachePath = '',
    [int]$MaxFiles = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$MicsUser = 'fwmda'
$Project = 'fwmda_0'
$PrimaryRoot = 'D:\updates\primary'
$EsInbox = Join-Path $PrimaryRoot 'UnprocessedESFiles'

$ftImport = 'D:\develbat\ftImport.exe'
$ftValidate = 'D:\develbat\ftValidate.exe'
$feImport = 'D:\develbat\feImport.exe'
$feValidate = 'D:\develbat\feValidate.exe'
$killTable = 'D:\develbat\KillTable.exe'

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

function Invoke-SqlRows {
    param([string]$Query)
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $sqlScript -Query $Query 2>&1 | Out-String
    $lines = @($raw -split "`r?`n" | Where-Object {
        $_ -and $_ -notmatch '^---' -and $_ -notmatch '^-+$' -and $_ -notmatch '^\(' -and $_ -notmatch 'rows affected'
    })
    if ($lines.Count -lt 2) { return @() }
    $headers = @($lines[0] -split '\|')
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^-+$') { continue }
        $parts = @($lines[$i] -split '\|')
        if ($parts.Count -lt $headers.Count) { continue }
        $obj = @{}
        for ($ci = 0; $ci -lt $headers.Count; $ci++) {
            $key = $headers[$ci].Trim()
            if ([string]::IsNullOrWhiteSpace($key)) { $key = 'c' + $ci }
            $obj[$key] = $parts[$ci].Trim()
        }
        $rows += [pscustomobject]$obj
    }
    return $rows
}

function Invoke-SqlScalar {
    param([string]$Query)
    $rows = @(Invoke-SqlRows -Query $Query)
    if ($rows.Count -lt 1) { return $null }
    $first = $rows[0].PSObject.Properties | Select-Object -First 1
    return [string]$first.Value
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

function Invoke-ExeCapture {
    param([string]$FilePath, [string[]]$ArgumentList, [string]$LogPath)
    $stdout = "$LogPath.out.txt"
    $stderr = "$LogPath.err.txt"
    $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    return @{
        ExitCode = $proc.ExitCode
        StdOut   = if (Test-Path $stdout) { Get-Content $stdout -Raw } else { '' }
        StdErr   = if (Test-Path $stderr) { Get-Content $stderr -Raw } else { '' }
        LogPath  = $LogPath
    }
}

function Write-JobJson {
    param([object]$Payload)
    if (-not $ResultPath) { return }
    $dir = Split-Path $ResultPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Set-Content -Path $ResultPath -Value ($Payload | ConvertTo-Json -Depth 12 -Compress) -Encoding UTF8
}

function Write-ValidateCache {
    param([object]$Payload)
    if (-not $CachePath) { return }
    $dir = Split-Path $CachePath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Set-Content -Path $CachePath -Value ($Payload | ConvertTo-Json -Depth 12 -Compress) -Encoding UTF8
}

function Parse-StagingFileName {
    param([string]$FileName, [string]$DirectoryPath)
    $filetype = if ($DirectoryPath -match 'UnprocessedESFiles') { 'ES' } else { 'TS' }
    if ($FileName -match '^([A-Za-z0-9]+)_(\d{10})_(.+)\.txt$') {
        return @{
            submitter = $Matches[1]
            timestamp = $Matches[2]
            pdfname   = $Matches[3]
            filetype  = $filetype
        }
    }
    if ($FileName -match '^([A-Za-z0-9_]{1,16})\.txt$') {
        return @{
            submitter = ''
            timestamp = ''
            pdfname   = $Matches[1]
            filetype  = $filetype
        }
    }
    return $null
}

function Test-PdfTableExists {
    param([string]$Schema, [string]$PdfName, [string]$FileType)
    $prefix = if ($FileType -eq 'ES') { 'fe' } else { 'ft' }
    $safeSchema = $Schema.Replace("'", "''")
    $safePdf = $PdfName.Replace("'", "''")
    $c = Invoke-SqlScalar "SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='$safeSchema' AND TABLE_NAME='${prefix}_${safePdf}_titl'"
    return ($c -and [int]$c -gt 0)
}

function Invoke-KillPdfTables {
    param(
        [string]$Schema,
        [string]$PdfName,
        [string]$FileType,
        [string]$LogDir,
        [string]$Label
    )
    if (-not (Test-PdfTableExists -Schema $Schema -PdfName $PdfName -FileType $FileType)) {
        return @{ ok = $true; skipped = $true; message = 'No PDF table set present' }
    }
    if (-not (Test-Path $killTable)) {
        return @{ ok = $false; message = "KillTable.exe missing at $killTable" }
    }
    $typeArg = if ($FileType -eq 'ES') { 'ES' } else { 'TS' }
    $run = Invoke-ExeCapture -FilePath $killTable -ArgumentList @('remicsdev', $typeArg, $PdfName, $Project) `
        -LogPath (Join-Path $LogDir ("KillTable_{0}" -f $Label))
    $still = Test-PdfTableExists -Schema $Schema -PdfName $PdfName -FileType $FileType
    $ok = (-not $still -and $run.ExitCode -eq 0)
    return @{
        ok = $ok
        exit_code = $run.ExitCode
        message = if ($ok) { "Dropped ${typeArg} table set $PdfName" } else { "KillTable exit=$($run.ExitCode); tables still present=$still" }
    }
}

function Get-ValidatedFlag {
    param([string]$Schema, [string]$PdfName, [string]$FileType)
    $prefix = if ($FileType -eq 'ES') { 'fe' } else { 'ft' }
    $safeSchema = $Schema.Replace("'", "''")
    $safePdf = $PdfName.Replace("'", "''")
    if (-not (Test-PdfTableExists -Schema $Schema -PdfName $PdfName -FileType $FileType)) { return $null }
    return Invoke-SqlScalar "SELECT validated AS c FROM ${safeSchema}.${prefix}_${safePdf}_titl"
}

function Get-InboxFiles {
    $files = @()
    foreach ($pair in @(
        @{ Dir = $PrimaryRoot; Type = 'TS' },
        @{ Dir = $EsInbox; Type = 'ES' }
    )) {
        if (-not (Test-Path $pair.Dir)) { continue }
        foreach ($fi in Get-ChildItem $pair.Dir -Filter '*.txt' -File | Sort-Object Name) {
            $files += [pscustomobject]@{
                Name = $fi.Name
                Path = $fi.FullName
                FileType = $pair.Type
                Bytes = $fi.Length
            }
        }
    }
    return $files
}

function Invoke-ValidateStagingFile {
    param(
        [string]$StagingPath,
        [string]$Schema,
        [string]$WorkDir,
        [string]$LogDir
    )
    $fileName = Split-Path $StagingPath -Leaf
    $meta = Parse-StagingFileName -FileName $fileName -DirectoryPath $StagingPath
    if (-not $meta) {
        return @{
            name = $fileName
            path = $StagingPath
            ok = $false
            validated = ''
            failed_step = 'parse'
            message = "Unrecognized staging filename: $fileName"
        }
    }

    $pdfname = [string]$meta.pdfname
    if ($pdfname.Length -gt 16) { $pdfname = $pdfname.Substring(0, 16) }

    $result = @{
        name = $fileName
        path = $StagingPath
        submitter = $meta.submitter
        pdfname = $pdfname
        filetype = $meta.filetype
        ok = $false
        validated = ''
        import_exit = $null
        validate_exit = $null
        failed_step = ''
        message = ''
    }

    try {
        $pre = Invoke-KillPdfTables -Schema $Schema -PdfName $pdfname -FileType $meta.filetype -LogDir $LogDir -Label 'preclean'
        if (-not $pre.ok) { throw "Pre-clean failed: $($pre.message)" }

        $importExe = if ($meta.filetype -eq 'ES') { $feImport } else { $ftImport }
        $importLabel = if ($meta.filetype -eq 'ES') { 'FeImport' } else { 'FtImport' }
        if (-not (Test-Path $importExe)) { throw "$importLabel.exe not found" }
        $importArgs = if ($meta.filetype -eq 'ES') {
            @('-d', 'remicsdev', $Project, $pdfname, $StagingPath)
        } else {
            @('remicsdev', $Project, $pdfname, $StagingPath, '-f')
        }
        $imp = Invoke-ExeCapture -FilePath $importExe -ArgumentList $importArgs -LogPath (Join-Path $LogDir $importLabel)
        $result.import_exit = $imp.ExitCode
        if ($imp.ExitCode -ne 0) { throw "Import failed exit=$($imp.ExitCode)" }

        $validateExe = if ($meta.filetype -eq 'ES') { $feValidate } else { $ftValidate }
        $validateLabel = if ($meta.filetype -eq 'ES') { 'FeValidate' } else { 'FtValidate' }
        $valOut = Join-Path $WorkDir ("{0}.txt" -f $pdfname)
        $val = Invoke-ExeCapture -FilePath $validateExe -ArgumentList @('remicsdev', $Project, $pdfname, ("-o{0}" -f $valOut)) `
            -LogPath (Join-Path $LogDir $validateLabel)
        $result.validate_exit = $val.ExitCode
        $validated = Get-ValidatedFlag -Schema $Schema -PdfName $pdfname -FileType $meta.filetype
        $result.validated = [string]$validated

        $valOk = ($val.ExitCode -eq 0) -and ($validated -in @('U', 'M'))
        if (-not $valOk) {
            $result.failed_step = 'validate'
            $result.message = "$validateLabel exit=$($val.ExitCode) validated=$validated (need U or M)"
            return $result
        }

        $result.ok = $true
        $result.message = "$validateLabel exit=$($val.ExitCode) validated=$validated"
    }
    catch {
        if (-not $result.failed_step) {
            $result.failed_step = if ($_.Exception.Message -match 'Import') { 'import' }
                elseif ($_.Exception.Message -match 'Validate') { 'validate' }
                else { 'pipeline' }
        }
        $result.message = $_.Exception.Message
    }
    finally {
        if ($meta -and $pdfname) {
            $post = Invoke-KillPdfTables -Schema $Schema -PdfName $pdfname -FileType $meta.filetype -LogDir $LogDir -Label 'postclean'
            $result.postclean = $post.message
        }
    }

    return $result
}

if (-not (Test-Path $sqlScript)) {
    Write-Output (@{ ok = $false; status = 'complete'; error = "SQL helper missing: $sqlScript" } | ConvertTo-Json -Compress)
    exit 1
}

if (-not $CachePath -and $ResultPath) {
    $CachePath = Join-Path (Split-Path $ResultPath -Parent) 'validate-cache.json'
}

$schema = Invoke-SqlScalar "SELECT RTRIM(PrimarySchema) AS c FROM dbo.t_UserDetails WHERE RTRIM(micsId)='fwmda'"
if (-not $schema) { $schema = 'fmda2' }

$workDir = "D:\Inetpub\remicsdev\mics\userdirs\$schema\$MicsUser\"
if (-not (Test-Path $workDir)) { New-Item -ItemType Directory -Force -Path $workDir | Out-Null }

$userPwdKey = 'MICS_TEST_PASSWORD_FWMDA'
$password = [Environment]::GetEnvironmentVariable($userPwdKey)
if (-not $password) { $password = Get-EnvLocalValue $userPwdKey }
if (-not $password) { $password = $env:MICS_TEST_PASSWORD }
if (-not $password) { $password = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
if (-not $password) { $password = 'x' }

Set-MicsBatchEnv -WorkDir $workDir -Project $Project -Pwd $password -User $MicsUser

$jobId = [guid]::NewGuid().ToString('N')
$logRoot = if ($ResultPath) {
    Join-Path (Split-Path $ResultPath -Parent) ("validate-{0}" -f $jobId)
} else {
    Join-Path $env:TEMP ("fwmda-validate-all-{0}" -f $jobId)
}
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

$inbox = @(Get-InboxFiles)
if ($MaxFiles -gt 0 -and $inbox.Count -gt $MaxFiles) {
    $inbox = @($inbox | Select-Object -First $MaxFiles)
}

$job = @{
    ok = $true
    status = 'running'
    job_id = $jobId
    jobId = $jobId
    type = 'validate_all'
    execution_user = $MicsUser
    execution_schema = $schema
    files_total = $inbox.Count
    files_done = 0
    passed = 0
    failed = 0
    current_file = ''
    started_utc = (Get-Date).ToUniversalTime().ToString('o')
    results = @()
    summary = ''
}

Write-JobJson -Payload $job

$cacheFiles = @{}
$passed = 0
$failed = 0
$idx = 0

foreach ($item in $inbox) {
    $idx++
    $job.current_file = $item.Name
    $job.files_done = $idx - 1
    Write-JobJson -Payload $job

    $fileLogDir = Join-Path $logRoot $item.Name
    New-Item -ItemType Directory -Force -Path $fileLogDir | Out-Null
    $one = Invoke-ValidateStagingFile -StagingPath $item.Path -Schema $schema -WorkDir $workDir -LogDir $fileLogDir
    if ($one.ok) { $passed++ } else { $failed++ }

    $job.results = @($job.results) + @($one)
    $job.files_done = $idx
    $job.passed = $passed
    $job.failed = $failed
    $cacheFiles[$item.Name] = @{
        ok = $one.ok
        validated = $one.validated
        failed_step = $one.failed_step
        message = $one.message
        checked_utc = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-JobJson -Payload $job
    Write-ValidateCache -Payload @{
        job_id = $jobId
        updated_utc = (Get-Date).ToUniversalTime().ToString('o')
        passed = $passed
        failed = $failed
        files_total = $inbox.Count
        files = $cacheFiles
    }
}

$job.status = 'complete'
$job.completed_utc = (Get-Date).ToUniversalTime().ToString('o')
$job.current_file = ''
$job.all_passed = ($failed -eq 0)
$job.ok = $true
$job.summary = "Validate all: $($inbox.Count) file(s), $passed passed, $failed failed"
Write-JobJson -Payload $job
Write-ValidateCache -Payload @{
    job_id = $jobId
    updated_utc = $job.completed_utc
    completed_utc = $job.completed_utc
    passed = $passed
    failed = $failed
    files_total = $inbox.Count
    files = $cacheFiles
}

Write-Output ($job | ConvertTo-Json -Depth 12 -Compress)
if (-not $job.all_passed) { exit 1 }
