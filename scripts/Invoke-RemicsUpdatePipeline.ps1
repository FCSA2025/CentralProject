#Requires -Version 5.1
<#
.SYNOPSIS
    Process a DbUpdate staging file through import, validate, and MtUpdate/MeUpdate as fwmda.

.DESCRIPTION
    All batch steps run as MICS user fwmda (schema from PrimarySchema, typically fmda2).
    Submitter identity is parsed from the staging filename for audit only.
    Pre/post killTable on fwmda PDF table sets avoids name collisions across operators.

.PARAMETER StagingFile
    Full path to staging .txt, or relative name under D:\updates\primary.

.PARAMETER JobId
    Retry/resume an existing job folder under processing/ or failed/.

.PARAMETER Spoof
    Legacy alias: when set without SpoofFirst/MainOnly, runs spoof-only (-s) without main cutover.

.PARAMETER SpoofFirst
    Sync spoof MDB from main, run MtUpdate/MeUpdate -s, then main update on success (default).

.PARAMETER SpoofOnly
    Sync + spoof (-s) only; never write main.* even when spoof succeeds.

.PARAMETER MainOnly
    Skip spoof sync/update; write main.* directly (production cutover mode).

.PARAMETER SkipCleanup
    Skip post-run killTable (debug only).

.PARAMETER DryRun
    Parse metadata and write job JSON without running batch steps.

.PARAMETER ResultPath
    Atomic JSON path for admin polling.
