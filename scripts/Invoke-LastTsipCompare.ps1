#Requires -Version 5.1
<#
.SYNOPSIS
    Re-run the most recent completed TSIP archive run and compare archive + report outputs.

.DESCRIPTION
    Looks up TOP 1 complete row in web.tsip_run, re-runs that parm via TpRunTsip.exe (CLI),
    waits for a new archive row, then compares:
      - web.tsip_run registry (num_int_cases, etc.)
      - Layer-2 arc table counts and calc fingerprints (tsip_arc_ts_chan)
      - web.tsip_run_report_line text (volatile timestamps called out separately)
      - on-disk report files (new tsip-runs folder vs user work-dir baseline, if present)
    Emits JSON with human-readable summary fields and writes compare-summary.txt
    under the new reports folder.

.PARAMETER TimeoutSec
    Max seconds to wait for the new archive row after TpRunTsip exits. Default 180.

.PARAMETER Password
    MICS password for batch env. Defaults to env MICS_TEST_PASSWORD or .env.local.

.PARAMETER Json
    Emit a single JSON object on stdout (for the admin HTTP handler).

.PARAMETER ResultPath
    Optional path to write the same JSON result when the job finishes (background job mode).
#>
[CmdletBinding()]
param(
    [int]$TimeoutSec = 180,
    [string]$Password = '',
    [switch]$Json,
    [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$tpRun = 'D:\develbat\TpRunTsip.exe'

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
        $_ -and
        $_ -notmatch '^---' -and
        $_ -notmatch '^-+$' -and
        $_ -notmatch '^\(' -and
        $_ -notmatch 'rows affected'
    })
    if ($lines.Count -lt 2) { return @() }
    $headers = @($lines[0] -split '\|')
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^-+$') { continue }
        $parts = @($lines[$i] -split '\|')
        if ($parts.Count -lt $headers.Count) { continue }
        $obj = [ordered]@{}
        for ($ci = 0; $ci -lt $headers.Count; $ci++) {
            $obj[$headers[$ci].Trim()] = $parts[$ci].Trim()
        }
        $rows += [pscustomobject]$obj
    }
    return $rows
}

function Write-Result {
    param([hashtable]$Data, [int]$ExitCode = 0)
    # Scalars + string summaries only - avoid nested objects that confuse ashx/UI consumers.
    $clean = [ordered]@{}
    foreach ($key in $Data.Keys) {
        $val = $Data[$key]
        if ($null -eq $val) {
            $clean[$key] = $null
        } elseif ($val -is [bool] -or $val -is [int] -or $val -is [long] -or $val -is [double]) {
            $clean[$key] = $val
        } else {
            $clean[$key] = [string]$val
        }
    }
    if (-not $clean.Contains('status')) {
        $clean['status'] = 'complete'
    }
    $jsonText = ($clean | ConvertTo-Json -Compress -Depth 4)

    if ($ResultPath) {
        $dir = Split-Path -Parent $ResultPath
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        # Write via temp + rename so status polls never read a partial file.
        $tmp = "$ResultPath.tmp"
        [System.IO.File]::WriteAllText($tmp, $jsonText, [System.Text.UTF8Encoding]::new($false))
        Move-Item -Path $tmp -Destination $ResultPath -Force
    }

    if ($Json) {
        $jsonText
    } else {
        $Data.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key, $_.Value }
    }
    exit $ExitCode
}

function Get-SqlScalarInt {
    param([string]$Query, [int]$Default = 0)
    $rows = @(Invoke-SqlRows -Query $Query)
    if ($rows.Count -lt 1) { return $Default }
    $val = $rows[-1] | Select-Object -ExpandProperty c -ErrorAction SilentlyContinue
    if ($null -eq $val) {
        $firstProp = @($rows[-1].PSObject.Properties)[0]
        if ($firstProp) { $val = $firstProp.Value }
    }
    $asText = [string]$val
    if ($asText -match '^-?\d+$') { return [int]$asText }
    return $Default
}

