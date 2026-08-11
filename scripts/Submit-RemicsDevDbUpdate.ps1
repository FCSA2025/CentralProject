#Requires -Version 5.1
<#
.SYNOPSIS
    Simulate operator DbUpdate submission: import, validate, export to inbox, enqueue auto-processing.

.PARAMETER StagingSource
    Path to staging .txt (seq10 fixture or exported file).

.PARAMETER MicsUser
    Operator account (default dnd1).

.PARAMETER FileType
    TS or ES (inferred from path if omitted).

.PARAMETER SkipEnqueue
    Copy to inbox only; do not INSERT adm.t_UpdateQueue_local row.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$StagingSource,
    [ValidateSet('dnd1', 'rctl1', 'rctl3', 'xci1')]
    [string]$MicsUser = 'dnd1',
    [ValidateSet('TS', 'ES', '')]
    [string]$FileType = '',
    [switch]$SkipEnqueue
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'RemicsDev-SqlHelpers.ps1')
$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$PrimaryRoot = 'D:\updates\primary'
$EsInbox = Join-Path $PrimaryRoot 'UnprocessedESFiles'

$ftImport = 'D:\develbat\ftImport.exe'
$ftValidate = 'D:\develbat\ftValidate.exe'
$ftPrint = 'D:\develbat\ftPrint.exe'
$feImport = 'D:\develbat\feImport.exe'
$feValidate = 'D:\develbat\feValidate.exe'
$fePrint = 'D:\develbat\FePrint.exe'
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