#>
[CmdletBinding()]
param(
    [string]$StagingFile = '',
    [string]$JobId = '',
    [switch]$Spoof,
    [switch]$SpoofFirst,
    [switch]$SpoofOnly,
    [switch]$MainOnly,
    [switch]$NoSpoof,
    [switch]$SkipCleanup,
    [switch]$DryRun,
    [string]$ResultPath = '',
    [int]$TimeoutSec = 600
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
$mtUpdate = 'D:\develbat\MtUpdate.exe'
$meUpdate = 'D:\develbat\MeUpdate.exe'
$killTable = 'D:\develbat\KillTable.exe'

$syncScript = Join-Path $PSScriptRoot 'Sync-FwmdaSpoofFromMain.ps1'

# Default: spoof-first (sync main -> fmda2, spoof -s, then main on success).
if ($MainOnly -or $NoSpoof) {
    $SpoofFirst = $false
    $SpoofOnly = $false
} elseif ($SpoofOnly) {
    $SpoofFirst = $false
} elseif (-not $PSBoundParameters.ContainsKey('SpoofFirst') -and -not $PSBoundParameters.ContainsKey('Spoof')) {
    $SpoofFirst = $true
}
# Legacy -Spoof without other flags => spoof only (no main cutover)
if ($Spoof -and -not $PSBoundParameters.ContainsKey('SpoofFirst') -and -not $SpoofOnly -and -not $MainOnly -and -not $NoSpoof) {
    $SpoofFirst = $false
    $SpoofOnly = $true
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
    Set-Content -Path $ResultPath -Value ($Payload | ConvertTo-Json -Depth 10 -Compress) -Encoding UTF8
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
    $result = @{
        step = $Label
        ok = $false
        skipped = $false
        exit_code = $null
        message = ''
    }
    if (-not (Test-PdfTableExists -Schema $Schema -PdfName $PdfName -FileType $FileType)) {
        $result.skipped = $true
        $result.ok = $true
        $result.message = 'No PDF table set present'
        return $result
    }
    if (-not (Test-Path $killTable)) {
        $result.message = "KillTable.exe missing at $killTable"
        return $result
    }
    $typeArg = if ($FileType -eq 'ES') { 'ES' } else { 'TS' }
    $run = Invoke-ExeCapture -FilePath $killTable -ArgumentList @('remicsdev', $typeArg, $PdfName, $Project) `
        -LogPath (Join-Path $LogDir ("KillTable_{0}" -f $Label))
    $result.exit_code = $run.ExitCode
    $still = Test-PdfTableExists -Schema $Schema -PdfName $PdfName -FileType $FileType
    if (-not $still -and $run.ExitCode -eq 0) {
        $result.ok = $true
        $result.message = "Dropped ${typeArg} table set $PdfName"
    } else {
        $result.message = "KillTable exit=$($run.ExitCode); tables still present=$still"
    }
    return $result
}

function Get-ValidatedFlag {
    param([string]$Schema, [string]$PdfName, [string]$FileType)
    $prefix = if ($FileType -eq 'ES') { 'fe' } else { 'ft' }
    $safeSchema = $Schema.Replace("'", "''")
    $safePdf = $PdfName.Replace("'", "''")
    return Invoke-SqlScalar "SELECT validated AS c FROM ${safeSchema}.${prefix}_${safePdf}_titl"
}

function Test-UpdateSucceeded {
    param(
        [hashtable]$Run,
        [string]$Schema,
        [string]$PdfName,
        [string]$FileType,
        [switch]$RequirePosted
    )
    if ($Run.ExitCode -ne 0) { return $false }
    $out = [string]$Run.StdOut
    if ($out -match 'No records were Updated, Deleted, or Added') { return $false }
    if ($RequirePosted) {
        $validated = Get-ValidatedFlag -Schema $Schema -PdfName $PdfName -FileType $FileType
        if ($validated -ne 'P') { return $false }
    }
    return $true
}

function Get-ObjProp {
    param($Obj, [string]$Name)
    if (-not $Obj) { return $null }
    $prop = $Obj.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Invoke-SpoofSync {
    param([string]$FileType, [string]$LogDir)
    if (-not (Test-Path $syncScript)) {
        throw "Spoof sync script missing: $syncScript"
    }
    $syncResultPath = Join-Path $LogDir 'sync_spoof.json'
    $syncOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $syncScript `
        -FileType $FileType -Json -ResultPath $syncResultPath 2>&1 | Out-String
    $syncPayload = $null
    if (Test-Path $syncResultPath) {
        try { $syncPayload = Get-Content $syncResultPath -Raw | ConvertFrom-Json } catch { }
    }
    if (-not $syncPayload) {
        try { $syncPayload = $syncOut.Trim() | ConvertFrom-Json } catch { }
    }
    $ok = (Get-ObjProp $syncPayload 'ok') -eq $true
    $message = [string](Get-ObjProp $syncPayload 'summary')
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = [string](Get-ObjProp $syncPayload 'error')
    }
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = $syncOut.Trim()
    }
    return @{
        step = 'sync_spoof'
        ok = $ok
        message = $message
        detail = $syncPayload
    }
}

function Ensure-PrimaryDirs {
    foreach ($sub in @('processing', 'completed', 'failed')) {
        $p = Join-Path $PrimaryRoot $sub
        if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
    }
}