function Get-NormalizedReportText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $t = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    # Report headers pad with dots: "Time:......14:16"
    $t = $t -replace 'Time:\.*\s*\d{1,2}:\d{2}(:\d{2})?', 'Time: __TIME__'
    $t = $t -replace 'at\.\d{4}\.\d{2}\.\d{2}\.\d{2}:\d{2}:\d{2}', 'at.__STAMP__'
    $t = $t -replace 'at \d{4}\.\d{2}\.\d{2}\s+\d{1,2}:\d{2}:\d{2}', 'at __STAMP__'
    $t = $t -replace 'At \d{4}\.\d{2}\.\d{2},\s*\d{1,2}:\d{2}(:\d{2})?', 'At __STAMP__'
    # Page headers: "Date: 2026.07.13" / "DATE: 2026.06.30" / "Date:2026.07.13"
    $t = $t -replace 'Date:\s*\d{4}\.\d{2}\.\d{2}', 'Date: __DATE__'
    $t = $t -replace 'DATE:\s*\d{4}\.\d{2}\.\d{2}', 'DATE: __DATE__'
    $t = $t -replace '\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(\.\d+)?', '__DATETIME__'
    $t = $t -replace 'cli\d{10}', '__PREFIX__'
    $t = $t -replace '(?m)(^|[^A-Za-z])tsip_', '${1}__PREFIX__'
    return $t
}

function Resolve-BaselineReportsDir {
    param(
        [string]$ReportsRoot,
        [string]$CurrentReportsDir,
        [string]$Parm,
        [string]$RunName,
        [string]$WorkDirFallback
    )
    # Prefer the previous isolated tsip-runs folder for the same parm/run.
    # User work-dir reports are often stale once TARGETDIRFORTSIPREPORTS is used.
    $suffix = ("_{0}_{1}" -f $Parm, $RunName)
    $candidates = @(Get-ChildItem -Path $ReportsRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase) -and
            ($_.FullName.TrimEnd('\') -ne $CurrentReportsDir.TrimEnd('\'))
        } |
        Sort-Object LastWriteTime -Descending)
    if ($candidates.Count -ge 1) {
        return $candidates[0].FullName
    }
    return $WorkDirFallback
}