function Invoke-SqlScalar {
    param([string]$Query)
    return Invoke-RemicsDevSqlScalar -Query $Query -SqlScript $sqlScript
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

function Prepare-TsImportFile {
    param([string]$Path, [string]$Schema)
    $operatorCode = $Schema.ToUpperInvariant()
    $lines = @(Get-Content $Path | Where-Object { $_ -match '\S' } | ForEach-Object {
        if ($_ -match '^SD,') { $_ -replace '^SD,([^,]*),[^,]*,', ("SD,`$1,{0}," -f $operatorCode) } else { $_ }
    })
    $lines | Set-Content -Path $Path -Encoding ASCII
}

function Escape-Sql { param([string]$Value) if ($null -eq $Value) { return '' }; return $Value.Replace("'", "''") }

if (-not (Test-Path $StagingSource)) { throw "Staging source not found: $StagingSource" }

$fileName = Split-Path $StagingSource -Leaf
if ($fileName -notmatch '^([A-Za-z0-9]+)_(\d{10})_(.+)\.txt$') {
    throw "Unrecognized staging filename: $fileName"
}
$pdfName = $Matches[3]
if ($pdfName.Length -gt 16) { $pdfName = $pdfName.Substring(0, 16) }

if (-not $FileType) {
    $FileType = if ($StagingSource -match 'UnprocessedESFiles|cyces') { 'ES' } else { 'TS' }
}

$schema = Invoke-SqlScalar "SELECT RTRIM(PrimarySchema) AS c FROM dbo.t_UserDetails WHERE RTRIM(micsId)='$($MicsUser -replace '''','''')'"
if (-not $schema) {
    $map = @{ dnd1 = 'dnd'; rctl1 = 'rctl'; rctl3 = 'rctl'; xci1 = 'xci' }
    $schema = $map[$MicsUser]
}
if (-not $schema) { throw "No schema for $MicsUser" }

$project = "${MicsUser}_0"
$workDir = "D:\Inetpub\remicsdev\mics\userdirs\$schema\$MicsUser\"
if (-not (Test-Path $workDir)) { New-Item -ItemType Directory -Force -Path $workDir | Out-Null }

$userPwdKey = 'MICS_TEST_PASSWORD_' + $MicsUser.ToUpperInvariant()
$password = [Environment]::GetEnvironmentVariable($userPwdKey)
if (-not $password) { $password = Get-EnvLocalValue $userPwdKey }
if (-not $password) { $password = $env:MICS_TEST_PASSWORD }
if (-not $password) { $password = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
if (-not $password) { $password = 'x' }

$logDir = Join-Path $env:TEMP ("dbupdate-submit-{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Set-MicsBatchEnv -WorkDir $workDir -Project $project -Pwd $password -User $MicsUser
Set-Location $workDir

$importExe = if ($FileType -eq 'ES') { $feImport } else { $ftImport }
$validateExe = if ($FileType -eq 'ES') { $feValidate } else { $ftValidate }
$printExe = if ($FileType -eq 'ES') { $fePrint } else { $ftPrint }
$typeArg = if ($FileType -eq 'ES') { 'ES' } else { 'TS' }

# Drop prior operator PDF tables so re-import works
$null = Start-Process -FilePath $killTable -ArgumentList @('remicsdev', $typeArg, $pdfName, $project) `
    -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $logDir 'prekill.out') `
    -RedirectStandardError (Join-Path $logDir 'prekill.err')

$workCopy = Join-Path $logDir $fileName
Copy-Item -LiteralPath $StagingSource -Destination $workCopy -Force
if ($FileType -eq 'TS') { Prepare-TsImportFile -Path $workCopy -Schema $schema }

$importArgs = if ($FileType -eq 'ES') {
    @('-d', 'remicsdev', $project, $pdfName, $workCopy)
} else {
    @('remicsdev', $project, $pdfName, $workCopy, '-f')
}
$imp = Start-Process -FilePath $importExe -ArgumentList $importArgs -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput (Join-Path $logDir 'import.out') -RedirectStandardError (Join-Path $logDir 'import.err')
if ($imp.ExitCode -ne 0) {
    throw "Operator import failed exit=$($imp.ExitCode) pdf=$pdfName user=$MicsUser"
}

$valOut = Join-Path $workDir ("{0}.txt" -f $pdfName)
$val = Start-Process -FilePath $validateExe -ArgumentList @('remicsdev', $project, $pdfName, ("-o{0}" -f $valOut)) `
    -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $logDir 'validate.out') `
    -RedirectStandardError (Join-Path $logDir 'validate.err')

$prefix = if ($FileType -eq 'ES') { 'fe' } else { 'ft' }
$validated = Invoke-SqlScalar "SELECT validated AS c FROM ${schema}.${prefix}_${pdfName}_titl"
if ($val.ExitCode -ne 0 -or $validated -notin @('U', 'M')) {
    throw "Operator validate failed exit=$($val.ExitCode) validated=$validated pdf=$pdfName"
}

# Export (ftPrint/fePrint) — same as exportForUpdate body
$exportTmp = Join-Path $logDir ("export_{0}.txt" -f $pdfName)
$printArgs = if ($FileType -eq 'ES') {
    @('remicsdev', $project, ("-o{0}" -f $exportTmp), $pdfName)
} else {
    @('remicsdev', $project, ("-o{0}" -f $exportTmp), 'L', $pdfName)
}
$pr = Start-Process -FilePath $printExe -ArgumentList $printArgs -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput (Join-Path $logDir 'print.out') -RedirectStandardError (Join-Path $logDir 'print.err')
if ($pr.ExitCode -ne 0 -or -not (Test-Path $exportTmp)) {
    throw "Export print failed exit=$($pr.ExitCode) pdf=$pdfName"
}

$stamp = Get-Date -Format 'yyMMddHHmm'
$inboxName = "{0}_{1}_{2}.txt" -f $MicsUser, $stamp, $pdfName
$inboxDir = if ($FileType -eq 'ES') { $EsInbox } else { $PrimaryRoot }
if (-not (Test-Path $inboxDir)) { New-Item -ItemType Directory -Force -Path $inboxDir | Out-Null }
$inboxPath = Join-Path $inboxDir $inboxName
Copy-Item -LiteralPath $exportTmp -Destination $inboxPath -Force

$queueId = $null
if (-not $SkipEnqueue) {
    $email = Invoke-SqlScalar "SELECT TOP 1 RTRIM(email) AS email FROM adm.account_details WHERE RTRIM(micsid)='$(Escape-Sql $MicsUser)'"
    $emailSql = if ($email) { "'$(Escape-Sql $email)'" } else { 'NULL' }
    $queueId = Invoke-SqlScalar @"
INSERT INTO adm.t_UpdateQueue_local (staging_file, staging_path, submitter, pdf_name, file_type, submitter_email, [status], [mode])
VALUES ('$(Escape-Sql $inboxName)', '$(Escape-Sql $inboxPath)', '$(Escape-Sql $MicsUser)', '$(Escape-Sql $pdfName)', '$FileType', $emailSql, 'N', 'spoof-first');
SELECT CAST(SCOPE_IDENTITY() AS INT) AS queue_id;
"@
    if (-not $queueId -or $queueId -notmatch '^\d+$') {
        throw "Failed to enqueue update queue row for $inboxName (queue_id=$queueId)"
    }
}

Remove-Item -LiteralPath $logDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Output (@{
    ok = $true
    mics_user = $MicsUser
    schema = $schema
    file_type = $FileType
    pdf_name = $pdfName
    validated = $validated
    inbox_file = $inboxName
    inbox_path = $inboxPath
    queue_id = $queueId
} | ConvertTo-Json -Depth 4 -Compress)