function Write-FinalResult {
    param(
        [object]$Job,
        [bool]$Ok,
        [string]$Status,
        [int]$ExitCode = 0
    )
    if ($Job -is [System.Collections.IDictionary]) {
        $Job['status'] = $Status
        $Job['ok'] = $Ok
        $Job['completed_utc'] = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-JobJson -Payload $Job
    if ($ResultPath) {
        $json = Get-Content $ResultPath -Raw
        Write-Output $json
    } else {
        Write-Output ($Job | ConvertTo-Json -Depth 10 -Compress)
    }
    if ($ExitCode -ne 0) { exit $ExitCode }
}

# ---- resolve schema / credentials ----
if (-not (Test-Path $sqlScript)) {
    Write-FinalResult @{ ok = $false; status = 'complete'; error = "SQL helper missing: $sqlScript" } -Ok $false -Status 'complete' -ExitCode 1
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

Ensure-PrimaryDirs

# ---- resolve job / staging path ----
$claimedPath = $null
$originalName = $null
$sourceInbox = $PrimaryRoot

if ($JobId) {
    if ($JobId -notmatch '^[a-fA-F0-9]{32}$') {
        Write-FinalResult @{ ok = $false; status = 'complete'; error = 'Invalid JobId' } -Ok $false -Status 'complete' -ExitCode 1
    }
    foreach ($state in @('processing', 'failed')) {
        $dir = Join-Path (Join-Path $PrimaryRoot $state) $JobId
        if (Test-Path $dir) {
            $txt = Get-ChildItem $dir -Filter '*.txt' | Select-Object -First 1
            if ($txt) {
                $claimedPath = $txt.FullName
                $originalName = $txt.Name
                break
            }
        }
    }
    if (-not $claimedPath) {
        Write-FinalResult @{ ok = $false; status = 'complete'; job_id = $JobId; error = 'Job folder or staging file not found' } -Ok $false -Status 'complete' -ExitCode 1
    }
} else {
    if (-not $StagingFile) {
        Write-FinalResult @{ ok = $false; status = 'complete'; error = 'StagingFile or JobId required' } -Ok $false -Status 'complete' -ExitCode 1
    }
    if (-not [System.IO.Path]::IsPathRooted($StagingFile)) {
        $candidate = Join-Path $PrimaryRoot $StagingFile
        if (-not (Test-Path $candidate)) {
            $candidate = Join-Path $EsInbox $StagingFile
            if (Test-Path $candidate) { $sourceInbox = $EsInbox }
        }
        $StagingFile = $candidate
    } else {
        if ($StagingFile -like "*UnprocessedESFiles*") { $sourceInbox = $EsInbox }
    }
    if (-not (Test-Path $StagingFile)) {
        Write-FinalResult @{ ok = $false; status = 'complete'; error = "Staging file not found: $StagingFile" } -Ok $false -Status 'complete' -ExitCode 1
    }
    if (-not $JobId) {
        $JobId = [guid]::NewGuid().ToString('N')
    }
    $originalName = Split-Path $StagingFile -Leaf
    $procDir = Join-Path (Join-Path $PrimaryRoot 'processing') $JobId
    New-Item -ItemType Directory -Force -Path $procDir | Out-Null
    $claimedPath = Join-Path $procDir $originalName
    Move-Item -LiteralPath $StagingFile -Destination $claimedPath -Force
}

$meta = Parse-StagingFileName -FileName $originalName -DirectoryPath $claimedPath
if (-not $meta) {
    Write-FinalResult @{ ok = $false; status = 'complete'; job_id = $JobId; error = "Unrecognized staging filename: $originalName" } -Ok $false -Status 'complete' -ExitCode 1
}

$pdfname = [string]$meta.pdfname
if ($pdfname.Length -gt 16) { $pdfname = $pdfname.Substring(0, 16) }

$jobDir = Split-Path $claimedPath -Parent
$logDir = Join-Path $jobDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$job = @{
    ok = $true
    status = 'running'
    job_id = $JobId
    staging_file = $originalName
    staging_path = $claimedPath
    submitter = $meta.submitter
    pdfname = $pdfname
    filetype = $meta.filetype
    execution_user = $MicsUser
    execution_schema = $schema
    project = $Project
    spoof_first = [bool]$SpoofFirst
    spoof_only = [bool]$SpoofOnly
    main_only = [bool]$MainOnly
    spoof = [bool]($SpoofFirst -or $SpoofOnly)
    started_utc = (Get-Date).ToUniversalTime().ToString('o')
    steps = @()
    summary = ''
}

Write-JobJson -Payload $job

if ($DryRun) {
    Write-FinalResult $job -Ok $true -Status 'complete'
}

Set-MicsBatchEnv -WorkDir $workDir -Project $Project -Pwd $password -User $MicsUser

$summary = New-Object System.Collections.Generic.List[string]
$modeLabel = if ($MainOnly) { 'main-only' } elseif ($SpoofOnly) { 'spoof-only' } elseif ($SpoofFirst) { 'spoof-first' } else { 'main-only' }
$summary.Add("DbUpdate pipeline: submitter=$($meta.submitter) pdf=$pdfname type=$($meta.filetype) exec=$MicsUser schema=$schema mode=$modeLabel")
$failed = $false
$failStep = ''
$failMessage = ''

function Add-Step {
    param([object]$Step)
    if (-not $job.steps) { $job.steps = @() }
    $job.steps = @($job.steps) + @($Step)
    Write-JobJson -Payload $job
}

try {
    # Step: pre-clean
    $pre = Invoke-KillPdfTables -Schema $schema -PdfName $pdfname -FileType $meta.filetype -LogDir $logDir -Label 'preclean'
    Add-Step $pre
    $summary.Add("preclean: $($pre.message)")
    if (-not $pre.ok) { throw "Pre-clean failed: $($pre.message)" }

    # Step: import
    $importExe = if ($meta.filetype -eq 'ES') { $feImport } else { $ftImport }
    $importLabel = if ($meta.filetype -eq 'ES') { 'FeImport' } else { 'FtImport' }
    if (-not (Test-Path $importExe)) { throw "$importLabel.exe not found" }
    $importArgs = if ($meta.filetype -eq 'ES') {
        @('-d', 'remicsdev', $Project, $pdfname, $claimedPath)
    } else {
        @('remicsdev', $Project, $pdfname, $claimedPath, '-f')
    }
    $imp = Invoke-ExeCapture -FilePath $importExe -ArgumentList $importArgs -LogPath (Join-Path $logDir $importLabel)
    $importStep = @{
        step = 'import'
        ok = ($imp.ExitCode -eq 0)
        exit_code = $imp.ExitCode
        message = "$importLabel exit=$($imp.ExitCode)"
    }
    Add-Step $importStep
    $summary.Add($importStep.message)
    if (-not $importStep.ok) { throw "Import failed exit=$($imp.ExitCode)" }

    # Step: validate
    $validateExe = if ($meta.filetype -eq 'ES') { $feValidate } else { $ftValidate }
    $validateLabel = if ($meta.filetype -eq 'ES') { 'FeValidate' } else { 'FtValidate' }
    $valOut = Join-Path $workDir ("{0}.txt" -f $pdfname)
    $val = Invoke-ExeCapture -FilePath $validateExe -ArgumentList @('remicsdev', $Project, $pdfname, ("-o{0}" -f $valOut)) `
        -LogPath (Join-Path $logDir $validateLabel)
    $validated = Get-ValidatedFlag -Schema $schema -PdfName $pdfname -FileType $meta.filetype
    $valOk = ($val.ExitCode -eq 0) -and ($validated -in @('U', 'M'))
    $valStep = @{
        step = 'validate'
        ok = $valOk
        exit_code = $val.ExitCode
        validated = $validated
        report_path = $valOut
        message = "$validateLabel exit=$($val.ExitCode) validated=$validated"
    }
    Add-Step $valStep
    $summary.Add($valStep.message)
    if (-not $valOk) { throw "Validate gate failed: exit=$($val.ExitCode) validated=$validated (need U or M)" }

    # Step: update (spoof-first, spoof-only, or main-only)
    $updateExe = if ($meta.filetype -eq 'ES') { $meUpdate } else { $mtUpdate }
    $updateLabel = if ($meta.filetype -eq 'ES') { 'MeUpdate' } else { 'MtUpdate' }
    if (-not (Test-Path $updateExe)) { throw "$updateLabel.exe not found" }

    $runUpdate = {
        param([string]$Label, [string[]]$UpdateArgs, [switch]$RequirePosted)
        $run = Invoke-ExeCapture -FilePath $updateExe -ArgumentList $UpdateArgs -LogPath (Join-Path $logDir $Label)
        $ok = Test-UpdateSucceeded -Run $run -Schema $schema -PdfName $pdfname -FileType $meta.filetype -RequirePosted:$RequirePosted
        $flagSuffix = ($UpdateArgs | Where-Object { $_ -match '^-' }) -join ' '
        return @{
            step = $Label.ToLowerInvariant()
            ok = $ok
            exit_code = $run.ExitCode
            args = ($UpdateArgs -join ' ')
            message = "$updateLabel exit=$($run.ExitCode) $flagSuffix".Trim()
            validated = Get-ValidatedFlag -Schema $schema -PdfName $pdfname -FileType $meta.filetype
            no_records = ([string]$run.StdOut -match 'No records were Updated, Deleted, or Added')
        }
    }

    if ($MainOnly) {
        $mainStep = & $runUpdate -Label $updateLabel -UpdateArgs @('remicsdev', $Project, $pdfname) -RequirePosted
        Add-Step $mainStep
        $summary.Add($mainStep.message)
        if (-not $mainStep.ok) { throw "Main update failed exit=$($mainStep.exit_code)" }
    }
    else {
        $sync = Invoke-SpoofSync -FileType $meta.filetype -LogDir $logDir
        Add-Step $sync
        $summary.Add("sync_spoof: $($sync.message)")
        if (-not $sync.ok) { throw "Spoof sync from main failed: $($sync.message)" }

        $spoofStep = & $runUpdate -Label ("{0}_spoof" -f $updateLabel) -UpdateArgs @('remicsdev', $Project, $pdfname, '-s') -RequirePosted
        $spoofStep.spoof = $true
        Add-Step $spoofStep
        $summary.Add("spoof: $($spoofStep.message) validated=$($spoofStep.validated)")
        if (-not $spoofStep.ok) {
            throw "Spoof update failed exit=$($spoofStep.exit_code) validated=$($spoofStep.validated) no_records=$($spoofStep.no_records)"
        }

        if ($SpoofFirst) {
            $mainStep = & $runUpdate -Label ("{0}_main" -f $updateLabel) -UpdateArgs @('remicsdev', $Project, $pdfname, '-p') -RequirePosted
            $mainStep.spoof = $false
            $mainStep.cutover = $true
            Add-Step $mainStep
            $summary.Add("main: $($mainStep.message) validated=$($mainStep.validated)")
            if (-not $mainStep.ok) { throw "Main cutover failed exit=$($mainStep.exit_code)" }
        }
    }

    $validatedAfter = Get-ValidatedFlag -Schema $schema -PdfName $pdfname -FileType $meta.filetype
    $job.validated_after = $validatedAfter
}
catch {
    $failed = $true
    $failStep = if ($_.Exception.Message -match '^(Import|Validate|Update|Pre-clean)') { $matches[0] } else { 'pipeline' }
    $failMessage = $_.Exception.Message
    $summary.Add("FAILED: $failMessage")
}
finally {
    if (-not $SkipCleanup) {
        $post = Invoke-KillPdfTables -Schema $schema -PdfName $pdfname -FileType $meta.filetype -LogDir $logDir -Label 'postclean'
        Add-Step $post
        $summary.Add("postclean: $($post.message)")
        $job.postclean = $post
    }

    $destRoot = if ($failed) { 'failed' } else { 'completed' }
    $destDir = Join-Path (Join-Path $PrimaryRoot $destRoot) $JobId
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
    if (Test-Path $claimedPath) {
        Move-Item -LiteralPath $claimedPath -Destination (Join-Path $destDir $originalName) -Force
    }
    if (Test-Path $logDir) {
        $destLogs = Join-Path $destDir 'logs'
        if (Test-Path $destLogs) { Remove-Item $destLogs -Recurse -Force }
        Move-Item -LiteralPath $logDir -Destination $destLogs -Force
    }
    if ((Split-Path $jobDir -Leaf) -eq $JobId -and (Split-Path $jobDir -Parent) -like '*processing*') {
        if (@(Get-ChildItem $jobDir -Force).Count -eq 0) {
            Remove-Item $jobDir -Force -ErrorAction SilentlyContinue
        }
    }

    $job.summary = ($summary -join "`n")
    $job.archive_dir = $destDir
    if ($failed) {
        $job.error = $failMessage
        $job.failed_step = $failStep
        Write-FinalResult $job -Ok $false -Status 'complete' -ExitCode 1
    }
    Write-FinalResult $job -Ok $true -Status 'complete'
}