function Compare-TsipArchiveRuns {
    param([int]$BaselineRunId, [int]$NewRunId, [string]$ProType)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Database archive compare: run_id $BaselineRunId -> $NewRunId")

    $siteTable = if ($ProType -eq 'E') { 'web.tsip_arc_te_site' } else { 'web.tsip_arc_ts_site' }
    $chanTable = if ($ProType -eq 'E') { 'web.tsip_arc_te_chan' } else { 'web.tsip_arc_ts_chan' }
    $anteTable = if ($ProType -eq 'E') { 'web.tsip_arc_te_ante' } else { 'web.tsip_arc_ts_ante' }
    $parmTable = if ($ProType -eq 'E') { 'web.tsip_arc_te_parm' } else { 'web.tsip_arc_ts_parm' }
    $statTable = if ($ProType -eq 'E') { 'web.tsip_arc_te_statsum' } else { 'web.tsip_arc_ts_statsum' }

    $countDiffs = 0
    foreach ($pair in @(
            @{ Name = 'site'; Table = $siteTable },
            @{ Name = 'chan'; Table = $chanTable },
            @{ Name = 'ante'; Table = $anteTable },
            @{ Name = 'parm'; Table = $parmTable },
            @{ Name = 'statsum'; Table = $statTable },
            @{ Name = 'report_line'; Table = 'web.tsip_run_report_line' }
        )) {
        $c1 = Get-SqlScalarInt "SELECT COUNT(*) AS c FROM $($pair.Table) WHERE run_id = $BaselineRunId"
        $c2 = Get-SqlScalarInt "SELECT COUNT(*) AS c FROM $($pair.Table) WHERE run_id = $NewRunId"
        $mark = if ($c1 -eq $c2) { 'OK' } else { 'DIFF'; $countDiffs++ }
        $lines.Add(("  {0,-12} rows: {1} -> {2} [{3}]" -f $pair.Name, $c1, $c2, $mark))
    }

    $calcMismatches = 0
    $onlyInBaseline = 0
    $onlyInNew = 0
    if ($ProType -ne 'E') {
        $calcMismatches = Get-SqlScalarInt @"
SELECT COUNT(*) AS c
FROM web.tsip_arc_ts_chan a
INNER JOIN web.tsip_arc_ts_chan b
  ON a.caseno = b.caseno AND a.intcall1 = b.intcall1 AND a.viccall1 = b.viccall1
 AND ISNULL(a.intchid, -1) = ISNULL(b.intchid, -1)
 AND ISNULL(a.vicchid, -1) = ISNULL(b.vicchid, -1)
WHERE a.run_id = $BaselineRunId AND b.run_id = $NewRunId
  AND (
       ISNULL(a.calcico, -999999) <> ISNULL(b.calcico, -999999)
    OR ISNULL(a.resti, -999999) <> ISNULL(b.resti, -999999)
    OR ISNULL(a.calcixp, -999999) <> ISNULL(b.calcixp, -999999)
    OR ISNULL(CONVERT(varchar(64), a.ohresult), '') <> ISNULL(CONVERT(varchar(64), b.ohresult), '')
  );
"@
        $onlyInBaseline = Get-SqlScalarInt @"
SELECT COUNT(*) AS c FROM web.tsip_arc_ts_chan a
WHERE a.run_id = $BaselineRunId
  AND NOT EXISTS (
    SELECT 1 FROM web.tsip_arc_ts_chan b
    WHERE b.run_id = $NewRunId
      AND a.caseno = b.caseno AND a.intcall1 = b.intcall1 AND a.viccall1 = b.viccall1
      AND ISNULL(a.intchid, -1) = ISNULL(b.intchid, -1)
      AND ISNULL(a.vicchid, -1) = ISNULL(b.vicchid, -1)
  );
"@
        $onlyInNew = Get-SqlScalarInt @"
SELECT COUNT(*) AS c FROM web.tsip_arc_ts_chan b
WHERE b.run_id = $NewRunId
  AND NOT EXISTS (
    SELECT 1 FROM web.tsip_arc_ts_chan a
    WHERE a.run_id = $BaselineRunId
      AND a.caseno = b.caseno AND a.intcall1 = b.intcall1 AND a.viccall1 = b.viccall1
      AND ISNULL(a.intchid, -1) = ISNULL(b.intchid, -1)
      AND ISNULL(a.vicchid, -1) = ISNULL(b.vicchid, -1)
  );
"@
    }
    $lines.Add(("  calc fingerprint mismatches: {0}" -f $calcMismatches))
    $lines.Add(("  chan rows only in baseline / new: {0} / {1}" -f $onlyInBaseline, $onlyInNew))

    # Report-line text compare in SQL (avoid piping line_text through | parser).
    # Volatile: timestamp/clock header lines. EXEC/STUDY excluded entirely.
    $repRows = @(Invoke-SqlRows -Query @"
SELECT a.report_type AS report_type,
       SUM(CASE
             WHEN a.line_text LIKE '%Time:%'
               OR b.line_text LIKE '%Time:%'
               OR a.line_text LIKE 'At 20%'
               OR b.line_text LIKE 'At 20%'
               OR a.line_text LIKE '% at 20%'
               OR b.line_text LIKE '% at 20%'
               OR a.line_text LIKE '%at.20%'
               OR b.line_text LIKE '%at.20%'
               OR a.line_text LIKE '%Date:%'
               OR b.line_text LIKE '%Date:%'
               OR a.line_text LIKE '%DATE:%'
               OR b.line_text LIKE '%DATE:%'
             THEN 1 ELSE 0
           END) AS volatile_diffs,
       SUM(CASE
             WHEN a.line_text LIKE '%Time:%'
               OR b.line_text LIKE '%Time:%'
               OR a.line_text LIKE 'At 20%'
               OR b.line_text LIKE 'At 20%'
               OR a.line_text LIKE '% at 20%'
               OR b.line_text LIKE '% at 20%'
               OR a.line_text LIKE '%at.20%'
               OR b.line_text LIKE '%at.20%'
               OR a.line_text LIKE '%Date:%'
               OR b.line_text LIKE '%Date:%'
               OR a.line_text LIKE '%DATE:%'
               OR b.line_text LIKE '%DATE:%'
             THEN 0 ELSE 1
           END) AS substantive_diffs
FROM web.tsip_run_report_line a
INNER JOIN web.tsip_run_report_line b
  ON a.report_type = b.report_type AND a.line_no = b.line_no
WHERE a.run_id = $BaselineRunId AND b.run_id = $NewRunId
  AND a.report_type NOT IN ('EXEC', 'STUDY')
  AND RTRIM(CAST(a.line_text AS NVARCHAR(MAX))) <> RTRIM(CAST(b.line_text AS NVARCHAR(MAX)))
GROUP BY a.report_type
ORDER BY a.report_type;
"@)
    $volatileDiffs = 0
    $substantiveDiffs = 0
    $detailLines = New-Object System.Collections.Generic.List[string]
    foreach ($r in $repRows) {
        $rt = [string](@($r.report_type)[0])
        $vRaw = @($r.volatile_diffs)[0]
        $sRaw = @($r.substantive_diffs)[0]
        $v = 0; $s = 0
        if ("$vRaw" -match '^-?\d+$') { $v = [int]"$vRaw" }
        if ("$sRaw" -match '^-?\d+$') { $s = [int]"$sRaw" }
        $volatileDiffs += $v
        $substantiveDiffs += $s
        $detailLines.Add(("    {0}: substantive={1} volatile={2}" -f $rt, $s, $v))
    }
    $lines.Add(("  report_line text diffs (excl EXEC/STUDY): substantive={0} volatile(timestamp)={1}" -f $substantiveDiffs, $volatileDiffs))
    foreach ($dl in $detailLines) { $lines.Add($dl) }

    $dbMatch = ($countDiffs -eq 0 -and $calcMismatches -eq 0 -and $onlyInBaseline -eq 0 -and $onlyInNew -eq 0 -and $substantiveDiffs -eq 0)
    if ($dbMatch) {
        $lines.Add('  SUMMARY: database archive matches (ignoring volatile timestamp lines).')
    } else {
        $lines.Add('  SUMMARY: database archive has substantive differences.')
    }

    return @{
        Match            = $dbMatch
        Summary          = ($lines -join "`n")
        CalcMismatches   = $calcMismatches
        SubstantiveDiffs = $substantiveDiffs
        VolatileDiffs    = $volatileDiffs
        CountDiffs       = $countDiffs
    }
}

function Get-ReportExtKey {
    param([string]$FileName)
    $n = $FileName.ToUpperInvariant()
    if ($n -match '\.AGGINT\.CSV$') { return 'AGGINT.CSV' }
    if ($n -match '\.([A-Z0-9_]+)$') { return $Matches[1] }
    return $null
}

function Compare-TsipReportFiles {
    param(
        [string]$BaselineDir,
        [string]$NewDir,
        [string]$Parm,
        [string]$RunName
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("On-disk report file compare")
    $lines.Add("  baseline dir: $(if ($BaselineDir) { $BaselineDir } else { '(not found)' })")
    $lines.Add("  new dir:      $NewDir")

    if (-not $BaselineDir -or -not (Test-Path $BaselineDir)) {
        $lines.Add('  SUMMARY: baseline report files not available for disk compare (DB report_line compare still applies).')
        return @{
            Match        = $true   # do not fail overall solely for missing baseline disk files
            Available    = $false
            Summary      = ($lines -join "`n")
            FileDiffs    = 0
            MissingFiles = 0
        }
    }

    $suffix = ("_{0}_{1}." -f $Parm, $RunName).ToUpperInvariant()
    $errSuffix = ("_{0}.ERR" -f $Parm).ToUpperInvariant()

    function Get-ExtMap([string]$Dir) {
        $map = @{}
        Get-ChildItem -Path $Dir -File -ErrorAction SilentlyContinue | ForEach-Object {
            $up = $_.Name.ToUpperInvariant()
            if ($up.EndsWith($errSuffix) -or $up.EndsWith('.ERR')) {
                $map['ERR'] = $_
                return
            }
            if ($up.EndsWith('.TXT')) { return }
            if ($up -notlike "*$suffix*") { return }
            $ext = Get-ReportExtKey $_.Name
            if ($ext) { $map[$ext] = $_ }
        }
        return $map
    }

    $baseMap = Get-ExtMap $BaselineDir
    $newMap = Get-ExtMap $NewDir
    $allExts = @($baseMap.Keys + $newMap.Keys | Select-Object -Unique | Sort-Object)

    $fileDiffs = 0
    $missing = 0
    $compared = 0
    foreach ($ext in $allExts) {
        $bf = if ($baseMap.ContainsKey($ext)) { $baseMap[$ext] } else { $null }
        $nf = if ($newMap.ContainsKey($ext)) { $newMap[$ext] } else { $null }
        if (-not $bf -or -not $nf) {
            $missing++
            $lines.Add(("  {0,-12} missing on {1}" -f $ext, $(if (-not $bf) { 'baseline' } else { 'new' })))
            continue
        }
        if ($ext -in @('EXEC', 'STUDY', 'ERR')) {
            $lines.Add(("  {0,-12} skipped (volatile/meta) sizes {1} / {2}" -f $ext, $bf.Length, $nf.Length))
            continue
        }
        $compared++
        $bt = Get-NormalizedReportText (Get-Content -LiteralPath $bf.FullName -Raw -ErrorAction SilentlyContinue)
        $nt = Get-NormalizedReportText (Get-Content -LiteralPath $nf.FullName -Raw -ErrorAction SilentlyContinue)
        if ($bt -eq $nt) {
            $lines.Add(("  {0,-12} OK (normalized, sizes {1}/{2})" -f $ext, $bf.Length, $nf.Length))
        } else {
            $fileDiffs++
            # Count differing non-empty lines after normalize
            $bl = @($bt -split "`n")
            $nl = @($nt -split "`n")
            $max = [Math]::Max($bl.Count, $nl.Count)
            $diffLines = 0
            for ($i = 0; $i -lt $max; $i++) {
                $a = if ($i -lt $bl.Count) { $bl[$i] } else { '' }
                $b = if ($i -lt $nl.Count) { $nl[$i] } else { '' }
                if ($a -ne $b) { $diffLines++ }
            }
            $lines.Add(("  {0,-12} DIFF normalized ({1} line deltas, sizes {2}/{3})" -f $ext, $diffLines, $bf.Length, $nf.Length))
        }
    }

    $available = ($compared -gt 0 -or $allExts.Count -gt 0)
    $filesMatch = ($fileDiffs -eq 0 -and $missing -eq 0)
    if (-not $available) {
        $lines.Add('  SUMMARY: no comparable report files found.')
    } elseif ($filesMatch) {
        $lines.Add('  SUMMARY: on-disk report files match after normalizing timestamps/prefixes.')
    } else {
        $lines.Add(("  SUMMARY: on-disk differences - file_content_diffs={0}, missing={1}" -f $fileDiffs, $missing))
    }

    return @{
        Match        = $filesMatch
        Available    = $available
        Summary      = ($lines -join "`n")
        FileDiffs    = $fileDiffs
        MissingFiles = $missing
    }
}

if (-not (Test-Path $tpRun)) {
    Write-Result @{ ok = $false; error = "TpRunTsip.exe not found at $tpRun" } -ExitCode 1
}
if (-not (Test-Path $sqlScript)) {
    Write-Result @{ ok = $false; error = "SQL helper not found: $sqlScript" } -ExitCode 1
}

if (-not $Password) {
    $Password = $env:MICS_TEST_PASSWORD
}
if (-not $Password) {
    $Password = Get-EnvLocalValue 'MICS_TEST_PASSWORD'
}
if (-not $Password) {
    # Historical CLI smoke tests on this host used a placeholder; override via .env.local when needed.
    $Password = 'x'
}

$baselineRows = @(Invoke-SqlRows -Query @"
SELECT TOP 1 run_id, mics_user, source_schema, parm_file, run_name, view_name, protype,
       num_int_cases, archive_status, CONVERT(varchar(33), run_started_utc, 126) AS run_started_utc
FROM web.tsip_run
WHERE archive_status = 'complete'
ORDER BY run_started_utc DESC;
"@)

if ($baselineRows.Count -lt 1) {
    Write-Result @{ ok = $false; error = 'No completed TSIP runs found in web.tsip_run' } -ExitCode 1
}

$base = $baselineRows[0]
$baselineRunId = [int]$base.run_id
$baselineCases = if ($base.num_int_cases -match '^\d+$') { [int]$base.num_int_cases } else { $null }
$micsUser = $base.mics_user
$schema = $base.source_schema
$parm = $base.parm_file
$runName = $base.run_name
$project = "${micsUser}_0"
$workDir = "D:\Inetpub\remicsdev\mics\userdirs\$schema\$micsUser\"
if (-not (Test-Path $workDir)) {
    Write-Result @{
        ok = $false
        error = "User work dir not found: $workDir"
        baseline_run_id = $baselineRunId
        parm_file = $parm
        run_name = $runName
        mics_user = $micsUser
    } -ExitCode 1
}

$prefix = 'cli' + (Get-Date -Format 'MMddHHmmss')
$startedUtc = (Get-Date).ToUniversalTime().ToString('o')

# Isolate test report files from the user's normal TSIP work dir.
# TARGETDIRFORTSIPREPORTS is process-local; normal web TSIP sets its own value per run.
$reportsRoot = 'D:\inetpub\fcsa\admin\tsip-runs'
$reportsDir = Join-Path $reportsRoot ("{0}_{1}_{2}" -f $prefix, $parm, $runName)
New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null
# Trailing backslash expected by TpRunTsip when the env var is set.
$reportsDirEnv = $reportsDir.TrimEnd('\') + '\'

$env:MICSUSER = $micsUser
$env:PASSWORD = $Password
$env:Domain = 'CLOUDMICSDEV'
$env:odbc = 'remicsdev'
$env:DBName = 'remicsdev'
$env:SqlInstance = 'EC2AMAZ-9DKDM82\REMICS_DEV'
$env:MICS_PROJECT = $project
$env:work_dir = $workDir
$env:WORK_DIR = $workDir
$env:webdrive = 'D:'
$env:TARGETDIRFORTSIPREPORTS = $reportsDirEnv

$argList = @('remicsdev', $project, $parm, "-o$prefix", "-u$micsUser")
$stdoutFile = Join-Path $env:TEMP "tsip-compare-out-$prefix.txt"
$stderrFile = Join-Path $env:TEMP "tsip-compare-err-$prefix.txt"
$proc = Start-Process -FilePath $tpRun -ArgumentList $argList -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
$exitCode = $proc.ExitCode
$stdout = if (Test-Path $stdoutFile) { Get-Content $stdoutFile -Raw } else { '' }
$stderr = if (Test-Path $stderrFile) { Get-Content $stderrFile -Raw } else { '' }

if ($exitCode -ne 0) {
    Write-Result @{
        ok = $false
        error = "TpRunTsip exited $exitCode"
        baseline_run_id = $baselineRunId
        baseline_num_int_cases = $baselineCases
        parm_file = $parm
        run_name = $runName
        reports_dir = $reportsDir
        report_prefix = $prefix
        stdout = $stdout
        stderr = $stderr
    } -ExitCode $exitCode
}

# Wait for a newer archive row for the same parm/run
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$newRow = $null
while ((Get-Date) -lt $deadline) {
    $rows = @(Invoke-SqlRows -Query @"
SELECT TOP 1 run_id, mics_user, source_schema, parm_file, run_name,
       num_int_cases, archive_status,
       CONVERT(varchar(33), run_started_utc, 126) AS run_started_utc
FROM web.tsip_run
WHERE parm_file = '$parm'
  AND run_name = '$runName'
  AND run_id > $baselineRunId
ORDER BY run_id DESC;
"@)
    if ($rows.Count -ge 1 -and $rows[0].archive_status -eq 'complete') {
        $newRow = $rows[0]
        break
    }
    Start-Sleep -Seconds 3
}

if (-not $newRow) {
    Write-Result @{
        ok = $false
        error = "TpRunTsip succeeded (exit 0) but no new web.tsip_run row appeared within ${TimeoutSec}s"
        baseline_run_id = $baselineRunId
        baseline_num_int_cases = $baselineCases
        parm_file = $parm
        run_name = $runName
        reports_dir = $reportsDir
        report_prefix = $prefix
    } -ExitCode 2
}

$newRunId = [int]$newRow.run_id
$newCases = if ($newRow.num_int_cases -match '^\d+$') { [int]$newRow.num_int_cases } else { $null }
$delta = if ($null -ne $baselineCases -and $null -ne $newCases) { $newCases - $baselineCases } else { $null }
$casesMatch = ($null -ne $baselineCases -and $null -ne $newCases -and $baselineCases -eq $newCases)

$proType = if ($base.protype) { [string]$base.protype.Trim() } else { 'T' }
$dbCmp = Compare-TsipArchiveRuns -BaselineRunId $baselineRunId -NewRunId $newRunId -ProType $proType

# Prefer previous isolated tsip-runs folder (same parm/run); work dir is often stale.
$baselineReportsDir = Resolve-BaselineReportsDir `
    -ReportsRoot $reportsRoot `
    -CurrentReportsDir $reportsDir `
    -Parm $parm `
    -RunName $runName `
    -WorkDirFallback $workDir
$diskCmp = Compare-TsipReportFiles -BaselineDir $baselineReportsDir -NewDir $reportsDir -Parm $parm -RunName $runName

$overallMatch = $casesMatch -and [bool]$dbCmp.Match -and (
    -not [bool]$diskCmp.Available -or [bool]$diskCmp.Match
)

$summaryParts = New-Object System.Collections.Generic.List[string]
$summaryParts.Add($(if ($casesMatch) {
    "Interference case count unchanged: $newCases (run $baselineRunId -> $newRunId)"
} else {
    "Interference case count changed: $baselineCases -> $newCases (delta $delta)"
}))
$summaryParts.Add('')
$summaryParts.Add([string]$dbCmp.Summary)
$summaryParts.Add('')
$summaryParts.Add([string]$diskCmp.Summary)
$summaryParts.Add('')
$summaryParts.Add($(if ($overallMatch) {
    'OVERALL: MATCH - cases, DB archive, and report files agree (volatile timestamps ignored).'
} else {
    'OVERALL: DIFFERENCES FOUND - see sections above.'
}))
$fullSummary = $summaryParts -join "`n"

$summaryPath = Join-Path $reportsDir 'compare-summary.txt'
try {
    [System.IO.File]::WriteAllText($summaryPath, $fullSummary, [System.Text.UTF8Encoding]::new($false))
} catch {
    $summaryPath = ''
}

Write-Result @{
    ok = $true
    match = $overallMatch
    cases_match = $casesMatch
    db_match = [bool]$dbCmp.Match
    files_match = [bool]$diskCmp.Match
    files_compared = [bool]$diskCmp.Available
    parm_file = $parm
    run_name = $runName
    mics_user = $micsUser
    baseline_run_id = $baselineRunId
    baseline_num_int_cases = $baselineCases
    baseline_started_utc = $base.run_started_utc
    new_run_id = $newRunId
    new_num_int_cases = $newCases
    new_started_utc = $newRow.run_started_utc
    delta_num_int_cases = $delta
    calc_mismatches = [int]$dbCmp.CalcMismatches
    report_substantive_diffs = [int]$dbCmp.SubstantiveDiffs
    report_volatile_diffs = [int]$dbCmp.VolatileDiffs
    file_content_diffs = [int]$diskCmp.FileDiffs
    file_missing = [int]$diskCmp.MissingFiles
    reports_dir = $reportsDir
    baseline_reports_dir = $baselineReportsDir
    report_prefix = $prefix
    compare_summary_path = $summaryPath
    db_summary = [string]$dbCmp.Summary
    files_summary = [string]$diskCmp.Summary
    summary = $fullSummary
    started_utc = $startedUtc
    message = if ($overallMatch) {
        "Overall match (run $baselineRunId -> $newRunId). See summary / compare-summary.txt"
    } else {
        "Differences found (run $baselineRunId -> $newRunId). See summary / compare-summary.txt"
    }
} -ExitCode 0
